import Foundation
import CoreML
import CoreImage
import Accelerate

public final class GapFiller: @unchecked Sendable {
    private let model: MLModel
    
    public init(modelURL: URL) throws {
        let config = MLModelConfiguration()
        config.computeUnits = .all
        self.model = try MLModel(contentsOf: modelURL, configuration: config)
    }
    
    public func fillGaps(in image: CGImage, progressCallback: (@Sendable (Double) -> Void)? = nil) async throws -> (filledImage: CGImage, mask: CGImage)? {
        let width = image.width
        let height = image.height
        let patchSize = 128
        let stride = 96 // 128 * 0.75
        
        let context = CIContext()
        let sourceCI = CIImage(cgImage: image)
        
        // Pad the image so we can extract exactly 128x128 patches covering the whole image
        let paddedWidth = max(width, Int(ceil(Double(width) / Double(stride))) * stride + (patchSize - stride))
        let paddedHeight = max(height, Int(ceil(Double(height) / Double(stride))) * stride + (patchSize - stride))
        
        // Render to float32 buffer for easy manipulation
        var sourceBuffer = [Float](repeating: 0, count: paddedWidth * paddedHeight * 4) // RGBA
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let cgContext = CGContext(data: &sourceBuffer,
                                  width: paddedWidth,
                                  height: paddedHeight,
                                  bitsPerComponent: 32,
                                  bytesPerRow: paddedWidth * 4 * 4,
                                  space: colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.floatComponents.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
        
        // Draw the image at the top left of the padded buffer
        cgContext.draw(image, in: CGRect(x: 0, y: paddedHeight - height, width: width, height: height))
        
        // We will accumulate results here
        var accumBuffer = [Float](repeating: 0, count: paddedWidth * paddedHeight * 4) // RGBA
        var maskAccumBuffer = [Float](repeating: 0, count: paddedWidth * paddedHeight) // Grayscale mask
        
        let multiArray = try MLMultiArray(shape: [1, 3, NSNumber(value: patchSize), NSNumber(value: patchSize)], dataType: .float32)
        let ptr = multiArray.dataPointer.assumingMemoryBound(to: Float.self)
        
        // PyTorch UNet is expecting input in [-1, 1], Channels First
        let xStrides = strideBy(from: 0, to: paddedWidth - patchSize + 1, by: stride)
        let yStrides = strideBy(from: 0, to: paddedHeight - patchSize + 1, by: stride)
        let totalPatches = xStrides.count * yStrides.count
        var currentPatch = 0
        
        for y in yStrides {
            for x in xStrides {
                currentPatch += 1
                if currentPatch % 5 == 0 {
                    progressCallback?(Double(currentPatch) / Double(totalPatches))
                    await Task.yield() // Prevent blocking the thread
                }
                
                // Read 128x128 into MultiArray
                for py in 0..<patchSize {
                    for px in 0..<patchSize {
                        let sy = y + py
                        let sx = x + px
                        
                        // Buffer is bottom-up in CGContext depending on coordinate system, but let's assume standard top-down for index math
                        // Actually CGContext origin is bottom-left, so: y=0 is bottom.
                        // Wait, iOS/macOS CGContext draws bottom-up.
                        let pixelIndex = (sy * paddedWidth + sx) * 4
                        // Normalized [0, 1] coming from float buffer
                        let r = sourceBuffer[pixelIndex]
                        let g = sourceBuffer[pixelIndex + 1]
                        let b = sourceBuffer[pixelIndex + 2]
                        
                        // Map to [-1, 1]
                        ptr[0 * patchSize * patchSize + py * patchSize + px] = r * 2.0 - 1.0
                        ptr[1 * patchSize * patchSize + py * patchSize + px] = g * 2.0 - 1.0
                        ptr[2 * patchSize * patchSize + py * patchSize + px] = b * 2.0 - 1.0
                    }
                }
                
                let inputFeature = try MLDictionaryFeatureProvider(dictionary: ["input": MLFeatureValue(multiArray: multiArray)])
                let output = try model.prediction(from: inputFeature)
                
                guard let outValue = output.featureValue(for: "output")?.multiArrayValue,
                      let maskValue = output.featureValue(for: "mask_output")?.multiArrayValue else {
                    continue
                }
                
                let outStrides = outValue.strides.map { $0.intValue }
                let maskStrides = maskValue.strides.map { $0.intValue }
                let isOutF16 = outValue.dataType == .float16
                let isMaskF16 = maskValue.dataType == .float16
                
                let outPtrF32 = isOutF16 ? nil : outValue.dataPointer.assumingMemoryBound(to: Float.self)
                let outPtrF16 = isOutF16 ? outValue.dataPointer.assumingMemoryBound(to: Float16.self) : nil
                
                let maskPtrF32 = isMaskF16 ? nil : maskValue.dataPointer.assumingMemoryBound(to: Float.self)
                let maskPtrF16 = isMaskF16 ? maskValue.dataPointer.assumingMemoryBound(to: Float16.self) : nil
                
                func readOut(c: Int, py: Int, px: Int) -> Float {
                    let offset = c * outStrides[1] + py * outStrides[2] + px * outStrides[3]
                    return isOutF16 ? Float(outPtrF16![offset]) : outPtrF32![offset]
                }
                
                func readMask(py: Int, px: Int) -> Float {
                    // Tuple slices might retain or drop dims. Usually mask is [1, 1, 128, 128] or [1, 128, 128].
                    let offset = maskStrides.count == 4 ? (0 * maskStrides[1] + py * maskStrides[2] + px * maskStrides[3]) : (py * maskStrides[maskStrides.count - 2] + px * maskStrides[maskStrides.count - 1])
                    return isMaskF16 ? Float(maskPtrF16![offset]) : maskPtrF32![offset]
                }
                
                for py in 0..<patchSize {
                    for px in 0..<patchSize {
                        let sy = y + py
                        let sx = x + px
                        
                        let r = (readOut(c: 0, py: py, px: px) + 1.0) / 2.0
                        let g = (readOut(c: 1, py: py, px: px) + 1.0) / 2.0
                        let b = (readOut(c: 2, py: py, px: px) + 1.0) / 2.0
                        
                        let mask = readMask(py: py, px: px)
                        
                        // Threshold mask
                        let binaryMask: Float = mask > 0.25 ? 1.0 : 0.0
                        
                        let pixelIndex = (sy * paddedWidth + sx) * 4
                        let origR = sourceBuffer[pixelIndex]
                        let origG = sourceBuffer[pixelIndex + 1]
                        let origB = sourceBuffer[pixelIndex + 2]
                        
                        // Just overwrite, last patch wins (like python merged behavior)
                        let newR = binaryMask > 0 ? r : origR
                        let newG = binaryMask > 0 ? g : origG
                        let newB = binaryMask > 0 ? b : origB
                        
                        accumBuffer[pixelIndex] = newR
                        accumBuffer[pixelIndex + 1] = newG
                        accumBuffer[pixelIndex + 2] = newB
                        accumBuffer[pixelIndex + 3] = 1.0 // Alpha
                        
                        maskAccumBuffer[sy * paddedWidth + sx] = binaryMask
                    }
                }
            }
        }
        
        // Convert accumulated buffers back to CGImage (cropping back to original size)
        var finalColorBytes = [UInt8](repeating: 0, count: width * height * 4)
        var finalMaskBytes = [UInt8](repeating: 0, count: width * height)
        
        for y in 0..<height {
            for x in 0..<width {
                let paddedY = paddedHeight - height + y
                let paddedX = x
                
                let paddedIdx = (paddedY * paddedWidth + paddedX) * 4
                let finalIdx = (y * width + x) * 4 // Normal top-down mapping
                
                finalColorBytes[finalIdx] = UInt8(max(0, min(255, accumBuffer[paddedIdx] * 255.0)))
                finalColorBytes[finalIdx + 1] = UInt8(max(0, min(255, accumBuffer[paddedIdx + 1] * 255.0)))
                finalColorBytes[finalIdx + 2] = UInt8(max(0, min(255, accumBuffer[paddedIdx + 2] * 255.0)))
                finalColorBytes[finalIdx + 3] = 255
                
                let maskIdx = (y * width + x)
                finalMaskBytes[maskIdx] = UInt8(maskAccumBuffer[paddedY * paddedWidth + paddedX] * 255.0)
            }
        }
        
        let outColorSpace = CGColorSpaceCreateDeviceRGB()
        let outContext = CGContext(data: &finalColorBytes, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: outColorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        
        let maskColorSpace = CGColorSpaceCreateDeviceGray()
        let maskContext = CGContext(data: &finalMaskBytes, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width, space: maskColorSpace, bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        
        return (outContext.makeImage()!, maskContext.makeImage()!)
    }
    
    private func strideBy(from: Int, to: Int, by: Int) -> [Int] {
        var values = [Int]()
        for i in stride(from: from, through: to, by: by) {
            values.append(i)
        }
        return values
    }
}
