import Foundation
import AVFoundation

final class AudioRecorder: NSObject {
    enum RecorderError: LocalizedError {
        case microphonePermissionDenied
        case cannotCreateRecorder
        case cannotStartRecording

        var errorDescription: String? {
            switch self {
            case .microphonePermissionDenied:
                return "Kein Mikrofonzugriff. Bitte in den macOS Systemeinstellungen für DictateFlow erlauben."
            case .cannotCreateRecorder:
                return "Audioaufnahme konnte nicht initialisiert werden."
            case .cannotStartRecording:
                return "Audioaufnahme konnte nicht gestartet werden."
            }
        }
    }

    private var recorder: AVAudioRecorder?
    private(set) var currentFileURL: URL?

    func requestPermissionIfNeeded() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    func startRecording() throws -> URL {
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

        let newRecorder = try AVAudioRecorder(url: fileURL, settings: settings)
        newRecorder.prepareToRecord()

        guard newRecorder.record() else {
            throw RecorderError.cannotStartRecording
        }

        recorder = newRecorder
        currentFileURL = fileURL

        return fileURL
    }

    func stopRecording() -> URL? {
        recorder?.stop()
        recorder = nil
        return currentFileURL
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
}
