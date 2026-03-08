import SwiftUI

struct CanvasView: View {
    @ObservedObject var viewModel: StarTrailsViewModel
    
    @State private var currentScale: CGFloat = 1.0
    @State private var finalScale: CGFloat = 1.0    
    @State private var currentOffset: CGSize = .zero
    @State private var finalOffset: CGSize = .zero
    
    private var totalScale: CGFloat { max(0.05, min(finalScale * currentScale, 20.0)) }
    private func totalOffset(in size: CGSize) -> CGSize {
        let raw = CGSize(width: finalOffset.width + currentOffset.width,
                         height: finalOffset.height + currentOffset.height)
        let maxOffsetX = max(0, size.width * (totalScale - 1) / 2)
        let maxOffsetY = max(0, size.height * (totalScale - 1) / 2)
        return CGSize(
            width: min(max(raw.width, -maxOffsetX), maxOffsetX),
            height: min(max(raw.height, -maxOffsetY), maxOffsetY)
        )
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(NSColor.darkGray).edgesIgnoringSafeArea(.all)
                
                if viewModel.isStackedImageSelected {
                    // Show Stacked Result
                    if let selectedID = viewModel.selectedImageID,
                       let stacked = viewModel.stackedImages.first(where: { $0.id == selectedID }) {
                        let nsImage = NSImage(cgImage: stacked.cgImage, size: .zero)
                        Image(nsImage: nsImage)
                            .resizable()
                            .scaledToFit()
                            .scaleEffect(totalScale)
                            .offset(totalOffset(in: geometry.size))
                            .gesture(dragGesture(in: geometry.size))
                            .gesture(magnificationGesture)
                            .background(ScrollWheelHandler(scale: $finalScale))
                    }
                } else if let selectedItem = viewModel.images.first(where: { $0.id == viewModel.selectedImageID }) {
                    
                    let imageToDisplay = NSImage(contentsOf: selectedItem.url) ?? NSImage()
                    
                    ZStack {
                        Image(nsImage: imageToDisplay)
                            .resizable()
                            .scaledToFit()
                        
                        // Draw OBBs
                        if !selectedItem.obbs.isEmpty {
                            let pixelWidth = imageToDisplay.representations.first?.pixelsWide ?? Int(imageToDisplay.size.width)
                            let pixelHeight = imageToDisplay.representations.first?.pixelsHigh ?? Int(imageToDisplay.size.height)
                            let trueSize = CGSize(width: pixelWidth, height: pixelHeight)
                            
                            DrawOBBView(obbs: selectedItem.obbs, imageSize: trueSize, viewSize: geometry.size)
                        }
                    }
                    .scaleEffect(totalScale)
                    .offset(totalOffset(in: geometry.size))
                    .gesture(dragGesture(in: geometry.size))
                    .gesture(magnificationGesture)
                    .background(ScrollWheelHandler(scale: $finalScale))
                } else {
                    Text("No image selected")
                        .foregroundColor(.gray)
                }
                
                // Reset View Button overlay
                VStack {
                    HStack {
                        Spacer()
                        Button(action: {
                            withAnimation {
                                finalScale = 1.0
                                currentScale = 1.0
                                finalOffset = .zero
                                currentOffset = .zero
                            }
                        }) {
                            Image(systemName: "arrow.up.left.and.down.right.and.arrow.up.right.and.down.left")
                                .padding(10)
                                .background(Color.black.opacity(0.6))
                                .foregroundColor(.white)
                                .clipShape(Circle())
                        }
                        .buttonStyle(PlainButtonStyle())
                        .padding(20)
                        .help("Reset Zoom and Position")
                    }
                    Spacer()
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }
    
    private func dragGesture(in size: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                currentOffset = value.translation
            }
            .onEnded { value in
                finalOffset = totalOffset(in: size)
                currentOffset = .zero
            }
    }
    
    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                currentScale = value
            }
            .onEnded { value in
                finalScale = max(0.05, min(finalScale * currentScale, 20.0))
                currentScale = 1.0
            }
    }
}

// Custom View to draw the Rotated Rectangles from YOLOPredictor
struct DrawOBBView: View {
    let obbs: [OBBResult]
    let imageSize: CGSize
    let viewSize: CGSize
    
    var body: some View {
        let widthRatio = viewSize.width / imageSize.width
        let heightRatio = viewSize.height / imageSize.height
        let scale = min(widthRatio, heightRatio)
        
        let xOffset = (viewSize.width - imageSize.width * scale) / 2
        let yOffset = (viewSize.height - imageSize.height * scale) / 2
        
        return Canvas { context, size in
            for obb in obbs {
                var path = Path()
                
                let points = obb.corners.map { point in
                    CGPoint(
                        x: CGFloat(point.x) * scale + xOffset,
                        y: CGFloat(point.y) * scale + yOffset
                    )
                }
                
                guard points.count == 4 else { continue }
                
                path.move(to: points[0])
                path.addLine(to: points[1])
                path.addLine(to: points[2])
                path.addLine(to: points[3])
                path.closeSubpath()
                
                context.fill(path, with: .color(Color.red.opacity(0.3)))
                context.stroke(path, with: .color(.red), lineWidth: 2.0)
            }
        }
    }
}

// Intercepts Mouse Scroll Wheel for Zooming
struct ScrollWheelHandler: NSViewRepresentable {
    @Binding var scale: CGFloat
    
    func makeNSView(context: Context) -> NSView {
        let view = ScrollCatchView()
        view.onScroll = { dy in
            DispatchQueue.main.async {
                self.scale = max(0.05, min(self.scale - dy * 0.05, 20.0))
            }
        }
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {}
}

class ScrollCatchView: NSView {
    var onScroll: ((CGFloat) -> Void)?
    
    override var acceptsFirstResponder: Bool { true }
    
    override func scrollWheel(with event: NSEvent) {
        onScroll?(event.scrollingDeltaY)
    }
}
