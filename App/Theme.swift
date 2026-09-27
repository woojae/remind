import AppKit
import SwiftUI

/// The look of woojae.com, brought to the Mac: white windows with dark title
/// bars and a marker-pen wordmark. (The site's sky-blue desktop survives only
/// in the app icon; on a Mac the real desktop is behind the window already.)
/// Every colour the app paints comes from here so the palette stays in one place.
enum Theme {
    static let ink        = Color(hex: 0x131417)
    static let body       = Color(hex: 0x55585f)   // secondary copy inside a window
    static let muted      = Color(hex: 0x82868f)
    static let windowBG   = Color.white
    static let titlebar   = Color(hex: 0x1b1b1e)
    static let accent     = Color(hex: 0x2f6cb0)
    static let field      = Color(hex: 0xf2f3f5)   // inputs and quiet buttons
    static let rule       = Color(hex: 0xececec)
    static let danger     = Color(hex: 0xe5484d)
    static let hover      = accent.opacity(0.10)
    static let highlight  = accent.opacity(0.16)

    static let windowRadius: CGFloat = 16
    static let titlebarHeight: CGFloat = 46
    /// Windows that carry the macOS traffic lights use a taller bar: with a
    /// hidden title bar and a unified toolbar the lights sit 26pt from the
    /// top, so 52pt centres them.
    static let chromeTitlebarHeight: CGFloat = 52
    static let controlRadius: CGFloat = 10

    /// Permanent Marker, bundled in Resources/Fonts; Marker Felt if it failed
    /// to register for some reason.
    static func mark(_ size: CGFloat) -> Font {
        NSFont(name: "Permanent Marker", size: size) != nil
            ? .custom("Permanent Marker", size: size)
            : .custom("Marker Felt", size: size)
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

// MARK: - Window chrome

/// A white window with a dark title bar, like `.window` on the site. The
/// optional close dot mirrors the site's `.window-close`; windows that have
/// macOS's own controls leave it out. `mark` sets the title in the marker
/// font, the way the site's wordmark is. `floating` adds the rounded corners
/// and shadow for a window drawn inside another; a window that *is* the
/// macOS window turns it off.
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
            content
        }
        .background(Theme.windowBG)
        .clipShape(shape)
        .shadow(color: .black.opacity(floating ? 0.24 : 0), radius: 24, y: 14)
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
            HStack {
                if let onClose {
                    Button(action: onClose) {
                        Circle().fill(.white).frame(width: 16, height: 16)
                    }
                    .buttonStyle(.plain)
                    .help("Close")
                }
                Spacer()
                if let trailing {
                    Text(trailing)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .padding(.horizontal, 15)
            // `mark` sets a small wordmark in the marker font, tilted like
            // the site's logo; otherwise a plain window title.
            Text(title)
                .font(mark ? Theme.mark(15) : .system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .rotationEffect(.degrees(mark ? -2 : 0))
                .lineLimit(1)
                .padding(.horizontal, 80)
        }
        .frame(height: height)
    }
}

/// The 1px separators the site uses between a window body and its status bar.
struct Rule: View {
    var body: some View { Theme.rule.frame(height: 1) }
}

/// Uppercase group label, like `.links-date`.
struct SectionLabel: View {
    let title: String
    let count: Int
    var tint: Color = Theme.muted

    var body: some View {
        HStack(spacing: 6) {
            Text(title.uppercased()).tracking(0.9).foregroundStyle(tint)
            Text("\(count)").foregroundStyle(Theme.muted)
        }
        .font(.system(size: 11.5, weight: .bold))
    }
}

/// The site's "hello." — a marker headline with a short bold line under it.
struct MarkHeadline: View {
    let mark: String
    let sub: String

    var body: some View {
        VStack(spacing: 14) {
            Text(mark)
                .font(Theme.mark(42))
                .foregroundStyle(Theme.ink)
                .rotationEffect(.degrees(-2))
            Text(sub)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
    }
}

// MARK: - Controls

/// `.pomo-btn`: a flat rounded pill. Primary is filled with the accent.
struct PillButtonStyle: ButtonStyle {
    enum Kind { case primary, quiet }
    var kind: Kind = .quiet

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(kind == .primary ? Color.white : Theme.ink)
            .padding(.horizontal, 18)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                    .fill(kind == .primary ? Theme.accent : Theme.field)
            )
            .shadow(color: kind == .primary ? Theme.accent.opacity(0.35) : .clear, radius: 8, y: 4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// `.window-statusbar a`: an accent-coloured text link.
struct LinkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(Theme.accent)
            .underline(configuration.isPressed)
            .contentShape(Rectangle())
    }
}

/// An input the way the site draws them: no border, a soft grey fill.
struct FieldBox<Content: View>: View {
    let label: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.system(size: 11, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(Theme.muted)
            content()
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous).fill(Theme.field))
        }
    }
}

// MARK: - Window plumbing

/// The theme is light-only, like the site, so each themed window is pinned
/// to the Aqua appearance regardless of the system setting. Also hands the
/// NSWindow to the caller for per-window tweaks (floating, draggable, …).
private struct WindowStyler: NSViewRepresentable {
    var configure: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.appearance = NSAppearance(named: .aqua)
            configure(window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

extension View {
    func themedWindow(_ configure: @escaping (NSWindow) -> Void = { _ in }) -> some View {
        environment(\.colorScheme, .light)
            .tint(Theme.accent)
            .background(WindowStyler(configure: configure))
    }
}
