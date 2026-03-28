import RealityKit
import Foundation

class EvolutionSystem: System {
    
    // MARK: - Evolution Parameters
    private enum Params {
        // Fitness Function
        static let tickAliveReward: Float = 0.1
        static let eatingReward: Float = 10.0
        static let evasionReward: Float = 5.0
        static let starvationPenalty: Float = 20.0
        static let oldAgePenalty: Float = 5.0
        static let childrenMultiplier: Float = 1.5
        
        // Population & Generation
        static let populationCollapseThreshold: Int = 5
        static let emergencyRepopulationCount: Int = 10
        static let generationDeathThreshold: Float = 0.7
        static let tournamentSize: Int = 3
        
        // Lifespan & Death
        static let maxLifespan: TimeInterval = 100.0 // seconds
        static let randomDeathChance: Float = 0.0005
        
        // Mutation
        static let baseMutationRate: Float = 0.15
        static let mutationRange: ClosedRange<Float> = -0.3...0.3
        static let weightClampRange: ClosedRange<Float> = -2.0...2.0
    }
    
    private static let fishQuery = EntityQuery(where: .has(LifespanComponent.self) && .has(HungerFearComponent.self))
    private static let predatorQuery = EntityQuery(where: .has(PredatorComponent.self))
        
    static var dependencies: [SystemDependency] { [.after(HungerFearSystem.self)] }
    
    // Track stats in the system itself - no entity needed
    private var evolutionStats = EvolutionStatsComponent()
    private weak var fishManager: FishManager?
    private var simulationStats: SimulationStats?
    
    required init(scene: Scene) { }
    
    func setFishManager(_ manager: FishManager) {
        self.fishManager = manager
    }
    
    func setSimulationStats(_ stats: SimulationStats) {
        self.simulationStats = stats
    }
    
    func update(context: SceneUpdateContext) {
        let speed = simulationStats?.simulationSpeed ?? 1.0
        let dt = context.deltaTime * Double(speed)
        
        let fish = context.scene.performQuery(Self.fishQuery).map { $0 }
        let predators = context.scene.performQuery(Self.predatorQuery).map { $0 }
        
        // 1. Emergency Repopulation Guard
        if fish.count > 0 && fish.count < Params.populationCollapseThreshold {
            triggerEmergencyRepopulation(in: context.scene, currentFish: fish.first!)
        }
        
        // 2. Generation Advancement Trigger
        let deathThreshold = Int(Float(fishCount) * Params.generationDeathThreshold)
        if evolutionStats.generationDeathCount >= deathThreshold {
            advanceGeneration(survivors: fish, scene: context.scene)
            updateSharedStats(population: fish.count)
            return // Skip normal update for this frame while we reset
        }
        
        for entity in fish {
            guard var lifespan = entity.components[LifespanComponent.self],
                  let hunger = entity.components[HungerFearComponent.self] else { continue }
            
            lifespan.age += dt
            
            // Reward per tick alive
            lifespan.fitness += Params.tickAliveReward * Float(speed)
            
            // Reward for successfully eating food (detect satiety increase)
            if hunger.satiety > lifespan.previousSatiety {
                lifespan.fitness += Params.eatingReward
            }
            lifespan.previousSatiety = hunger.satiety
            
            // Reward per tick spent within predator detection range while surviving
            for predator in predators {
                if entity.distance(from: predator) < sharkVisibility {
                    lifespan.fitness += Params.evasionReward * Float(speed)
                    break
                }
            }
            
            // Update best fitness stats
            if lifespan.fitness > evolutionStats.bestEverFitness {
                evolutionStats.bestEverFitness = lifespan.fitness
                evolutionStats.bestEverWeights = hunger.model.weights.inputToHiddenWeights + hunger.model.weights.hiddenToOutputWeights
                evolutionStats.bestEverBiases = hunger.model.weights.inputToHiddenBias + hunger.model.weights.hiddenToOutputBias
            }
            
            if lifespan.fitness > evolutionStats.bestFitness {
                evolutionStats.bestFitness = lifespan.fitness
                evolutionStats.bestFitnessGeneration = lifespan.generation
            }
        
            // Check for death conditions
            if shouldDie(lifespan: lifespan, hunger: hunger, speed: speed) {
                let cause = determineCauseOfDeath(lifespan: lifespan, hunger: hunger)
                lifespan.causeOfDeath = cause
                
                // Apply death penalties
                if cause == .starvation {
                    lifespan.fitness -= Params.starvationPenalty
                    simulationStats?.starvationDeaths += 1
                } else if cause == .oldAge {
                    lifespan.fitness -= Params.oldAgePenalty
                    simulationStats?.oldAgeDeaths += 1
                } else {
                    simulationStats?.accidentDeaths += 1
                }
                
                // Apply children multiplier
                lifespan.fitness += Float(lifespan.childrenCount) * Params.childrenMultiplier
                
                entity.components[LifespanComponent.self] = lifespan
                evolutionStats.generationDeathCount += 1
                
                // Remove the dead fish
                Task { @MainActor in
                    entity.removeFromParent()
                }
            } else {
                entity.components[LifespanComponent.self] = lifespan
            }
        }
        
        // Update population history
        evolutionStats.populationHistory.append(fish.count)
        evolutionStats.totalGenerations = max(evolutionStats.totalGenerations,
                                            fish.compactMap { $0.components[LifespanComponent.self]?.generation }.max() ?? 0)
                                            
        updateSharedStats(population: fish.count)
    }
    
