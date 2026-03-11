import SwiftUI
import CoreGraphics
import CoreML

public struct ImageItem: Identifiable, Equatable {
    public let id = UUID()
    public let url: URL
    public let thumbnail: NSImage
    
    public var streaksMask: CGImage? // 1-channel mask 
    public var obbs: [OBBResult] = []
    public var hasBeenDetected: Bool = false
    
    public static func ==(lhs: ImageItem, rhs: ImageItem) -> Bool {
        lhs.id == rhs.id
    }
}

public struct StackedImageItem: Identifiable, Equatable {
    public let id: UUID
    public let name: String
    public let cgImage: CGImage
    
    public init(id: UUID = UUID(), name: String, cgImage: CGImage) {
        self.id = id
        self.name = name
        self.cgImage = cgImage
    }
    
    public static func ==(lhs: StackedImageItem, rhs: StackedImageItem) -> Bool {
        lhs.id == rhs.id
    }
}

@MainActor
public class StarTrailsViewModel: ObservableObject {
    @Published public var images: [ImageItem] = []
    @Published public var selectedImageID: UUID?
    
    @Published public var isProcessing = false
    @Published public var statusMessage = "Ready"
    @Published public var progress: Double = 0.0
    @Published public var batchSize: Int = 4
    @Published public var fadeAmount: Double = 0.2
    
    @Published public var stackedImages: [StackedImageItem] = []
    
    @Published public var yoloLoaded = false
    @Published public var gapFillLoaded = false
    
    private let imageStacker = ImageStacker()
    private var yoloPredictor: YOLOPredictor? {
        didSet { DispatchQueue.main.async { self.yoloLoaded = self.yoloPredictor != nil } }
    }
    private var gapFiller: GapFiller? {
        didSet { DispatchQueue.main.async { self.gapFillLoaded = self.gapFiller != nil } }
    }
    
    public init() {
        loadDefaultModels()
    }
    
