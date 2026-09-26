import SwiftUI
import UIKit

/// The text page's paper in its illustration's pastels: a soft gradient from the picture's top
/// colour to its bottom colour, two blurred watercolour blooms of its overall colour, and a
/// faint mirrored echo of the picture itself rising from the bottom edge.
struct PastelPageBackground: View {
    let palette: PagePalette
    let image: UIImage?

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                LinearGradient(colors: [palette.top, palette.bottom], startPoint: .top, endPoint: .bottom)
                Circle()
                    .fill(palette.wash)
                    .frame(width: size.width * 0.9)
                    .blur(radius: 60)
                    .opacity(0.7)
                    .offset(x: -size.width * 0.35, y: -size.height * 0.3)
                Circle()
                    .fill(palette.wash)
                    .frame(width: size.width * 0.7)
                    .blur(radius: 50)
                    .opacity(0.55)
                    .offset(x: size.width * 0.4, y: size.height * 0.25)
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: size.width, height: size.height)
                        .scaleEffect(x: -1, y: 1)
                        .saturation(0.6)
                        .blur(radius: 2)
                        .opacity(0.22)
                        .mask(
                            LinearGradient(stops: [
                                .init(color: .clear, location: 0),
                                .init(color: .clear, location: 0.55),
                                .init(color: .black, location: 1),
                            ], startPoint: .top, endPoint: .bottom)
                        )
                }
            }
            .frame(width: size.width, height: size.height)
        }
        .clipped()
        .accessibilityHidden(true)
    }
}
