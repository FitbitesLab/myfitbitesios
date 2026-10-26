import SwiftUI
import UIKit

/// Hosts the one-stage Too preview. The Tiel preview is intentionally excluded.
struct ArcadeDemoView: View {
    let onBack: () -> Void
    var run: ArcadeRun? = nil
    @EnvironmentObject private var appState: AppState
    @State private var isPlaying = false
    @State private var creditLocked = false
    @State private var chargingLife = false
    @State private var lifeChargeError = false
    @State private var lifeMessage = ""
    @State private var canContinueLife = false
    @Environment(\.scenePhase) private var phase

    var body: some View {
        Group {
            if isPlaying {
                GameScreen(onMenu: onBack, demoMode: true, creditBalance: appState.arcadeCredits?.total, creditLocked: creditLocked, onLifeLost: lifeLost, onNewRun: onBack)
            } else {
                ZStack(alignment: .topLeading) {
                    tooTitle
                    HStack {
                        Button(action: onBack) { Label("My Arcade", systemImage: "chevron.left") }
                            .accessibilityIdentifier("arcade-demo-back")
                        Spacer()
                        Text("DEMO").font(.system(size: 12, weight: .black, design: .monospaced)).tracking(2)
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(16)
                    .background(LinearGradient(colors: [.black.opacity(0.65), .clear], startPoint: .top, endPoint: .bottom))
                }
            }
        }
        .allowsHitTesting(!creditLocked)
        .overlay {
            if creditLocked {
                ZStack {
                    Color.black.opacity(0.7).ignoresSafeArea()
                    VStack(spacing: 14) {
                        Text("LIFE LOST").font(.system(size: 26, weight: .black, design: .rounded))
                        Text(lifeMessage).multilineTextAlignment(.center)
                        Text(appState.arcadeCredits.map { "CREDITS \($0.total)" } ?? "Updating credits…")
                            .font(.system(size: 18, weight: .heavy, design: .monospaced))
                        if chargingLife { ProgressView().tint(.white) }
                        else if lifeChargeError {
                            Button("Retry credit sync") { Task { await settleLife() } }
                        } else if canContinueLife {
                            Button("Continue") { creditLocked = false }
                        }
                        if !chargingLife { Button("Back to My Arcade", action: onBack) }
                    }.foregroundStyle(.white).padding(28)
                        .background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 22))
                        .buttonStyle(.borderedProminent).tint(.teal)
                }
            }
        }
        .background(.black)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onAppear {
            ArcadeOrientation.set(.landscape)
            TielSoundEffects.preload()
        }
        .onDisappear {
            TielSoundEffects.stopAll()
            ArcadeOrientation.set(.portrait)
        }
        .onChange(of: phase) { _, value in
            if value != .active { TielSoundEffects.stopAll() }
        }
        #if DEBUG
        .task {
            if ProcessInfo.processInfo.arguments.contains("--arcade-demo-smoke") { await smokeTest() }
        }
        #endif
    }

    private func lifeLost() {
        guard !creditLocked else { return }
        creditLocked = true; canContinueLife = false
        lifeMessage = "Updating your credits…"
        Task { await settleLife() }
    }

    @MainActor
    private func settleLife() async {
        guard !chargingLife else { return }
        chargingLife = true; lifeChargeError = false
        defer { chargingLife = false }
        do {
            guard let run else { throw NSError(domain: "Arcade", code: 400) }
            canContinueLife = try await appState.chargeArcadeLife(runID: run.id)
            lifeMessage = canContinueLife ? "1 credit used." : "No credits available to continue."
        } catch {
            lifeChargeError = true
            lifeMessage = "Couldn’t sync your credit. Retry to continue."
        }
    }

    private var tooTitle: some View {
        GeometryReader { proxy in
            ZStack {
                Image("neighborhood-panorama")
                    .resizable().scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height).clipped()
                LinearGradient(colors: [.black.opacity(0.25), .black.opacity(0.8)], startPoint: .top, endPoint: .bottom)
                VStack(spacing: 16) {
                    Spacer()
                    Text("TOO").font(.system(size: 68, weight: .black, design: .rounded))
                        .foregroundStyle(.yellow)
                    Text("BEAT THEM ALL").font(.system(size: 24, weight: .heavy, design: .rounded)).tracking(3)
                    Text("One stage. Three waves. Bring your best bop.")
                        .font(.system(size: 14, weight: .medium))
                    Button { TielSoundEffects.select { isPlaying = true } } label: {
                        Text("PRESS START").font(.system(size: 24, weight: .heavy, design: .monospaced))
                            .tracking(4).padding(16)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("too-home-start")
                    Spacer()
                }.foregroundStyle(.white)
            }.ignoresSafeArea()
        }
    }

    #if DEBUG
    @MainActor
    private func smokeTest() async {
        var results: [String: Bool] = [:]
        try? await Task.sleep(for: .seconds(3))
        results["landscape"] = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first?.interfaceOrientation.isLandscape == true
        isPlaying = true
        try? await Task.sleep(for: .seconds(3))
        results["tooRunning"] = NavigationProbe.too?.view != nil && NavigationProbe.too?.isPaused == false
        results["tooStageLimited"] = NavigationProbe.too?.maximumStage == 1
        isPlaying = false
        try? await Task.sleep(for: .seconds(1))
        results["sceneReleased"] = NavigationProbe.too == nil
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("too-demo-smoke.json")
        try? JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys]).write(to: url)
    }
    #endif
}

final class MyFitbitesAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        ArcadeOrientation.mask
    }
}

@MainActor
enum ArcadeOrientation {
    static var mask: UIInterfaceOrientationMask = .portrait
    static func set(_ value: UIInterfaceOrientationMask) {
        mask = value
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for window in scene.windows {
                var controller = window.rootViewController
                controller?.setNeedsUpdateOfSupportedInterfaceOrientations()
                while let presented = controller?.presentedViewController {
                    presented.setNeedsUpdateOfSupportedInterfaceOrientations()
                    controller = presented
                }
            }
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: value))
        }
    }
}
