//
//  QualityScale.swift
//  VMAF
//
//  The one place a VMAF score is turned into a color or a band name.
//

import AppKit
import SwiftUI

/// Fixed VMAF interpretation bands.
///
/// Bands are absolute score ranges rather than a clip's own min/max, so the
/// same score is painted the same color in every comparison and a clip whose
/// frames all sit at 99.2 is not rendered as "poor". The names are the
/// conventional four-step quality labels; the ranges are printed next to them
/// wherever they appear so nothing reads as a percentage of retained quality.
enum QualityBand: String, CaseIterable, Identifiable {
    case poor = "Poor"
    case fair = "Fair"
    case good = "Good"
    case excellent = "Excellent"

    var id: Self { self }

    /// Position in `allCases`, precomputed per frame for run detection.
    var caseIndex: Int { Self.allCases.firstIndex(of: self) ?? 0 }

    /// Highest score that still reads as this band, exclusive upper bound for
    /// everything below `excellent`.
    static let poorLimit = 90.0
    static let fairLimit = 95.0
    static let goodLimit = 99.0

    /// Score used to sample the ramp for this band's swatch, so the legend
    /// colors come from the same data as the plot.
    private var representativeScore: Double {
        switch self {
        case .poor: return 85.0
        case .fair: return 92.5
        case .good: return 97.0
        case .excellent: return 99.8
        }
    }

    /// Short label for the band's range, e.g. "90 – 95".
    var rangeLabel: String {
        switch self {
        case .poor: return "< \(Int(Self.poorLimit))"
        case .fair: return "\(Int(Self.poorLimit)) – \(Int(Self.fairLimit))"
        case .good: return "\(Int(Self.fairLimit)) – \(Int(Self.goodLimit))"
        case .excellent: return "≥ \(Int(Self.goodLimit))"
        }
    }

    var threshold: Double {
        switch self {
        case .poor: return Self.poorLimit
        case .fair: return Self.fairLimit
        case .good: return Self.goodLimit
        case .excellent: return 100.0
        }
    }

    var tint: Color { QualityScale.color(at: representativeScore) }

    init(vmafScore: Double) {
        switch vmafScore {
        case ..<Self.poorLimit: self = .poor
        case ..<Self.fairLimit: self = .fair
        case ..<Self.goodLimit: self = .good
        default: self = .excellent
        }
    }
}

/// Continuous score → color ramp used by every quality visualization.
///
/// Blending happens in linear light (see `RGB`). SwiftUI's default
/// `Perceptual` blend takes a muddy brownish path between hue-distinct anchors
/// like orange and yellow, which is exactly the range most encodes occupy.
enum QualityScale {
    /// An RGB color kept in **linear light**. Anchors are authored as sRGB and
    /// decoded through `init(srgbRed:green:blue:)`, so `blend` interpolates in
    /// linear light and only `nsColor` re-encodes for display.
    struct RGB: Equatable, Hashable {
        var red: Double
        var green: Double
        var blue: Double

        /// Raw linear-light components.
        init(_ red: Double, _ green: Double, _ blue: Double) {
            self.red = red
            self.green = green
            self.blue = blue
        }

        /// Author a color in the sRGB values a designer would pick.
        init(srgbRed red: Double, green: Double, blue: Double) {
            self.red = Self.decoded(red)
            self.green = Self.decoded(green)
            self.blue = Self.decoded(blue)
        }

        /// sRGB opto-electronic transfer: a display value back to linear light.
        static func decoded(_ channel: Double) -> Double {
            let c = max(0, min(1, channel))
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }

        static func encoded(_ channel: Double) -> Double {
            let c = max(0, min(1, channel))
            return c <= 0.0031308 ? c * 12.92 : 1.055 * pow(c, 1.0 / 2.4) - 0.055
        }

        static func blend(_ lhs: RGB, _ rhs: RGB, _ amount: Double) -> RGB {
            let t = max(0, min(1, amount))
            return RGB(
                lhs.red + (rhs.red - lhs.red) * t,
                lhs.green + (rhs.green - lhs.green) * t,
                lhs.blue + (rhs.blue - lhs.blue) * t
            )
        }

        var nsColor: NSColor {
            NSColor(
                srgbRed: Self.encoded(red),
                green: Self.encoded(green),
                blue: Self.encoded(blue),
                alpha: 1
            )
        }

        var color: Color { Color(nsColor: nsColor) }
    }

    /// Anchors, authored as the sRGB values a designer would pick. The ramp
    /// saturates below 88 so very poor frames stay inside the Poor red instead
    /// of inventing an undefined color.
    private static let anchors: [(score: Double, srgb: (Double, Double, Double))] = [
        (0, (0.55, 0.10, 0.10)),
        (88, (0.89, 0.17, 0.16)),
        (90, (0.94, 0.45, 0.13)),
        (93, (0.96, 0.63, 0.15)),
        (95, (0.92, 0.80, 0.17)),
        (97, (0.55, 0.79, 0.22)),
        (99, (0.18, 0.74, 0.32)),
        (100, (0.10, 0.72, 0.47)),
    ]

