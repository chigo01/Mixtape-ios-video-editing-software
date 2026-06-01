//  MixtapeApp.swift
//  Mixtape

import SwiftUI

@main
struct MixtapeApp: App {
    init() {
        AudioSessionConfigurator.configureForVideoPlayback()
    }

    var body: some Scene {
        WindowGroup {
            
          
                ProjectListScreen()
                
            }
    }
}
