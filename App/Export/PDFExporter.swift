import PopKit
import UIKit

/// PDF export (ROADMAP Phase 6): a cover page, then one landscape spread per page with the
/// text on the left and the picture on the right, like the book on the Duo.
enum PDFExporter {
    static let pageSize = CGSize(width: 792, height: 612)  // US Letter, landscape
    private static let margin: CGFloat = 36

    static func export(_ book: Book, kid: KidProfile, to directory: URL = FileManager.default.temporaryDirectory) throws -> URL {
        let title = book.title ?? book.bible.title ?? "A Pop! story"
        let url = directory.appending(path: "\(safeFileName(title)).pdf")
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize))
        try renderer.writePDF(to: url) { context in
            context.beginPage()
            drawCover(book, title: title, kid: kid)
            for page in book.pages where !page.text.isEmpty {
                context.beginPage()
                drawSpread(page, total: book.pages.count)
            }
        }
        return url
    }

    private static func drawCover(_ book: Book, title: String, kid: KidProfile) {
        UIColor(Theme.coverBottom).setFill()
        UIRectFill(CGRect(origin: .zero, size: pageSize))
        if let image = StillImageLoader.image(for: book.coverPath ?? book.pages.first?.stillPath) {
            let side: CGFloat = 330
            draw(image, filling: CGRect(x: (pageSize.width - side) / 2, y: 60, width: side, height: side), cornerRadius: 24)
        }
        drawText(Book.coverLine(title: title, firstName: kid.firstName),
                 in: CGRect(x: margin, y: 420, width: pageSize.width - margin * 2, height: 120),
                 font: .systemFont(ofSize: 34, weight: .bold), color: .white, alignment: .center)
        drawText("Made with Pop!", in: CGRect(x: margin, y: pageSize.height - 60, width: pageSize.width - margin * 2, height: 24),
                 font: .systemFont(ofSize: 13, weight: .semibold), color: .white.withAlphaComponent(0.8), alignment: .center)
    }

    private static func drawSpread(_ page: PageContent, total: Int) {
        let half = pageSize.width / 2
        UIColor(Theme.paper).setFill()
        UIRectFill(CGRect(origin: .zero, size: pageSize))
        let serif = UIFont(descriptor: UIFont.systemFont(ofSize: 22, weight: .medium).fontDescriptor.withDesign(.serif) ?? UIFont.systemFont(ofSize: 22).fontDescriptor, size: 22)
        drawText(page.text, in: CGRect(x: margin, y: margin * 2, width: half - margin * 2, height: pageSize.height - margin * 4),
                 font: serif, color: UIColor(Theme.ink), alignment: .left)
        drawText("\(page.index + 1)", in: CGRect(x: margin, y: pageSize.height - margin - 16, width: half - margin * 2, height: 16),
                 font: .systemFont(ofSize: 11), color: UIColor(Theme.softInk), alignment: .center)
        let art = CGRect(x: half, y: 0, width: half, height: pageSize.height)
        if let image = StillImageLoader.image(for: page.stillPath) {
            draw(image, filling: art, cornerRadius: 0)
        } else {
            UIColor(Theme.paperShade).setFill()
            UIRectFill(art)
        }
    }

    /// Draws `image` scaled to fill `rect`, cropped to it.
    private static func draw(_ image: UIImage, filling rect: CGRect, cornerRadius: CGFloat) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.saveGState()
        UIBezierPath(roundedRect: rect, cornerRadius: cornerRadius).addClip()
        let scale = max(rect.width / image.size.width, rect.height / image.size.height)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        image.draw(in: CGRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height))
        context.restoreGState()
    }

    private static func drawText(_ text: String, in rect: CGRect, font: UIFont, color: UIColor, alignment: NSTextAlignment) {
        let style = NSMutableParagraphStyle()
        style.alignment = alignment
        style.lineSpacing = font.pointSize * 0.3
        (text as NSString).draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                                attributes: [.font: font, .foregroundColor: color, .paragraphStyle: style], context: nil)
    }

    static func safeFileName(_ title: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(.whitespaces)
        let cleaned = String(title.unicodeScalars.filter { allowed.contains($0) }).trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? "Pop story" : cleaned
    }
}
