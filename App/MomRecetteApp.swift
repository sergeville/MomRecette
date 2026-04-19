import SwiftUI
import UIKit

enum AppAppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system:
            return "Systeme"
        case .light:
            return "Jour"
        case .dark:
            return "Nuit"
        }
    }

    var systemImage: String {
        switch self {
        case .system:
            return "circle.lefthalf.filled"
        case .light:
            return "sun.max.fill"
        case .dark:
            return "moon.fill"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
}

struct MomRecetteSetup {
    struct RecipeWorkspace {
        static let defaultSection: RecipeWorkspaceSection = .ingredients

        static func defaultIngredientPresentation(hasRecipeCard: Bool) -> IngredientPresentation {
            hasRecipeCard ? .recipeCard : .checklist
        }
    }

    struct WindowState {
        static let frameDefaultsKey = "momrecette.window_frame"
        static let minimumWidth: CGFloat = 480
        static let minimumHeight: CGFloat = 360
    }

    struct Appearance {
        static let modeStorageKey = "momrecette.appearance_mode"
        static let defaultMode: AppAppearanceMode = .system
    }

    struct SettingsPanel {
        static let minimumWidth: CGFloat = 520
        static let idealWidth: CGFloat = 560
        static let minimumHeight: CGFloat = 420
        static let idealHeight: CGFloat = 460
    }
}

@main
struct MomRecetteApp: App {
    @UIApplicationDelegateAdaptor(MomRecetteAppDelegate.self) private var appDelegate
    @StateObject private var store = RecipeStore()
    @AppStorage(MomRecetteSetup.Appearance.modeStorageKey)
    private var appearanceModeRawValue = MomRecetteSetup.Appearance.defaultMode.rawValue

    private var appearanceMode: AppAppearanceMode {
        AppAppearanceMode(rawValue: appearanceModeRawValue) ?? MomRecetteSetup.Appearance.defaultMode
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .tint(Color(red: 0.82, green: 0.35, blue: 0.20)) // Warm terracotta accent
                .preferredColorScheme(appearanceMode.colorScheme)
        }
    }
}

extension Notification.Name {
    static let openMomRecetteSettings = Notification.Name("openMomRecetteSettings")
}

final class MomRecetteAppDelegate: UIResponder, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = MomRecetteSceneDelegate.self
        return configuration
    }

    #if targetEnvironment(macCatalyst)
    override func buildMenu(with builder: any UIMenuBuilder) {
        super.buildMenu(with: builder)

        let settingsCommand = UIKeyCommand(
            title: "Settings...",
            action: #selector(openSettingsFromMenu),
            input: ",",
            modifierFlags: .command
        )
        let settingsMenu = UIMenu(
            title: "",
            identifier: .preferences,
            options: .displayInline,
            children: [settingsCommand]
        )

        if builder.menu(for: .preferences) != nil {
            builder.replace(menu: .preferences, with: settingsMenu)
        } else {
            builder.insertSibling(settingsMenu, afterMenu: .about)
        }
    }

    @objc private func openSettingsFromMenu() {
        NotificationCenter.default.post(name: .openMomRecetteSettings, object: nil)
    }
    #endif
}

final class MomRecetteSceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        WindowFramePersistence.restoreIfAvailable(for: windowScene)
    }

    func sceneWillResignActive(_ scene: UIScene) {
        guard let windowScene = scene as? UIWindowScene else { return }
        WindowFramePersistence.saveFrame(from: windowScene)
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        guard let windowScene = scene as? UIWindowScene else { return }
        WindowFramePersistence.saveFrame(from: windowScene)
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        guard let windowScene = scene as? UIWindowScene else { return }
        WindowFramePersistence.saveFrame(from: windowScene)
    }

    func windowScene(
        _ windowScene: UIWindowScene,
        didUpdate previousCoordinateSpace: any UICoordinateSpace,
        interfaceOrientation previousInterfaceOrientation: UIInterfaceOrientation,
        traitCollection previousTraitCollection: UITraitCollection
    ) {
        WindowFramePersistence.saveFrame(from: windowScene)
    }
}

