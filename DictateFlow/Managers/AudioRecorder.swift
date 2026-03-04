import Foundation
import AVFoundation

final class AudioRecorder: NSObject {
    private enum MicrophonePermissionState {
        case granted
        case denied
        case undetermined
    }

    enum RecorderError: LocalizedError {
        case microphonePermissionDenied
        case cannotCreateRecorder
        case cannotStartRecording
        case inputDeviceNotFound
        case inputDeviceSelectionFailed(String)

        var errorDescription: String? {
            switch self {
            case .microphonePermissionDenied:
                return "Kein Mikrofonzugriff. Bitte in den macOS Systemeinstellungen für DictateFlow erlauben."
            case .cannotCreateRecorder:
                return "Audioaufnahme konnte nicht initialisiert werden."
            case .cannotStartRecording:
                return "Audioaufnahme konnte nicht gestartet werden."
            case .inputDeviceNotFound:
                return "Das ausgewählte Mikrofon wurde nicht gefunden. Bitte wähle ein verfügbares Eingabegerät."
            case let .inputDeviceSelectionFailed(details):
                return "Das ausgewählte Mikrofon konnte nicht aktiviert werden: \(details)"
            }
        }
    }

    private var recorder: AVAudioRecorder?
    private(set) var currentFileURL: URL?
    private var previousDefaultInputDeviceID: UInt32?

    func isMicrophonePermissionGranted() -> Bool {
        microphonePermissionState() == .granted
    }

    func requestPermissionIfNeeded() async -> Bool {
        switch microphonePermissionState() {
        case .granted:
            return true
        case .undetermined:
            let granted: Bool = await withCheckedContinuation { continuation in
                if #available(macOS 14.0, *) {
                    AVAudioApplication.requestRecordPermission { granted in
                        continuation.resume(returning: granted)
                    }
                } else {
                    AVCaptureDevice.requestAccess(for: .audio) { granted in
                        continuation.resume(returning: granted)
                    }
                }
            }
            if granted {
                return true
            }
            // Defensive polling: TCC updates can lag briefly right after the system prompt closes.
            return await waitForMicrophonePermission(timeout: 1.5, pollInterval: 0.25)
        case .denied:
            return false
        }
    }

    func waitForMicrophonePermission(timeout: TimeInterval = 20, pollInterval: TimeInterval = 0.5) async -> Bool {
        if isMicrophonePermissionGranted() {
            return true
        }

        let interval = max(0.1, pollInterval)
        let deadline = Date().addingTimeInterval(max(0, timeout))
        while Date() < deadline {
            let nanoseconds = UInt64(interval * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            if isMicrophonePermissionGranted() {
                return true
            }
        }

        return isMicrophonePermissionGranted()
    }

    private func microphonePermissionState() -> MicrophonePermissionState {
        if #available(macOS 14.0, *) {
            switch AVAudioApplication.shared.recordPermission {
            case .granted:
                return .granted
            case .denied:
                return .denied
            case .undetermined:
                return .undetermined
            @unknown default:
                return .denied
            }
        }

        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return .granted
        case .notDetermined:
            return .undetermined
        case .denied, .restricted:
            return .denied
        @unknown default:
            return .denied
        }
    }

    func startRecording(preferredInputDeviceUID: String?) throws -> URL {
        do {
            try switchInputDeviceIfNeeded(preferredInputDeviceUID: preferredInputDeviceUID)
        } catch {
            if let recorderError = error as? RecorderError {
                throw recorderError
            }
            throw RecorderError.inputDeviceSelectionFailed(error.localizedDescription)
        }

        let directory = try recordingsDirectory()
        let filename = "recording-\(Int(Date().timeIntervalSince1970)).wav"
        let fileURL = directory.appendingPathComponent(filename)

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            let newRecorder = try AVAudioRecorder(url: fileURL, settings: settings)
            newRecorder.isMeteringEnabled = true
            newRecorder.prepareToRecord()

            guard newRecorder.record() else {
                throw RecorderError.cannotStartRecording
            }

            recorder = newRecorder
            currentFileURL = fileURL
            return fileURL
        } catch {
            restoreDefaultInputDeviceIfNeeded()
            throw error
        }
    }

    func stopRecording() -> URL? {
        recorder?.stop()
        recorder = nil
        let finishedURL = currentFileURL
        currentFileURL = nil
        restoreDefaultInputDeviceIfNeeded()
        return finishedURL
    }

    func cancelRecording() {
        recorder?.stop()
        recorder = nil

        if let currentFileURL {
            try? FileManager.default.removeItem(at: currentFileURL)
        }
        self.currentFileURL = nil
        restoreDefaultInputDeviceIfNeeded()
    }

    private func switchInputDeviceIfNeeded(preferredInputDeviceUID: String?) throws {
        previousDefaultInputDeviceID = nil

        let trimmedUID = preferredInputDeviceUID?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !trimmedUID.isEmpty else {
            return
        }

        guard let requestedDeviceID = AudioInputDeviceManager.deviceID(forUID: trimmedUID) else {
            throw RecorderError.inputDeviceNotFound
        }

        let currentDefault = try AudioInputDeviceManager.defaultInputDeviceID()
        guard currentDefault != requestedDeviceID else {
            return
        }

        do {
            try AudioInputDeviceManager.setDefaultInputDevice(id: requestedDeviceID)
            previousDefaultInputDeviceID = currentDefault
        } catch {
            throw RecorderError.inputDeviceSelectionFailed(
                (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            )
        }
    }

    private func restoreDefaultInputDeviceIfNeeded() {
        guard let previousDefaultInputDeviceID else { return }
        defer { self.previousDefaultInputDeviceID = nil }
        try? AudioInputDeviceManager.setDefaultInputDevice(id: previousDefaultInputDeviceID)
    }

    private func recordingsDirectory() throws -> URL {
        let fileManager = FileManager.default
        let appSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        let recordingsFolder = appSupport
            .appendingPathComponent("DictateFlow", isDirectory: true)
            .appendingPathComponent("Recordings", isDirectory: true)

        try fileManager.createDirectory(at: recordingsFolder, withIntermediateDirectories: true)
        return recordingsFolder
    }

    func recordingLevel() -> Double {
        guard let recorder, recorder.isRecording else { return 0 }
        recorder.updateMeters()

        let averagePower = Double(recorder.averagePower(forChannel: 0))
        let clampedPower = max(-60.0, min(0.0, averagePower))
        let normalized = (clampedPower + 60.0) / 60.0
        return normalized
    }
}
