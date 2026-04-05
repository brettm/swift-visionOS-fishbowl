//  EvolutionComponent.swift

import RealityKit
import Foundation

struct LifespanComponent: Component {
    var age: TimeInterval = 0
    var fitness: Float = 0
    var causeOfDeath: DeathCause? = nil
    var generation: Int = 0
    var childrenCount: Int = 0
    var previousSatiety: Float = 0.5
}

enum DeathCause {
    case starvation
    case predation
    case oldAge
    case accident
}

struct EvolutionStatsComponent: Component {
    var totalGenerations: Int = 0
    var averageFitness: Float = 0
    var bestFitness: Float = 0
    var bestFitnessGeneration: Int = 0

    var bestEverFitness: Float = 0
    var bestEverWeights: [Float] = []
    var bestEverBiases: [Float] = []

    var generationDeathCount: Int = 0
    var starvationDeaths: Int = 0
    var oldAgeDeaths: Int = 0
    var accidentDeaths: Int = 0
    
    var totalFitnessAccumulated: Float = 0
    var totalFishThisGeneration: Int = 0
}

extension EvolutionStatsComponent {
    /// Creates and returns a named entity carrying this component,
    /// ready to be added to the scene.
    static func makeStatsEntity() -> Entity {
        let entity = Entity()
        entity.name = "EvolutionStats"
        entity.components.set(EvolutionStatsComponent())
        return entity
    }
}
