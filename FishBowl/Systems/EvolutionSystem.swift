//  EvolutionSystem.swift

import RealityKit
import Foundation

class EvolutionSystem: System {

    // MARK: - Parameters

    private enum Params {
        static let tickAliveReward: Float         = 0.001
        static let eatingReward: Float            = 50.0
        static let evasionReward: Float           = 0.1
        static let starvationPenalty: Float       = 20.0
        static let oldAgePenalty: Float           = 5.0
        static let childrenMultiplier: Float      = 1.5

        static let populationCollapseThreshold: Int  = 5
        static let emergencyRepopulationCount: Int   = 10
        static let generationDeathThreshold: Float   = 0.7
        static let tournamentSize: Int               = 3

        static let maxLifespan: TimeInterval      = 100.0
        static let randomDeathChance: Float       = 0.000005

        static let baseMutationRate: Float        = 0.15
        static let mutationRange: ClosedRange<Float> = -0.3...0.3
        static let weightClampRange: ClosedRange<Float> = -2.0...2.0

        static let krillSpawnInterval: TimeInterval = 3.0
        static let krillSpawnCount: Int             = 3
        static let maxKrillCount: Int               = 30
    }

    // MARK: - Queries

    private static let fishQuery      = EntityQuery(where: .has(LifespanComponent.self) && .has(HungerFearComponent.self))
    private static let predatorQuery  = EntityQuery(where: .has(PredatorComponent.self))
    private static let krillQuery     = EntityQuery(where: .has(KrillComponent.self))
    private static let statsQuery     = EntityQuery(where: .has(EvolutionStatsComponent.self))

    static var dependencies: [SystemDependency] { [.after(HungerFearSystem.self)] }

    // MARK: - State

    static weak var fishManager: FishManager?

    private var isAdvancingGeneration = false
    private var isRepopulating        = false
    private var isSpawningKrill       = false
    private var krillSpawnTimer: TimeInterval = 0

    required init(scene: Scene) { }

    // MARK: - Update

    func update(context: SceneUpdateContext) {
        guard let statsEntity = context.scene.performQuery(Self.statsQuery).first(where: { _ in true })
        else { return }

        var stats = statsEntity.components[EvolutionStatsComponent.self] ?? EvolutionStatsComponent()

        let simSpeed = SimulationStats.shared.simulationSpeed
        let dt = context.deltaTime * Double(simSpeed)

        let fish      = context.scene.performQuery(Self.fishQuery).map { $0 }
        let predators = context.scene.performQuery(Self.predatorQuery).map { $0 }

        tickKrillSpawner(deltaTime: context.deltaTime, scene: context.scene)
        checkEmergencyRepopulation(fish: fish, stats: stats)

        if shouldAdvanceGeneration(fish: fish, stats: stats) {
            advanceGeneration(survivors: fish, stats: &stats)
            statsEntity.components.set(stats)
            return
        }

        updateFish(fish, predators: predators, dt: dt, simSpeed: simSpeed, stats: &stats)

        stats.totalGenerations = max(
            stats.totalGenerations,
            fish.compactMap { $0.components[LifespanComponent.self]?.generation }.max() ?? 0
        )

        statsEntity.components.set(stats)
    }

    // MARK: - Fish Update

    private func updateFish(
        _ fish: [Entity],
        predators: [Entity],
        dt: TimeInterval,
        simSpeed: Float,
        stats: inout EvolutionStatsComponent
    ) {
        for entity in fish {
            guard var lifespan = entity.components[LifespanComponent.self],
                  let hunger   = entity.components[HungerFearComponent.self]
            else { continue }

            lifespan.age     += dt
            lifespan.fitness += Params.tickAliveReward

            if hunger.satiety > lifespan.previousSatiety {
                lifespan.fitness += Params.eatingReward
            }
            lifespan.previousSatiety = hunger.satiety

            if isNearPredator(entity, predators: predators) {
                lifespan.fitness += Params.evasionReward
            }

            updateBestFitness(lifespan: lifespan, hunger: hunger, stats: &stats)

            if shouldDie(lifespan: lifespan, hunger: hunger, speed: simSpeed) {
                kill(entity, lifespan: &lifespan, stats: &stats)
            } else {
                entity.components[LifespanComponent.self] = lifespan
            }
        }
    }

    // MARK: - Death

    private func shouldDie(lifespan: LifespanComponent, hunger: HungerFearComponent, speed: Float) -> Bool {
        hunger.satiety <= 0
            || lifespan.age > Params.maxLifespan
            || Float.random(in: 0...1) < (Params.randomDeathChance * speed)
    }

