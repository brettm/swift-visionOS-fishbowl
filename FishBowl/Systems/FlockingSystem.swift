/*
 Copyright © 2021 Apple Inc.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 */

import RealityKit

struct FlockingComponent: Component { }
    
var maxSteeringForceVector: SIMD3<Float> {
    SIMD3<Float>(repeating: 5.0)
}

let separationWeight: Float = 2.8
let cohesionWeight: Float = 1.0
let alignmentWeight: Float = 1.0
let hungerWeight: Float = 2
let fearWeight: Float = 0.0
let topSpeed: Float = 0.018
let maxSteeringForce: Float = 5.0
let maxNeighborDistance: Float = 1.0
let desiredSeparation: Float = 0.2
let animationScalar: Float = 400.0
let attractorWeight: Float = 1.0

class FlockingSystem: RealityKit.System {
    
    
    private static let query = EntityQuery(where: .has(FlockingComponent.self) && .has(MotionComponent.self))// && .has(SettingsComponent.self))
    //private static let leaderQuery = EntityQuery(where: .has(FlockLeader.self))

    // This system runs before the Motion system because it manages the acceleration and velocity, which this system modifies.
    static var dependencies: [SystemDependency] { [.before(MotionSystem.self)] }

    required init(scene: RealityKit.Scene) { }

    func update(context: SceneUpdateContext) {

//        let leader = context.scene.performQuery(Self.leaderQuery).map { $0 }.first

        let flockers = context.scene.performQuery(Self.query)

        for entity in flockers {
            guard var motion = entity.components[MotionComponent.self] else { continue }
            //guard let settings = (entity.components[SettingsComponent.self] as? SettingsComponent)?.settings else { continue }

            let separation = separate(from: entity, flockers)
            let alignment = align(from: entity, flockers)
            let cohesion = cohere(from: entity, flockers)

            motion.forces.append(MotionComponent.Force(acceleration: separation, multiplier: separationWeight, name: "sep"))
            motion.forces.append(MotionComponent.Force(acceleration: alignment, multiplier: alignmentWeight, name: "al"))
            motion.forces.append(MotionComponent.Force(acceleration: cohesion, multiplier: cohesionWeight, name: "coh"))

            // If there is a flock leader, follow them for a bit. This prevents the fish from flocking straight in one direction forever.
//            if let leader = leader {
//                var steer = normalize(leader.position - entity.position)
//                steer *= settings.topSpeed
//                motion.forces.append(MotionComponent.Force(acceleration: steer, multiplier: settings.cohesionWeight, name: "leader"))
//            }

            entity.components[MotionComponent.self] = motion
        }
    }

    private func separate(from entity1: Entity, _ entities: QueryResult<Entity>) -> SIMD3<Float> {
        guard let motion = entity1.components[MotionComponent.self]
//        let settings = (entity1.components[SettingsComponent.self] as? SettingsComponent)?.settings
        else { return .zero }

        var steer = SIMD3<Float>.zero

        var numEntities = 0

        let desiredSeparation = desiredSeparation

        for entity2 in entities where entity2 != entity1 {

            let distance = entity1.distance(from: entity2)

            if distance < desiredSeparation {
                var diff = entity1.transform.translation - entity2.transform.translation

                diff = normalize(diff)
                if distance > 0 {
                    diff /= distance
                } else {
                    // If they're in exactly the same position, choose a random vector.
                    diff = SIMD3<Float>.random(in: -maxSteeringForce..<maxSteeringForce)
                }
                steer += diff
            }

            numEntities += 1
        }

        if numEntities > 0 {
            steer *= (1.0 / Float(numEntities))
        }

        if simd_length(steer) > 0 {
            steer = normalize(steer)
            steer *= topSpeed
            steer -= motion.velocity
            steer.clamp(lowerBound: -maxSteeringForceVector, upperBound: maxSteeringForceVector)
        }

        return steer
    }

    private func align(from entity1: Entity, _ entities: QueryResult<Entity>) -> SIMD3<Float> {
        guard let velocity = (entity1.components[MotionComponent.self])?.velocity else { return .zero }
//        guard let settings = (entity1.components[SettingsComponent.self] as? SettingsComponent)?.settings else { return .zero }

        var sum = SIMD3<Float>.zero
        var numNeighbors = 0
        for entity2 in entities where entity2 != entity1 {
            guard let otherMotionComponent = entity2.components[MotionComponent.self] else { continue }

            if entity1.isDistanceWithinThreshold(from: entity2, max: maxNeighborDistance) {
                sum += otherMotionComponent.velocity
                numNeighbors += 1
            }
        }

        if numNeighbors > 0 && sum.length > 0 {
            sum /= Float(numNeighbors)
            sum = normalize(sum)
            sum *= topSpeed
            var steer: SIMD3<Float> = sum - velocity
            steer.clamp(lowerBound: -maxSteeringForceVector, upperBound: maxSteeringForceVector)
            return steer
        } else {
            return .zero
        }
    }

    private func cohere(from entity1: Entity, _ entities: QueryResult<Entity>) -> SIMD3<Float> {
//        guard let settings = (entity1.components[SettingsComponent.self] as? SettingsComponent)?.settings else { return .zero }
        var sum = SIMD3<Float>.zero
        var numNeighbors = 0

        for entity2 in entities where entity2 != entity1 {
            if entity1.isDistanceWithinThreshold(from: entity2, max: maxNeighborDistance) {
                sum += entity2.transform.translation
                numNeighbors += 1
            }
        }

        if numNeighbors > 0 {
            sum /= Float(numNeighbors)
            return entity1.seek(sum)
        } else {
            return .zero
        }
    }
}

extension Entity {

    func seek(_ target: SIMD3<Float>) -> SIMD3<Float> {
        guard let velocity = (self.components[MotionComponent.self])?.velocity else { return .zero }
//        guard let settings = (self.components[SettingsComponent.self] as? SettingsComponent)?.settings else { return .zero }
        var desired = target - self.position
        desired = normalize(desired)
        desired *= topSpeed

        var steer = desired - velocity
        steer.clamp(lowerBound: -maxSteeringForceVector, upperBound: maxSteeringForceVector)
        return steer
    }
}
