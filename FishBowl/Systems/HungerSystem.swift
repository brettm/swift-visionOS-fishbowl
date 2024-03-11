/*
 Copyright © 2021 Apple Inc.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 */
import RealityKit

struct HungerComponent: RealityKit.Component {
    var currentFoodTarget: Entity?
}

struct AlgaeEaterComponent: RealityKit.Component { }
struct PlanktonEaterComponent: RealityKit.Component { }

struct FoodComponent: RealityKit.Component { }
struct AlgaeComponent: RealityKit.Component { }
struct PlanktonComponent: RealityKit.Component { }

class EatingSystem: RealityKit.System {
    required init(scene: RealityKit.Scene) { }

    // Food-seeking behavior runs after flocking finishes, but before the
    // MovementSystem applies acceleration to move the fish.
    static var dependencies: [SystemDependency] = [.after(FlockingSystem.self), .before(MotionSystem.self)]

    static let planktonLoverQuery = EntityQuery(where: .has(HungerComponent.self) && .has(MotionComponent.self) && .has(PlanktonEaterComponent.self))
    static let algaeLoverQuery = EntityQuery(where: .has(HungerComponent.self) && .has(MotionComponent.self) && .has(AlgaeEaterComponent.self))

    static let planktonQuery = EntityQuery(where: .has(PlanktonComponent.self))
    static let algaeQuery = EntityQuery(where: .has(AlgaeComponent.self))

    func update(context: SceneUpdateContext) {

        let algae = context.scene.performQuery(Self.algaeQuery).map { $0 }
        let plankton = context.scene.performQuery(Self.planktonQuery).map { $0 }

        // If there's no food in the scene, don't do anything.
        guard !(algae.isEmpty && plankton.isEmpty) else { return }

        let planktonLovers = context.scene.performQuery(Self.planktonLoverQuery).map { $0 }
        let algaeLovers = context.scene.performQuery(Self.algaeLoverQuery).map { $0 }

        let eaters = algaeLovers + planktonLovers

        for eater in eaters {
            guard var motion = eater.components[MotionComponent.self] else { continue }
            guard var hungerComponent = eater.components[HungerComponent.self] else { continue }
//            guard let settings = (eater.components[SettingsComponent.self])?.settings else { continue }

            // Pick a random food for the fish follow if it's not already following food.
            if hungerComponent.currentFoodTarget == nil {

                if eater.components.has(PlanktonEaterComponent.self) {
                    hungerComponent.currentFoodTarget = plankton.randomElement()
                }

                if hungerComponent.currentFoodTarget == nil, eater.components.has(AlgaeEaterComponent.self) {
                    hungerComponent.currentFoodTarget = algae.randomElement()
                }
            }

            // If there's no food available, there's nothing to do.
            guard let food = hungerComponent.currentFoodTarget else { continue }

            // This fish should steer toward the food.
            var steer = normalize(food.position - eater.position)
            steer *= topSpeed
            steer -= motion.velocity
            motion.forces.append(MotionComponent.Force(acceleration: steer, multiplier: hungerWeight, name: "hunger"))

            // Store changes to the MotionComponent and HungerComponent
            // back into the entity's components collection.
            eater.components[MotionComponent.self] = motion
            eater.components[HungerComponent.self] = hungerComponent
        }
    }
}