    private func updateSharedStats(population: Int) {
        guard let stats = simulationStats else { return }
        stats.currentGeneration = evolutionStats.totalGenerations
        stats.populationCount = population
        stats.averageFitness = evolutionStats.averageFitness
        stats.bestEverFitness = evolutionStats.bestEverFitness
        stats.deathsThisGeneration = evolutionStats.generationDeathCount
    }
    
    private func shouldDie(lifespan: LifespanComponent, hunger: HungerFearComponent, speed: Float) -> Bool {
        if hunger.satiety <= 0 { return true }
        if lifespan.age > Params.maxLifespan { return true }
        if Float.random(in: 0...1) < (Params.randomDeathChance * speed) { return true }
        return false
    }
    
    private func determineCauseOfDeath(lifespan: LifespanComponent, hunger: HungerFearComponent) -> DeathCause {
        if hunger.satiety <= 0 { return .starvation }
        if lifespan.age > Params.maxLifespan { return .oldAge }
        return .accident
    }
    
    private func triggerEmergencyRepopulation(in scene: Scene, currentFish: Entity) {
        guard let physicsAnchor = findPhysicsAnchor(in: currentFish) else { return }
        
        Task {
            let newFishes = await ModelFactory().createModels(ofType: .fish, count: Params.emergencyRepopulationCount)
            
            await MainActor.run {
                for newFish in newFishes {
                    if var newHunger = newFish.components[HungerFearComponent.self],
                       var newLifespan = newFish.components[LifespanComponent.self] {
                        
                        // Use best ever weights if available
                        if !self.evolutionStats.bestEverWeights.isEmpty {
                            let inHidCount = newHunger.model.shape.inputNodesCount * newHunger.model.shape.hiddenNodesCount
                            let hidOutCount = newHunger.model.shape.hiddenNodesCount * newHunger.model.shape.outputNodesCount
                            
                            if self.evolutionStats.bestEverWeights.count == inHidCount + hidOutCount {
                                let inHidWeights = Array(self.evolutionStats.bestEverWeights[0..<inHidCount])
                                let hidOutWeights = Array(self.evolutionStats.bestEverWeights[inHidCount...])
                                
                                let inHidBias = Array(self.evolutionStats.bestEverBiases[0..<newHunger.model.shape.hiddenNodesCount])
                                let hidOutBias = Array(self.evolutionStats.bestEverBiases[newHunger.model.shape.hiddenNodesCount...])
                                
                                let bestWeights = ModelWeights(
                                    inputToHiddenWeights: inHidWeights,
                                    inputToHiddenBias: inHidBias,
                                    hiddenToOutputWeights: hidOutWeights,
                                    hiddenToOutputBias: hidOutBias
                                )
                                
                                newHunger.model.weights = self.mutateWeights(bestWeights, mutationRate: Params.baseMutationRate, fitness: self.evolutionStats.bestEverFitness)
                            }
                        }
                        
                        newLifespan.generation = self.evolutionStats.totalGenerations
                        newFish.components[HungerFearComponent.self] = newHunger
                        newFish.components[LifespanComponent.self] = newLifespan
                        
                        newFish.position = .spawnPoint(from: .zero, radius: 0.5)
                        physicsAnchor.addChild(newFish)
                    }
                }
            }
        }
    }
    
