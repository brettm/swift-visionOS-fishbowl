/*
 Copyright © 2021 Apple Inc.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 */
import RealityKit

// Use the evolved generated weights derived from the simulation from the project https://github.com/brettm/swift-neuroevolution
//
struct HungerFearComponent: RealityKit.Component {
    var foodPosition: SIMD3<Float>?
    var satiety: Float
    var model: OrganismModel
    init(foodPosition: SIMD3<Float>? = nil, satiety: Float = 0.5, model: OrganismModel) {
        self.foodPosition = foodPosition
        self.satiety = satiety
        self.model = model
    }
}

//struct FoodComponent: RealityKit.Component { }
struct KrillEaterComponent: RealityKit.Component { }
struct KrillComponent: RealityKit.Component { }

class HungerFearSystem: RealityKit.System {
    required init(scene: RealityKit.Scene) { }

    static var dependencies: [SystemDependency] = [.after(FlockingSystem.self), .before(MotionSystem.self)]

    static let krillEaterQuery = EntityQuery(where: .has(HungerFearComponent.self) && .has(MotionComponent.self) && .has(KrillEaterComponent.self))
    static let krillQuery = EntityQuery(where: .has(KrillComponent.self))
    static let predatorQuery = EntityQuery(where: .has(PredatorComponent.self) && .has(MotionComponent.self))

    func update(context: SceneUpdateContext) {

        let krill = context.scene.performQuery(Self.krillQuery).map { $0 }
        guard !(krill.isEmpty) else { return }
        
        let eaters = context.scene.performQuery(Self.krillEaterQuery).map { $0 }
        let predators = context.scene.performQuery(Self.predatorQuery).map { $0 }
        
        for eater in eaters {
            guard
                var motion = eater.components[MotionComponent.self],
                var hungerComponent = eater.components[HungerFearComponent.self]
            else { continue }

            // Fish are opportunists so always pick the closest food!
            let distances = krill.indices.map{ (eater.distance(from: krill[$0]), $0) }.filter{ $0.0 < fishVisibility }.sorted(by: <)
            if let distance = distances.first {
                hungerComponent.foodPosition = krill[distance.1].position
            }
            
            let hungerChange = hungerRate * Float(context.deltaTime * context.deltaTime)
            hungerComponent.satiety = max(hungerComponent.satiety - hungerChange, 0)
            
            // If there's no food available, there's nothing to do.
            var nTargetDirection: SIMD3<Float> = .zero
            var targetDistance: Float = -1.0
            if let foodPosition = hungerComponent.foodPosition {
                let targetDir = foodPosition - eater.position
                targetDistance = targetDir.magnitude() / 100.0
                nTargetDirection = normalize(targetDir)
            }
            
            // Steer the fish toward the food using our learned model
            var nFearDirection: SIMD3<Float> = .zero
            var fearDistance: Float = -1.0
            if let fearPosition = predators.first?.position {
                let fearDirection = fearPosition - eater.position
                fearDistance = fearDirection.magnitude() / 100.0
                nFearDirection = normalize(fearDirection)
            }
            
            let prediction = hungerComponent.model.predict([
                nTargetDirection.x, nTargetDirection.y, nTargetDirection.z, targetDistance,
                nFearDirection.x, nFearDirection.y, nFearDirection.z, fearDistance
            ])
            
            // Update the motion forces with the model prediction
            var steer = SIMD3(prediction[0...2])
            steer *= prediction[3]
            steer *= topSpeed
            steer -= motion.velocity
            
            let multiplier: Float = 10.0
            motion.forces.append(
                MotionComponent.Force(
                    acceleration: steer,
                    multiplier: multiplier,
                    name: "hunger")
            )
            
            // Store changes to the MotionComponent and HungerComponent
            eater.components[MotionComponent.self] = motion
            eater.components[HungerFearComponent.self] = hungerComponent
        }
    }
}
