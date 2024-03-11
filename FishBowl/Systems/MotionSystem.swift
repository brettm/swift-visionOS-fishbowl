/*
 Copyright © 2021 Apple Inc.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 */

import RealityKit

/// This system applies the calculated acceleration to the current velocity and moves the entities accordingly.
class MotionSystem: RealityKit.System {

    private static let query = EntityQuery(where: .has(MotionComponent.self)) //&& .has(SettingsComponent.self))

    required init(scene: RealityKit.Scene) { }

    func update(context: SceneUpdateContext) {

        let deltaTime = Float(context.deltaTime)
        let dtSquared = deltaTime * deltaTime

        context.scene.performQuery(Self.query).forEach { entity in

            guard var motion = entity.components[MotionComponent.self]
//            let settings = (entity.components[SettingsComponent.self] as? SettingsComponent)?.settings 
            else { return }

            defer {
                // Reset acceleration for the next update so that the other systems that modify acceleration have a blank slate.
                motion.forces = [MotionComponent.Force]()
                entity.components[MotionComponent.self] = motion
            }

            var newTransform = entity.transform

            // Add up all the forces that our other systems have applied to the MotionComponent, and use that to change the velocity.
            let acceleration = combinedForces(values: motion.forces)

            let accelerationScaled = acceleration * dtSquared //* settings.timeScale

            motion.velocity += accelerationScaled

            newTransform.translation += motion.velocity

            entity.move(to: newTransform, relativeTo: nil)

            // If the creature is moving at all, have it look in the direction it's moving.
            if motion.velocity.length > 0 {
                entity.look(
                    at: newTransform.translation - motion.velocity,
                    from: newTransform.translation,
                    relativeTo: nil
                )
            }
        }
    }

    private func combinedForces(values: [MotionComponent.Force]) -> SIMD3<Float> {
        values.reduce(.zero) { result, force in
            result + (force.acceleration * force.multiplier)
        }
    }
}
