//
//  ModelFactory.swift
//  FishBowl
//
//  Created by Brett Meader on 12/03/2024.
//

import Foundation
import RealityKit

struct EntityFactory {
    var protoType: Entity
    func createClones(count: Int) async throws -> [Entity] {
        var entities: [Entity] = []
        try await withThrowingTaskGroup(of: Entity.self) { group in
            for _ in 0..<count {
                group.addTask {
                    return await protoType.clone(recursive: true)
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

extension CollisionGroup {
    static var fishGroup = CollisionGroup(rawValue: 1 << 0)
    static var foodGroup = CollisionGroup(rawValue: 1 << 1)
}

//extension ModelType {
//    var collisionGroup: CollisionGroup {
//        return switch self {
//        case .fish: .fishGroup
//        case .krill: .foodGroup
//        }
//    }
//}

class ProtoTypeBuilder {
    static func buildPrototype(modelType: ModelType) async -> Entity {
        let protoType = try! await Entity(named: modelType.modelName)
        return addComponents(protoType, modelType: modelType)
    }
    
    @discardableResult
    static private func addComponents(_ entity: Entity, modelType: ModelType) -> Entity {
        switch modelType {
        case .fish:
            addFishComponents(entity)
//            addFoodCollisions(entity)
            addFishCollisions(entity, childName: "fish_clown_bind")
        case .krill:
            addKrillComponents(entity)
            addFoodCollisions(entity)
        }
        return addAnimationComponents(entity)
    }

    @discardableResult
    static private func addFishComponents(_ entity: Entity) -> Entity {
        entity.components[MotionComponent.self] = MotionComponent()
        entity.components[WanderComponent.self] = WanderComponent()
        entity.components[FlockingComponent.self] = FlockingComponent()
        entity.components[HungerComponent.self] = HungerComponent()
        entity.components[KrillEaterComponent.self] = KrillEaterComponent()
        return entity
    }
    
    @discardableResult
    static private func addKrillComponents(_ entity: Entity) -> Entity {
        entity.components[KrillComponent.self] = KrillComponent()
        entity.components[FoodComponent.self] = FoodComponent()
        return entity
    }

    // This function needs to be called after entities have been cloned
    @discardableResult
    static func addAnimationComponents(_ entity: Entity) -> Entity {
        if let anim = entity.availableAnimations.first {
            entity.components[AnimationSpeedComponent.self] = AnimationSpeedComponent(animationController: entity.playAnimation(anim.repeat()))
        }
        return entity
    }
    
    @discardableResult
    static func addFishCollisions(_ entity: Entity, childName: String) -> Entity {
        // Create collision shapes for all this entity's children, then replace
        // the root entity's CollisionComponent with a collider.
        entity.generateCollisionShapes(recursive: true)
        if let colliderChild = entity.findEntity(named: childName) {
            var collisionComponent = colliderChild.components[CollisionComponent.self]
            collisionComponent?.filter = CollisionFilter(group: .fishGroup, mask: [ .foodGroup ])
            entity.components[CollisionComponent.self] = collisionComponent
            colliderChild.components[CollisionComponent.self] = nil
        }
        return entity
    }
    
    @discardableResult
    static func addFoodCollisions(_ entity: Entity) -> Entity {
        let spherical = ShapeResource.generateSphere(radius: foodSize)
        var collision = CollisionComponent(shapes: [spherical])
        collision.filter = CollisionFilter(group: .foodGroup, mask: [ .fishGroup ])
        entity.components[CollisionComponent.self] = collision
        entity.generateCollisionShapes(recursive: true)
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
            foodFactory = EntityFactory(protoType: foodPrototype)
            fishFactory = EntityFactory(protoType: fishProtoype)
        }
    }
    
    public func createModels(ofType type: ModelType, count: Int) async -> [Entity] {
        switch type {
        case .fish:
            // Unfortunately cloned entities animation components do not play automatically so we need to re-add the animation components after cloning
            return try! await fishFactory.createClones(count: count).map{ ProtoTypeBuilder.addAnimationComponents( $0 )
            }
        case .krill:
            return try! await foodFactory.createClones(count: count).map{ ProtoTypeBuilder.addAnimationComponents( $0 )
            }
        }
    }
}

