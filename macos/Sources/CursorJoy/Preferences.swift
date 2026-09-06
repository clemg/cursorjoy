import Foundation

/// One slider: where it is stored, its legal range, how it is labelled, and
/// what the preview shows while it is being dragged. The view used to carry the
/// last three as parallel arguments, and the two lists drifted apart.
struct Setting {
    let key: String
    let title: String
    let format: String
    let guide: PreviewGuide
    let `default`: Double
    let range: ClosedRange<Double>

    var value: Double { UserDefaults.standard.double(forKey: key) }
    var span: Double { range.upperBound - range.lowerBound }

    /// Native settings sliders have a small dent at the default value.
    func snapped(_ raw: Double) -> Double {
        abs(raw - `default`) < span * 0.025 ? `default` : raw
    }
}

enum Pref {
    static let force = Setting(key: "swing.force", title: "Sensitivity",
                               format: "%.0f", guide: .sensitivity,
                               default: 20, range: 0...80)
    static let maxAngle = Setting(key: "swing.maxAngle", title: "Max tilt",
                                  format: "%.0f°", guide: .tilt,
                                  default: 45, range: 10...130)
    static let frequency = Setting(key: "swing.frequency", title: "Wobble",
                                   format: "%.1f Hz", guide: .wobble,
                                   default: 2.1, range: 0.5...6)
    static let damping = Setting(key: "swing.damping", title: "Damping",
                                 format: "%.2f", guide: .wobble,
                                 default: 0.32, range: 0.02...1)
    static let size = Setting(key: "swing.size", title: "Pointer size",
                              format: "%.2f×", guide: .size,
                              default: 1.0, range: 0.4...1.6)

    /// Every slider, in the order the panel shows them.
    static let all = [force, maxAngle, frequency, damping, size]

    /// Off means the physically natural direction (the body trails the motion).
    static let invertKey = "swing.invert"
    private static let askedLoginKey = "app.askedLaunchAtLogin"

    static var invert: Bool { UserDefaults.standard.bool(forKey: invertKey) }

    static var hasAskedLaunchAtLogin: Bool {
        get { UserDefaults.standard.bool(forKey: askedLoginKey) }
        set { UserDefaults.standard.set(newValue, forKey: askedLoginKey) }
    }

    static func registerDefaults() {
        var defaults: [String: Any] = [invertKey: false]
        for setting in all { defaults[setting.key] = setting.default }
        UserDefaults.standard.register(defaults: defaults)
    }
}

/// A snapshot of the tuning, read once per frame.
struct SwingTune {
    var gain: Double
    var maxAngleDeg: Double
    var frequencyHz: Double
    var damping: Double
    /// +1 natural, -1 inverted.
    var direction: Double

    static var current: SwingTune {
        SwingTune(gain: Pref.force.value,
                  maxAngleDeg: Pref.maxAngle.value,
                  frequencyHz: Pref.frequency.value,
                  damping: Pref.damping.value,
                  direction: Pref.invert ? -1 : 1)
    }
}
