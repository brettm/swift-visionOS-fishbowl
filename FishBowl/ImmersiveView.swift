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
    @State var sharks: [Entity] = []
    @State var sphere: Entity?
    
    @State var stats = SimulationStats()
    
    let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            RealityView { content in
                _ = content.subscribe(to: SceneEvents.Update.self) { event in
                    Task { worldTransform = await visionPro.transformMatrix() }
                    
                    // Pass stats to systems
                    if let evoSystem = RealityViewContent.scene.first(where: { $0.type == EvolutionSystem.self }) {
                        evoSystem.setSimulationStats(stats)
                    }
                    if let motionSystem = content.systems.first(where: { $0.type == MotionSystem.self }) {
                        motionSystem.setSimulationStats(stats)
                    }
                    if let wanderSystem = content.systems.first(where: { $0.type == WanderSystem.self }) {
                        wanderSystem.setSimulationStats(stats)
                    }
                    if let hungerSystem = content.systems.first(where: { $0.type == HungerFearSystem.self }) {
                        hungerSystem.setSimulationStats(stats)
                    }
                    if let animSystem = content.systems.first(where: { $0.type == AnimationSpeedSystem.self }) {
                        animSystem.setSimulationStats(stats)
                    }
                }
                
                // Add the initial RealityKit content
                if let immersiveContentEntity = try? await Entity(named: "Immersive", in: realityKitContentBundle) {
                    content.add(immersiveContentEntity)
                    
                    sphere = immersiveContentEntity.findEntity(named: "Sphere")
                    sphere?.scale = .init(repeating: sphereScale)
                    sphere?.components[MotionComponent.self] = MotionComponent()
                    sphere?.components[WanderComponent.self] = WanderComponent()
                    
                    let skydome = immersiveContentEntity.findEntity(named: "Skydome")
                    skydome?.scale = .init(-500, 500, 500)
                    
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

                    fishes = await self.modelFactory.createModels(ofType: .fish, count: fishCount)
                    _ = fishes.enumerated().map{ (idx, fish) in
                        fish.name = "fish_clone_\(idx)"
                        fish.position = .spawnPoint(from: SIMD3(x: .random(in: 0..<2), y: .random(in: 0..<2), z: .random(in: 0..<2)), radius: 0.5)
                        content.subscribe(to: CollisionEvents.Began.self, on: fish) { event in
                            self.handleFishCollision(event: event, fish: event.entityA, other: event.entityB)
                        }.store(in: &subscriptions)
                        content.subscribe(to: CollisionEvents.Updated.self, on: fish) { event in
                            self.handleFishCollision(event: event, fish: event.entityA, other: event.entityB)
                        }.store(in: &subscriptions)
                        
                        physicsAnchor.addChild(fish)
                        fish.components[WanderComponent.self]?.attractor = sphere
                    }
                    
                    let shark = immersiveContentEntity.findEntity(named: "Swimming_Shark")!
                    ProtoTypeBuilder.addComponents(shark, modelType: .shark)
                    ProtoTypeBuilder.addAnimationComponents( shark, scalar: sharkAnimationScalar)
                    physicsAnchor.addChild(shark)
                    shark.components[WanderComponent.self]?.attractor = sphere
                    shark.scale = .init(repeating: 3)
                    sharks = [shark]
                }
            }
            .onChange(of: worldTransform, { _, _ in
                let transform = Transform(matrix: worldTransform)
                tapAnchor.transform = transform
                handlePlayerTransform(transform)
            })
            .onReceive(timer) { input in
                sphere?.components[MotionComponent.self]?.forces.append(MotionComponent.Force(acceleration: .random(in: -5...5), multiplier: 1, name: "wander"))
            }
            .gesture(
                SpatialTapGesture()
                    .targetedToAnyEntity()
                    .onEnded { value in
                        print(value.entity)
                        print(value.gestureValue.location3D)
                        Task {
                            let worldPosition: SIMD3<Float> = value.convert(value.location3D, from: .local, to: .scene)
                            await addFood(atLocation: worldPosition)
                        }
                    }
                )
            .task {
                await visionPro.runArkitSession()
            }
            
            DebugStatsView(stats: stats)
                .padding(.top, 50)
                .padding(.leading, 50)
        }
    }
    
    private func handlePlayerTransform(_ transform: Transform) {
        if let spherePosition = sphere?.position {
            let distance = transform.translation.distance(from: spherePosition)
            if distance < sphereScale {
                sphere?.scale = .init(-sphereScale, sphereScale, sphereScale)
                return
            }
            sphere?.scale = .init(repeating: sphereScale)
        }
    }
    
    private func handleFishCollision(event: Event, fish: Entity, other: Entity) {
        if other.components[KrillComponent.self] != nil,
           fish.components[HungerFearComponent.self] != nil
        {
            other.removeFromParent()
            fish.components[HungerFearComponent.self]?.satiety += 1
            _=fishes.map{
                $0.components[HungerFearComponent.self]?.foodPosition = nil
            }
        }
        else if other.components[PredatorComponent.self] != nil {
            print(other.availableAnimations)
        }
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
}
