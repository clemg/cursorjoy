import AppKit
import SwiftUI

/// Shared state between the menu bar, the panel and the overlay.
final class AppModel: ObservableObject {
    @Published var swingEnabled = false { didSet { onSwingChange?(swingEnabled) } }
    @Published var launchAtLogin = false { didSet { onLaunchChange?(launchAtLogin) } }

    var onSwingChange: ((Bool) -> Void)?
    var onLaunchChange: ((Bool) -> Void)?
}

/// Control Centre's shapes: one pane of glass holding flat tiles — pills with a
/// round icon badge, and thick draggable bars. None of this comes from stock
/// controls; `Slider` and `Toggle` render as System Settings, not Control Centre.
struct SettingsView: View {
    @ObservedObject var model: AppModel

    @AppStorage(Pref.invertKey) private var invert = false

    /// Which control is in use, so the preview can explain it.
    @State private var guide: PreviewGuide?

    var body: some View {
        VStack(spacing: 7) {
            PreviewHost(guide: guide, swingEnabled: model.swingEnabled)
                .frame(height: 112)
                .tile()

            Pill(title: "Swing cursor", status: model.swingEnabled ? "On" : "Off",
                 icon: "cursorarrow.motionlines", isOn: $model.swingEnabled)

            VStack(spacing: 10) {
                ForEach(Pref.all, id: \.key) { Bar($0, $guide) }
            }
            .padding(10)
            .tile()

            HStack(spacing: 8) {
                Pill(title: "Invert", status: invert ? "On" : "Off",
                     icon: "arrow.left.arrow.right", isOn: $invert)
                    .onHover { guide = $0 ? .invert : nil }
                Pill(title: "At login", status: model.launchAtLogin ? "On" : "Off",
                     icon: "power", isOn: $model.launchAtLogin)
            }

            Button("Quit Cursor Joy") { NSApp.terminate(nil) }
                .buttonStyle(CapsuleButton())
                .padding(.top, 2)
        }
        .padding(10)
        .frame(width: 320)
    }
}

/// Control Centre's tiles are not flat fills: they are lit from the top and
/// edged with a hairline, and that is where the depth comes from. The base stays
/// semantic so both themes follow the OS; the sheen and the edge are white at low
/// opacity, which is how a real glass edge behaves in light *and* dark.
private struct Tile: ViewModifier {
    var radius: CGFloat = 14

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
    }

    func body(content: Content) -> some View {
        content.background {
            shape
                .fill(Color.primary.opacity(0.06))
                .overlay {
                    shape.fill(LinearGradient(colors: [.white.opacity(0.18), .white.opacity(0.03)],
                                              startPoint: .top, endPoint: .bottom))
                }
                .overlay {
                    shape.strokeBorder(
                        LinearGradient(colors: [.white.opacity(0.34), .white.opacity(0.06)],
                                       startPoint: .top, endPoint: .bottom),
                        lineWidth: 0.8)
                }
        }
    }
}

private extension View {
    func tile(radius: CGFloat = 14) -> some View { modifier(Tile(radius: radius)) }
}

/// Wi-Fi and Bluetooth in Control Centre: a round icon badge that fills with the
/// accent colour when on, a title, and its state underneath. The whole tile taps.
private struct Pill: View {
    let title: String
    let status: String
    let icon: String
    @Binding var isOn: Bool

    var body: some View {
        Button { isOn.toggle() } label: {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isOn ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                    .frame(width: 30, height: 30)
                    .background {
                        Circle().fill(isOn ? AnyShapeStyle(.tint)
                                           : AnyShapeStyle(Color.primary.opacity(0.12)))
                        Circle().fill(LinearGradient(
                            colors: [.white.opacity(isOn ? 0.38 : 0.20), .clear],
                            startPoint: .top, endPoint: .bottom))
                        Circle().strokeBorder(.white.opacity(0.22), lineWidth: 0.8)
                    }
                    .shadow(color: .black.opacity(isOn ? 0.22 : 0), radius: 3, y: 1)
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).font(.system(size: 12, weight: .semibold))
                    Text(status).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .tile()
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.15), value: isOn)
    }
}

/// The brightness and volume bar: a thick capsule you drag anywhere along.
private struct Bar: View {
    let setting: Setting
    @AppStorage private var value: Double
    /// Which control the preview is currently explaining.
    @Binding var active: PreviewGuide?

    init(_ setting: Setting, _ active: Binding<PreviewGuide?>) {
        self.setting = setting
        self._value = AppStorage(wrappedValue: setting.default, setting.key)
        self._active = active
    }

    private var fraction: Double {
        ((value - setting.range.lowerBound) / setting.span).clamped(to: 0...1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(setting.title).font(.system(size: 11, weight: .medium))
                Spacer(minLength: 0)
                Text(String(format: setting.format, value))
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.16))
                        .overlay { Capsule().strokeBorder(.black.opacity(0.10), lineWidth: 0.8) }
                    GlassFill()
                        .overlay {
                            Capsule()
                                .fill(LinearGradient(colors: [.white.opacity(0.45), .clear],
                                                     startPoint: .top, endPoint: .bottom))
                                .allowsHitTesting(false)
                        }
                        .clipShape(.capsule)
                        .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
                        .frame(width: max(geo.size.width * fraction, geo.size.height))
                }
                .contentShape(.rect)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { drag in
                            active = setting.guide
                            let t = (drag.location.x / max(geo.size.width, 1)).clamped(to: 0...1)
                            value = setting.snapped(setting.range.lowerBound + setting.span * t)
                        }
                        .onEnded { _ in active = nil }
                )
                .simultaneousGesture(TapGesture(count: 2).onEnded { value = setting.default })
            }
            .frame(height: 22)
        }
    }
}

/// The slider fill is real AppKit glass. A flat white capsule read as old iOS,
/// and SwiftUI's .glassEffect renders as a flat fill inside this hosting view
/// (the same reason the panel itself uses NSGlassEffectView — see SettingsPanel).
private struct GlassFill: NSViewRepresentable {
    func makeNSView(context: Context) -> CapsuleGlass {
        let view = CapsuleGlass()
        view.style = .regular
        view.tintColor = .white
        return view
    }

    func updateNSView(_ view: CapsuleGlass, context: Context) {}
}

/// NSGlassEffectView takes a corner radius, not a shape, so the capsule has to be
/// re-derived whenever the bar is laid out.
private final class CapsuleGlass: NSGlassEffectView {
    override func layout() {
        super.layout()
        cornerRadius = bounds.height / 2
    }
}

private struct CapsuleButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
            .tile(radius: 100)
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

private struct PreviewHost: NSViewRepresentable {
    let guide: PreviewGuide?
    let swingEnabled: Bool

    func makeNSView(context: Context) -> PreviewView { PreviewView(frame: .zero) }

    func updateNSView(_ view: PreviewView, context: Context) {
        view.guide = guide
        view.swingEnabled = swingEnabled
    }
}
