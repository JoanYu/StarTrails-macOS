import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var viewModel = StarTrailsViewModel()
    @StateObject private var monitor = ResourceMonitor()
    
    var body: some View {
        HStack(spacing: 0) {
            // Sidebar Controls
            VStack(alignment: .leading, spacing: 20) {
                Text("Controls")
                    .font(.headline)
                
                VStack(spacing: 8) {
                    HStack {
                        Button(action: {
                            if let url = selectModel() {
                                viewModel.loadYOLOModel(url: url)
                            }
                        }) {
                            Label("Load Streaks", systemImage: viewModel.yoloLoaded ? "checkmark.circle.fill" : "xmark.circle.fill")
                        }
                        .foregroundColor(viewModel.yoloLoaded ? .green : .primary)
                        
                        Button(action: {
                            if let url = selectModel() {
                                viewModel.loadGapFillModel(url: url)
                            }
                        }) {
                            Label("Load GapFill", systemImage: viewModel.gapFillLoaded ? "checkmark.circle.fill" : "xmark.circle.fill")
                        }
                        .foregroundColor(viewModel.gapFillLoaded ? .green : .primary)
                    }
                    .font(.caption)
                }
                
                Divider()
                
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    Button(action: {
                        addImages()
                    }) {
                        VStack {
                            Image(systemName: "photo.on.rectangle.angled")
                                .font(.system(size: 20))
                                .padding(.bottom, 2)
                            Text("Load Images")
                                .font(.caption)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity, minHeight: 60)
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.isProcessing)
                    
                    Button(action: {
                        Task { await viewModel.detectStreaks() }
                    }) {
                        VStack {
                            Image(systemName: "viewfinder")
                                .font(.system(size: 20))
                                .padding(.bottom, 2)
                            Text("Detect Streaks")
                                .font(.caption)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity, minHeight: 60)
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.images.isEmpty || viewModel.isProcessing || !viewModel.yoloLoaded)
                    
                    Button(action: {
                        Task { await viewModel.filterStaticStreaks() }
                    }) {
                        VStack {
                            Image(systemName: "camera.filters")
                                .font(.system(size: 20))
                                .padding(.bottom, 2)
                            Text("Filter Static")
                                .font(.caption)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity, minHeight: 60)
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.images.isEmpty || viewModel.isProcessing || !viewModel.images.contains(where: { $0.hasBeenDetected }))
                    
                    Button(action: {
                        Task { await viewModel.stackImages() }
                    }) {
                        VStack {
                            Image(systemName: "square.stack.3d.up.fill")
                                .font(.system(size: 20))
                                .padding(.bottom, 2)
                            Text("Stack Images")
                                .font(.caption)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity, minHeight: 60)
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.images.isEmpty || viewModel.isProcessing)
                    
                    Button(action: {
                        Task { await viewModel.fillGaps() }
                    }) {
                        VStack {
                            Image(systemName: "wand.and.stars.inverse")
                                .font(.system(size: 20))
                                .padding(.bottom, 2)
                            Text("Fill Gaps")
                                .font(.caption)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity, minHeight: 60)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!viewModel.isStackedImageSelected || viewModel.isProcessing || !viewModel.gapFillLoaded)
                    
                    Button(action: {
                        Task { await viewModel.saveStackedImage() }
                    }) {
                        VStack {
                            Image(systemName: "square.and.arrow.down")
                                .font(.system(size: 20))
                                .padding(.bottom, 2)
                            Text("Save Output")
                                .font(.caption)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity, minHeight: 60)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!viewModel.isStackedImageSelected || viewModel.isProcessing)
                }
                
                Divider()
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "cpu")
                            .foregroundColor(.secondary)
                        Text("Batch Size:")
                            .font(.caption)
                            .fontWeight(.medium)
                        Spacer()
                        TextField("", value: $viewModel.batchSize, format: .number)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .frame(width: 45)
                            .multilineTextAlignment(.center)
                            .font(.caption.monospacedDigit())
                        Stepper("", value: $viewModel.batchSize, in: 1...32)
                            .labelsHidden()
                    }
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.05)))
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "circle.lefthalf.filled")
                            .foregroundColor(.secondary)
                        Text("Fade Mode:")
                            .font(.caption)
                            .fontWeight(.medium)
                        Spacer()
                        TextField("", value: $viewModel.fadeAmount, format: .number)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .frame(width: 45)
                            .multilineTextAlignment(.center)
                            .font(.caption.monospacedDigit())
                        Stepper("", value: $viewModel.fadeAmount, in: 0.0...0.5, step: 0.05)
                            .labelsHidden()
                    }
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.05)))
                
                Spacer()
                
                if viewModel.isProcessing {
                    VStack(alignment: .leading) {
                        ProgressView(value: viewModel.progress)
                            .padding(.vertical, 8)
                        Text(viewModel.statusMessage)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Divider()
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("System Resources")
                        .font(.caption)
                        .bold()
                    Text(String(format: "CPU: %.1f%%", monitor.cpuUsage))
                        .font(.caption2)
                    Text(String(format: "Mem: %.0f MB / %.0f MB", monitor.memoryUsage, monitor.totalMemory))
                        .font(.caption2)
                }
                .padding(.top, 5)
            }
            .padding()
            .frame(width: 250)
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // Main Area
            VStack(spacing: 0) {
                // Canvas
                CanvasView(viewModel: viewModel)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                Divider()
                
                // File Strip
                FileStripView(viewModel: viewModel)
            }
        }
        .onAppear {
            monitor.startMonitoring()
        }
        .onDisappear {
            monitor.stopMonitoring()
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            var added = false
            for provider in providers {
                if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                    provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                        if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                            DispatchQueue.main.async {
                                viewModel.addImages(urls: [url])
                            }
                        } else if let url = item as? URL {
                            DispatchQueue.main.async {
                                viewModel.addImages(urls: [url])
                            }
                        }
                    }
                    added = true
                }
            }
            return added
        }
    }
    
    private func addImages() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK {
            viewModel.addImages(urls: panel.urls)
        }
    }
    
    private func selectModel() -> URL? {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.treatsFilePackagesAsDirectories = false // Crucial for selecting .mlpackage bundles
        
        if panel.runModal() == .OK {
            return panel.url
        }
        return nil
    }
}
