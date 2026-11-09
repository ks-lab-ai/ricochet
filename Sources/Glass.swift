import Cocoa
import SwiftUI

// Style commun, repris des widgets de bureau de l'équipe : verre sombre très flouté,
// texte blanc, coins arrondis, filet blanc discret, sélecteurs en pastilles.

enum Glass {
    static let accent = Color(hue: 0.07, saturation: 0.72, brightness: 0.98)
    static let green = Color(hue: 0.34, saturation: 0.78, brightness: 0.96)
    static let red = Color(hue: 0.01, saturation: 0.78, brightness: 0.96)
    static let orange = Color(hue: 0.08, saturation: 0.78, brightness: 0.96)
    static let secondary = Color.white.opacity(0.55)
    static let spring = Animation.spring(response: 0.38, dampingFraction: 0.82)
}

struct VisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .hudWindow
        v.blendingMode = .behindWindow
        v.state = .active
        v.appearance = NSAppearance(named: .darkAqua)
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

extension View {
    /// Curseur en forme de main au survol (macOS 15 et plus récent).
    @ViewBuilder func handCursor() -> some View {
        if #available(macOS 15.0, *) { pointerStyle(.link) } else { self }
    }

    /// Fond d'une fenêtre entière.
    func glassWindow() -> some View {
        background {
            ZStack {
                VisualEffect()
                Color.black.opacity(0.68)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(.white.opacity(0.1), lineWidth: 1))
        .environment(\.colorScheme, .dark)
        .foregroundStyle(.white)
    }

    /// Carte intérieure, légèrement plus claire que la fenêtre.
    func glassCard(padding: CGFloat = 12) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.07)))
    }

    /// Champ de saisie.
    func glassField() -> some View {
        background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(0.08)))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(.white.opacity(0.1)))
    }
}

/// En-tête : icône, titre, et ce qu'on veut à droite.
struct GlassHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 28, height: 28)
            Text(title).font(.system(size: 21, weight: .medium))
            Spacer(minLength: 8)
            trailing
        }
    }
}

/// Petit bouton carré à icône.
struct SquareButton: View {
    let icon: String
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white.opacity(hover ? 0.95 : 0.7))
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(.white.opacity(hover ? 0.14 : 0.07)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .handCursor()
    }
}

/// Bouton plein (vert) pour l'action principale, ou discret pour les autres.
struct GlassButton: ButtonStyle {
    var primary = false
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(primary ? Color.black : Color.white.opacity(0.9))
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(primary ? Glass.accent : Color.white.opacity(0.1)))
            .opacity(enabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.6), value: configuration.isPressed)
            .handCursor()
    }
}

/// Sélecteur en pastilles, la pastille glisse d'une option à l'autre.
struct Pills<T: Hashable>: View {
    let items: [T]
    @Binding var selection: T
    let label: (T) -> String
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items, id: \.self) { item in
                let on = item == selection
                Button {
                    withAnimation(Glass.spring) { selection = item }
                } label: {
                    Text(label(item))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(on ? 1 : 0.5))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .frame(height: 24)
                        .background {
                            if on {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(.white.opacity(0.14))
                                    .matchedGeometryEffect(id: "pill", in: ns)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .handCursor()
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(0.06)))
    }
}

/// Étiquette colorée de statut.
struct StatusTag: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(color.opacity(0.16)))
    }
}

/// Fenêtre sans bordure ni titre, entièrement dessinée par SwiftUI.
final class GlassPanel: NSPanel, NSWindowDelegate {
    /// Se ferme dès qu'on clique ailleurs (fenêtre de la barre de menus).
    var closesOnResign = false
    /// Coin haut gauche à conserver quand la hauteur change.
    var anchorTop: NSPoint?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    convenience init<V: View>(root: V, movable: Bool = true) {
        self.init(contentRect: NSRect(x: 0, y: 0, width: 340, height: 300),
                  styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                  backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        isMovableByWindowBackground = movable
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        appearance = NSAppearance(named: .darkAqua)
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        delegate = self
        contentView = FirstMouseHostingView(rootView: root)
    }

    func windowDidResignKey(_ notification: Notification) {
        if closesOnResign { orderOut(nil) }
    }

    func windowDidResize(_ notification: Notification) {
        if let anchorTop { setFrameTopLeftPoint(anchorTop) }
        invalidateShadow()
    }

    override func cancelOperation(_ sender: Any?) { orderOut(nil) }
}

/// Icône de la barre de menus : l'étoile et ses filets de vitesse, teintée par macOS.
func statusIcon() -> NSImage {
    let image = NSImage(size: NSSize(width: 22, height: 18), flipped: false) { _ in
        NSColor.black.setStroke()
        let center = NSPoint(x: 14, y: 9)
        for i in 0..<9 {
            let a = CGFloat(i) / 9 * 2 * .pi + 0.14
            let r: CGFloat = i % 2 == 0 ? 7.5 : 6.2
            let ray = NSBezierPath()
            ray.lineWidth = 1.7
            ray.lineCapStyle = .round
            ray.move(to: center)
            ray.line(to: NSPoint(x: center.x + cos(a) * r, y: center.y + sin(a) * r))
            ray.stroke()
        }
        for (y, x0, x1) in [(CGFloat(12.5), CGFloat(1.5), CGFloat(5.5)), (9, 0.5, 5), (5.5, 1.5, 5.5)] {
            let streak = NSBezierPath()
            streak.lineWidth = 1.3
            streak.lineCapStyle = .round
            streak.move(to: NSPoint(x: x0, y: y))
            streak.line(to: NSPoint(x: x1, y: y))
            streak.stroke()
        }
        return true
    }
    image.isTemplate = true
    image.accessibilityDescription = "Ricochet"
    return image
}
