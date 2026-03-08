import Foundation
import CoreML
import Vision
import CoreImage

public final class YOLOPredictor: @unchecked Sendable {
    private let model: MLModel
    private let postProcessor = OBBPostProcessor()
    
    public init(modelURL: URL) throws {
        let config = MLModelConfiguration()
        // We removed dynamic shapes on export, so we can finally use the Neural Engine + GPU!
        config.computeUnits = .all 
        self.model = try MLModel(contentsOf: modelURL, configuration: config)
    }
    
    public func predict(imagePath: String, confThreshold: Float = 0.25, iouThreshold: Float = 0.45) throws -> [OBBResult] {
        let url = URL(fileURLWithPath: imagePath)
        guard let ciImage = CIImage(contentsOf: url) else {
            throw NSError(domain: "YOLOPredictor", code: -1, userInfo: [NSLocalizedDescriptionKey: "Cannot load image from path \(imagePath)"])
        }
        
        let originalWidth = ciImage.extent.width
        let originalHeight = ciImage.extent.height
        
        // Static Shape YOLO size
        let targetSize = CGSize(width: 1024, height: 1024)
        
        // --- 1. Full Image (Downscaled) Prediction ---
        let scaleX = targetSize.width / originalWidth
        let scaleY = targetSize.height / originalHeight
        let scale = min(scaleX, scaleY)
        
        let scaledWidth = originalWidth * scale
        let scaledHeight = originalHeight * scale
        
        let paddingX = (targetSize.width - scaledWidth) / 2.0
        let paddingY = (targetSize.height - scaledHeight) / 2.0
        
        let scaleTransform = CGAffineTransform(scaleX: scale, y: scale)
        let translationTransform = CGAffineTransform(translationX: paddingX, y: paddingY)
        let finalTransform = scaleTransform.concatenating(translationTransform)
        let transformedImage = ciImage.transformed(by: finalTransform)
        
        var allOBBs = [OBBResult]()
        
        let fullImageOBBsRaw = try predictSinglePatch(image: transformedImage, targetSize: targetSize, confThreshold: confThreshold)
        for box in fullImageOBBsRaw {
            let originalCX = Float((CGFloat(box.cx) - paddingX) / scale)
            let originalCY = Float((CGFloat(box.cy) - paddingY) / scale)
            let originalW = Float(CGFloat(box.w) / scale)
            let originalH = Float(CGFloat(box.h) / scale)
            allOBBs.append(OBBResult(cx: originalCX, cy: originalCY, w: originalW, h: originalH, conf: box.conf, angle: box.angle))
        }
        
        // --- 2. Sliced SAHI Predictions ---
        let patchSize: CGFloat = targetSize.width
        let stride: CGFloat = round(patchSize * 0.8) // 20% overlap
        
        let xStrides = getStrides(length: originalWidth, patchSize: patchSize, stride: stride)
        let yStrides = getStrides(length: originalHeight, patchSize: patchSize, stride: stride)
        
        for startY in yStrides {
            for startX in xStrides {
                // CIImage coordinate system is bottom-left
                let ciCropRect = CGRect(x: startX, y: originalHeight - patchSize - startY, width: patchSize, height: patchSize)
                let patchCI = ciImage.cropped(to: ciCropRect)
                let translatedPatch = patchCI.transformed(by: CGAffineTransform(translationX: -startX, y: -(originalHeight - patchSize - startY)))
                
                let patchOBBsRaw = try predictSinglePatch(image: translatedPatch, targetSize: targetSize, confThreshold: confThreshold)
                for box in patchOBBsRaw {
                    let globalCX = box.cx + Float(startX)
                    let globalCY = box.cy + Float(startY)
                    allOBBs.append(OBBResult(cx: globalCX, cy: globalCY, w: box.w, h: box.h, conf: box.conf, angle: box.angle))
                }
            }
        }
        
        // --- 3. Weighted Boxes Fusion Merge ---
        let finalOBBs = OBBPostProcessor.weightedBoxesFusion(allOBBs, iouThreshold: iouThreshold)
        return finalOBBs
    }
    
    private func predictSinglePatch(image: CIImage, targetSize: CGSize, confThreshold: Float) throws -> [OBBResult] {
        let background = CIImage(color: .black).cropped(to: CGRect(origin: .zero, size: targetSize))
        let paddedImage = image.composited(over: background)
        
        guard let pixelBuffer = paddedImage.toPixelBuffer(size: targetSize) else {
            return []
        }
        
        let inputName = model.modelDescription.inputDescriptionsByName.keys.first ?? "image"
        let imageFeature = try MLDictionaryFeatureProvider(dictionary: [inputName: MLFeatureValue(pixelBuffer: pixelBuffer)])
        
        let output = try model.prediction(from: imageFeature)
        
        guard let outputName = output.featureNames.first,
              let varArray = output.featureValue(for: outputName)?.multiArrayValue else {
            return []
        }
        
        let isF16 = varArray.dataType == .float16
        let numBoxes = varArray.shape[min(2, varArray.shape.count - 1)].intValue
        
        var f32Pointer: UnsafeMutablePointer<Float>
        var shouldDeallocate = false
        
        if isF16 {
            let f16Pointer = varArray.dataPointer.bindMemory(to: Float16.self, capacity: varArray.count)
            f32Pointer = UnsafeMutablePointer<Float>.allocate(capacity: varArray.count)
            shouldDeallocate = true
            for i in 0..<varArray.count {
                f32Pointer[i] = Float(f16Pointer[i])
            }
        } else {
            f32Pointer = varArray.dataPointer.bindMemory(to: Float.self, capacity: varArray.count)
        }
        
        defer {
            if shouldDeallocate { f32Pointer.deallocate() }
        }
        
        return OBBPostProcessor.parse(f32Pointer, numBoxes: numBoxes, confThreshold: confThreshold)
    }
    
    private func getStrides(length: CGFloat, patchSize: CGFloat, stride: CGFloat) -> [CGFloat] {
        if length <= patchSize { return [0] }
        var result = [CGFloat]()
        var current: CGFloat = 0
        while current + patchSize < length {
            result.append(current)
            current += stride
        }
        result.append(length - patchSize)
        return Array(Set(result)).sorted()
    }
}

// Extension to help convert CIImage to CVPixelBuffer
extension CIImage {
    func toPixelBuffer(size: CGSize) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let attributes: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]
        
        let status = CVPixelBufferCreate(kCFAllocatorDefault,
                                         Int(size.width),
                                         Int(size.height),
                                         kCVPixelFormatType_32BGRA,
                                         attributes as CFDictionary,
                                         &pixelBuffer)
        
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            return nil
        }
        
        let context = CIContext()
        context.render(self, to: buffer)
        return buffer
    }
}
