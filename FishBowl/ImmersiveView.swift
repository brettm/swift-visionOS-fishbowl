//
//  ImmersiveView.swift
//
//  Created by Brett Meader on 06/03/2024.
//

import SwiftUI
import RealityKit
import RealityKitContent
import ARKit
import Combine

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

extension Cancellable {
    func addTo(_ subs: inout [AnyCancellable]) {
        subs.append(AnyCancellable(self))
    }
}

extension Optional where Wrapped: Cancellable {
    func addTo(_ subs: inout [AnyCancellable]) {
        if let subscription = self {
            subs.append(AnyCancellable(subscription))
        }
    }
}

struct ImmersiveView: View {
    @State var physicsAnchor: Entity = AnchorEntity(world: .zero)
    @State var tapAnchor: Entity = AnchorEntity(world: .zero)
    @State var worldTransform: simd_float4x4 = .init()
    @State var collisionSubscriptions: [AnyCancellable] = []
    
    @State var fishManager: FishManager?
    @State var sharks: [Entity] = []
    @State var sphere: Entity?
    @State var hudAnchor: Entity = Entity()
    
//    @State private var stats = SimulationStats()
    
    let visionPro = VisionPro()
    let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    
    var body: some View {
        RealityView { content, attachments in
            guard let immersiveContentEntity = try? await Entity(named: "Immersive", in: realityKitContentBundle) else { return }
            
            content.add(immersiveContentEntity)
            
            sphere = immersiveContentEntity.findEntity(named: "Sphere")
            sphere?.scale = .init(repeating: sphereScale)
            sphere?.components[MotionComponent.self] = MotionComponent()
            sphere?.components[WanderComponent.self] = WanderComponent()
            
            let skydome = immersiveContentEntity.findEntity(named: "Skydome")
            skydome?.scale = .init(-500, 500, 500)
            
            immersiveContentEntity.addChild(physicsAnchor)
            immersiveContentEntity.addChild(tapAnchor)
            
            // HUD anchor — positioned relative to player in the update closure
            immersiveContentEntity.addChild(hudAnchor)
            if let hudView = attachments.entity(for: "hud") {
                hudAnchor.addChild(hudView)
            }
            
            let statsEntity = EvolutionStatsComponent.makeStatsEntity()
            immersiveContentEntity.addChild(statsEntity)
            
            // Tap plane for food placement
            let tapPlane = Entity()
            tapPlane.name = "FoodPlane"
            tapPlane.components.set(CollisionComponent(shapes: [
                ShapeResource.generateBox(width: 0.2, height: 0.2, depth: 0.01)
            ]))
            tapPlane.components.set(InputTargetComponent())
            tapPlane.position = SIMD3(x: 0, y: 0, z: -0.2)
            tapAnchor.addChild(tapPlane)
            
            guard let resource = try? await EnvironmentResource(named: "ImageBasedLight") else { return }
            let iblComponent = ImageBasedLightComponent(source: .single(resource), intensityExponent: 0.3)
            immersiveContentEntity.components.set(iblComponent)
            immersiveContentEntity.components.set(ImageBasedLightReceiverComponent(imageBasedLight: immersiveContentEntity))
            
            // FishManager is the single source of truth for fish lifecycle
            let manager = await FishManager(physicsAnchor: physicsAnchor)
            fishManager = manager
            EvolutionSystem.fishManager = manager
            
            // Create initial fish — collision subscriptions stay in ImmersiveView
            // since RealityViewContent is only available here
            
            await manager.createInitialFish(count: fishCount, attractor: sphere) { fish in
                guard let scene = fish.scene else { return }
                
                scene.subscribe(to: CollisionEvents.Began.self, on: fish) { event in
                    manager.handleFishCollision(fish: event.entityA, other: event.entityB)
                }.addTo(&collisionSubscriptions)
                
                scene.subscribe(to: CollisionEvents.Updated.self, on: fish) { event in
                    manager.handleFishCollision(fish: event.entityA, other: event.entityB)
                }.addTo(&collisionSubscriptions)
            }
      
            manager.onFishSpawned = { [weak manager] fish in
                guard let manager = manager else { return }
                
                // This now works perfectly with the updated extension above
                fish.scene?.subscribe(to: CollisionEvents.Began.self, on: fish) { event in
                    manager.handleFishCollision(fish: event.entityA, other: event.entityB)
                }.addTo(&collisionSubscriptions)

                fish.scene?.subscribe(to: CollisionEvents.Updated.self, on: fish) { event in
                    manager.handleFishCollision(fish: event.entityA, other: event.entityB)
                }.addTo(&collisionSubscriptions)
            }
            
            // Shark setup
            let shark = immersiveContentEntity.findEntity(named: "Swimming_Shark")!
            ProtoTypeBuilder.addComponents(shark, modelType: .shark)
            ProtoTypeBuilder.addAnimationComponents(shark, scalar: sharkAnimationScalar)
            physicsAnchor.addChild(shark)
            shark.components[WanderComponent.self]?.attractor = sphere
            shark.components[WanderComponent.self]?.attractorOffset = SIMD3(2.0, 0.5, 0.0)
            shark.scale = .init(repeating: 3)
            sharks = [shark]
            
        } update: { content, _ in
            let playerTransform = Transform(matrix: worldTransform)
            let forward = playerTransform.matrix.columns.2
            hudAnchor.position = playerTransform.translation
                + SIMD3<Float>(-forward.x, -forward.y, -forward.z) * 0.6
                + SIMD3(0, -0.15, 0)
            // Face the player without flipping — match player orientation directly
            hudAnchor.orientation = playerTransform.rotation
            
        } attachments: {
            // HUD rendered as a SwiftUI attachment anchored to hudAnchor
            // This keeps it in the immersive space, always facing the player
            Attachment(id: "hud") {
                DebugStatsView(stats: SimulationStats.shared)
                    .frame(width: 320)
                    .glassBackgroundEffect()
            }
        }
        .onChange(of: worldTransform) { _, _ in
            let transform = Transform(matrix: worldTransform)
            tapAnchor.transform = transform
            handlePlayerTransform(transform)
        }
//        .onReceive(timer) { _ in
//            sphere?.components[MotionComponent.self]?.forces.append(
//                MotionComponent.Force(acceleration: .random(in: -5...5), multiplier: 1, name: "wander")
//            )
//        }
        .gesture(
            SpatialTapGesture()
                .targetedToAnyEntity()
                .onEnded { value in
                    guard value.entity.name == "FoodPlane" else { return }
                    Task {
                        let worldPosition: SIMD3<Float> = value.convert(
                            value.location3D,
                            from: .local,
                            to: .scene
                        )
                        await fishManager?.spawnKrill(count: 3, at: worldPosition)
                    }
                }
        )
        .task {
            await visionPro.runArkitSession()
        }
        .task {
            // Keep worldTransform updated for HUD positioning
            for await _ in AsyncStream<Void>.makeStream().stream {
                worldTransform = await visionPro.transformMatrix()
            }
        }
    }
    
    private func handlePlayerTransform(_ transform: Transform) {
        guard let spherePosition = sphere?.position else { return }
        let distance = transform.translation.distance(from: spherePosition)
        sphere?.scale = distance < sphereScale
            ? .init(-sphereScale, sphereScale, sphereScale)
            : .init(repeating: sphereScale)
    }
}
