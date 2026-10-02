import CoreGraphics

/// Where the map goes on each page of an exported PDF (FR-IO-05). Plain
/// geometry, so page counts and placement are tested without drawing.
///
/// Picture and page rectangles are measured from the top-left corner, as the
/// canvas does; `transform(for:pictureHeight:)` turns that into PDF's
/// bottom-left coordinates.
nonisolated struct PDFPageLayout: Equatable {
    struct Page: Equatable {
        /// The part of the picture on this page, in picture points.
        let source: CGRect
        /// Where that part lands on the page, in PDF points.
        let destination: CGRect
    }

    /// The page, turned to landscape when that suits the map better.
    let pageSize: CGSize
    /// PDF points per picture point.
    let scale: CGFloat
    /// In reading order: left to right, then top to bottom.
    let pages: [Page]

    /// - Parameters:
    ///   - content: The picture's size in points.
    ///   - paper: The portrait paper size in PDF points.
    ///   - margin: Blank paper kept on every side.
    init(content: CGSize, paper: CGSize, mode: PDFPageMode, margin: CGFloat) {
        let portrait = CGSize(width: min(paper.width, paper.height), height: max(paper.width, paper.height))
        let landscape = CGSize(width: portrait.height, height: portrait.width)
        let content = CGSize(width: max(content.width, 1), height: max(content.height, 1))

        switch mode {
        case .singlePage:
            let page = content.width > content.height ? landscape : portrait
            let printable = Self.printable(page, margin: margin)
            // A small map stays at actual size rather than being blown up.
            let scale = min(1, printable.width / content.width, printable.height / content.height)
            let size = CGSize(width: content.width * scale, height: content.height * scale)
            let destination = CGRect(
                x: margin + (printable.width - size.width) / 2,
                y: margin + (printable.height - size.height) / 2,
                width: size.width,
                height: size.height
            )
            self.pageSize = page
            self.scale = scale
            self.pages = [Page(source: CGRect(origin: .zero, size: content), destination: destination)]

        case .multiplePages:
            // The orientation that needs fewer sheets; portrait on a tie.
            let page = Self.grid(content, on: landscape, margin: margin).count < Self.grid(content, on: portrait, margin: margin).count
                ? landscape : portrait
            self.pageSize = page
            self.scale = 1
            self.pages = Self.grid(content, on: page, margin: margin)
        }
    }

    private static func printable(_ page: CGSize, margin: CGFloat) -> CGSize {
        CGSize(width: max(page.width - 2 * margin, 1), height: max(page.height - 2 * margin, 1))
    }

    /// Tiles the size of the printable area, with the map centred on the grid
    /// so the blank space is shared by the outer pages.
    private static func grid(_ content: CGSize, on page: CGSize, margin: CGFloat) -> [Page] {
        let tile = printable(page, margin: margin)
        // The tolerance keeps a map that fits exactly from spilling onto a page of rounding error.
        let columns = max(1, Int((content.width / tile.width - 1e-6).rounded(.up)))
        let rows = max(1, Int((content.height / tile.height - 1e-6).rounded(.up)))
        let inset = CGPoint(
            x: (CGFloat(columns) * tile.width - content.width) / 2,
            y: (CGFloat(rows) * tile.height - content.height) / 2
        )
        let bounds = CGRect(origin: .zero, size: content)
        var pages: [Page] = []
        pages.reserveCapacity(columns * rows)
        for row in 0..<rows {
            for column in 0..<columns {
                let cell = CGRect(
                    x: CGFloat(column) * tile.width - inset.x,
                    y: CGFloat(row) * tile.height - inset.y,
                    width: tile.width,
                    height: tile.height
                )
                let source = cell.intersection(bounds)
                guard !source.isNull, source.width > 0, source.height > 0 else { continue }
                let destination = CGRect(
                    x: margin + source.minX - cell.minX,
                    y: margin + source.minY - cell.minY,
                    width: source.width,
                    height: source.height
                )
                pages.append(Page(source: source, destination: destination))
            }
        }
        return pages
    }

    /// Maps the picture, as a renderer draws it into a bottom-left-origin
    /// context (its top edge at `pictureHeight`), onto `page`.
    func transform(for page: Page, pictureHeight: CGFloat) -> CGAffineTransform {
        // A picture point p is drawn at (p.x, pictureHeight − p.y); it belongs at
        // destination.min + (p − source.min) × scale, measured from the page's top.
        let x = page.destination.minX - page.source.minX * scale
        let y = pageSize.height - page.destination.minY + page.source.minY * scale - pictureHeight * scale
        return CGAffineTransform(translationX: x, y: y).scaledBy(x: scale, y: scale)
    }

    /// The destination in PDF coordinates, for clipping a tile to its page.
    func clip(for page: Page) -> CGRect {
        CGRect(
            x: page.destination.minX,
            y: pageSize.height - page.destination.maxY,
            width: page.destination.width,
            height: page.destination.height
        )
    }
}
