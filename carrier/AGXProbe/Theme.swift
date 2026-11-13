//
//  Theme.swift
//  Bench27
//
//  One palette for the whole app: near-black background, green console text,
//  red only for the things that panic the device.
//

import UIKit

enum Theme {

    // Backdrop
    static let background = UIColor(red: 0.02, green: 0.04, blue: 0.03, alpha: 1)
    static let surface = UIColor(red: 0.045, green: 0.075, blue: 0.06, alpha: 1)
    static let surfaceHigh = UIColor(red: 0.06, green: 0.10, blue: 0.08, alpha: 1)

    // Green family
    static let green = UIColor(red: 0.23, green: 1.0, blue: 0.55, alpha: 1)
    static let greenDim = UIColor(red: 0.18, green: 0.62, blue: 0.38, alpha: 1)
    static let greenSoft = UIColor(red: 0.55, green: 0.95, blue: 0.72, alpha: 1)
    static let greenFaint = UIColor(red: 0.30, green: 0.55, blue: 0.42, alpha: 1)

    // Text
    static let text = UIColor(red: 0.86, green: 0.98, blue: 0.90, alpha: 1)
    static let textDim = UIColor(red: 0.45, green: 0.62, blue: 0.52, alpha: 1)
    static let textFaint = UIColor(red: 0.28, green: 0.40, blue: 0.33, alpha: 1)

    // Signals
    static let warn = UIColor(red: 1.0, green: 0.72, blue: 0.25, alpha: 1)
    static let danger = UIColor(red: 1.0, green: 0.35, blue: 0.35, alpha: 1)
    static let dangerSurface = UIColor(red: 0.16, green: 0.05, blue: 0.05, alpha: 1)
    static let warnSurface = UIColor(red: 0.14, green: 0.10, blue: 0.03, alpha: 1)

    static func mono(_ size: CGFloat, _ weight: UIFont.Weight = .regular) -> UIFont {
        .monospacedSystemFont(ofSize: size, weight: weight)
    }

    static func sans(_ size: CGFloat, _ weight: UIFont.Weight = .regular) -> UIFont {
        .systemFont(ofSize: size, weight: weight)
    }

    /// Wide, spaced-out title: the console look, with tracking instead of a
    /// condensed face.
    static func title(_ text: String, size: CGFloat, colour: UIColor = Theme.green) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: mono(size, .heavy),
            .foregroundColor: colour,
            .kern: size * 0.16,
        ])
    }

    /// Thin green border used on cards and fields.
    static func outline(_ view: UIView, colour: UIColor = Theme.greenDim, width: CGFloat = 1) {
        view.layer.borderWidth = width
        view.layer.borderColor = colour.withAlphaComponent(0.45).cgColor
    }
}

/// A faint terminal grid behind the content, so the screen reads as a console
/// without costing animation time.
final class MatrixBackdrop: UIView {

    private let grid = CAShapeLayer()
    private let glow = CAGradientLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false

        glow.colors = [
            Theme.green.withAlphaComponent(0.10).cgColor,
            UIColor.clear.cgColor,
            Theme.green.withAlphaComponent(0.04).cgColor,
        ]
        glow.locations = [0, 0.45, 1]
        glow.startPoint = CGPoint(x: 0, y: 0)
        glow.endPoint = CGPoint(x: 1, y: 1)
        layer.addSublayer(glow)

        grid.strokeColor = Theme.green.withAlphaComponent(0.05).cgColor
        grid.lineWidth = 0.5
        layer.addSublayer(grid)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        glow.frame = bounds

        let step: CGFloat = 28
        let path = UIBezierPath()
        var x: CGFloat = 0
        while x <= bounds.width {
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: bounds.height))
            x += step
        }
        var y: CGFloat = 0
        while y <= bounds.height {
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: bounds.width, y: y))
            y += step
        }
        grid.path = path.cgPath
        grid.frame = bounds
    }
}

