//
//  FishManager.swift
//  FishBowl
//
//  Created by Brett Meader on 12/11/2025.
//

import RealityKit
import Foundation

@MainActor
class FishManager {
    
    var onFishSpawned: ((Entity) -> Void)?
    
    private let modelFactory: ModelFactory
    private weak var physicsAnchor: Entity?
    private var collisionSubscriptions: [EventSubscription] = []
    
    // Krill management
    private var krillSpawnTimer: TimeInterval = 0
    private let krillSpawnInterval: TimeInterval = 3.0  // spawn every 3 seconds
    private let maxKrillCount: Int = 30                 // enough for a bowl of radius 10
    // Krill spawn radius relative to fish centroid — keeps food in
    // the neighbourhood the fish are actually swimming in
    private let krillSpawnRadius: Float = 2.0
    
    private(set) var activeFish: [Entity] = []
    private(set) var totalFishCreated: Int = 0
    
    init(physicsAnchor: Entity) async {
        self.physicsAnchor = physicsAnchor
        self.modelFactory = await ModelFactory()
    }
    
    // MARK: - Fish Creation
    
    func createInitialFish(count: Int, attractor: Entity?, subscribeToCollisions: (Entity) -> Void) async {
        let fishes = await modelFactory.createModels(ofType: .fish, count: count)
        for (idx, fish) in fishes.enumerated() {
            fish.name = "fish_initial_\(idx)"
            fish.position = .spawnPoint(
                from: SIMD3(x: .random(in: 0..<2), y: .random(in: 0..<2), z: .random(in: 0..<2)),
                radius: 0.5
            )
            fish.components[WanderComponent.self]?.attractor = attractor
            subscribeToCollisions(fish)
            physicsAnchor?.addChild(fish)
            activeFish.append(fish)
            onFishSpawned?(fish)
        }
        totalFishCreated += fishes.count
    }
    
    func spawnGeneration(
        count: Int,
        generation: Int,
        parentData: [ParentWeightData],
        mutate: (ModelWeights, Float) -> ModelWeights
    ) async {
        removeAllFish()
        
        let newFishes = await modelFactory.createModels(ofType: .fish, count: count)
        for (index, fish) in newFishes.enumerated() {
            fish.name = "fish_gen\(generation)_\(index)"
            fish.position = .spawnPoint(from: .zero, radius: 0.5)
            
            if index < parentData.count,
               var hunger = fish.components[HungerFearComponent.self] {
                hunger.model.weights = mutate(parentData[index].weights, parentData[index].fitness)
                fish.components[HungerFearComponent.self] = hunger
            }
            
            if var lifespan = fish.components[LifespanComponent.self] {
                lifespan.generation = generation
                fish.components[LifespanComponent.self] = lifespan
            }
            
            physicsAnchor?.addChild(fish)
            activeFish.append(fish)
            onFishSpawned?(fish)
        }
        totalFishCreated += newFishes.count
    }
    
    func spawnEmergencyFish(
        count: Int,
        generation: Int,
        bestWeights: ModelWeights?,
        bestFitness: Float,
        mutate: (ModelWeights, Float) -> ModelWeights
    ) async {
        let newFishes = await modelFactory.createModels(ofType: .fish, count: count)
        for (index, fish) in newFishes.enumerated() {
            fish.name = "fish_emergency_gen\(generation)_\(index)"
            fish.position = .spawnPoint(from: .zero, radius: 0.5)
            
            if let best = bestWeights,
               var hunger = fish.components[HungerFearComponent.self] {
                hunger.model.weights = mutate(best, bestFitness)
                fish.components[HungerFearComponent.self] = hunger
            }
            
            if var lifespan = fish.components[LifespanComponent.self] {
                lifespan.generation = generation
                fish.components[LifespanComponent.self] = lifespan
            }
            
            physicsAnchor?.addChild(fish)
            activeFish.append(fish)
            onFishSpawned?(fish)
        }
        totalFishCreated += newFishes.count
    }
    
    // MARK: - Fish Removal
    
    func removeFish(_ fish: Entity) {
        fish.removeFromParent()
        activeFish.removeAll { $0 == fish }
    }
    
    func removeAllFish() {
        activeFish.forEach { $0.removeFromParent() }
        activeFish.removeAll()
    }
    
    // MARK: - Krill
    
    /// Called each frame from ImmersiveView's RealityView update closure.
    /// Rate-limited internally — only spawns every krillSpawnInterval seconds.
    func updateKrill(deltaTime: TimeInterval) async {
        krillSpawnTimer += deltaTime
        guard krillSpawnTimer >= krillSpawnInterval else { return }
        krillSpawnTimer = 0
        
        let existingKrill = physicsAnchor?.children.filter {
            $0.components[KrillComponent.self] != nil
        }.count ?? 0
        
        guard existingKrill < maxKrillCount else { return }
        
        let spawnCount = min(3, maxKrillCount - existingKrill)
        await spawnKrill(count: spawnCount, at: nil)
    }
    
    /// Spawns krill near the current fish centroid so food always appears
    /// where fish are actually swimming — within fishVisibility range.
    /// Pass a specific location for tap-to-feed, nil for auto-spawn.
    @discardableResult
    func spawnKrill(count: Int, at location: SIMD3<Float>?) async -> [Entity] {
        let foods = await modelFactory.createModels(ofType: .krill, count: count)
        
        // Calculate fish centroid for smart auto-spawn positioning
        let spawnOrigin: SIMD3<Float>
        if let location {
            spawnOrigin = location
        } else if !activeFish.isEmpty {
            // Spawn near where fish are actually swimming
            let sum = activeFish.reduce(SIMD3<Float>.zero) { $0 + $1.position }
            spawnOrigin = sum / Float(activeFish.count)
        } else {
            spawnOrigin = physicsAnchor?.position ?? .zero
        }
        
        for (index, food) in foods.enumerated() {
            food.name = "krill_\(totalFishCreated)_\(index)"
            food.position = .spawnPoint(from: spawnOrigin, radius: krillSpawnRadius)
            // Use preservingWorldTransform for tap-to-feed so position
            // is interpreted in world space, not anchor-local space
            physicsAnchor?.addChild(food, preservingWorldTransform: location != nil)
        }
        print("[Krill] spawned \(foods.count) at \(spawnOrigin) — anchor children: \(physicsAnchor?.children.count ?? 0)")
        return foods
    }
    
    // MARK: - Collision Handling
    
    func handleFishCollision(fish: Entity, other: Entity) {
        if other.components[KrillComponent.self] != nil,
           fish.components[HungerFearComponent.self] != nil {
            print("[Collision] fish ate krill — satiety before: \(fish.components[HungerFearComponent.self]?.satiety ?? -1)")
            other.removeFromParent()
            fish.components[HungerFearComponent.self]?.satiety += 1
            print("[Collision] satiety after: \(fish.components[HungerFearComponent.self]?.satiety ?? -1)")
            // Clear cached food position so all fish re-evaluate next tick
            activeFish.forEach {
                $0.components[HungerFearComponent.self]?.foodPosition = nil
            }
        } else if other.components[PredatorComponent.self] != nil {
            print(other.availableAnimations)
        }
    }
}

// MARK: - Supporting Types

/// Sendable snapshot of a parent's genetic material for safe cross-Task capture
struct ParentWeightData: Sendable {
    let weights: ModelWeights
    let fitness: Float
}
