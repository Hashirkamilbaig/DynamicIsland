import SwiftUI

@main
struct DynamicIslandApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // UI lives in the floating NSPanel from AppDelegate.
        Settings {
            VStack(alignment: .leading, spacing: 8) {
                Text("Dynamic Island")
                    .font(.headline)
                Text("Shelf TTL is 20 seconds. Volume controls the Mac output device.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .frame(width: 320)
        }
    }
}
