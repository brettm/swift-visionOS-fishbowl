import RealityKit

class MotionSystem: RealityKit.System {

    private static let query = EntityQuery(where: .has(MotionComponent.self))

    required init(scene: RealityKit.Scene) { }

    func update(context: SceneUpdateContext) {
        let speed = SimulationStats.shared.simulationSpeed
        let deltaTime = Float(context.deltaTime) * speed
        let dtSquared = deltaTime * deltaTime

        context.scene.performQuery(Self.query).forEach { entity in
            guard var motion = entity.components[MotionComponent.self] else { return }

            defer {
                motion.forces = []
                entity.components[MotionComponent.self] = motion
            }

            var newTransform = entity.transform
            let acceleration = combinedForces(values: motion.forces)

            motion.velocity += acceleration * dtSquared
            newTransform.translation += motion.velocity
            entity.move(to: newTransform, relativeTo: nil)

            if motion.velocity.length > 0 {
                entity.look(
                    at: newTransform.translation - motion.velocity,
                    from: newTransform.translation,
                    relativeTo: nil
                )
                motion.velocity *= pow(Float(friction), dtSquared)
            }
        }
    }

    private func combinedForces(values: [MotionComponent.Force]) -> SIMD3<Float> {
        values.reduce(.zero) { result, force in
            result + (force.acceleration * force.multiplier)
        }
    }
}