private enum WindowFramePersistence {
    static func restoreIfAvailable(for windowScene: UIWindowScene) {
        #if targetEnvironment(macCatalyst)
        guard let frame = loadFrame() else { return }

        let preferences = UIWindowScene.GeometryPreferences.Mac(systemFrame: frame)
        windowScene.requestGeometryUpdate(preferences) { error in
            #if DEBUG
            print("Window frame restore skipped: \(error.localizedDescription)")
            #endif
        }
        #endif
    }

    static func saveFrame(from windowScene: UIWindowScene) {
        #if targetEnvironment(macCatalyst)
        let frame = windowScene.effectiveGeometry.systemFrame
        guard frame.isFiniteWindowFrame else { return }

        let persistedFrame = PersistedWindowFrame(frame: frame)

        do {
            let data = try JSONEncoder().encode(persistedFrame)
            UserDefaults.standard.set(data, forKey: MomRecetteSetup.WindowState.frameDefaultsKey)
        } catch {
            #if DEBUG
            print("Window frame save failed: \(error.localizedDescription)")
            #endif
        }
        #endif
    }

    #if targetEnvironment(macCatalyst)
    private static func loadFrame() -> CGRect? {
        guard let data = UserDefaults.standard.data(forKey: MomRecetteSetup.WindowState.frameDefaultsKey) else { return nil }
        guard let persistedFrame = try? JSONDecoder().decode(PersistedWindowFrame.self, from: data) else {
            UserDefaults.standard.removeObject(forKey: MomRecetteSetup.WindowState.frameDefaultsKey)
            return nil
        }

        let frame = persistedFrame.cgRect
        guard frame.isFiniteWindowFrame else {
            UserDefaults.standard.removeObject(forKey: MomRecetteSetup.WindowState.frameDefaultsKey)
            return nil
        }

        return frame
    }
    #endif
}

private struct PersistedWindowFrame: Codable {
    let originX: Double
    let originY: Double
    let width: Double
    let height: Double

    init(frame: CGRect) {
        originX = frame.origin.x
        originY = frame.origin.y
        width = frame.size.width
        height = frame.size.height
    }

    var cgRect: CGRect {
        CGRect(x: originX, y: originY, width: width, height: height)
    }
}

private extension CGRect {
    var isFiniteWindowFrame: Bool {
        !isNull &&
        !isInfinite &&
        origin.x.isFinite &&
        origin.y.isFinite &&
        size.width.isFinite &&
        size.height.isFinite &&
        size.width >= MomRecetteSetup.WindowState.minimumWidth &&
        size.height >= MomRecetteSetup.WindowState.minimumHeight
    }
}

struct AppSettingsView: View {
    @AppStorage(MomRecetteSetup.Appearance.modeStorageKey)
    private var appearanceModeRawValue = MomRecetteSetup.Appearance.defaultMode.rawValue

    private var appearanceMode: AppAppearanceMode {
        AppAppearanceMode(rawValue: appearanceModeRawValue) ?? MomRecetteSetup.Appearance.defaultMode
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Apparence") {
                    Picker("Theme", selection: $appearanceModeRawValue) {
                        ForEach(AppAppearanceMode.allCases) { mode in
                            Label(mode.title, systemImage: mode.systemImage)
                                .tag(mode.rawValue)
                        }
                    }
                    .pickerStyle(.inline)

                    Text("Choisissez le rendu de MomRecette sur macOS.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Fenetre") {
                    Button("Reinitialiser la taille et la position") {
                        UserDefaults.standard.removeObject(forKey: MomRecetteSetup.WindowState.frameDefaultsKey)
                    }

                    Text("Le prochain lancement utilisera la geometrie par defaut.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
        }
        .frame(
            minWidth: MomRecetteSetup.SettingsPanel.minimumWidth,
            idealWidth: MomRecetteSetup.SettingsPanel.idealWidth,
            minHeight: MomRecetteSetup.SettingsPanel.minimumHeight,
            idealHeight: MomRecetteSetup.SettingsPanel.idealHeight
        )
    }
}