    private func kill(_ entity: Entity, lifespan: inout LifespanComponent, stats: inout EvolutionStatsComponent) {
        let cause = deathCause(for: lifespan, hunger: entity.components[HungerFearComponent.self])
        applyDeathPenalty(to: &lifespan, cause: cause)
        entity.components[LifespanComponent.self] = lifespan
        recordDeath(cause: cause, lifespan: lifespan, stats: &stats)  // pass lifespan
        print("[Evolution] Fish died: \(cause) | fitness: \(String(format: "%.1f", lifespan.fitness)) | age: \(String(format: "%.1f", lifespan.age))s")
        Task { @MainActor in Self.fishManager?.removeFish(entity) }
    }

    private func deathCause(for lifespan: LifespanComponent, hunger: HungerFearComponent?) -> DeathCause {
        if hunger?.satiety ?? 1 <= 0  { return .starvation }
        if lifespan.age > Params.maxLifespan { return .oldAge }
        return .accident
    }

    private func applyDeathPenalty(to lifespan: inout LifespanComponent, cause: DeathCause) {
        switch cause {
        case .starvation: lifespan.fitness -= Params.starvationPenalty
        case .oldAge:     lifespan.fitness -= Params.oldAgePenalty
        case .predation, .accident: break
        }
        lifespan.fitness += Float(lifespan.childrenCount) * Params.childrenMultiplier
    }

    private func recordDeath(cause: DeathCause, lifespan: LifespanComponent, stats: inout EvolutionStatsComponent) {
        stats.generationDeathCount += 1
        stats.totalFitnessAccumulated += lifespan.fitness
        stats.totalFishThisGeneration += 1
        switch cause {
        case .starvation: stats.starvationDeaths += 1
        case .oldAge:     stats.oldAgeDeaths     += 1
        case .predation, .accident: stats.accidentDeaths += 1
        }
    }
    // MARK: - Fitness Tracking

    private func updateBestFitness(
        lifespan: LifespanComponent,
        hunger: HungerFearComponent,
        stats: inout EvolutionStatsComponent
    ) {
        guard lifespan.fitness > stats.bestEverFitness else { return }
        stats.bestEverFitness  = lifespan.fitness
        stats.bestEverWeights  = hunger.model.weights.inputToHiddenWeights + hunger.model.weights.hiddenToOutputWeights
        stats.bestEverBiases   = hunger.model.weights.inputToHiddenBias    + hunger.model.weights.hiddenToOutputBias
        stats.bestFitness      = lifespan.fitness
        stats.bestFitnessGeneration = lifespan.generation
    }

    // MARK: - Generation Advancement

    private func shouldAdvanceGeneration(fish: [Entity], stats: EvolutionStatsComponent) -> Bool {
        guard !isAdvancingGeneration else { return false }
        let currentPopulation = fish.count + stats.generationDeathCount
        let threshold = Int(Float(currentPopulation) * Params.generationDeathThreshold)
        return threshold > 0 && stats.generationDeathCount >= threshold
    }

    private func advanceGeneration(survivors: [Entity], stats: inout EvolutionStatsComponent) {
        
        let survivorFitnessTotal = survivors.reduce(0.0) { $0 + ($1.components[LifespanComponent.self]?.fitness ?? 0) }
        let totalFitness = stats.totalFitnessAccumulated + survivorFitnessTotal
        let totalCount = stats.totalFishThisGeneration + survivors.count
        stats.averageFitness = totalCount > 0 ? totalFitness / Float(totalCount) : 0
        stats.totalGenerations += 1

        let parentData   = buildParentData(from: survivors)
        let nextGen      = stats.totalGenerations
        let avgFitness   = stats.averageFitness

        // Reset per-generation death counters in the component
        stats.generationDeathCount = 0
        stats.starvationDeaths     = 0
        stats.oldAgeDeaths         = 0
        stats.accidentDeaths       = 0

        isAdvancingGeneration = true
        print("[Evolution] Advancing to generation \(nextGen) — avg fitness: \(String(format: "%.1f", avgFitness))")

        Task { @MainActor in
            guard let manager = Self.fishManager else {
                print("[Evolution] ERROR: fishManager is nil — cannot spawn generation \(nextGen)")
                self.isAdvancingGeneration = false
                return
            }
            await manager.spawnGeneration(
                count: fishCount,
                generation: nextGen,
                parentData: parentData,
                mutate: { [weak self] weights, fitness in
                    self?.mutateWeights(weights, mutationRate: Params.baseMutationRate, fitness: fitness) ?? weights
                }
            )
            print("[Evolution] Generation \(nextGen) spawned")
            self.isAdvancingGeneration = false
        }
        
        // Reset accumulators for next generation
        stats.totalFitnessAccumulated = 0
        stats.totalFishThisGeneration = 0
    }

    // MARK: - Emergency Repopulation

