import RealityKit
import Foundation

class EvolutionSystem: System {
    private static let fishQuery = EntityQuery(where: .has(LifespanComponent.self) && .has(HungerFearComponent.self))
    private static let predatorQuery = EntityQuery(where: .has(PredatorComponent.self))
        
    static var dependencies: [SystemDependency] { [.after(HungerFearSystem.self)] }
    
    // Evolution parameters
    private let maxLifespan: TimeInterval = 100.0 // seconds
    private let baseMutationRate: Float = 0.15
    
    // Track stats in the system itself - no entity needed
    private var evolutionStats = EvolutionStatsComponent()
    private weak var fishManager: FishManager?
    
    required init(scene: Scene) { }
    
    func setFishManager(_ manager: FishManager) {
        self.fishManager = manager
    }
    
    func update(context: SceneUpdateContext) {
        let fish = context.scene.performQuery(Self.fishQuery).map { $0 }
        let predators = context.scene.performQuery(Self.predatorQuery).map { $0 }
        
        // 1. Emergency Repopulation Guard
        if fish.count > 0 && fish.count < 5 {
            triggerEmergencyRepopulation(in: context.scene, currentFish: fish.first!)
        }
        
        // 2. Generation Advancement Trigger
        let deathThreshold = Int(Float(fishCount) * 0.7)
        if evolutionStats.generationDeathCount >= deathThreshold {
            advanceGeneration(survivors: fish, scene: context.scene)
            return // Skip normal update for this frame while we reset
        }
        
        for entity in fish {
            guard var lifespan = entity.components[LifespanComponent.self],
                  var hunger = entity.components[HungerFearComponent.self] else { continue }
            
            lifespan.age += context.deltaTime
            
            // +0.1 per tick alive
            lifespan.fitness += 0.1
            
            // +10.0 for successfully eating food (detect satiety increase)
            if hunger.satiety > lifespan.previousSatiety {
                lifespan.fitness += 10.0
            }
            lifespan.previousSatiety = hunger.satiety
            
            // +5.0 per tick spent within predator detection range while surviving
            for predator in predators {
                if entity.distance(from: predator) < sharkVisibility {
                    lifespan.fitness += 5.0
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
            if shouldDie(lifespan: lifespan, hunger: hunger) {
                let cause = determineCauseOfDeath(lifespan: lifespan, hunger: hunger)
                lifespan.causeOfDeath = cause
                
                // Apply death penalties
                if cause == .starvation {
                    lifespan.fitness -= 20.0
                } else if cause == .oldAge {
                    lifespan.fitness -= 5.0
                }
                
                // Apply children multiplier
                lifespan.fitness += Float(lifespan.childrenCount) * 1.5
                
                entity.components[LifespanComponent.self] = lifespan
                evolutionStats.generationDeathCount += 1
                
                // Remove the dead fish
                Task { @MainActor in
                    entity.removeFromParent()
                }
            } else {
                entity.components[LifespanComponent.self] = lifespan
                entity.components[HungerFearComponent.self] = hunger
            }
        }
        
        // Update population history
        evolutionStats.populationHistory.append(fish.count)
        evolutionStats.totalGenerations = max(evolutionStats.totalGenerations,
                                            fish.compactMap { $0.components[LifespanComponent.self]?.generation }.max() ?? 0)
    }
    
    private func shouldDie(lifespan: LifespanComponent, hunger: HungerFearComponent) -> Bool {
        if hunger.satiety <= 0 { return true }
        if lifespan.age > maxLifespan { return true }
        if Float.random(in: 0...1) < 0.0005 { return true }
        return false
    }
    
    private func determineCauseOfDeath(lifespan: LifespanComponent, hunger: HungerFearComponent) -> DeathCause {
        if hunger.satiety <= 0 { return .starvation }
        if lifespan.age > maxLifespan { return .oldAge }
        return .accident
    }
    
    private func triggerEmergencyRepopulation(in scene: Scene, currentFish: Entity) {
        guard let physicsAnchor = findPhysicsAnchor(in: currentFish) else { return }
        
        Task {
            let newFishes = await ModelFactory().createModels(ofType: .fish, count: 10)
            
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
                                
                                newHunger.model.weights = self.mutateWeights(bestWeights, mutationRate: self.baseMutationRate, fitness: self.evolutionStats.bestEverFitness)
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
        
        // Tournament selection
        var parents: [Entity] = []
        if !survivors.isEmpty {
            for _ in 0..<fishCount {
                var tournament: [Entity] = []
                for _ in 0..<min(3, survivors.count) {
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
        
        // Spawn new generation
        Task {
            let newFishes = await ModelFactory().createModels(ofType: .fish, count: fishCount)
            
            await MainActor.run {
                for (index, newFish) in newFishes.enumerated() {
                    if var newHunger = newFish.components[HungerFearComponent.self],
                       var newLifespan = newFish.components[LifespanComponent.self] {
                        
                        if index < parents.count {
                            let parent = parents[index]
                            if let parentHunger = parent.components[HungerFearComponent.self],
                               let parentLifespan = parent.components[LifespanComponent.self] {
                                newHunger.model.weights = self.mutateWeights(parentHunger.model.weights, mutationRate: self.baseMutationRate, fitness: parentLifespan.fitness)
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
                newWeights.inputToHiddenWeights[i] += Float.random(in: -0.3...0.3)
                newWeights.inputToHiddenWeights[i] = max(-2.0, min(2.0, newWeights.inputToHiddenWeights[i]))
            }
        }
        
        for i in 0..<newWeights.hiddenToOutputWeights.count {
            if Float.random(in: 0...1) < effectiveMutationRate {
                newWeights.hiddenToOutputWeights[i] += Float.random(in: -0.3...0.3)
                newWeights.hiddenToOutputWeights[i] = max(-2.0, min(2.0, newWeights.hiddenToOutputWeights[i]))
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
