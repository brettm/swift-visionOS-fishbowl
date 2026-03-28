//
//  FishManager.swift
//  FishBowl
//
//  Created by Brett Meader on 12/11/2025.
//

import RealityKit
import Foundation

@MainActor
class FishManager: ObservableObject {
    private let modelFactory = ModelFactory()
    private weak var physicsAnchor: Entity?
    private var collisionSubscriptions: [EventSubscription] = []
    
    @Published private(set) var fishCount: Int = 0
    @Published private(set) var totalFishCreated: Int = 0
    
    init(physicsAnchor: Entity) {
        self.physicsAnchor = physicsAnchor
    }
    
    func createInitialFish(count: Int) async -> [Entity] {
        let fishes = await modelFactory.createModels(ofType: .fish, count: count)
        
        for (idx, fish) in fishes.enumerated() {
            await setupFish(fish, name: "fish_initial_\(idx)")
        }
        
        await MainActor.run {
            fishCount = fishes.count
            totalFishCreated += fishes.count
        }
        
        return fishes
    }
    
    func createNewFish(from parent: Entity? = nil) async -> Entity? {
        guard let newFish = await modelFactory.createModels(ofType: .fish, count: 1).first else {
            return nil
        }
        
        let parentName = parent?.name ?? "system"
        let fishName = "fish_gen_\(totalFishCreated + 1)_from_\(parentName)"
        
        await setupFish(newFish, name: fishName)
        
        await MainActor.run {
            fishCount += 1
            totalFishCreated += 1
        }
        
        return newFish
    }
    
    private func setupFish(_ fish: Entity, name: String) async {
        await MainActor.run {
            fish.name = name
            fish.position = .spawnPoint(from: SIMD3<Float>.zero, radius: 0.5)
            
            // Add lifespan component
            fish.components[LifespanComponent.self] = LifespanComponent()
            
            // Setup collision handling
            setupCollisionHandling(for: fish)
            
            // Add to physics anchor
            physicsAnchor?.addChild(fish)
        }
    }
    
    private func setupCollisionHandling(for fish: Entity) {
        // This would need to be integrated with your existing collision handling
        // For now, we'll create a placeholder - you'll need to adapt this to your existing collision system
        
        _ = physicsAnchor?.scene
        // You would subscribe to collision events here similar to your existing code
    }
    
    func removeFish(_ fish: Entity) {
        Task { @MainActor in
            fish.removeFromParent()
            fishCount = max(0, fishCount - 1)
        }
    }
    
    func getEvolutionCandidate(from deadFish: Entity) -> Entity? {
        guard let lifespan = deadFish.components[LifespanComponent.self],
              lifespan.fitness >= 2.0 else { // minimum fitness threshold
            return nil
        }
        return deadFish
    }
}
