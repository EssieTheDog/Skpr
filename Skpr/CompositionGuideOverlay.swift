import SwiftUI

/// Which composition grid, if any, is drawn over the live preview.
enum CompositionGuide: String, CaseIterable, Identifiable {
    case off = "Off"
    case thirds = "Rule of Thirds"
    case goldenRatio = "Golden Ratio"

    var id: String { rawValue }
}

/// Draws thin guide lines over the live camera preview to help with
/// composition -- purely visual, never affects the actual photo.
struct CompositionGuideOverlay: View {
    let guide: CompositionGuide

    var body: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                switch guide {
                case .off:
                    break
                case .thirds:
                    drawGrid(context: context, size: size, fractions: [1.0 / 3, 2.0 / 3])
                case .goldenRatio:
                    // phi ~= 1.618; 1/phi ~= 0.618, 1 - 1/phi ~= 0.382.
                    let phi = (1 + 5.0.squareRoot()) / 2
                    let a = 1 / phi
                    let b = 1 - a
                    drawGrid(context: context, size: size, fractions: [b, a])
                }
            }
        }
        .allowsHitTesting(false)
    }

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
}
