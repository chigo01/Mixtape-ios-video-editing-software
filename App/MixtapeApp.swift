//  MixtapeApp.swift
//  Mixtape

import SwiftUI

@main
struct MixtapeApp: App {
    @AppStorage("onboarding.completed.v1") private var hasCompletedOnboarding = false
    @State private var showsSplash = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
 
    init() {
        AudioSessionConfigurator.configureForVideoPlayback()
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                Group {
                    if hasCompletedOnboarding {
                        DashboardScreen()
                    } else {
                        OnboardingScreen { hasCompletedOnboarding = true }
                    }
                }
                .allowsHitTesting(!showsSplash)
                .accessibilityHidden(showsSplash)

                if showsSplash {
                    SplashScreen()
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            .task {
                guard showsSplash else { return }
                do {
                    try await Task.sleep(for: .seconds(2))
                } catch {
                    return
                }
                withAnimation(.easeOut(duration: reduceMotion ? 0.15 : 0.45)) {
                    showsSplash = false
                }
            }
        }
    }
}