    private func advanceGeneration(survivors: [Entity], scene: Scene) {
        guard let firstFish = survivors.first, let physicsAnchor = findPhysicsAnchor(in: firstFish) else { return }
        
        // Calculate average fitness
        let totalFitness = survivors.reduce(0) { $0 + ($1.components[LifespanComponent.self]?.fitness ?? 0) }
        evolutionStats.averageFitness = survivors.isEmpty ? 0 : totalFitness / Float(survivors.count)
        
        evolutionStats.totalGenerations += 1
        evolutionStats.generationDeathCount = 0
        
        // Reset death counters for the new generation
        simulationStats?.starvationDeaths = 0
        simulationStats?.oldAgeDeaths = 0
        simulationStats?.accidentDeaths = 0
        
        // Tournament selection
        var parents: [Entity] = []
        if !survivors.isEmpty {
            for _ in 0..<fishCount {
                var tournament: [Entity] = []
                for _ in 0..<min(Params.tournamentSize, survivors.count) {
                    if let randomFish = survivors.randomElement() {
                        tournament.append(randomFish)
                    }
                }
                
                let winner = tournament.max(by: { 
                    ($0.components[LifespanComponent.self]?.fitness ?? 0) < ($1.components[LifespanComponent.self]?.fitness ?? 0) 
                })
                
                if let winner = winner {
                    parents.append(winner)
                }
            }
        }
        
        // Remove old generation
        for fish in survivors {
            Task { @MainActor in
                fish.removeFromParent()
            }
        }
        
        let selectedParents = parents
        
        // Spawn new generation
        Task {
            let newFishes = await ModelFactory().createModels(ofType: .fish, count: fishCount)
            
            await MainActor.run {
                for (index, newFish) in newFishes.enumerated() {
                    if var newHunger = newFish.components[HungerFearComponent.self],
                       var newLifespan = newFish.components[LifespanComponent.self] {
                        
                        if index < selectedParents.count {
                            let parent = selectedParents[index]
                            if let parentHunger = parent.components[HungerFearComponent.self],
                               let parentLifespan = parent.components[LifespanComponent.self] {
                                newHunger.model.weights = self.mutateWeights(parentHunger.model.weights, mutationRate: Params.baseMutationRate, fitness: parentLifespan.fitness)
                            }
                        }
                        
                        newLifespan.generation = self.evolutionStats.totalGenerations
                        newFish.components[HungerFearComponent.self] = newHunger
                        newFish.components[LifespanComponent.self] = newLifespan
                        
                        newFish.position = .spawnPoint(from: .zero, radius: 0.5)
                        physicsAnchor.addChild(newFish)
                    }
                }
            }
        }
    }
    
    private func mutateWeights(_ weights: ModelWeights, mutationRate: Float, fitness: Float) -> ModelWeights {
        var newWeights = weights
        let effectiveMutationRate = mutationRate / max(1.0, fitness * 0.5)
        
        for i in 0..<newWeights.inputToHiddenWeights.count {
            if Float.random(in: 0...1) < effectiveMutationRate {
                newWeights.inputToHiddenWeights[i] += Float.random(in: Params.mutationRange)
                newWeights.inputToHiddenWeights[i] = max(Params.weightClampRange.lowerBound, min(Params.weightClampRange.upperBound, newWeights.inputToHiddenWeights[i]))
            }
        }
        
        for i in 0..<newWeights.hiddenToOutputWeights.count {
            if Float.random(in: 0...1) < effectiveMutationRate {
                newWeights.hiddenToOutputWeights[i] += Float.random(in: Params.mutationRange)
                newWeights.hiddenToOutputWeights[i] = max(Params.weightClampRange.lowerBound, min(Params.weightClampRange.upperBound, newWeights.hiddenToOutputWeights[i]))
            }
        }
        
        return newWeights
    }
    
    private func findPhysicsAnchor(in entity: Entity) -> Entity? {
        var current = entity
        while let parent = current.parent {
            if parent.name == "physicsAnchor" || parent.components[PhysicsBodyComponent.self] != nil {
                return parent
            }
            current = parent
        }
        return nil
    }
    
    func getCurrentStats() -> EvolutionStatsComponent {
        return evolutionStats
    }
}
