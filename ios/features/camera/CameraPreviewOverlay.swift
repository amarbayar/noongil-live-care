import SwiftUI

struct CameraPreviewOverlay: View {
    @ObservedObject var cameraService: PhoneCameraService
    let onCapture: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Drag handle
            Capsule()
                .fill(Color.white.opacity(0.4))
                .frame(width: 40, height: 5)
                .padding(.top, 10)

            // Filter badge
            HStack {
                if cameraService.currentFilter != "none" {
                    Text(cameraService.currentFilter.capitalized)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.2))
                        .clipShape(Capsule())
                }

                Spacer()

                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.white.opacity(0.5))
                }
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel("Close camera")
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)

            // Live preview
            Group {
                if let image = cameraService.latestFilteredImage {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .cornerRadius(16)
                } else {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                        .aspectRatio(3.0 / 4.0, contentMode: .fit)
                        .overlay(
                            ProgressView()
                                .tint(.white.opacity(0.5))
                        )
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)

            // Controls
            HStack(spacing: 40) {
                // Camera flip
                Button {
                    Task {
                        let newPosition: PhoneCameraService.CameraPosition =
                            cameraService.currentPosition == .front ? .back : .front
                        await cameraService.switchCamera(to: newPosition)
                    }
                } label: {
                    Image(systemName: "camera.rotate")
                        .font(.title2)
                        .foregroundColor(.white)
                        .frame(width: 60, height: 60)
                }
                .accessibilityLabel("Switch camera")

                // Shutter
                Button(action: onCapture) {
                    Circle()
                        .stroke(Color.white, lineWidth: 4)
                        .frame(width: 72, height: 72)
                        .overlay(
                            Circle()
                                .fill(Color.white)
                                .frame(width: 60, height: 60)
                        )
                }
                .accessibilityLabel("Take photo")

                // Placeholder for symmetry
                Color.clear
                    .frame(width: 60, height: 60)
            }
            .padding(.top, 16)
            .padding(.bottom, 16)
        }
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(Color.white.opacity(0.12))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(0.35), radius: 24, y: -4)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