    public func addImages(urls: [URL]) {
        for url in urls {
            // Memory efficient thumbnail extraction (prevents RAM leaks loading 400+ images)
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: 150
            ]
            
            if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
               let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
                let thumb = NSImage(cgImage: cgImage, size: .zero)
                let item = ImageItem(url: url, thumbnail: thumb)
                images.append(item)
            }
        }
        if selectedImageID == nil {
            selectedImageID = images.first?.id
        }
    }
    
    public func loadDefaultModels() {
        // Use a safe accessor that works in both standard macOS .app and swift build scenarios
        let bundleLoader: Bundle? = {
            if let resourcesURL = Bundle.main.resourceURL {
                let checkURL = resourcesURL.appendingPathComponent("StarTrailsApp_StarTrailsApp.bundle")
                if let resolved = Bundle(url: checkURL) { return resolved }
            }
            return Bundle.module
        }()
        
        if let streaksURL = bundleLoader?.url(forResource: "streaks", withExtension: "mlpackage") {
            loadYOLOModel(url: streaksURL)
        }
        if let gapFillURL = bundleLoader?.url(forResource: "gapfill", withExtension: "mlpackage") {
            loadGapFillModel(url: gapFillURL)
        }
    }
    
    public func loadYOLOModel(url: URL) {
        do {
            let compiledURL = url.pathExtension == "mlpackage" ? try MLModel.compileModel(at: url) : url
            self.yoloPredictor = try YOLOPredictor(modelURL: compiledURL)
            self.statusMessage = "Loaded Streaks model"
        } catch {
            self.statusMessage = "Failed to load Streaks model: \(error)"
            print("Streaks load error: \(error)")
        }
    }
    
    public func loadGapFillModel(url: URL) {
        do {
            let compiledURL = url.pathExtension == "mlpackage" ? try MLModel.compileModel(at: url) : url
            self.gapFiller = try GapFiller(modelURL: compiledURL)
            self.statusMessage = "Loaded GapFill model"
        } catch {
            self.statusMessage = "Failed to load GapFill model: \(error)"
            print("GapFill load error: \(error)")
        }
    }
    
    public var isStackedImageSelected: Bool {
        guard let id = selectedImageID else { return false }
        return stackedImages.contains(where: { $0.id == id })
    }
    
    public func detectStreaks() async {
        guard let predictor = self.yoloPredictor else {
            self.statusMessage = "Model not loaded"
            return
        }
        
        let startTime = Date()
        self.isProcessing = true
        self.statusMessage = "Detecting streaks... (0/\(images.count))"
        
        let total = images.count
        for chunkStart in stride(from: 0, to: total, by: batchSize) {
            let chunkEnd = min(chunkStart + batchSize, total)
            
            await withTaskGroup(of: (Int, [OBBResult]).self) { group in
                for i in chunkStart..<chunkEnd {
                    let path = images[i].url.path
                    group.addTask {
                        let results = (try? predictor.predict(imagePath: path)) ?? []
                        return (i, results)
                    }
                }
                
                for await (index, results) in group {
                    images[index].obbs = results
                    images[index].hasBeenDetected = true
                }
            }
            
            let completed = chunkEnd
            let elapsed = Date().timeIntervalSince(startTime)
            let remaining = (elapsed / Double(completed)) * Double(total - completed)
            self.progress = Double(completed) / Double(total)
            self.statusMessage = String(format: "Detecting streaks (%d/%d) - Elapsed: %.1fs, Remaining: %.1fs", completed, total, elapsed, remaining)
        }
        
        self.progress = 1.0
        self.statusMessage = String(format: "Streaks detected (%d/%d) in %.1fs.", total, total, Date().timeIntervalSince(startTime))
        self.isProcessing = false
    }
    
    public func filterStaticStreaks() async {
        let startTime = Date()
        self.isProcessing = true
        self.statusMessage = "Filtering static persistent boxes..."
        
        let total = images.count
        guard total > 0 else {
            self.isProcessing = false
            return
        }
        
        // Background thread with MainActor protection for UI updates
        for i in 0..<total {
            var keptOBBs = [OBBResult]()
            for box in images[i].obbs {
                var occurrences = 0
                
                // Compare with all frames
                for j in 0..<total {
                    if i == j { continue }
                    
                    let hasMatch = images[j].obbs.contains { other in
                        let dist = hypot(box.cx - other.cx, box.cy - other.cy)
                        return dist < 40.0 // 40 pixels distance tolerance for "static"
                    }
                    if hasMatch { occurrences += 1 }
                }
                
                // If it appears in > 50% of the frames, it's a fixed object (pole, cable)
                if occurrences < Int(Float(total) * 0.50) {
                    keptOBBs.append(box)
                }
            }
            images[i].obbs = keptOBBs
            
            self.progress = Double(i + 1) / Double(total)
            self.statusMessage = String(format: "Filtering static objects (%.1f%%)", self.progress * 100)
            await Task.yield()
        }
        
        self.statusMessage = String(format: "Finished filtering static objects in %.1fs.", Date().timeIntervalSince(startTime))
        self.progress = 1.0
        self.isProcessing = false
    }
    
    public func fillGaps() async {
        guard let filler = self.gapFiller else {
            self.statusMessage = "GapFill model not loaded."
            return
        }
        guard let selectedID = self.selectedImageID,
              let stackedIdx = self.stackedImages.firstIndex(where: { $0.id == selectedID }) else {
            self.statusMessage = "No stacked image selected. Please select a stacked image first."
            return
        }
        
        let cgImage = self.stackedImages[stackedIdx].cgImage
        
        let startTime = Date()
        self.isProcessing = true
        self.statusMessage = "Filling gaps on stacked image..."
        
        do {
            let result = try await filler.fillGaps(in: cgImage) { progressVal in
                Task { @MainActor in
                    self.progress = progressVal
                    self.statusMessage = String(format: "Filling gaps... %.1f%%", progressVal * 100)
                }
            }
            
            if let r = result {
                self.stackedImages[stackedIdx] = StackedImageItem(id: selectedID, name: self.stackedImages[stackedIdx].name, cgImage: r.filledImage)
                self.statusMessage = String(format: "Gaps filled on stacked image in %.1fs.", Date().timeIntervalSince(startTime))
            } else {
                self.statusMessage = "Failed to fill gaps."
            }
        } catch {
            print("Error filling gaps: \(error)")
            self.statusMessage = "Error filling gaps."
        }
        
        self.isProcessing = false
        self.progress = 1.0
    }
    
    public func stackImages() async {
        let startTime = Date()
        self.isProcessing = true
        self.statusMessage = "Stacking images... (0/\(images.count))"
        self.imageStacker.reset()
        
        let newID = UUID()
        let newName = "output_image\(self.stackedImages.count)"
        // It will be updated progressively, we'll insert a blank or wait for the first chunk. Let's just append after the first chunk or create a dummy 1x1 image, but better to insert it dynamically or let the user see it appear.
        // Actually, we can wait until the first image is stacked, or we can create an empty image if needed. Let's just create it at the end of the first iteration.
        self.selectedImageID = newID
        
        // Stacking does not parallelize nicely if accumulated, so we run synchronously but grouped for UI progress.
        // Grab local reference to ImageStacker (which is now @unchecked Sendable) to pass to background thread
        let stacker = self.imageStacker
        
        let total = images.count
        let gradient = makeFadeGradient(frameCount: total)
        
        for chunkStart in stride(from: 0, to: total, by: batchSize) {
            let chunkEnd = min(chunkStart + batchSize, total)
            
            // Extract ONLY sendable data required for processing, including Fade Alpha
            let chunkData = self.images[chunkStart..<chunkEnd].enumerated().map { (idx, item) in 
                (url: item.url, obbs: item.obbs, alpha: gradient[chunkStart + idx]) 
            }
            
            await Task.detached {
                // To avoid re-allocating memory for masking
                var maskBuffer: [UInt8] = []
                var currentWidth = 0
                var currentHeight = 0
                
                let ciContext = CIContext(options: [.useSoftwareRenderer: false])
                
                for item in chunkData {
                    autoreleasepool {
                        if let ciImage = CIImage(contentsOf: item.url, options: [.applyOrientationProperty: true]),
                           var cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) {
                            
                            // Mask out the detected streaks with black color
                            if !item.obbs.isEmpty {
                                let width = cgImage.width
                                let height = cgImage.height
                                let bytesPerRow = width * 4
                                
                                // Resize reusable buffer if necessary
                                if width != currentWidth || height != currentHeight {
                                    maskBuffer = [UInt8](repeating: 0, count: height * bytesPerRow)
                                    currentWidth = width
                                    currentHeight = height
                                }
                                
                                let colorSpace = CGColorSpaceCreateDeviceRGB()
                                if let context = CGContext(data: &maskBuffer, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
                                    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
                                    context.setFillColor(NSColor.black.cgColor)
                                    
                                    for obb in item.obbs {
                                        context.saveGState()
                                        // OBB has cx, cy from top-left.
                                        // To map top-left to bottom-left context:
                                        let flippedCy = CGFloat(height) - CGFloat(obb.cy)
                                        context.translateBy(x: CGFloat(obb.cx), y: flippedCy)
                                        // Angle needs to be negated because rotation in bottom-left vs top-left
                                        context.rotate(by: CGFloat(-obb.angle))
                                        let rect = CGRect(x: CGFloat(-obb.w / 2.0),
                                                          y: CGFloat(-obb.h / 2.0),
                                                          width: CGFloat(obb.w),
                                                          height: CGFloat(obb.h))
                                        context.addRect(rect)
                                        context.fillPath()
                                        context.restoreGState()
                                    }
                                    
                                    if let maskedImage = context.makeImage() {
                                        cgImage = maskedImage
                                    }
                                }
                            }
                            stacker.add(image: cgImage, alpha: CGFloat(item.alpha))
                        }
                    }
                }
            }.value
            
            let completed = chunkEnd
            let elapsed = Date().timeIntervalSince(startTime)
            let remaining = (elapsed / Double(completed)) * Double(total - completed)
            self.progress = Double(completed) / Double(total)
            self.statusMessage = String(format: "Stacking images (%d/%d) - Elapsed: %.1fs, Remaining: %.1fs", completed, total, elapsed, remaining)
            
            // Progressive UI Update!
            if let resultCGImage = self.imageStacker.getResult() {
                if let existingIdx = self.stackedImages.firstIndex(where: { $0.id == newID }) {
                    self.stackedImages[existingIdx] = StackedImageItem(id: newID, name: newName, cgImage: resultCGImage)
                } else {
                    self.stackedImages.append(StackedImageItem(id: newID, name: newName, cgImage: resultCGImage))
                }
            }
            await Task.yield()
        }
        
        self.progress = 1.0
        self.statusMessage = String(format: "Stacking complete (%d/%d) in %.1fs.", total, total, Date().timeIntervalSince(startTime))
        self.isProcessing = false
    }
    
    public func saveStackedImage() async {
        guard let selectedID = self.selectedImageID,
              let selectedStacked = self.stackedImages.first(where: { $0.id == selectedID }) else { return }
        
        let cgImage = selectedStacked.cgImage
        
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.jpeg]
        panel.nameFieldStringValue = selectedStacked.name + ".jpg"
        panel.title = "Save Final Image"
        
        // Ensure UI displays over the main window
        if let window = NSApplication.shared.windows.first {
            let response = await panel.beginSheetModal(for: window)
            if response == .OK, let url = panel.url {
                saveImage(cgImage: cgImage, to: url)
            }
        } else {
            let response = panel.runModal()
            if response == .OK, let url = panel.url {
                saveImage(cgImage: cgImage, to: url)
            }
        }
    }
    
    private func saveImage(cgImage: CGImage, to url: URL) {
        let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
        if let jpegData = bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: NSNumber(value: 0.95)]) {
            do {
                try jpegData.write(to: url)
                self.statusMessage = "Image saved successfully."
            } catch {
                print("Failed to save image: \(error)")
                self.statusMessage = "Failed to save image: \(error.localizedDescription)"
            }
        }
    }
    
    private func makeFadeGradient(frameCount: Int) -> [Double] {
        let fadeFrameStartCount = Int(fadeAmount * Double(frameCount))
        let fadeFrameEndCount = Int(fadeAmount * Double(frameCount))

        var fadeGradient = [Double](repeating: 1.0, count: frameCount)
        if fadeFrameStartCount > 0 {
            for i in 0..<fadeFrameStartCount {
                fadeGradient[i] = Double(i + 1) / Double(fadeFrameStartCount)
            }
        }
        if fadeFrameEndCount > 0 {
            for i in 0..<fadeFrameEndCount {
                fadeGradient[frameCount - i - 1] = Double(i + 1) / Double(fadeFrameEndCount)
            }
        }
        return fadeGradient
    }
}

extension NSImage {
    func resized(to newSize: CGSize) -> NSImage? {
        let newImage = NSImage(size: newSize)
        newImage.lockFocus()
        self.draw(in: NSRect(origin: .zero, size: newSize),
                  from: NSRect(origin: .zero, size: self.size),
                  operation: .copy,
                  fraction: 1.0)
        newImage.unlockFocus()
        return newImage
    }
}
