/*
 Copyright © 2021 Apple Inc.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 */
import RealityKit
import Foundation

class WanderSystem: RealityKit.System {

    private static let query = EntityQuery(where: .has(WanderComponent.self) && .has(MotionComponent.self)) //&& .has(SettingsComponent.self))
    // This system should always run before the Motion system, which manages
    // acceleration, which this system modifies.
    static var dependencies: [SystemDependency] { [.before(MotionSystem.self)] }
    private var simulationStats: SimulationStats?

    required init(scene: Scene) { }
    
    func setSimulationStats(_ stats: SimulationStats) {
        self.simulationStats = stats
    }

    func update(context: SceneUpdateContext) {
        let speed = simulationStats?.simulationSpeed ?? 1.0
        let wanderers = context.scene.performQuery(Self.query)

        for entity in wanderers {
            guard var motion = entity.components[MotionComponent.self],
                  let wander = entity.components[WanderComponent.self]
                //let settings = (entity.components[SettingsComponent.self] as? SettingsComponent)?.settings 
            else { continue }

            if let attractor = wander.attractor {
                var steer = normalize(attractor.position - entity.position)
                if !steer.isNaN {
                    steer *= topSpeed * wander.wanderlust * speed
                    steer -= motion.velocity
                    motion.forces.append(MotionComponent.Force(acceleration: steer, multiplier: attractorWeight, name: "wander"))
                }
            }

            entity.components[MotionComponent.self] = motion
        }
    }
}
