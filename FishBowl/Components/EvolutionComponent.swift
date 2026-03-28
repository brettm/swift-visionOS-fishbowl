//
//  EvolutionComponent.swift
//  FishBowl
//
//  Created by Brett Meader on 12/11/2025.
//

import Foundation

import RealityKit

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
    var bestFitness: Float = 0
    var bestFitnessGeneration: Int = 0
    var populationHistory: [Int] = []
    
    var bestEverFitness: Float = 0
    var bestEverWeights: [Float] = []
    var bestEverBiases: [Float] = []
    var generationDeathCount: Int = 0
    var averageFitness: Float = 0
}
