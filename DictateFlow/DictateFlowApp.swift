import SwiftUI
import AppKit

@main
struct DictateFlowApp: App {
    @StateObject private var settingsStore: SettingsStore
    @StateObject private var viewModel: AppViewModel

    init() {
        let settings = SettingsStore()
        _settingsStore = StateObject(wrappedValue: settings)
        _viewModel = StateObject(wrappedValue: AppViewModel(settings: settings))
    }

    var body: some Scene {
        WindowGroup("DictateFlow") {
            MainView()
                .environmentObject(settingsStore)
                .environmentObject(viewModel)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    viewModel.shutdown()
                }
        }
        .defaultSize(width: 1100, height: 760)
    }
}
