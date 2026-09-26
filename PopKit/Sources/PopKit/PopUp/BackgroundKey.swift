import CoreGraphics

/// Cuts a generated character out of its backdrop (ROADMAP Phase 4). Gemini's "flat"
/// backgrounds come back textured and not quite the colour asked for, and a character can
/// share that colour (a green dragon on green), so this samples the backdrop from the image's
/// border and clears only the pixels connected to the edges that are close to it.
public enum BackgroundKey {
    /// Clears the edge-connected backdrop; `tolerance` is the RGB distance (0…1) still counted
    /// as backdrop, measured against the border's median colour.
    public static func removeBackground(from image: CGImage, tolerance: Double = 0.16) -> CGImage? {
        let width = image.width
        let height = image.height
        guard width > 2, height > 2, var pixels = rgba(image) else { return nil }
        let backdrop = borderMedian(pixels, width: width, height: height)
        let limit = tolerance * tolerance * 3 * 255 * 255

        func isBackdrop(_ index: Int) -> Bool {
            let offset = index * 4
            let dr = Double(pixels[offset]) - backdrop.0
            let dg = Double(pixels[offset + 1]) - backdrop.1
            let db = Double(pixels[offset + 2]) - backdrop.2
            return dr * dr + dg * dg + db * db <= limit
        }

        var visited = [Bool](repeating: false, count: width * height)
        var stack: [Int] = []
        stack.reserveCapacity(width * 4)
        for x in 0..<width {
            stack.append(x)
            stack.append((height - 1) * width + x)
        }
        for y in 0..<height {
            stack.append(y * width)
            stack.append(y * width + width - 1)
        }
        while let index = stack.popLast() {
            guard !visited[index] else { continue }
            visited[index] = true
            guard isBackdrop(index) else { continue }
            pixels[index * 4 + 3] = 0
            pixels[index * 4] = 0
            pixels[index * 4 + 1] = 0
            pixels[index * 4 + 2] = 0
            let x = index % width
            let y = index / width
            if x > 0 { stack.append(index - 1) }
            if x < width - 1 { stack.append(index + 1) }
            if y > 0 { stack.append(index - width) }
            if y < height - 1 { stack.append(index + width) }
        }
        return makeImage(&pixels, width: width, height: height)
    }

    /// The image's pixels as premultiplied RGBA bytes, row by row.
    public static func rgba(_ image: CGImage) -> [UInt8]? {
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                                          bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        return drawn ? pixels : nil
    }

    /// Paints a solid rectangle (x, y, width, height in pixels from the top left); for tests.
    static func paint(_ image: CGImage, rect: (Int, Int, Int, Int), color: (UInt8, UInt8, UInt8)) -> CGImage? {
        guard var pixels = rgba(image) else { return nil }
        for y in rect.1..<(rect.1 + rect.3) {
            for x in rect.0..<(rect.0 + rect.2) {
                let offset = (y * image.width + x) * 4
                pixels[offset] = color.0
                pixels[offset + 1] = color.1
                pixels[offset + 2] = color.2
                pixels[offset + 3] = 255
            }
        }
        return makeImage(&pixels, width: image.width, height: image.height)
    }

    private static func borderMedian(_ pixels: [UInt8], width: Int, height: Int) -> (Double, Double, Double) {
        var reds: [UInt8] = []
        var greens: [UInt8] = []
        var blues: [UInt8] = []
        func add(_ x: Int, _ y: Int) {
            let offset = (y * width + x) * 4
            reds.append(pixels[offset])
            greens.append(pixels[offset + 1])
            blues.append(pixels[offset + 2])
        }
        for x in 0..<width {
            add(x, 0)
            add(x, height - 1)
        }
        for y in 0..<height {
            add(0, y)
            add(width - 1, y)
        }
        func median(_ values: [UInt8]) -> Double { Double(values.sorted()[values.count / 2]) }
        return (median(reds), median(greens), median(blues))
    }

    private static func makeImage(_ pixels: inout [UInt8], width: Int, height: Int) -> CGImage? {
        pixels.withUnsafeMutableBytes { buffer in
            CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
        }
    }
}
