import RealityKit
import Foundation

class WanderSystem: RealityKit.System {

    private static let query = EntityQuery(where: .has(WanderComponent.self) && .has(MotionComponent.self))

    static var dependencies: [SystemDependency] { [.before(MotionSystem.self)] }

    required init(scene: Scene) { }

    func update(context: SceneUpdateContext) {
        let speed = SimulationStats.shared.simulationSpeed
        let wanderers = context.scene.performQuery(Self.query)

        for entity in wanderers {
            guard var motion = entity.components[MotionComponent.self],
                  let wander = entity.components[WanderComponent.self]
            else { continue }

            if let attractor = wander.attractor {
                let distance = (attractor.position - entity.position).magnitude()
                guard distance > 0.1 else { continue }

                var steer = normalize(attractor.position - entity.position)
                if !steer.isNaN {
                    steer *= topSpeed * wander.wanderlust * speed
                    steer -= motion.velocity
                    motion.forces.append(
                        MotionComponent.Force(acceleration: steer, multiplier: attractorWeight, name: "wander")
                    )
                }
            }

            entity.components[MotionComponent.self] = motion
        }
    }
}
