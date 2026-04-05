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
        KrillComponent.registerComponent()
        KrillEaterComponent.registerComponent()
        HungerFearComponent.registerComponent()
        LifespanComponent.registerComponent()
        EvolutionStatsComponent.registerComponent()  // now a real ECS component
    }

    static private func registerSystems() {
        MotionSystem.registerSystem()
        WanderSystem.registerSystem()
        AnimationSpeedSystem.registerSystem()
        FlockingSystem.registerSystem()
        HungerFearSystem.registerSystem()
        PredatorSystem.registerSystem()
        EvolutionSystem.registerSystem()
        SimulationStatsSystem.registerSystem()       // bridge runs after everything
    }

    static public func register() {
        registerComponents()
        registerSystems()
    }
}

@main
struct FishBowlApp: App {
    var body: some Scene {
        // Launch window — opens the immersive space then dismisses itself
        WindowGroup(id: "ContentWindow") {
            ContentView()
                .task { FishBowlSystems.register() }
        }
        
        ImmersiveSpace(id: "ImmersiveSpace") {
            ImmersiveView()
        }
        .immersionStyle(selection: .constant(.full), in: .full)
    }
}
