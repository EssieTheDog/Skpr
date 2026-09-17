import SwiftUI

/// Which composition grid, if any, is drawn over the live preview.
enum CompositionGuide: String, CaseIterable, Identifiable {
    case off = "Off"
    case thirds = "Rule of Thirds"
    case phiGrid = "Phi Grid"
    case goldenTriangle = "Golden Triangle"
    case diagonals = "Diagonals"
    case goldenSpiral = "Golden Spiral"
    case harmonicArmature = "Harmonic Armature"

    var id: String { rawValue }
}

/// Draws thin guide lines over the live camera preview to help with
/// composition -- purely visual, drawn with Canvas, never touches the
/// actual captured photo.
struct CompositionGuideOverlay: View {
    let guide: CompositionGuide

    private let kappa = 4.0 / 3.0 * (2.0.squareRoot() - 1) // ~0.5523, standard quarter-circle Bezier constant

    var body: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                switch guide {
                case .off:
                    break
                case .thirds:
                    drawGrid(context: context, size: size, fractions: [1.0 / 3, 2.0 / 3])
                case .phiGrid:
                    // Golden ratio ~= 0.618. Line 1 sits at 61.8% from the
                    // left; line 2 sits at 61.8% from the right (i.e. 38.2%
                    // from the left). That splits each axis into
                    // 38.2% : 23.6% : 38.2% -- a narrower center band
                    // flanked by two wider, equal outer sections.
                    let phi = (1 + 5.0.squareRoot()) / 2
                    let a = 1 / phi   // 0.618
                    let b = 1 - a     // 0.382
                    drawGrid(context: context, size: size, fractions: [b, a])
                case .goldenTriangle:
                    drawGoldenTriangle(context: context, size: size)
                case .diagonals:
                    drawDiagonals(context: context, size: size)
                case .goldenSpiral:
                    drawGoldenSpiral(context: context, size: size)
                case .harmonicArmature:
                    drawHarmonicArmature(context: context, size: size)
                }
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: Rule of Thirds / Phi Grid

    private func drawGrid(context: GraphicsContext, size: CGSize, fractions: [CGFloat]) {
        let lineColor = Color.white.opacity(0.65)
        for fraction in fractions {
            var vertical = Path()
            vertical.move(to: CGPoint(x: size.width * fraction, y: 0))
            vertical.addLine(to: CGPoint(x: size.width * fraction, y: size.height))
            context.stroke(vertical, with: .color(lineColor), lineWidth: 1)

            var horizontal = Path()
            horizontal.move(to: CGPoint(x: 0, y: size.height * fraction))
            horizontal.addLine(to: CGPoint(x: size.width, y: size.height * fraction))
            context.stroke(horizontal, with: .color(lineColor), lineWidth: 1)
        }
    }

    // MARK: Diagonals

