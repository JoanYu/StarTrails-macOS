import Foundation
import CoreML
import Vision
import CoreImage

let modelPath = "/Users/xduyzy/Documents/GitHub/startrails-main/models/detectStreaks/streaks.mlpackage"
guard let compiledUrl = try? MLModel.compileModel(at: URL(fileURLWithPath: modelPath)) else {
    print("Failed to compile")
    exit(1)
}

func testModel(computeUnits: MLComputeUnits) {
    print("Testing compute units: \(computeUnits.rawValue)")
    let config = MLModelConfiguration()
    config.computeUnits = computeUnits
    guard let model = try? MLModel(contentsOf: compiledUrl, configuration: config) else {
        print("Failed to load model")
        return
    }
    
    // Create dummy input MultiArray
    guard let inputMultiArray = try? MLMultiArray(shape: [1, 3, 1024, 1024], dataType: .float32) else { return }
    for i in 0..<inputMultiArray.count { inputMultiArray[i] = NSNumber(value: Float.random(in: 0...1)) }
    
    let inputName = model.modelDescription.inputDescriptionsByName.keys.first ?? "image"
    print("Input description:", model.modelDescription.inputDescriptionsByName[inputName]!)
    guard let imageFeature = try? MLDictionaryFeatureProvider(dictionary: [inputName: MLFeatureValue(multiArray: inputMultiArray)]) else { return }
    
    do {
        let output = try model.prediction(from: imageFeature)
        let outputName = output.featureNames.first!
        let varArray = output.featureValue(for: outputName)!.multiArrayValue!
        
        let numBoxes = varArray.shape[min(2, varArray.shape.count - 1)].intValue
        print("numBoxes: \(numBoxes), dataType: \(varArray.dataType.rawValue)")
        
        let count = min(varArray.count, 100)
        var sum: Float = 0
        if varArray.dataType == .float16 {
            let f16ptr = varArray.dataPointer.bindMemory(to: Float16.self, capacity: varArray.count)
            for i in 0..<count { sum += Float(f16ptr[i]) }
        } else {
            let f32ptr = varArray.dataPointer.bindMemory(to: Float.self, capacity: varArray.count)
            for i in 0..<count { sum += f32ptr[i] }
        }
        print("Sum of first 100 elements: \(sum)")
    } catch {
        print("Prediction failed with error: \(error)")
        return
    }
}

testModel(computeUnits: .cpuOnly)
testModel(computeUnits: .all)
