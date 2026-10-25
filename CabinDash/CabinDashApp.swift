import SwiftUI

@main @MainActor
struct CabinDashApp: App {
    @State private var model = AppModel()
    @State private var location = LocationModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(location)
                .preferredColorScheme(model.prefs.theme.colorScheme)
        }
    }
}
