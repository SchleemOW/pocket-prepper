//
//  Pocket_PrepperApp.swift
//  Pocket Prepper
//
//  Created by Nima Adhami on 2026-05-16.
//

import SwiftUI

@main
struct Pocket_PrepperApp: App {
    init() {
        // Disable HuggingFace Hub's network monitor which incorrectly
        // flags cellular (5G/LTE) and hotspot as "offline" due to isExpensive flag.
        // Without this, model downloads fail on any non-WiFi connection.
        setenv("CI_DISABLE_NETWORK_MONITOR", "1", 1)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
