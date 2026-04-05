//
//  SimulationStats.swift
//  FishBowl
//

import Foundation
import SwiftUI

@MainActor
@Observable
class SimulationStats {
    var currentGeneration: Int = 0
    var populationCount: Int = 0
    var averageFitness: Float = 0.0
    var bestEverFitness: Float = 0.0
    var deathsThisGeneration: Int = 0
    
    var starvationDeaths: Int = 0
    var oldAgeDeaths: Int = 0
    var accidentDeaths: Int = 0
    
    var simulationSpeed: Float = 1.0
    
    static var shared = SimulationStats()
}
