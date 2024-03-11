//
//  FishBowlApp.swift
//
//  Created by Brett Meader on 06/03/2024.
//

import SwiftUI

enum FishBowlSystems {
    static private func registerComponents() {
        MotionComponent.registerComponent()
        WanderComponent.registerComponent()
        AnimationSpeedComponent.registerComponent()
        FlockingComponent.registerComponent()
    }
    static private func registerSystems() {
        MotionSystem.registerSystem()
        WanderSystem.registerSystem()
        AnimationSpeedSystem.registerSystem()
        FlockingSystem.registerSystem()
        
    }
    static public func register() {
        registerComponents()
        registerSystems()
    }
}

@main
struct FishBowlApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .task { FishBowlSystems.register() }
        }
        ImmersiveSpace(id: "ImmersiveSpace") {
            ImmersiveView()
        }.immersionStyle(selection: .constant(.full), in: .full)
    }
}
