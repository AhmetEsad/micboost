//
//  micboostApp.swift
//  micboost
//
//  Created by ahmet on 28/11/2025.
//

import SwiftUI

@main
struct micboostApp: App {
    @StateObject private var engine = MicEQEngine()
    
    var body: some Scene {
        MenuBarExtra("Mic Boost", systemImage: engine.isRunning ? "mic.fill" : "mic.slash") {
            ContentView(engine: engine)
        }
        .menuBarExtraStyle(.window)
    }
}
