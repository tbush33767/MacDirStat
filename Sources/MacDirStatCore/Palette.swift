import Foundation

/// 8-bit RGB color, AppKit-free so Core stays UI-independent.
public struct RGB: Hashable, Sendable {
    public var r: UInt8
    public var g: UInt8
    public var b: UInt8
    public init(_ r: UInt8, _ g: UInt8, _ b: UInt8) {
        self.r = r
        self.g = g
        self.b = b
    }

    func scaled(_ factor: Double) -> RGB {
        RGB(
            UInt8(min(255, Double(r) * factor)),
            UInt8(min(255, Double(g) * factor)),
            UInt8(min(255, Double(b) * factor))
        )
    }
}

/// WinDirStat-style extension→color assignment: a set of saturated base hues
/// extended with brightness-stepped variants, handed out to extensions in
/// descending order of total on-disk bytes. Everything else shares grey.
public struct Palette: Sendable {
    public static let grey = RGB(90, 90, 90)
    public static let directoryColor = RGB(110, 110, 110)

    static let baseHues: [RGB] = [
        RGB(0, 0, 255),     // blue
        RGB(255, 0, 0),     // red
        RGB(0, 255, 0),     // green
        RGB(0, 255, 255),   // cyan
        RGB(255, 0, 255),   // magenta
        RGB(255, 255, 0),   // yellow
        RGB(120, 180, 255), // light blue
    ]

    private let colorsByExtension: [String: RGB]

    /// - Parameter extensionsBySize: lowercased extensions, largest total first.
    public init(extensionsBySize: [String]) {
        var map: [String: RGB] = [:]
        var colors: [RGB] = []
        for factor in [1.0, 0.66, 0.4] {
            for hue in Self.baseHues {
                colors.append(hue.scaled(factor))
            }
        }
        for (i, ext) in extensionsBySize.enumerated() {
            map[ext] = i < colors.count ? colors[i] : Self.grey
        }
        colorsByExtension = map
    }

    public func color(forExtension ext: String) -> RGB {
        colorsByExtension[ext] ?? Self.grey
    }
}
