import CoreGraphics
import CoreImage
import Foundation

/// Turns a picture rendered on a flat chroma background into an alpha-masked
/// cutout, for the pop-up's layered plate and character cutouts
/// (docs/CONTRACTS.md §3 `art`: `cutout` and `plate` are drawn on flat
/// chroma green `#00FF00`).
public enum ChromaKey {
    public struct Color: Sendable, Equatable {
        public let red: CGFloat
        public let green: CGFloat
        public let blue: CGFloat

        public init(red: CGFloat, green: CGFloat, blue: CGFloat) {
            self.red = red
            self.green = green
            self.blue = blue
        }

        /// `#00FF00`, the contract's fixed chroma color.
        public static let chromaGreen = Color(red: 0, green: 1, blue: 0)
    }

    /// Every pixel within `tolerance` (Euclidean distance in 0...1 RGB space) of
    /// `chroma` becomes fully transparent; every other pixel keeps its color, fully
    /// opaque. Built with a `CIColorCube` lookup table rather than a custom kernel,
    /// so it needs no Metal shader compilation. Returns `nil` only if CoreImage
    /// itself fails to render the filtered image.
    public static func apply(
        to image: CGImage, chroma: Color = .chromaGreen, tolerance: CGFloat = 0.35, cubeDimension: Int = 32, context: CIContext = CIContext()
    ) -> CGImage? {
        // Skip color matching: the cube's lattice is built directly in the image's
        // own raw RGB values, so it must see those same raw values, not ones
        // reinterpreted into CoreImage's working color space.
        let ciImage = CIImage(cgImage: image, options: [.colorSpace: NSNull()])
        guard
            let filter = CIFilter(name: "CIColorCube", parameters: [
                kCIInputImageKey: ciImage,
                "inputCubeDimension": cubeDimension,
                "inputCubeData": colorCubeData(chroma: chroma, tolerance: tolerance, dimension: cubeDimension),
            ]),
            let output = filter.outputImage
        else { return nil }

        return context.createCGImage(output, from: ciImage.extent, format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
    }

    /// A `dimension`³ RGBA float lattice: identity color, alpha 0 near `chroma`
    /// and 1 elsewhere. Ordered R fastest, then G, then B, per `CIColorCube`'s
    /// documented layout.
    private static func colorCubeData(chroma: Color, tolerance: CGFloat, dimension: Int) -> Data {
        let toleranceSquared = tolerance * tolerance
        var samples = [Float](repeating: 0, count: dimension * dimension * dimension * 4)
        var offset = 0
        for b in 0..<dimension {
            let blue = CGFloat(b) / CGFloat(dimension - 1)
            for g in 0..<dimension {
                let green = CGFloat(g) / CGFloat(dimension - 1)
                for r in 0..<dimension {
                    let red = CGFloat(r) / CGFloat(dimension - 1)
                    let dr = red - chroma.red, dg = green - chroma.green, db = blue - chroma.blue
                    let distanceSquared = dr * dr + dg * dg + db * db
                    samples[offset] = Float(red)
                    samples[offset + 1] = Float(green)
                    samples[offset + 2] = Float(blue)
                    samples[offset + 3] = distanceSquared < toleranceSquared ? 0 : 1
                    offset += 4
                }
            }
        }
        return samples.withUnsafeBufferPointer { Data(buffer: $0) }
    }
}
