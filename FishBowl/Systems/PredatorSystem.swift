//
//  PredatorSystem.swift
//  FishBowl
//
//  Created by Brett Meader on 09/09/2024.
//
import RealityKit

struct PredatorComponent: RealityKit.Component {
    var prey: Entity?
}

class PredatorSystem: RealityKit.System {

    private static let predatorQuery = EntityQuery(where: .has(PredatorComponent.self) && .has(MotionComponent.self))
    private static let krillEaterQuery = EntityQuery(where: .has(HungerFearComponent.self) && .has(MotionComponent.self) && .has(KrillEaterComponent.self))

    static var dependencies: [SystemDependency] { [.before(MotionSystem.self)] }

    // Minimum distance before shark stops actively chasing — prevents
    // oscillation/flickering when the shark catches up with its prey
    private let minimumChaseDistance: Float = 0.05

    required init(scene: Scene) { }

    func update(context: SceneUpdateContext) {
        let speed = SimulationStats.shared.simulationSpeed
        let predators = context.scene.performQuery(Self.predatorQuery).map { $0 }
        let preys = context.scene.performQuery(Self.krillEaterQuery).map { $0 }

        for predator in predators {
            guard var motionComponent = predator.components[MotionComponent.self],
                  var predatorComponent = predator.components[PredatorComponent.self]
            else { continue }

            // Pick closest visible prey
            let visible = preys.filter { predator.distance(from: $0) < sharkVisibility }
            predatorComponent.prey = visible
                .sorted { $0.distance(from: predator.position) < $1.distance(from: predator.position) }
                .first

            if let prey = predatorComponent.prey {
                let toPreyVector = prey.position - predator.position
                let distanceToPrey = toPreyVector.magnitude()

                // Only apply chase force if outside minimum distance —
                // prevents flickering when shark is on top of prey
                if distanceToPrey > minimumChaseDistance {
                    var steer = normalize(toPreyVector)
                    if !steer.isNaN {
                        steer *= topSpeed * speed
                        steer -= motionComponent.velocity
                        motionComponent.forces.append(
                            MotionComponent.Force(acceleration: steer, multiplier: attractorWeight, name: "predator")
                        )
                    }
                }
            }

            predator.components[MotionComponent.self] = motionComponent
            predator.components[PredatorComponent.self] = predatorComponent
        }
    }
}
