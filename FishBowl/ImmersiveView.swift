//
//  ImmersiveView.swift
//
//  Created by Brett Meader on 06/03/2024.
//

import SwiftUI
import RealityKit
import RealityKitContent
import ARKit

@Observable class VisionPro {
    let session = ARKitSession()
    let worldTracking = WorldTrackingProvider()
    
    func transformMatrix() async -> simd_float4x4 {
        guard let deviceAnchor = worldTracking.queryDeviceAnchor(atTimestamp: .zero)
        else { return .init() }
        return deviceAnchor.originFromAnchorTransform
    }
    
    func runArkitSession() async {
        Task { try? await session.run([worldTracking]) }
    }
}

extension EventSubscription {
    func store(in subs: inout [EventSubscription]) {
        subs.append(self)
    }
}

struct ImmersiveView: View {
    @State var physicsAnchor: Entity = AnchorEntity(world: .zero)
    @State var tapAnchor: Entity = AnchorEntity(world: .zero)
    @State var worldTransform: simd_float4x4 = .init()
    @State var subscriptions = [EventSubscription]()
    
    let visionPro = VisionPro()
    let modelFactory = ModelFactory()
    
    @State var fishes: [Entity] = []
    
    var body: some View {
        RealityView { content in
            _ = content.subscribe(to: SceneEvents.Update.self) { _ in
                Task {
                    worldTransform = await visionPro.transformMatrix()
                }
            }
            // Add the initial RealityKit content
            if let immersiveContentEntity = try? await Entity(named: "Immersive", in: realityKitContentBundle) {
                content.add(immersiveContentEntity)
                
                immersiveContentEntity.addChild(physicsAnchor)
                immersiveContentEntity.addChild(tapAnchor)
                
                let tapPlane = Entity()
                let collisionComponent = CollisionComponent(shapes: [ShapeResource.generateBox(width: 0.2, height: 0.2, depth: 0.01)])
                tapPlane.name = "FoodPlane"
                tapPlane.components.set(collisionComponent)
                tapPlane.components.set(InputTargetComponent())
                tapPlane.position = SIMD3(x: 0, y: 0, z: -0.2)
                tapAnchor.addChild(tapPlane)
                
                // Add an ImageBasedLight for the immersive content
                guard let resource = try? await EnvironmentResource(named: "ImageBasedLight") else { return }
                let iblComponent = ImageBasedLightComponent(source: .single(resource), intensityExponent: 0.3)
                immersiveContentEntity.components.set(iblComponent)
                immersiveContentEntity.components.set(ImageBasedLightReceiverComponent(imageBasedLight: immersiveContentEntity))

                // Put skybox here.  See example in World project available at
                // https://developer.apple.com/
//                let fishAnchor = AnchorEntity(world: .zero)
//                immersiveContentEntity.addChild(fishAnchor)
                
                fishes = await self.modelFactory.createModels(ofType: .fish, count: fishCount)
                _ = fishes.enumerated().map{ (idx, fish) in
                    fish.name = "fish_clone_\(idx)"
                    fish.position = .spawnPoint(from: SIMD3(x: 0, y: 0, z: 0), radius: 0.5)
                    fish.position.y = Float.random(in: 0..<0.5)
                    content.subscribe(to: CollisionEvents.Began.self, on: fish) { event in
                        self.handleFishCollision(event: event, fish: event.entityA, other: event.entityB)
                    }.store(in: &subscriptions)
                    content.subscribe(to: CollisionEvents.Updated.self, on: fish) { event in
                        self.handleFishCollision(event: event, fish: event.entityA, other: event.entityB)
                    }.store(in: &subscriptions)
                    
                    physicsAnchor.addChild(fish)
                }
            }
        }
        .onChange(of: worldTransform, { _, _ in
            tapAnchor.transform = Transform(matrix: worldTransform)
        })
        .gesture(
            SpatialTapGesture()
//                        .targetedToEntity(tapAnchor)
                .targetedToAnyEntity()
                .onEnded { value in
                    print(value.entity)
                    print(value.gestureValue.location3D)
                    Task {
                        let worldPosition: SIMD3<Float> = value.convert(value.location3D, from: .local, to: .scene)
                        await addFood(atLocation: worldPosition)
                    }
//                           playAnimation(entity: foodAnchor)
                }
            )
        .task {
            await visionPro.runArkitSession()
        }
    }
    