    private func checkEmergencyRepopulation(fish: [Entity], stats: EvolutionStatsComponent) {
        guard !isRepopulating,
              fish.count > 0,
              fish.count < Params.populationCollapseThreshold
        else { return }

        isRepopulating = true
        print("[Evolution] Emergency repopulation — population: \(fish.count)")

        let bestWeights  = stats.bestEverWeights
        let bestBiases   = stats.bestEverBiases
        let bestFitness  = stats.bestEverFitness
        let generation   = stats.totalGenerations

        Task { @MainActor in
            guard let manager = Self.fishManager else {
                self.isRepopulating = false
                return
            }
            let reconstructed = reconstructWeights(
                from: bestWeights, biases: bestBiases,
                templateFish: manager.activeFish.first
            )
            await manager.spawnEmergencyFish(
                count: Params.emergencyRepopulationCount,
                generation: generation,
                bestWeights: reconstructed,
                bestFitness: bestFitness,
                mutate: { [weak self] weights, fitness in
                    self?.mutateWeights(weights, mutationRate: Params.baseMutationRate, fitness: fitness) ?? weights
                }
            )
            print("[Evolution] Emergency repopulation complete")
            self.isRepopulating = false
        }
    }

    private func reconstructWeights(from weights: [Float], biases: [Float], templateFish: Entity?) -> ModelWeights? {
        guard let hunger = templateFish?.components[HungerFearComponent.self], !weights.isEmpty else { return nil }
        let inHidCount = hunger.model.shape.inputNodesCount * hunger.model.shape.hiddenNodesCount
        let hidCount   = hunger.model.shape.hiddenNodesCount
        guard weights.count >= inHidCount, biases.count >= hidCount else { return nil }
        return ModelWeights(
            inputToHiddenWeights: Array(weights[0..<inHidCount]),
            inputToHiddenBias:    Array(biases[0..<hidCount]),
            hiddenToOutputWeights: Array(weights[inHidCount...]),
            hiddenToOutputBias:    Array(biases[hidCount...])
        )
    }

    // MARK: - Krill Spawning

    private func tickKrillSpawner(deltaTime: TimeInterval, scene: Scene) {
        guard !isSpawningKrill else { return }
        krillSpawnTimer += deltaTime
        guard krillSpawnTimer >= Params.krillSpawnInterval else { return }
        krillSpawnTimer = 0

        let existingKrill = scene.performQuery(Self.krillQuery).reduce(0) { count, _ in count + 1 }
        guard existingKrill < Params.maxKrillCount else { return }

        let spawnCount = min(Params.krillSpawnCount, Params.maxKrillCount - existingKrill)
        isSpawningKrill = true
        Task { @MainActor in
            await Self.fishManager?.spawnKrill(count: spawnCount, at: nil)
            self.isSpawningKrill = false
        }
    }

    // MARK: - Helpers

    private func isNearPredator(_ entity: Entity, predators: [Entity]) -> Bool {
        predators.contains { entity.distance(from: $0) < sharkVisibility }
    }

    private func buildParentData(from survivors: [Entity]) -> [ParentWeightData] {
        guard survivors.count >= 2 else {
                // Not enough diversity — use best ever weights instead
                return []
            }
        return (0..<fishCount).compactMap { _ in
            let tournament = (0..<min(Params.tournamentSize, survivors.count))
                .compactMap { _ in survivors.randomElement() }
            guard let winner  = tournament.max(by: { ($0.components[LifespanComponent.self]?.fitness ?? 0) < ($1.components[LifespanComponent.self]?.fitness ?? 0) }),
                  let hunger   = winner.components[HungerFearComponent.self],
                  let lifespan = winner.components[LifespanComponent.self]
            else { return nil }
            return ParentWeightData(weights: hunger.model.weights, fitness: lifespan.fitness)
        }
    }

    private func mutateWeights(_ weights: ModelWeights, mutationRate: Float, fitness: Float) -> ModelWeights {
        let effectiveRate = mutationRate / max(1.0, fitness * 0.5)
        var newWeights = weights
        newWeights.inputToHiddenWeights  = newWeights.inputToHiddenWeights.map  { mutate($0, rate: effectiveRate) }
        newWeights.hiddenToOutputWeights = newWeights.hiddenToOutputWeights.map { mutate($0, rate: effectiveRate) }
        return newWeights
    }

    private func mutate(_ weight: Float, rate: Float) -> Float {
        guard Float.random(in: 0...1) < rate else { return weight }
        return (weight + Float.random(in: Params.mutationRange)).clamped(to: Params.weightClampRange)
    }
}

private extension Float {
    func clamped(to range: ClosedRange<Float>) -> Float {
        Swift.max(range.lowerBound, Swift.min(range.upperBound, self))
    }
}
