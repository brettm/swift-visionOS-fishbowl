//
//  LivingEntityModel.swift
//  Organisms
//
//  Created by Brett Meader on 16/01/2024.
//

import Foundation
import Accelerate

public struct MLPNodeShape {
    let inputNodeCount: Int
    let hiddenNodeCount: Int
    let outputNodeCount: Int
    var inputToHiddenWeightsCount: Int { Int(inputNodeCount * hiddenNodeCount) }
    var inputToHiddenBiasCount: Int { inputToHiddenWeightsCount }
    var hiddenToOutputWeightsCount: Int { Int(hiddenNodeCount * outputNodeCount) }
    var hiddenToOutputBiasCount: Int { hiddenToOutputWeightsCount }
    
    internal init(inputNodeCount: Int = 8, hiddenNodeCount: Int = 32, outputNodeCount: Int = 4) {
        self.inputNodeCount = inputNodeCount
        self.hiddenNodeCount = hiddenNodeCount
        self.outputNodeCount = outputNodeCount
    }
}

public struct ModelWeights {
    private(set) var shape: MLPNodeShape
    var inputToHiddenWeights: [Float]
    var inputToHiddenBias: [Float]
    var hiddenToOutputWeights: [Float]
    var hiddenToOutputBias: [Float]
    
    init(shape: MLPNodeShape = .init(), inputToHiddenWeights: [Float] = [], inputToHiddenBias: [Float] = [], hiddenToOutputWeights: [Float] = [], hiddenToOutputBias: [Float] = []) {
        self.shape = shape
        self.inputToHiddenWeights = inputToHiddenWeights
        self.inputToHiddenBias = inputToHiddenBias
        self.hiddenToOutputWeights = hiddenToOutputWeights
        self.hiddenToOutputBias = hiddenToOutputBias
    }
    
    var randomWeights: ModelWeights {
        ModelWeights(
            shape: shape,
            inputToHiddenWeights: ( 0..<shape.inputToHiddenWeightsCount ).map { _ in .random(in: -1.0...1.0) },
            inputToHiddenBias: ( 0..<shape.inputToHiddenBiasCount ).map { _ in .random(in: -1.0...1.0) },
            hiddenToOutputWeights:( 0..<shape.hiddenToOutputWeightsCount ).map { _ in .random(in: -1.0...1.0) },
            hiddenToOutputBias: ( 0..<shape.hiddenToOutputBiasCount ).map { _ in .random(in: -0.1...0.1) }
        )
    }
    
    func variateWeights(variation: Float) -> ModelWeights {
        return ModelWeights(
            shape: shape,
            inputToHiddenWeights: self.inputToHiddenWeights.map{ $0 * .random(in: 1-variation...1+variation) },
            inputToHiddenBias: self.inputToHiddenBias.map{ $0 * .random(in: 1-variation...1+variation) },
            hiddenToOutputWeights: self.hiddenToOutputWeights.map{ $0 * .random(in: 1-variation...1+variation) },
            hiddenToOutputBias: self.hiddenToOutputBias.map{ $0 * .random(in: 1-variation...1+variation) }
        )
    }
}

public struct OrganismModel {
    
    private var hiddenLayer: BNNSFilter?
    private var outputLayer: BNNSFilter?
    
    internal var weights: ModelWeights
    
    init(weights: ModelWeights = ModelWeights().randomWeights) {
        self.weights = weights
    }
        
    func predict(_ input: [Float]) -> [Float] {
        precondition(hiddenLayer != nil)
        precondition(outputLayer != nil)
        // These arrays hold the inputs and outputs to and from the layers.
        var hidden: [Float] = ( 0..<weights.shape.hiddenNodeCount ).map { _ in 0 }
        var output: [Float] = ( 0..<weights.shape.outputNodeCount ).map { _ in 0 }
        
        var status = BNNSFilterApply(hiddenLayer, input, &hidden)
        if status != 0 {
            print("BNNSFilterApply failed on hidden layer")
        }
        status = BNNSFilterApply(outputLayer, hidden, &output)
        if status != 0 {
            print("BNNSFilterApply failed on output layer")
        }
        return output
    }
    