    private func handleFishCollision(event: Event, fish: Entity, other: Entity) {

        if
           other.components[KrillComponent.self] != nil,
           var hungerComponent = fish.components[HungerComponent.self],
           let target = hungerComponent.currentFoodTarget,
           other == target {
            // This fish got to its food target - eat it.
            other.removeFromParent()
            fish.components[HungerComponent.self]?.satiety = 1.0
            // Any other fish that was gunning for this same food is out of luck.
            fishes = fishes.map{
                $0.components[HungerComponent.self]?.currentFoodTarget = nil
                return $0
            }
        }
//        else if other is HasSceneUnderstanding,
//           other.components.has(CollisionComponent.self),
//           var motion = fish.components[MotionComponent.self] {
//            
//            print("\(fish.name)  \(other.name) ")

//            if let collisionUpdated = (event as? CollisionEvents.Began) {
//
//                // Clear out all the other forces, just for this frame, and send
//                // the fish away from this real-world object.
//                motion.forces.removeAll()
//                motion.velocity = .zero
//                var steer = SIMD3<Float>.zero
//                let results = scene.raycast(origin: fish.position,
//                                            direction: normalize(fish.position.vector(to: collisionUpdated.position)),
//                                            length: 1.0,
//                                            query: .nearest,
//                                            mask: .sceneUnderstanding,
//                                            relativeTo: nil)
//
//                if let result = results.first {
//                    steer = normalize(result.normal)
//
//                    motion.forces.append(MotionComponent.Force(acceleration: steer, multiplier: settings.bonkWeight, name: "bonk"))
//                    
//                    fish.components[MotionComponent.self] = motion
//                }
//            }
//        }
    }
    
    @discardableResult
    func addFood(atLocation location: SIMD3<Float>) async -> Entity? {
        guard let food = await modelFactory.createModels(ofType: .krill, count: 1).first else { return nil }
        Task { @MainActor in
            food.name = "krill_\(physicsAnchor.children.count)"
            food.position = location
            physicsAnchor.addChild(food, preservingWorldTransform: true)
        }
        return food
    }
    
    func playAnimation(entity: Entity) {
            let goUp = FromToByAnimation<Transform>(
                name: "goUp",
                from: .init(scale: .init(repeating: 1), translation: entity.position),
                to: .init(scale: .init(repeating: 1), translation: entity.position + .init(x: 0, y: 0.4, z: 0)),
                duration: 0.2,
                timing: .easeOut,
                bindTarget: .transform
            )

            let pause = FromToByAnimation<Transform>(
                name: "pause",
                from: .init(scale: .init(repeating: 1), translation: entity.position + .init(x: 0, y: 0.4, z: 0)),
                to: .init(scale: .init(repeating: 1), translation: entity.position + .init(x: 0, y: 0.4, z: 0)),
                duration: 0.1,
                bindTarget: .transform
            )

            let goDown = FromToByAnimation<Transform>(
                name: "goDown",
                from: .init(scale: .init(repeating: 1), translation: entity.position + .init(x: 0, y: 0.4, z: 0)),
                to: .init(scale: .init(repeating: 1), translation: entity.position),
                duration: 0.2,
                timing: .easeOut,
                bindTarget: .transform
            )

            let goUpAnimation = try! AnimationResource
                .generate(with: goUp)

            let pauseAnimation = try! AnimationResource
                .generate(with: pause)

            let goDownAnimation = try! AnimationResource
                .generate(with: goDown)

            let animation = try! AnimationResource.sequence(with: [goUpAnimation, pauseAnimation, goDownAnimation])

            entity.playAnimation(animation, transitionDuration: 0.5)
        }
}

//#Preview {
//    ImmersiveView()
//        .previewLayout(.sizeThatFits)
//}
