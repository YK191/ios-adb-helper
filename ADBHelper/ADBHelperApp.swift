import SwiftUI

@main
struct ADBHelperApp: App {
    @StateObject private var model = DeviceViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
        }
    }
}