    mutating func destroyNetwork() {
        BNNSFilterDestroy(hiddenLayer)
        hiddenLayer = nil
        BNNSFilterDestroy(outputLayer)
        outputLayer = nil
    }
    
    // TODO: Update to latest BNNS framework
    @discardableResult
    mutating func createNetwork() -> Bool {
        
        let hiddenActivation = BNNSActivation(function: BNNSActivationFunction.identity, alpha: 0, beta: 0)
        let outActivation = BNNSActivation(function: BNNSActivationFunction.tanh, alpha: 0, beta: 0)
        
        _ = weights.inputToHiddenWeights.withUnsafeBufferPointer { inputToHiddenWeightsBP in
            weights.inputToHiddenBias.withUnsafeBufferPointer { inputToHiddenBiasDataBP in
                weights.hiddenToOutputWeights.withUnsafeBufferPointer { hiddenToOutputWeightsBP in
                    weights.hiddenToOutputBias.withUnsafeBufferPointer { hiddenToOutputBiasBP in
                        
                        let inputToHiddenWeightsData = BNNSLayerData(
                            data: inputToHiddenWeightsBP.baseAddress!, data_type: BNNSDataType.float,
                            data_scale: 0, data_bias: 0, data_table: nil)
                        
                        let inputToHiddenBiasData = BNNSLayerData(
                            data: inputToHiddenBiasDataBP.baseAddress!, data_type: BNNSDataType.float,
                            data_scale: 0, data_bias: 0, data_table: nil)
                        
                        let hiddenToOutputWeightsData = BNNSLayerData(
                            data:hiddenToOutputWeightsBP.baseAddress!, data_type: BNNSDataType.float,
                            data_scale: 0, data_bias: 0, data_table: nil)
                        
                        let hiddenToOutputBiasData = BNNSLayerData(
                            data: hiddenToOutputBiasBP.baseAddress!, data_type: BNNSDataType.float,
                            data_scale: 0, data_bias: 0, data_table: nil)
                        
                        var inputToHiddenParams = BNNSFullyConnectedLayerParameters(
                            in_size: weights.shape.inputNodeCount, out_size: weights.shape.hiddenNodeCount, weights: inputToHiddenWeightsData,
                            bias: inputToHiddenBiasData, activation: hiddenActivation)
                        
                        var hiddenToOutputParams = BNNSFullyConnectedLayerParameters(
                            in_size: weights.shape.hiddenNodeCount, out_size: weights.shape.outputNodeCount, weights: hiddenToOutputWeightsData,
                            bias: hiddenToOutputBiasData, activation: outActivation)
                        
                        var inputDesc = BNNSVectorDescriptor(
                            size: weights.shape.inputNodeCount, data_type: BNNSDataType.float, data_scale: 0, data_bias: 0)
                        
                        var hiddenDesc = BNNSVectorDescriptor(
                            size: weights.shape.hiddenNodeCount, data_type: BNNSDataType.float, data_scale: 0, data_bias: 0)
                        
                        hiddenLayer = BNNSFilterCreateFullyConnectedLayer(&inputDesc, &hiddenDesc, &inputToHiddenParams, nil)
                        if hiddenLayer == nil {
                            print("BNNSFilterCreateFullyConnectedLayer failed for hidden layer")
                            return false
                        }
                        
                        var outputDesc = BNNSVectorDescriptor(
                            size: weights.shape.outputNodeCount, data_type: BNNSDataType.float, data_scale: 0, data_bias: 0)
                        
                        outputLayer = BNNSFilterCreateFullyConnectedLayer(&hiddenDesc, &outputDesc, &hiddenToOutputParams, nil)
                        if outputLayer == nil {
                            print("BNNSFilterCreateFullyConnectedLayer failed for output layer")
                            return false
                        }
                        return true
                    }
                }
            }
        }
        return true
    }
}
