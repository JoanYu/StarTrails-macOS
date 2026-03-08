import Foundation
import CoreGraphics
import Accelerate
import simd

public final class ImageStacker: @unchecked Sendable {
    
    // Accumulator for the maximum values
    private var maxBuffer: [UInt8] = []
    private var currentBuffer: [UInt8] = []
    private var isFirst = true
    private var width: Int = 0
    private var height: Int = 0
    private var bytesPerRow: Int = 0
    
    public init() {}
    
    /// Stacks an image into the current accumulator.
    /// Expects all images to have the same dimensions.
    public func add(image: CGImage, alpha: CGFloat = 1.0) {
        if isFirst {
            width = image.width
            height = image.height
            bytesPerRow = width * 4 // Assuming 32-bit RGBA
            maxBuffer = [UInt8](repeating: 0, count: bytesPerRow * height)
            currentBuffer = [UInt8](repeating: 0, count: bytesPerRow * height)
            
            draw(image: image, to: &maxBuffer, alpha: alpha)
            isFirst = false
        } else {
            guard image.width == width && image.height == height else {
                print("Image sizes do not match. Skipping.")
                return
            }
            
            draw(image: image, to: &currentBuffer, alpha: alpha)
            
            maxBuffer.withUnsafeMutableBufferPointer { destPtr in
                currentBuffer.withUnsafeMutableBufferPointer { srcPtr in
                    let count = destPtr.count
                    
                    // Hardware-accelerated SIMD pixel-wise Maximum using SIMD pointers
                    // Unsafe raw pointers allow us to read chunks of 64 contiguous bytes at once
                    srcPtr.withMemoryRebound(to: SIMD64<UInt8>.self) { srcSimd in
                        destPtr.withMemoryRebound(to: SIMD64<UInt8>.self) { destSimd in
                            for i in 0..<destSimd.count {
                                // .max is an accelerated single-cycle SIMD instruction on ARM Neon
                                destSimd[i] = simd_max(srcSimd[i], destSimd[i])
                            }
                        }
                    }
                    
                    // Handle the remaining unaligned tail elements scalar-wise
                    let remainder = count % 64
                    if remainder > 0 {
                        let offset = count - remainder
                        for i in offset..<count {
                            destPtr[i] = max(srcPtr[i], destPtr[i])
                        }
                    }
                }
            }
        }
    }
    
    /// Returns the final stacked image
    public func getResult() -> CGImage? {
        guard !isFirst else { return nil }
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(data: &maxBuffer,
                                width: width,
                                height: height,
                                bitsPerComponent: 8,
                                bytesPerRow: bytesPerRow,
                                space: colorSpace,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        
        return context?.makeImage()
    }
    
    public func reset() {
        isFirst = true
        maxBuffer.removeAll(keepingCapacity: false)
        currentBuffer.removeAll(keepingCapacity: false)
    }
    
    private func draw(image: CGImage, to buffer: inout [UInt8], alpha: CGFloat = 1.0) {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        if let context = CGContext(data: &buffer,
                                   width: width,
                                   height: height,
                                   bitsPerComponent: 8,
                                   bytesPerRow: bytesPerRow,
                                   space: colorSpace,
                                   bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
            
            // To ensure consistency, clear and draw
            context.clear(CGRect(x: 0, y: 0, width: width, height: height))
            context.setAlpha(alpha)
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
    }
}
