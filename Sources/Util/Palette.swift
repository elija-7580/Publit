import Foundation

/// Status and accent colours. The iOS system green and orange reach only about 2.2:1 on white,
/// which is too faint for the live/delay times people read at a glance, so light mode uses
/// darker tones (all at least 4.5:1 on white and on grouped backgrounds). Dark mode keeps the
/// system tones, which already pass on black.
public enum Palette {
    public struct Tone: Sendable { public let light: String; public let dark: String }
    public static let live   = Tone(light: "1b7a33", dark: "30d158")
    public static let delay  = Tone(light: "b25000", dark: "ff9f0a")
    public static let danger = Tone(light: "d70015", dark: "ff453a")
    public static let accent = Tone(light: "0066d6", dark: "0a84ff")
    public static let all: [Tone] = [live, delay, danger, accent]
    /// System background colours the tones are drawn on (light: white and grouped grey; dark: black and grouped dark grey).
    public static let lightBackgrounds = ["ffffff", "f2f2f7"]
    public static let darkBackgrounds = ["000000", "1c1c1e"]
}
