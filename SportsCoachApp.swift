//
//  SportsCoachApp.swift
//  SportsCoach
//
//  Created by wesley on 2024/6/2.
//

import SwiftUI
import SwiftData

@available(iOS 17, *)
@main
struct SportsCoachApp: App {
        init() {
                clearTemporaryDirectory()
        }
        var body: some Scene {
                WindowGroup {
                        ContentView()
                }
        }
}
