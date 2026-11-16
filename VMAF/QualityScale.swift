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
/// Interpolation happens in linear light. SwiftUI's default `Perceptual`
/// blend takes a muddy brownish path between hue-distinct anchors like orange
/// and yellow, which is exactly the range most encodes occupy.
enum QualityScale {
    struct RGB: Equatable, Hashable {
        var red: Double
        var green: Double
        var blue: Double

        init(_ red: Double, _ green: Double, _ blue: Double) {
            self.red = red
            self.green = green
            self.blue = blue
        }

        /// sRGB electro-optical transfer, so blending happens in linear light.
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

    /// Anchors in sRGB. The ramp saturates below 88 so very poor frames stay
    /// inside the Poor red instead of inventing an undefined color.
    private static let anchors: [(score: Double, rgb: RGB)] = [
        (0, RGB(0.55, 0.10, 0.10)),
        (88, RGB(0.89, 0.17, 0.16)),
        (90, RGB(0.94, 0.45, 0.13)),
        (93, RGB(0.96, 0.63, 0.15)),
        (95, RGB(0.92, 0.80, 0.17)),
        (97, RGB(0.55, 0.79, 0.22)),
        (99, RGB(0.18, 0.74, 0.32)),
        (100, RGB(0.10, 0.72, 0.47)),
    ]

    /// The score range the ramp is drawn across, so a legend and the plot
    /// cannot disagree about where a color starts.
    static let rampDomain = 80.0...100.0

    static func rgb(at score: Double) -> RGB {
        let s = max(anchors.first!.score, min(anchors.last!.score, score))
        for lower in anchors where lower.score >= s { return lower.rgb }
        for index in 0..<(anchors.count - 1) {
            let a = anchors[index]
            let b = anchors[index + 1]
            if s >= a.score && s <= b.score {
                guard b.score > a.score else { return b.rgb }
                return RGB.blend(a.rgb, b.rgb, (s - a.score) / (b.score - a.score))
            }
        }
        return anchors.last!.rgb
    }

    static func color(at score: Double) -> Color { rgb(at: score).color }

    /// Gradient stops across `rampDomain`, for the legend bar.
    static func legendStops(in domain: ClosedRange<Double> = rampDomain) -> [Gradient.Stop] {
        let steps = 12
        let span = domain.upperBound - domain.lowerBound
        guard span > 0 else { return [Gradient.Stop(color: color(at: domain.lowerBound), location: 0)] }
        return (0...steps).map { step in
            let location = Double(step) / Double(steps)
            return Gradient.Stop(
                color: color(at: domain.lowerBound + span * location),
                location: location
            )
        }
    }
}
