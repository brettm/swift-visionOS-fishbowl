//
//  DebugStatsView.swift
//  FishBowl
//

import SwiftUI

struct DebugStatsView: View {
    var stats: SimulationStats
    @State private var isVisible: Bool = true
    
    // Timer to throttle UI updates to once per second
    @State private var displayGeneration: Int = 0
    @State private var displayPopulation: Int = 0
    @State private var displayAvgFitness: Float = 0.0
    @State private var displayBestFitness: Float = 0.0
    @State private var displayDeaths: Int = 0
    @State private var displayStarvation: Int = 0
    @State private var displayOldAge: Int = 0
    @State private var displayAccident: Int = 0
    
    let timer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()
    
    var body: some View {
        VStack(alignment: .leading) {
            Button(action: {
                isVisible.toggle()
            }) {
                Text(isVisible ? "Hide Stats" : "Show Stats")
                    .font(.caption)
            }
            .padding(.bottom, 4)
            
            if isVisible {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Gen: \(displayGeneration) | Pop: \(displayPopulation)")
                        .font(.headline)
                    
                    Text("Avg Fitness: \(String(format: "%.1f", displayAvgFitness))")
                    Text("Best Ever Fitness: \(String(format: "%.1f", displayBestFitness))")
                    
                    Divider().background(Color.white)
                    
                    Text("Deaths This Gen: \(displayDeaths)")
                    Text("Starvation: \(displayStarvation)")
                    Text("Old Age: \(displayOldAge)")
                    Text("Accident: \(displayAccident)")
                    
                    Divider().background(Color.white)
                    
                    Text("Simulation Speed")
                        .font(.caption)
                    Picker("Speed", selection: Bindable(stats).simulationSpeed) {
                        Text("1x").tag(Float(1.0))
                        Text("2x").tag(Float(2.0))
                        Text("5x").tag(Float(5.0))
                        Text("10x").tag(Float(10.0))
                    }
                    .pickerStyle(.segmented)
                }
                .padding()
                .background(Color.black.opacity(0.7))
                .cornerRadius(10)
                .foregroundColor(.white)
            }
        }
        .padding()
        .frame(maxWidth: 300)
        .onReceive(timer) { _ in
            if isVisible {
                displayGeneration = stats.currentGeneration
                displayPopulation = stats.populationCount
                displayAvgFitness = stats.averageFitness
                displayBestFitness = stats.bestEverFitness
                displayDeaths = stats.deathsThisGeneration
                displayStarvation = stats.starvationDeaths
                displayOldAge = stats.oldAgeDeaths
                displayAccident = stats.accidentDeaths
            }
        }
    }
}
