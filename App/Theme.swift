import AppKit
import SwiftUI

/// Control-room Remind: a near-black terminal with a faint grid behind it,
/// dot-matrix headlines, monospace copy and one hot accent for whatever is
/// due right now. Think classified telemetry, not a to-do list.
/// Every colour the app paints comes from here so the palette stays in one place.
enum Theme {
    static let ink        = Color(hex: 0xe8e6dd)   // phosphor off-white
    static let body       = Color(hex: 0x9c9b93)   // secondary copy
    static let muted      = Color(hex: 0x5e5f66)
    static let windowBG   = Color(hex: 0x0a0a0c)
    static let titlebar   = Color(hex: 0x0a0a0c)
    static let panel      = Color(hex: 0x121215)   // inputs and quiet buttons
    static let accent     = Color(hex: 0xff2e63)   // the "Kp-05" hot pink
    static let signal     = Color(hex: 0x74f0c8)   // confirmations
    static let rule       = Color(hex: 0x1f1f24)
    static let border     = Color(hex: 0x2a2a30)
    static let grid       = Color.white.opacity(0.045)
    static let danger     = Color(hex: 0xff5a3c)
    static let hover      = Color.white.opacity(0.035)
    static let highlight  = accent.opacity(0.14)

    static let windowRadius: CGFloat = 4
    static let titlebarHeight: CGFloat = 44
    /// Windows that carry the macOS traffic lights use a taller bar: with a
    /// hidden title bar and a unified toolbar the lights sit 26pt from the
    /// top, so 52pt centres them.
    static let chromeTitlebarHeight: CGFloat = 52
    static let controlRadius: CGFloat = 2
    static let gridStep: CGFloat = 22

    enum Weight { case regular, medium, bold }

    /// JetBrains Mono, bundled in Resources/Fonts; the system monospace if
    /// it failed to register for some reason.
    static func mono(_ size: CGFloat, _ weight: Weight = .regular) -> Font {
        let name: String
        switch weight {
        case .regular: name = "JetBrainsMono-Regular"
        case .medium:  name = "JetBrainsMonoRoman-Medium"
        case .bold:    name = "JetBrainsMonoRoman-Bold"
        }
        if NSFont(name: name, size: size) != nil { return .custom(name, size: size) }
        let w: Font.Weight = weight == .regular ? .regular : weight == .medium ? .medium : .bold
        return .system(size: size, weight: w, design: .monospaced)
    }

    /// Doto, the dot-matrix display face used for the wordmark, headlines
    /// and counters. Falls back to bold system monospace.
    static func dot(_ size: CGFloat) -> Font {
        NSFont(name: "Doto-Black_Bold", size: size) != nil
            ? .custom("Doto-Black_Bold", size: size)
            : .system(size: size, weight: .black, design: .monospaced)
    }

    /// Small caps-ish label: mono, uppercase, letterspaced.
    static let labelTracking: CGFloat = 1.6

    /// Two-digit readouts, the way a panel would show them: 03, 12, 99+.
    static func readout(_ n: Int) -> String {
        n > 99 ? "99+" : String(format: "%02d", n)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xff) / 255,
                  green: Double((hex >> 8) & 0xff) / 255,
                  blue: Double(hex & 0xff) / 255,
                  opacity: 1)
    }
}

// MARK: - Backdrop

/// The faint engineering grid behind every window body.
struct GridBackground: View {
    var body: some View {
        Canvas { ctx, size in
            var path = Path()
            var x: CGFloat = 0.5
            while x < size.width { path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: size.height)); x += Theme.gridStep }
            var y: CGFloat = 0.5
            while y < size.height { path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: size.width, y: y)); y += Theme.gridStep }
            ctx.stroke(path, with: .color(Theme.grid), lineWidth: 1)
        }
        .allowsHitTesting(false)
    }
}

