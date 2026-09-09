//  MixtapeApp.swift
//  Mixtape

import SwiftUI

@main
struct MixtapeApp: App {
    @AppStorage("onboarding.completed.v1") private var hasCompletedOnboarding = false

    init() {
        AudioSessionConfigurator.configureForVideoPlayback()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if hasCompletedOnboarding {
                    DashboardScreen()
                } else {
                    OnboardingScreen { hasCompletedOnboarding = true }
                }
            }
        }
    }
}
