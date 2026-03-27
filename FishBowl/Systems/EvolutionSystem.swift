import RealityKit
import Foundation

class EvolutionSystem: System {
    private static let fishQuery = EntityQuery(where: .has(LifespanComponent.self) && .has(HungerFearComponent.self))
        
    static var dependencies: [SystemDependency] { [.after(HungerFearSystem.self)] }
    
    // Evolution parameters
    private let minimumReproductionFitness: Float = 2.0
    private let maxLifespan: TimeInterval = 100.0 // seconds
    private let baseMutationRate: Float = 0.15
    private let reproductionChance: Float = 0.7
    
    // Track stats in the system itself - no entity needed
    private var evolutionStats = EvolutionStatsComponent()
    private weak var fishManager: FishManager?
    
    required init(scene: Scene) { }
    
  
    func setFishManager(_ manager: FishManager) {
        self.fishManager = manager
    }
    
    func update(context: SceneUpdateContext) {
            let fish = context.scene.performQuery(Self.fishQuery).map { $0 }
            
            for entity in fish {
                guard var lifespan = entity.components[LifespanComponent.self],
                      let hunger = entity.components[HungerFearComponent.self] else { continue }
                
                lifespan.age += context.deltaTime
                
                // Update fitness based on current state
                lifespan.fitness = calculateFitness(lifespan: lifespan, hunger: hunger)
                
                // Update best fitness stats
                if lifespan.fitness > evolutionStats.bestFitness {
                    evolutionStats.bestFitness = lifespan.fitness
                    evolutionStats.bestFitnessGeneration = lifespan.generation
                }
            
                // Check for death conditions
                if shouldDie(lifespan: lifespan, hunger: hunger) {
                    let cause = determineCauseOfDeath(lifespan: lifespan, hunger: hunger)
                    lifespan.causeOfDeath = cause
                    entity.components[LifespanComponent.self] = lifespan
                    
                    // Evolve and potentially spawn new fish
                    if lifespan.fitness >= minimumReproductionFitness && Float.random(in: 0...1) < reproductionChance {
                        evolveFromFish(entity)
                    }
                    
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
    }
    
    private func calculateFitness(lifespan: LifespanComponent, hunger: HungerFearComponent) -> Float {
        var fitness: Float = 0
        
        // Base fitness from lifespan (longer life = better)
        fitness += Float(lifespan.age) * 0.5
        
        // Bonus for maintaining good satiety
        fitness += hunger.satiety * 3.0
        
        // Bonus for having children (successful genes)
        fitness += Float(lifespan.childrenCount) * 10.0
        
        // Small penalty for old age to encourage efficient behaviors
        if lifespan.age > maxLifespan * 0.7 {
            fitness -= Float(lifespan.age - (maxLifespan * 0.7)) * 0.1
        }
        
        return max(0, fitness)
    }
    
    private func shouldDie(lifespan: LifespanComponent, hunger: HungerFearComponent) -> Bool {
        // Starvation
        if hunger.satiety <= 0 { return true }
        
        // Old age
        if lifespan.age > maxLifespan { return true }
        
        // Random accidents (very small chance)
        if Float.random(in: 0...1) < 0.0005 { return true }
        
        return false
    }
    
    private func determineCauseOfDeath(lifespan: LifespanComponent, hunger: HungerFearComponent) -> DeathCause {
        if hunger.satiety <= 0 { return .starvation }
        if lifespan.age > maxLifespan { return .oldAge }
        return .accident
    }
    
    private func evolveFromFish(_ deadFish: Entity) {
        guard let deadLifespan = deadFish.components[LifespanComponent.self],
              let deadHunger = deadFish.components[HungerFearComponent.self] else { return }
        
        // Create new fish
        Task {
            let newFish = await createNewFish()
            
            await MainActor.run {
                if var newHunger = newFish.components[HungerFearComponent.self],
                   var newLifespan = newFish.components[LifespanComponent.self] {
                    
                    // Inherit and mutate weights
                    newHunger.model.weights = mutateWeights(
                        deadHunger.model.weights,
                        mutationRate: baseMutationRate,
                        fitness: deadLifespan.fitness
                    )
                    
                    // Set up new fish lifespan
                    newLifespan.generation = deadLifespan.generation + 1
                    newLifespan.fitness = 0 // Start fresh
                    
                    newFish.components[HungerFearComponent.self] = newHunger
                    newFish.components[LifespanComponent.self] = newLifespan
                    
                    // Update parent's child count (for fitness calculation)
                    if var updatedDeadLifespan = deadFish.components[LifespanComponent.self] {
                        updatedDeadLifespan.childrenCount += 1
                        deadFish.components[LifespanComponent.self] = updatedDeadLifespan
                    }
                    
                    // Update stats
                    self.evolutionStats.totalGenerations = max(self.evolutionStats.totalGenerations, newLifespan.generation)
                    
                    // Add to scene
                    if let physicsAnchor = self.findPhysicsAnchor(in: deadFish) {
                        newFish.position = .spawnPoint(from: deadFish.position, radius: 0.3)
                        physicsAnchor.addChild(newFish)
                    }
                }
            }
        }
    }
    
    private func mutateWeights(_ weights: ModelWeights, mutationRate: Float, fitness: Float) -> ModelWeights {
        var newWeights = weights
        
        // More successful fish mutate less (their genes are proven)
        let effectiveMutationRate = mutationRate / max(1.0, fitness * 0.5)
        
        // Mutate input-to-hidden weights
        for i in 0..<newWeights.inputToHiddenWeights.count {
            if Float.random(in: 0...1) < effectiveMutationRate {
                let mutation = Float.random(in: -0.3...0.3)
                newWeights.inputToHiddenWeights[i] += mutation
                // Keep weights in reasonable range
                newWeights.inputToHiddenWeights[i] = max(-2.0, min(2.0, newWeights.inputToHiddenWeights[i]))
            }
        }
        
        // Mutate hidden-to-output weights
        for i in 0..<newWeights.hiddenToOutputWeights.count {
            if Float.random(in: 0...1) < effectiveMutationRate {
                let mutation = Float.random(in: -0.3...0.3)
                newWeights.hiddenToOutputWeights[i] += mutation
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
    
    private func createNewFish() async -> Entity {
        let newFish = await ModelFactory().createModels(ofType: .fish, count: 1).first!
        return newFish
    }
    
    // Helper method to get current stats (useful for debugging/UI)
    func getCurrentStats() -> EvolutionStatsComponent {
        return evolutionStats
    }
}



