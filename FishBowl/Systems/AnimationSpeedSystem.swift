/*
 Copyright © 2021 Apple Inc.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 */

import RealityKit

class AnimationSpeedSystem: RealityKit.System {

    private static let query = EntityQuery(where: .has(AnimationSpeedComponent.self) && .has(MotionComponent.self))
    private var simulationStats: SimulationStats?

    required init(scene: Scene) { }

    static var dependencies: [SystemDependency] { [.after(MotionSystem.self)] }
    
    func setSimulationStats(_ stats: SimulationStats) {
        self.simulationStats = stats
    }

    func update(context: SceneUpdateContext) {
        let speed = simulationStats?.simulationSpeed ?? 1.0
        let animators = context.scene.performQuery(Self.query)

        for animator in animators {
            guard let component = animator.components[AnimationSpeedComponent.self],
                  let motion = animator.components[MotionComponent.self]
                  //let settings = (animator.components[SettingsComponent.self] as? SettingsComponent)?.settings
            else { continue }

            let animationController = component.animationController
            // Make the animation play faster when the fish is swimming fast,
            // slower when it's swimming slowly.
            let animationFramerate = max(0.001, motion.velocity.length) * component.scalar * speed
            animationController.speed = animationFramerate
        }
    }
}
