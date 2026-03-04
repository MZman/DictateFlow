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
        Window("DictateFlow", id: "main") {
            MainView()
                .environmentObject(settingsStore)
                .environmentObject(viewModel)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    viewModel.shutdown()
                }
        }
        .defaultSize(width: 1100, height: 760)

        MenuBarExtra {
            MenuBarControlView()
                .environmentObject(settingsStore)
                .environmentObject(viewModel)
        } label: {
            // Gewünschtes Mikrowellen-/Radiowellen-Symbol in der Menüleiste.
            Image(systemName: "dot.radiowaves.left.and.right")
        }
        .menuBarExtraStyle(.window)
    }
}
