import SwiftUI

/// Which composition grid, if any, is drawn over the live preview.
enum CompositionGuide: String, CaseIterable, Identifiable {
    case off = "Off"
    case thirds = "Rule of Thirds"
    case goldenRatio = "Golden Ratio"
    case goldenTriangle = "Golden Triangle"
    case diagonals = "Diagonals"
    case goldenSpiral = "Golden Spiral"

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
                case .goldenRatio:
                    let phi = (1 + 5.0.squareRoot()) / 2
                    let a = 1 / phi
                    let b = 1 - a
                    drawGrid(context: context, size: size, fractions: [b, a])
                case .goldenTriangle:
                    drawGoldenTriangle(context: context, size: size)
                case .diagonals:
                    drawDiagonals(context: context, size: size)
                case .goldenSpiral:
                    drawGoldenSpiral(context: context, size: size)
                }
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: Rule of Thirds / Golden Ratio

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

    /// Both corner-to-corner diagonals, forming an X across the frame.
    /// The simplest version of the "diagonal method" -- place your subject
    /// or leading lines along either diagonal for a dynamic composition.
    private func drawDiagonals(context: GraphicsContext, size: CGSize) {
        let lineColor = Color.white.opacity(0.65)
        var path = Path()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: size.width, y: size.height))
        path.move(to: CGPoint(x: size.width, y: 0))
        path.addLine(to: CGPoint(x: 0, y: size.height))
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

    /// Approximates the classic Fibonacci/golden spiral: repeatedly cut the
    /// largest possible square off the current rectangle's longer side,
    /// alternating which end each time so the squares wind inward, and
    /// trace a quarter-circle (via a standard Bezier approximation) across
    /// each square. Phone screens aren't golden-ratio proportioned, so this
    /// is an approximation rather than a mathematically perfect spiral --
    /// but it still traces the same nested, winding shape used to guide
    /// the eye toward a focal point.
    private func drawGoldenSpiral(context: GraphicsContext, size: CGSize) {
        var rect = CGRect(origin: .zero, size: size)
        var path = Path()
        var cutFromFarEnd = false
        var isFirstSegment = true

        for _ in 0..<7 {
            let side = min(rect.width, rect.height)
            guard side > 8 else { break }

            let cutHorizontally = rect.width >= rect.height
            let square: CGRect
            let remaining: CGRect

            if cutHorizontally {
                if !cutFromFarEnd {
                    square = CGRect(x: rect.minX, y: rect.minY, width: side, height: side)
                    remaining = CGRect(x: rect.minX + side, y: rect.minY, width: rect.width - side, height: rect.height)
                } else {
                    square = CGRect(x: rect.maxX - side, y: rect.minY, width: side, height: side)
                    remaining = CGRect(x: rect.minX, y: rect.minY, width: rect.width - side, height: rect.height)
                }
            } else {
                if !cutFromFarEnd {
                    square = CGRect(x: rect.minX, y: rect.minY, width: side, height: side)
                    remaining = CGRect(x: rect.minX, y: rect.minY + side, width: rect.width, height: rect.height - side)
                } else {
                    square = CGRect(x: rect.minX, y: rect.maxY - side, width: side, height: side)
                    remaining = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height - side)
                }
            }

            let topLeft = CGPoint(x: square.minX, y: square.minY)
            let topRight = CGPoint(x: square.maxX, y: square.minY)
            let bottomLeft = CGPoint(x: square.minX, y: square.maxY)
            let bottomRight = CGPoint(x: square.maxX, y: square.maxY)

            // Pick the arc's pivot corner and endpoints so the curve winds
            // consistently as the cut direction alternates.
            let center: CGPoint
            let start: CGPoint
            let end: CGPoint
            if cutHorizontally {
                if !cutFromFarEnd {
                    center = bottomRight; start = topRight; end = bottomLeft
                } else {
                    center = bottomLeft; start = topLeft; end = bottomRight
                }
            } else {
                if !cutFromFarEnd {
                    center = bottomRight; start = bottomLeft; end = topRight
                } else {
                    center = topRight; start = topLeft; end = bottomRight
                }
            }

            let cp1 = CGPoint(x: start.x + kappa * (end.x - center.x), y: start.y + kappa * (end.y - center.y))
            let cp2 = CGPoint(x: end.x + kappa * (start.x - center.x), y: end.y + kappa * (start.y - center.y))

            if isFirstSegment {
                path.move(to: start)
                isFirstSegment = false
            } else {
                path.addLine(to: start)
            }
            path.addCurve(to: end, control1: cp1, control2: cp2)

            rect = remaining
            cutFromFarEnd.toggle()
        }

        context.stroke(path, with: .color(.white.opacity(0.75)), lineWidth: 1.5)
    }
}