/// Four corner brackets, like a targeting reticle drawn around a readout.
struct Reticle: View {
    var color: Color = Theme.muted
    var arm: CGFloat = 10
    var inset: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height, i = inset, a = arm
            Path { p in
                p.move(to: CGPoint(x: i, y: i + a)); p.addLine(to: CGPoint(x: i, y: i)); p.addLine(to: CGPoint(x: i + a, y: i))
                p.move(to: CGPoint(x: w - i - a, y: i)); p.addLine(to: CGPoint(x: w - i, y: i)); p.addLine(to: CGPoint(x: w - i, y: i + a))
                p.move(to: CGPoint(x: i, y: h - i - a)); p.addLine(to: CGPoint(x: i, y: h - i)); p.addLine(to: CGPoint(x: i + a, y: h - i))
                p.move(to: CGPoint(x: w - i - a, y: h - i)); p.addLine(to: CGPoint(x: w - i, y: h - i)); p.addLine(to: CGPoint(x: w - i, y: h - i - a))
            }
            .stroke(color, lineWidth: 1)
        }
        .allowsHitTesting(false)
    }
}

/// A blinking terminal cursor block.
struct Cursor: View {
    var color: Color = Theme.accent

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.6)) { ctx in
            let on = Int(ctx.date.timeIntervalSinceReferenceDate / 0.6) % 2 == 0
            Rectangle()
                .fill(color)
                .frame(width: 7, height: 12)
                .opacity(on ? 1 : 0.15)
        }
    }
}

// MARK: - Window chrome

/// A black window with a thin ruled title bar. The optional close control is
/// a small square; windows that have macOS's own controls leave it out.
/// `mark` sets the title as the dot-matrix wordmark. `floating` adds the
/// rounded corners and shadow for a window drawn inside another; a window
/// that *is* the macOS window turns it off.
struct DesktopWindow<Content: View>: View {
    var title: String
    var trailing: String? = nil
    var onClose: (() -> Void)? = nil
    var mark = false
    var titlebarHeight = Theme.titlebarHeight
    var floating = true
    let content: Content

    init(title: String, trailing: String? = nil, onClose: (() -> Void)? = nil,
         mark: Bool = false, titlebarHeight: CGFloat = Theme.titlebarHeight,
         floating: Bool = true, @ViewBuilder content: () -> Content) {
        self.title = title
        self.trailing = trailing
        self.onClose = onClose
        self.mark = mark
        self.titlebarHeight = titlebarHeight
        self.floating = floating
        self.content = content()
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: floating ? Theme.windowRadius : 0, style: .continuous)
        VStack(spacing: 0) {
            WindowTitlebar(title: title, trailing: trailing, onClose: onClose, mark: mark, height: titlebarHeight)
            Rule()
            content
        }
        .background(GridBackground())
        .background(Theme.windowBG)
        .clipShape(shape)
        .overlay(shape.stroke(Theme.border, lineWidth: floating ? 1 : 0))
        .shadow(color: .black.opacity(floating ? 0.6 : 0), radius: 28, y: 16)
    }
}

struct WindowTitlebar: View {
    var title: String
    var trailing: String? = nil
    var onClose: (() -> Void)? = nil
    var mark = false
    var height = Theme.titlebarHeight

    var body: some View {
        ZStack {
            Theme.titlebar
            HStack(spacing: 10) {
                if let onClose {
                    Button(action: onClose) {
                        Rectangle().fill(Theme.accent).frame(width: 10, height: 10)
                    }
                    .buttonStyle(.plain)
                    .help("Close")
                }
                Spacer()
                if let trailing {
                    Text(trailing)
                        .font(Theme.mono(11, .medium))
                        .tracking(Theme.labelTracking)
                        .textCase(.uppercase)
                        .foregroundStyle(Theme.accent)
                }
            }
            .padding(.horizontal, 16)
            HStack(spacing: 8) {
                Text(title)
                    .font(mark ? Theme.dot(20) : Theme.mono(12, .bold))
                    .tracking(mark ? 3 : Theme.labelTracking)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Text("::").font(Theme.mono(12, .bold)).foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 90)
        }
        .frame(height: height)
    }
}

