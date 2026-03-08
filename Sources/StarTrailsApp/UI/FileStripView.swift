import SwiftUI

struct FileStripView: View {
    @ObservedObject var viewModel: StarTrailsViewModel
    
    var body: some View {
        HStack(spacing: 0) {
            // Stacked Images Container (Fixed on the left)
            if !viewModel.stackedImages.isEmpty {
                ScrollView(.horizontal, showsIndicators: true) {
                    HStack(spacing: 10) {
                        ForEach(viewModel.stackedImages) { stacked in
                            VStack {
                                Image(nsImage: NSImage(cgImage: stacked.cgImage, size: CGSize(width: 80, height: 80)))
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 80, height: 80)
                                    .cornerRadius(8)
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.blue, lineWidth: viewModel.selectedImageID == stacked.id ? 3 : .zero))
                                
                                Text(stacked.name)
                                    .font(.caption2)
                                    .lineLimit(1)
                                    .frame(width: 80)
                            }
                            .padding(.leading, 10)
                            .onTapGesture {
                                viewModel.selectedImageID = stacked.id
                            }
                        }
                    }
                    .padding(.vertical, 10)
                    .padding(.trailing, 10)
                }
                .frame(maxWidth: 300) // Constrain the list so it doesn't take over
                
                Divider()
            }
            
            // Source Images Frames
            ScrollView(.horizontal, showsIndicators: true) {
                HStack(spacing: 10) {
                    ForEach(viewModel.images) { item in
                        VStack {
                            ZStack(alignment: .topTrailing) {
                                Image(nsImage: item.thumbnail)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 80, height: 80)
                                    .cornerRadius(8)
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.blue, lineWidth: viewModel.selectedImageID == item.id ? 3 : .zero))
                                
                                // Status indicators
                                HStack(spacing: 2) {
                                    if item.hasBeenDetected {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                            .background(Circle().fill(Color.white))
                                            .font(.system(size: 14))
                                            .padding(2)
                                    }
                                }
                            }
                            
                            Text(item.url.lastPathComponent)
                                .font(.caption2)
                                .lineLimit(1)
                                .frame(width: 80)
                        }
                        .onTapGesture {
                            viewModel.selectedImageID = item.id
                        }
                    }
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 5)
            }
        }
        .frame(height: 120)
        .background(Color(NSColor.controlBackgroundColor))
    }
}
