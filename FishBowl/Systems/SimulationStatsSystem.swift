//
//  SimulationStatsSystem.swift
//  FishBowl
//
//  Created by Brett Meader on 31/03/2026.
//


import RealityKit

/// Bridges ECS state to the SwiftUI HUD.
/// Reads EvolutionStatsComponent each frame and pushes values
/// to SimulationStats.shared on the main actor.
/// This is the only place that touches SimulationStats — no other
/// system needs to know the UI layer exists.
class SimulationStatsSystem: System {

    private static let statsQuery = EntityQuery(where: .has(EvolutionStatsComponent.self))
    private static let fishQuery  = EntityQuery(where: .has(LifespanComponent.self))

    required init(scene: Scene) { }

    func update(context: SceneUpdateContext) {
        guard let statsEntity = context.scene.performQuery(Self.statsQuery).first(where: { _ in true }),
              let ecs = statsEntity.components[EvolutionStatsComponent.self]
        else { return }

        let population = context.scene.performQuery(Self.fishQuery).reduce(0) { count, _ in count + 1 }

        Task { @MainActor in
            let shared = SimulationStats.shared
            shared.currentGeneration    = ecs.totalGenerations
            shared.populationCount      = population
            shared.averageFitness       = ecs.averageFitness
            shared.bestEverFitness      = ecs.bestEverFitness
            shared.deathsThisGeneration = ecs.generationDeathCount
            shared.starvationDeaths     = ecs.starvationDeaths
            shared.oldAgeDeaths         = ecs.oldAgeDeaths
            shared.accidentDeaths       = ecs.accidentDeaths
        }
    }
}
