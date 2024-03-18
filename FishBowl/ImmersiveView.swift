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


struct ImmersiveView: View {
    
    @State var foodAnchor: Entity = AnchorEntity(world: .zero)
    @State var tapAnchor: Entity = AnchorEntity(world: .zero)
    @State var worldTransform: simd_float4x4 = .init()
    
    let visionPro = VisionPro()
    let modelFactory = ModelFactory()
    
    var body: some View {
        RealityView { content in
            _ = content.subscribe(to: SceneEvents.Update.self) { _ in
                Task {
                    worldTransform = await visionPro.transformMatrix()
//                    let x = await visionPro.transformMatrix().columns.0.x
//                    let y = await visionPro.transformMatrix().columns.1.y
//                    let z = await visionPro.transformMatrix().columns.2.z
//                    print(String(format: "%.2f, %.2f, %.2f", x, y, z))
                }
            }
            // Add the initial RealityKit content
            if let immersiveContentEntity = try? await Entity(named: "Immersive", in: realityKitContentBundle) {
                content.add(immersiveContentEntity)
                
                immersiveContentEntity.addChild(foodAnchor)
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
                var fishAnchor = AnchorEntity(world: .zero)
                immersiveContentEntity.addChild(fishAnchor)
                
                var fishCount = 100
                var fishes = await self.modelFactory.createModels(ofType: .fish, count: fishCount)
                _ = fishes.map{ fish in
                    fish.position = .spawnPoint(from: SIMD3(x: 0, y: 0.5, z: 0), radius: 0.5)
                    fishAnchor.addChild(fish)
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
    
    func addFood(atLocation location: SIMD3<Float>) async {
        guard let food = await modelFactory.createModels(ofType: .krill, count: 1).first else { return }
        await MainActor.run {
            food.position = location
            foodAnchor.addChild(food, preservingWorldTransform: true)
        }
        
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
