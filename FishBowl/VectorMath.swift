/*
 Copyright © 2021 Apple Inc.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 */

import RealityKit

extension SIMD3 where Scalar == Float {
    func distance(from other: SIMD3<Float>) -> Float {
        return simd_distance(self, other)
    }

    var printed: String {
        String(format: "(%.8f, %.8f, %.8f)", x, y, z)
    }

    static func spawnPoint(from: SIMD3<Float>, radius: Float) -> SIMD3<Float> {
        from + (radius == 0 ? .zero : SIMD3<Float>.random(in: Float(-radius)..<Float(radius)))
    }

    func angle(other: SIMD3<Float>) -> Float {
        atan2f(other.x - self.x, other.z - self.z) + Float.pi
    }

    var length: Float { return distance(from: .init()) }

    var isNaN: Bool {
        x.isNaN || y.isNaN || z.isNaN
    }

    var normalized: SIMD3<Float> {
        return self / length
    }

    static let up: Self = .init(0, 1, 0)

    func vector(to b: SIMD3<Float>) -> SIMD3<Float> {
        b - self
    }

    var isVertical: Bool {
        dot(self, Self.up) > 0.9
    }
}

extension SIMD2 where Scalar == Float {
    func distance(from other: Self) -> Float {
        return simd_distance(self, other)
    }

    var length: Float { return distance(from: .init()) }
}

extension BoundingBox {

    var volume: Float { extents.x * extents.y * extents.z }
}
