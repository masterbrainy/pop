import SwiftUI

/// The fallback living page (`StillPanScene`): the still drifts in a slow pan and zoom, so a
/// page still feels alive when Orbis is off, failed, or hasn't started yet.
struct StillPanView: View {
    let image: UIImage
    var isMoving = true

    @State private var forward = false

    var body: some View {
        GeometryReader { proxy in
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: proxy.size.width, height: proxy.size.height)
                .scaleEffect(forward && isMoving ? 1.12 : 1.02)
                .offset(x: forward && isMoving ? -proxy.size.width * 0.03 : proxy.size.width * 0.02)
                .clipped()
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 14).repeatForever(autoreverses: true)) { forward = true }
        }
        .accessibilityHidden(true)
    }
}