    /// A true 45-degree line from each of the 4 corners, each running into
    /// the frame until it hits an edge -- not the corner-to-corner diagonal
    /// (which is only 45 degrees if the frame happens to be square).
    private func drawDiagonals(context: GraphicsContext, size: CGSize) {
        let lineColor = Color.white.opacity(0.65)
        let w = size.width, h = size.height
        let s = min(w, h) // distance traveled before a 45-degree line exits the frame

        var path = Path()
        // Top-left, heading down-right.
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: s, y: s))
        // Top-right, heading down-left.
        path.move(to: CGPoint(x: w, y: 0))
        path.addLine(to: CGPoint(x: w - s, y: s))
        // Bottom-left, heading up-right.
        path.move(to: CGPoint(x: 0, y: h))
        path.addLine(to: CGPoint(x: s, y: h - s))
        // Bottom-right, heading up-left.
        path.move(to: CGPoint(x: w, y: h))
        path.addLine(to: CGPoint(x: w - s, y: h - s))

        context.stroke(path, with: .color(lineColor), lineWidth: 1)
    }

    // MARK: Golden Triangle

    /// One main diagonal (top-left to bottom-right) plus two "reciprocal"
    /// lines, each dropped perpendicular to the main diagonal from one of
    /// the other two corners -- splitting the frame into four triangles.
    private func drawGoldenTriangle(context: GraphicsContext, size: CGSize) {
        let lineColor = Color.white.opacity(0.65)
        let w = size.width, h = size.height
        let d = CGPoint(x: w, y: h) // direction of the main diagonal, from (0,0)

        func footOfPerpendicular(from q: CGPoint) -> CGPoint {
            let t = (q.x * d.x + q.y * d.y) / (d.x * d.x + d.y * d.y)
            return CGPoint(x: t * d.x, y: t * d.y)
        }

        var path = Path()
        // Main diagonal.
        path.move(to: .zero)
        path.addLine(to: CGPoint(x: w, y: h))

        // Reciprocal from the top-right corner.
        let topRight = CGPoint(x: w, y: 0)
        path.move(to: topRight)
        path.addLine(to: footOfPerpendicular(from: topRight))

        // Reciprocal from the bottom-left corner.
        let bottomLeft = CGPoint(x: 0, y: h)
        path.move(to: bottomLeft)
        path.addLine(to: footOfPerpendicular(from: bottomLeft))

        context.stroke(path, with: .color(lineColor), lineWidth: 1)
    }

    // MARK: Golden Spiral

    /// The classic Fibonacci spiral: repeatedly cut the largest possible
    /// square off the current rectangle's longer side. Which end each cut
    /// comes from alternates independently per axis (horizontal cuts go
    /// left, right, left, right...; vertical cuts go bottom, top, bottom,
    /// top...), which is what makes consecutive squares wind in a single
    /// consistent direction instead of bouncing around. Verified by hand
    /// against the standard 1,1,2,3,5,8,13 square-Fibonacci construction.
    /// Draws both the nested-square subdivision lines and the curved arc
    /// that winds through them.
    private func drawGoldenSpiral(context: GraphicsContext, size: CGSize) {
        enum CutSide { case left, right, top, bottom }

        var rect = CGRect(origin: .zero, size: size)
        var nextHorizontalFromRight = false // horizontal cuts: left, right, left, right...
        var nextVerticalFromBottom = true   // vertical cuts: bottom, top, bottom, top...

        var linesPath = Path()
        var curvePath = Path()
        var isFirstSquare = true

        for _ in 0..<8 {
            let side = min(rect.width, rect.height)
            guard side > 6 else { break }

            let cutSide: CutSide
            if rect.width >= rect.height {
                cutSide = nextHorizontalFromRight ? .right : .left
                nextHorizontalFromRight.toggle()
            } else {
                cutSide = nextVerticalFromBottom ? .bottom : .top
                nextVerticalFromBottom.toggle()
            }

            let square: CGRect
            let remaining: CGRect
            let dividerStart: CGPoint
            let dividerEnd: CGPoint

            switch cutSide {
            case .left:
                square = CGRect(x: rect.minX, y: rect.minY, width: side, height: side)
                remaining = CGRect(x: rect.minX + side, y: rect.minY, width: rect.width - side, height: rect.height)
                dividerStart = CGPoint(x: rect.minX + side, y: rect.minY)
                dividerEnd = CGPoint(x: rect.minX + side, y: rect.minY + side)
            case .right:
                square = CGRect(x: rect.maxX - side, y: rect.minY, width: side, height: side)
                remaining = CGRect(x: rect.minX, y: rect.minY, width: rect.width - side, height: rect.height)
                dividerStart = CGPoint(x: rect.maxX - side, y: rect.minY)
                dividerEnd = CGPoint(x: rect.maxX - side, y: rect.minY + side)
            case .bottom:
                square = CGRect(x: rect.minX, y: rect.maxY - side, width: side, height: side)
                remaining = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height - side)
                dividerStart = CGPoint(x: rect.minX, y: rect.maxY - side)
                dividerEnd = CGPoint(x: rect.minX + side, y: rect.maxY - side)
            case .top:
                square = CGRect(x: rect.minX, y: rect.minY, width: side, height: side)
                remaining = CGRect(x: rect.minX, y: rect.minY + side, width: rect.width, height: rect.height - side)
                dividerStart = CGPoint(x: rect.minX, y: rect.minY + side)
                dividerEnd = CGPoint(x: rect.minX + side, y: rect.minY + side)
            }

            linesPath.move(to: dividerStart)
            linesPath.addLine(to: dividerEnd)

            let topLeft = CGPoint(x: square.minX, y: square.minY)
            let topRight = CGPoint(x: square.maxX, y: square.minY)
            let bottomLeft = CGPoint(x: square.minX, y: square.maxY)
            let bottomRight = CGPoint(x: square.maxX, y: square.maxY)

            // Verified mapping: which corner is the arc's pivot/center, and
            // which two (always diagonal to each other) are its endpoints.
            let pivot: CGPoint, entry: CGPoint, exit: CGPoint
            switch cutSide {
            case .left:   pivot = topLeft;     entry = bottomLeft; exit = topRight
            case .right:  pivot = bottomRight; entry = topRight;   exit = bottomLeft
            case .bottom: pivot = bottomLeft;  entry = bottomRight; exit = topLeft
            case .top:    pivot = topRight;    entry = topLeft;    exit = bottomRight
            }

            let cp1 = CGPoint(x: entry.x + kappa * (exit.x - pivot.x), y: entry.y + kappa * (exit.y - pivot.y))
            let cp2 = CGPoint(x: exit.x + kappa * (entry.x - pivot.x), y: exit.y + kappa * (entry.y - pivot.y))

            if isFirstSquare {
                curvePath.move(to: entry)
                isFirstSquare = false
            }
            curvePath.addCurve(to: exit, control1: cp1, control2: cp2)

            rect = remaining
        }

        context.stroke(linesPath, with: .color(.white.opacity(0.35)), lineWidth: 1)
        context.stroke(curvePath, with: .color(.white.opacity(0.85)), lineWidth: 1.5)
    }

    // MARK: Harmonic Armature

    /// The classical "armature of the rectangle": both main diagonals, the
    /// vertical and horizontal center lines, plus each corner connected to
    /// the two edge-midpoints on the sides it doesn't touch. (The diamond
    /// connecting the four edge-midpoints to each other is deliberately
    /// left out.)
    private func drawHarmonicArmature(context: GraphicsContext, size: CGSize) {
        let w = size.width, h = size.height
        let tl = CGPoint(x: 0, y: 0)
        let tr = CGPoint(x: w, y: 0)
        let br = CGPoint(x: w, y: h)
        let bl = CGPoint(x: 0, y: h)
        let tm = CGPoint(x: w / 2, y: 0)
        let bm = CGPoint(x: w / 2, y: h)
        let lm = CGPoint(x: 0, y: h / 2)
        let rm = CGPoint(x: w, y: h / 2)

        let segments: [(CGPoint, CGPoint)] = [
            // The two main diagonals.
            (tl, br), (tr, bl),
            // Vertical and horizontal center lines.
            (tm, bm), (lm, rm),
            // Each corner to the two midpoints on its far (non-adjacent) sides.
            (tl, rm), (tl, bm),
            (tr, bm), (tr, lm),
            (br, tm), (br, lm),
            (bl, tm), (bl, rm)
        ]

        var path = Path()
        for (start, end) in segments {
            path.move(to: start)
            path.addLine(to: end)
        }

        context.stroke(path, with: .color(.white.opacity(0.5)), lineWidth: 1)
    }
}
