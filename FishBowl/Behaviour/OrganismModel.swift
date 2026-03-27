import Foundation
import Accelerate

public struct MLPNodeStructure {
    public let inputNodesCount: Int
    public let hiddenNodesCount: Int
    public let outputNodesCount: Int

    public init(inputNodesCount: Int, hiddenNodesCount: Int, outputNodesCount: Int) {
        self.inputNodesCount = inputNodesCount
        self.hiddenNodesCount = hiddenNodesCount
        self.outputNodesCount = outputNodesCount
    }
}

public struct ModelWeights: Equatable {
    var inputToHiddenWeights: [Float]
    var inputToHiddenBias: [Float]
    var hiddenToOutputWeights: [Float]
    var hiddenToOutputBias: [Float]
}

public struct OrganismModel {
    public let shape: MLPNodeStructure // holds layer sizes
    internal var weights: ModelWeights

    public init(
        shape: MLPNodeStructure = MLPNodeStructure(inputNodesCount: 8, hiddenNodesCount: 16, outputNodesCount: 4),
        initialWeights: ModelWeights? = nil
    ) {
        let inHidCount = shape.inputNodesCount * shape.hiddenNodesCount
        let hidOutCount = shape.hiddenNodesCount * shape.outputNodesCount

        self.shape = shape
        self.weights = ModelWeights(
            inputToHiddenWeights: initialWeights?.inputToHiddenWeights ?? (0..<inHidCount).map { _ in .random(in: -1.0...1.0) },
            inputToHiddenBias: initialWeights?.inputToHiddenBias ?? (0..<shape.hiddenNodesCount).map { _ in .random(in: -0.1...0.1) },
            hiddenToOutputWeights: initialWeights?.hiddenToOutputWeights ?? (0..<hidOutCount).map { _ in .random(in: -1.0...1.0) },
            hiddenToOutputBias: initialWeights?.hiddenToOutputBias ?? (0..<shape.outputNodesCount).map { _ in .random(in: -0.1...0.1) }
        )
    }

    // Fast forward pass using Accelerate (vDSP for matmul, vForce for tanh activation)
    public func predict(_ input: [Float]) -> [Float] {
        precondition(input.count == shape.inputNodesCount, "Input count mismatch.")
        
        // Hidden Layer (linear)
        var hidden = [Float](repeating: 0, count: shape.hiddenNodesCount)
        weights.inputToHiddenWeights.withUnsafeBufferPointer { wPtr in
            input.withUnsafeBufferPointer { inPtr in
                vDSP_mmul(
                    inPtr.baseAddress!, 1,
                    wPtr.baseAddress!, 1,
                    &hidden, 1,
                    1,
                    vDSP_Length(shape.hiddenNodesCount),
                    vDSP_Length(shape.inputNodesCount)
                )
            }
        }
        vDSP_vadd(hidden, 1, weights.inputToHiddenBias, 1, &hidden, 1, vDSP_Length(shape.hiddenNodesCount))
        
        // Output Layer
        var output = [Float](repeating: 0, count: shape.outputNodesCount)
        weights.hiddenToOutputWeights.withUnsafeBufferPointer { wPtr in
            hidden.withUnsafeBufferPointer { hidPtr in
                vDSP_mmul(
                    hidPtr.baseAddress!, 1,
                    wPtr.baseAddress!, 1,
                    &output, 1,
                    1,
                    vDSP_Length(shape.outputNodesCount),
                    vDSP_Length(shape.hiddenNodesCount)
                )
            }
        }
        vDSP_vadd(output, 1, weights.hiddenToOutputBias, 1, &output, 1, vDSP_Length(shape.outputNodesCount))
        
        // Tanh activation for output
        var outCount = Int32(shape.outputNodesCount)
        vvtanhf(&output, output, &outCount)
        
        return output
    }
}
