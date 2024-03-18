//
//  ModelFactory.swift
//  FishBowl
//
//  Created by Brett Meader on 12/03/2024.
//

import Foundation
import RealityKit

struct EntityFactory {
    var clone: Entity
    func createClones(count: Int) async throws -> [Entity] {
        var entities: [Entity] = []
        try await withThrowingTaskGroup(of: Entity.self) { group in
            for _ in 0..<count {
                group.addTask {
                    return await clone.clone(recursive: true)
                }
            }
            for try await entity in group {
                entities += [entity]
            }
        }
        return entities
    }
}

enum ModelType {
    case fish
    case krill
    
    var modelName: String {
        return switch self {
        case .fish: "fish_clown/fish_clown_stylized_lod2_anim_ip_loop_swim_1x"
        case .krill: "krill"
        }
    }
}

class ProtoTypeBuilder {
    static func buildPrototype(modelType: ModelType) async -> Entity {
        let protoType = try! await Entity(named: modelType.modelName)
        return addComponents(toEntity: protoType, modelType: modelType)
    }
    
    @discardableResult
    static private func addComponents(toEntity entity: Entity, modelType: ModelType) -> Entity {
        let entity = switch modelType {
        case .fish: addFishComponents(toEntity: entity)
        case .krill: addKrillComponents(toEntity: entity)
        }
        return addAnimationComponents(toEntity: entity)
    }

    @discardableResult
    static private func addFishComponents(toEntity entity: Entity) -> Entity {
        entity.components[MotionComponent.self] = MotionComponent()
        entity.components[WanderComponent.self] = WanderComponent()
        entity.components[FlockingComponent.self] = FlockingComponent()
        entity.components[HungerComponent.self] = HungerComponent()
        entity.components[KrillEaterComponent.self] = KrillEaterComponent()
        return entity
    }
    
    @discardableResult
    static private func addKrillComponents(toEntity entity: Entity) -> Entity {
        addFoodComponents(toEntity: entity)
        entity.components[KrillComponent.self] = KrillComponent()
        return entity
    }

    @discardableResult
    static private func addFoodComponents(toEntity entity: Entity) -> Entity {
        entity.components[FoodComponent.self] = FoodComponent()
        return entity
    }

    // This function needs to be called after entities have been cloned
    @discardableResult
    static func addAnimationComponents(toEntity entity: Entity) -> Entity {
        if let anim = entity.availableAnimations.first {
            entity.components[AnimationSpeedComponent.self] = AnimationSpeedComponent(animationController: entity.playAnimation(anim.repeat()))
        }
        return entity
    }
}

class ModelFactory {
    private var fishFactory: EntityFactory!
    private var foodFactory: EntityFactory!
    
    public init() {
        Task {
            let foodPrototype = await ProtoTypeBuilder.buildPrototype(modelType: .krill)
            let fishProtoype = await ProtoTypeBuilder.buildPrototype(modelType: .fish)
            foodFactory = EntityFactory(clone: foodPrototype)
            fishFactory = EntityFactory(clone: fishProtoype)
        }
    }
    
    public func createModels(ofType type: ModelType, count: Int) async -> [Entity] {
        switch type {
        case .fish:
            // Unfortunately cloned entities animation components do not play so we need to re-add the animation components after cloning
            return try! await fishFactory.createClones(count: count).map{ ProtoTypeBuilder.addAnimationComponents(toEntity: $0) }
        case .krill:
            return try! await foodFactory.createClones(count: count).map{ ProtoTypeBuilder.addAnimationComponents(toEntity: $0) }
        }
    }
}

