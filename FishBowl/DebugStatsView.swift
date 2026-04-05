//
//  DebugStatsView.swift
//  FishBowl
//

import SwiftUI

struct DebugStatsView: View {
    // @Observable means SwiftUI automatically re-renders when any
    // property accessed in body changes — no timer or copied vars needed
    var stats: SimulationStats
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            
            Text("🐟 Fish Bowl Evolution")
                .font(.headline)
                .padding(.bottom, 2)
            
            Divider()
            
            HStack {
                statLabel("Generation", value: "\(stats.currentGeneration)")
                Spacer()
                statLabel("Population", value: "\(stats.populationCount)")
            }
            
            HStack {
                statLabel("Avg Fitness", value: String(format: "%.1f", stats.averageFitness))
                Spacer()
                statLabel("Best Ever", value: String(format: "%.1f", stats.bestEverFitness))
            }
            
            Divider()
            
            Text("Deaths This Generation: \(stats.deathsThisGeneration)")
                .font(.subheadline)
            
            HStack(spacing: 16) {
                deathLabel("🍽️ Starved", count: stats.starvationDeaths)
                deathLabel("👴 Old Age", count: stats.oldAgeDeaths)
                deathLabel("💥 Accident", count: stats.accidentDeaths)
            }
            
            Divider()
            
            Text("Simulation Speed")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Picker("Speed", selection: Bindable(stats).simulationSpeed) {
                Text("1x").tag(Float(1.0))
                Text("2x").tag(Float(2.0))
                Text("5x").tag(Float(5.0))
                Text("10x").tag(Float(10.0))
            }
            .pickerStyle(.segmented)
        }
        .padding()
        .frame(width: 300)
    }
    
    @ViewBuilder
    private func statLabel(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
                .monospacedDigit()
        }
    }
    
    @ViewBuilder
    private func deathLabel(_ title: String, count: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("\(count)")
                .font(.body)
                .fontWeight(.medium)
                .monospacedDigit()
        }
    }
}
