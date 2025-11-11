//
//  HunterSystem.swift
//  FishBowl
//
//  Created by Brett Meader on 09/09/2024.
//
import RealityKit

struct PredatorComponent: RealityKit.Component { 
    var prey: Entity?
}

class PredatorSystem: RealityKit.System {

    private static let predatorQuery = EntityQuery(where: .has(PredatorComponent.self) && .has(MotionComponent.self)) //&& .has(SettingsComponent.self))
    private static let krillEaterQuery = EntityQuery(where: .has(HungerFearComponent.self) && .has(MotionComponent.self) && .has(KrillEaterComponent.self))
    // This system should always run before the Motion system, which manages
    // acceleration, which this system modifies.
    static var dependencies: [SystemDependency] { [.before(MotionSystem.self)] }

    required init(scene: Scene) { }

    func update(context: SceneUpdateContext) {
        let predators = context.scene.performQuery(Self.predatorQuery).map{ $0 }
        let preys = context.scene.performQuery(Self.krillEaterQuery).map { $0 }

        for predator in predators {
            guard var motionComponent = predator.components[MotionComponent.self],
                  var predatorComponent = predator.components[PredatorComponent.self]
                //let settings = (entity.components[SettingsComponent.self] as? SettingsComponent)?.settings
            else { continue }

            let visible = preys.filter{ predator.distance(from: $0) < sharkVisibility }
            predatorComponent.prey = visible.sorted{ $0.distance(from: predator.position) < $1.distance(from: predator.position) }.first
//            var distanceFromAttractor = Float(0)
//            if let attractor = wander.attractor {
//                distanceFromAttractor = entity.distance(from: attractor)
//            }
//            // This method has reached its attractor; pick a new one.
//            if distanceFromAttractor < 0.01 {
////                var newAttractor = SIMD3<Float>.spawnPoint(from: Settings.fishOrigin, radius: Settings.wanderRadius)
//                var newAttractor = SIMD3<Float>.spawnPoint(from: .zero, radius: 0.5)
//                // Keep the wanderer roughly level with where it currently is
//                // to avoid going up or down too steeply.
//                newAttractor.y = entity.position.y + Float.random(in: 0..<0.5)
//
//                let obstacles = context.scene.raycast(from: entity.position,
//                                                      to: newAttractor,
//                                                      query: .nearest,
//                                                      mask: .sceneUnderstanding,
//                                                      relativeTo: nil)
//
//                // Don't pick a point in the wall.
//                if let nearest = obstacles.first {
//                    newAttractor = nearest.position
//                }
//                wander.attractor = newAttractor
//            }

            if let prey = predatorComponent.prey {
                var steer = normalize(prey.position - predator.position)
                if !steer.isNaN {
                    steer *= topSpeed //* wander.wanderlust
                    steer -= motionComponent.velocity
                    motionComponent.forces.append(MotionComponent.Force(acceleration: steer, multiplier: attractorWeight, name: "wander"))
                }
            }

            predator.components[MotionComponent.self] = motionComponent
            predator.components[PredatorComponent.self] = predatorComponent
        }
    }
}