/// The 1px separators between a window's zones.
struct Rule: View {
    var body: some View { Theme.rule.frame(height: 1) }
}

/// Uppercase group label with a two-digit readout: `NOW :: 03`.
struct SectionLabel: View {
    let title: String
    let count: Int
    var tint: Color = Theme.muted

    var body: some View {
        HStack(spacing: 8) {
            Text(title.uppercased())
                .font(Theme.mono(11, .bold))
                .tracking(Theme.labelTracking)
                .foregroundStyle(tint)
            Text("::").font(Theme.mono(11, .bold)).foregroundStyle(Theme.muted)
            Text(Theme.readout(count))
                .font(Theme.dot(15))
                .foregroundStyle(tint)
            Rectangle().fill(Theme.rule).frame(height: 1)
        }
    }
}

/// A dot-matrix headline with a short mono line under it.
struct MarkHeadline: View {
    let mark: String
    let sub: String

    var body: some View {
        VStack(spacing: 16) {
            Text(mark)
                .font(Theme.dot(40))
                .tracking(4)
                .textCase(.uppercase)
                .foregroundStyle(Theme.ink)
            Text(sub)
                .font(Theme.mono(12))
                .foregroundStyle(Theme.body)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .frame(maxWidth: 320)
        }
        .padding(28)
        .overlay(Reticle(color: Theme.border, arm: 14, inset: 0))
    }
}

// MARK: - Controls

/// A square, letterspaced button. Primary is filled with the accent; quiet
/// is a 1px outline.
struct PillButtonStyle: ButtonStyle {
    enum Kind { case primary, quiet }
    var kind: Kind = .quiet

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
        configuration.label
            .font(Theme.mono(11.5, .bold))
            .tracking(Theme.labelTracking)
            .textCase(.uppercase)
            .foregroundStyle(kind == .primary ? Theme.windowBG : Theme.ink)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(shape.fill(kind == .primary ? Theme.accent : Theme.panel))
            .overlay(shape.stroke(kind == .primary ? Theme.accent : Theme.border, lineWidth: 1))
            .shadow(color: kind == .primary ? Theme.accent.opacity(0.45) : .clear, radius: 10, y: 0)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

/// An accent-coloured text command, `[UNDO]` style.
struct LinkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 0) {
            Text("[").foregroundStyle(Theme.muted)
            configuration.label.foregroundStyle(Theme.accent)
            Text("]").foregroundStyle(Theme.muted)
        }
        .font(Theme.mono(11.5, .bold))
        .textCase(.uppercase)
        .opacity(configuration.isPressed ? 0.6 : 1)
        .contentShape(Rectangle())
    }
}

/// An input: dark panel, 1px border, uppercase label above.
struct FieldBox<Content: View>: View {
    let label: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Text(label.uppercased())
                Text("::").foregroundStyle(Theme.border)
            }
            .font(Theme.mono(10.5, .bold))
            .tracking(Theme.labelTracking)
            .foregroundStyle(Theme.muted)
            content()
                .textFieldStyle(.plain)
                .font(Theme.mono(13))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(shape.fill(Theme.panel))
                .overlay(shape.stroke(Theme.border, lineWidth: 1))
        }
    }
}

// MARK: - Window plumbing

/// The theme is dark-only, so each themed window is pinned to the dark
/// appearance regardless of the system setting. Also hands the NSWindow to
/// the caller for per-window tweaks (floating, draggable, …).
private struct WindowStyler: NSViewRepresentable {
    var configure: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.appearance = NSAppearance(named: .darkAqua)
            configure(window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

extension View {
    func themedWindow(_ configure: @escaping (NSWindow) -> Void = { _ in }) -> some View {
        environment(\.colorScheme, .dark)
            .tint(Theme.accent)
            .background(WindowStyler(configure: configure))
    }
}