    /// Linear-light form of `anchors`, built once. `blend` runs in this space so
    /// orange→yellow travels through a clean orange-gold instead of brown.
    private static let linearAnchors: [(score: Double, rgb: RGB)] = anchors.map {
        ($0.score, RGB(srgbRed: $0.srgb.0, green: $0.srgb.1, blue: $0.srgb.2))
    }

    /// The score range the ramp is drawn across, so a legend and the plot
    /// cannot disagree about where a color starts.
    static let rampDomain = 80.0...100.0

    static func rgb(at score: Double) -> RGB {
        let s = max(linearAnchors.first!.score, min(linearAnchors.last!.score, score))
        for index in 0..<(linearAnchors.count - 1) {
            let a = linearAnchors[index]
            let b = linearAnchors[index + 1]
            if s >= a.score, s <= b.score, b.score > a.score {
                return RGB.blend(a.rgb, b.rgb, (s - a.score) / (b.score - a.score))
            }
        }
        return s <= linearAnchors.first!.score
            ? linearAnchors.first!.rgb
            : linearAnchors.last!.rgb
    }

    static func color(at score: Double) -> Color { rgb(at: score).color }

    /// The scores where the ramp changes slope, exposed so the legend can put
    /// a stop on each one.
    static var anchorScores: [Double] { anchors.map { $0.score } }

    /// Gradient stops across `rampDomain`, for the legend bar.
    ///
    /// The ramp is piecewise-linear **in linear light**, but a gradient
    /// interpolates its stops in display-encoded sRGB — so uniformly spaced
    /// samples drift off the plot's curve (13 stops put the legend near an
    /// olive `(0.61, 0.62, 0.27)` at 95 where the heat map paints
    /// `(0.92, 0.80, 0.17)`). Stops therefore sit on every slope change, and
    /// each span is subdivided into as many pieces as its own curvature
    /// demands to hold the chord within ~1.5/255 of the plot's colour.
    static func legendStops(in domain: ClosedRange<Double> = rampDomain) -> [Gradient.Stop] {
        let span = domain.upperBound - domain.lowerBound
        guard span > 0 else { return [Gradient.Stop(color: color(at: domain.lowerBound), location: 0)] }
        var knots: [Double] = [domain.lowerBound]
        for anchor in anchorScores where anchor > domain.lowerBound && anchor < domain.upperBound {
            knots.append(anchor)
        }
        knots.append(domain.upperBound)
        var stops: [Gradient.Stop] = []
        for index in 0..<(knots.count - 1) {
            let start = knots[index]
            let end = knots[index + 1]
            let pieces = legendPieces(from: start, to: end)
            for piece in 0..<pieces {
                let score = start + (end - start) * Double(piece) / Double(pieces)
                stops.append(Gradient.Stop(
                    color: color(at: score),
                    location: CGFloat((score - domain.lowerBound) / span)
                ))
            }
        }
        stops.append(Gradient.Stop(color: color(at: domain.upperBound), location: 1))
        return stops
    }

    /// Pieces a straight encoded-space chord between `start` and `end` needs
    /// to stay within tolerance of the ramp: measured, not guessed, so flat
    /// spans (deep red below 88) get two stops and sharp turns (97→99) get
    /// many more.
    private static func legendPieces(from start: Double, to end: Double) -> Int {
        let encodedStart = encodedRGB(at: start)
        let encodedEnd = encodedRGB(at: end)
        var worst = 0.0
        for step in 1...8 {
            let t = Double(step) / 9
            let curve = encodedRGB(at: start + (end - start) * t)
            for channel in 0...2 {
                let chord = encodedStart[channel] + (encodedEnd[channel] - encodedStart[channel]) * t
                worst = max(worst, abs(chord - curve[channel]))
            }
        }
        // Empirical, not textbook: doubling stops on the sharpest spans
        // (97→99) halves the chord error, so linear subdivision holds the
        // budget conservatively. Cap keeps a degenerate domain bounded; total
        // stops across 0–100 stay well under 100.
        let tolerance = 1.2 / 255
        guard worst > tolerance else { return 2 }
        let pieces = Int((worst / tolerance).rounded(.up))
        return max(2, min(32, pieces))
    }

    private static func encodedRGB(at score: Double) -> [Double] {
        let linear = rgb(at: score)
        return [RGB.encoded(linear.red), RGB.encoded(linear.green), RGB.encoded(linear.blue)]
    }
}
