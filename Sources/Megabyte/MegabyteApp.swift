import SwiftUI

@main
struct MegabyteApp: App {
    private let store = MonitorStore()

    var body: some Scene {
        MenuBarExtra {
            PanelView()
                .environment(store)
        } label: {
            Image(systemName: store.connected ? "display" : "display.trianglebadge.exclamationmark")
        }
        .menuBarExtraStyle(.window)
    }
}
