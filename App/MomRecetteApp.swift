import SwiftUI

@main
struct MomRecetteApp: App {
    @StateObject private var store = RecipeStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .tint(Color(red: 0.82, green: 0.35, blue: 0.20)) // Warm terracotta accent
        }
    }
}
