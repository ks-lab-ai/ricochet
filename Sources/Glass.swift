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

    /// Fond d'une fenêtre entière. `dim` : opacité du voile noir posé sur le flou.
    func glassWindow(dim: CGFloat = 0.58) -> some View {
        background {
            ZStack {
                VisualEffect()
                Color.black.opacity(dim)
                DragHandle()
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

/// Petit bouton carré à icône, discret ou plein (orange, icône blanche en gras).
struct SquareButton: View {
    let icon: String
    var filled = false
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: filled ? 13 : 11, weight: filled ? .heavy : .bold))
                .foregroundStyle(filled ? Color.white : Color.white.opacity(hover ? 0.95 : 0.7))
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(background))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .handCursor()
    }

    private var background: Color {
        if filled { return Glass.accent.opacity(hover ? 0.85 : 1) }
        return Color.white.opacity(hover ? 0.14 : 0.07)
    }
}

/// Bouton plein (orange) pour l'action principale, ou discret pour les autres.
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

/// Fenêtre sans bordure ni titre, entièrement dessinée par SwiftUI et déplaçable par son fond.
final class GlassPanel: NSPanel, NSWindowDelegate {
    /// Se ferme dès qu'on clique ailleurs (fenêtre de la barre de menus), tant qu'on ne l'a pas déplacée.
    var closesOnResign = false
    /// Coin haut gauche à conserver quand la hauteur change.
    var anchorTop: NSPoint?
    /// Vrai pour le widget : se cale sur la grille au lâcher.
    var snapsToGrid = false
    /// Clé sous laquelle mémoriser la taille choisie par l'utilisateur.
    var sizeKey: String?
    /// Vrai pendant un glisser de la poignée.
    var gripResizing = false
    private var placing = false

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    convenience init<V: View>(root: V, resizable: Bool = false) {
        var mask: NSWindow.StyleMask = [.borderless, .nonactivatingPanel, .fullSizeContentView]
        if resizable { mask.insert(.resizable) }
        self.init(contentRect: NSRect(x: 0, y: 0, width: 340, height: 300),
                  styleMask: mask, backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        appearance = NSAppearance(named: .darkAqua)
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        delegate = self
        let host = FirstMouseHostingView(rootView: root)
        // Redimensionnable : la vue impose seulement sa taille minimale, c'est l'utilisateur qui choisit.
        if resizable { host.sizingOptions = [.minSize] }
        contentView = host
    }

    /// Applique la taille mémorisée, ou la taille par défaut.
    func restoreSize(default size: NSSize) {
        var target = size
        if let sizeKey, let saved = UserDefaults.standard.string(forKey: sizeKey) {
            let z = NSSizeFromString(saved)
            if z.width > 0, z.height > 0 { target = z }
        }
        setContentSize(target)
    }

    /// Fin d'un redimensionnement : mémorise la taille et le nouveau coin haut gauche.
    func finishResize() {
        if anchorTop != nil { anchorTop = NSPoint(x: frame.minX, y: frame.maxY) }
        if let sizeKey { UserDefaults.standard.set(NSStringFromSize(frame.size), forKey: sizeKey) }
        invalidateShadow()
    }

    /// Place la fenêtre par programme, sans la considérer comme déplacée par l'utilisateur.
    func place(top: NSPoint) {
        placing = true
        anchorTop = top
        setFrameTopLeftPoint(top)
        placing = false
    }

    func windowDidResignKey(_ notification: Notification) {
        if closesOnResign { orderOut(nil) }
    }

    func windowDidEndLiveResize(_ notification: Notification) { finishResize() }

    func windowDidMove(_ notification: Notification) {
        guard !placing, !gripResizing, !inLiveResize, anchorTop != nil else { return }
        anchorTop = NSPoint(x: frame.minX, y: frame.maxY)
        closesOnResign = false
    }

    func windowDidResize(_ notification: Notification) {
        if !inLiveResize, !gripResizing, let anchorTop { place(top: anchorTop) }
        invalidateShadow()
    }

    override func cancelOperation(_ sender: Any?) { orderOut(nil) }
}

/// Poignée de redimensionnement, en bas à droite d'une fenêtre.
final class ResizeGripView: NSView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        if #available(macOS 15.0, *) {
            addCursorRect(bounds, cursor: .frameResize(position: .bottomRight, directions: .all))
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard let panel = window as? GlassPanel else { return }
        let start = NSEvent.mouseLocation
        let frame = panel.frame
        panel.gripResizing = true
        defer {
            panel.gripResizing = false
            panel.finishResize()
        }
        while let e = panel.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]), e.type == .leftMouseDragged {
            let now = NSEvent.mouseLocation
            let width = frame.width + now.x - start.x
            let height = frame.height + start.y - now.y
            // Le coin haut gauche reste fixe. La taille minimale vient du contenu.
            panel.setFrame(NSRect(x: frame.minX, y: frame.maxY - height, width: width, height: height), display: true)
            if panel.frame.height != height {
                panel.setFrameTopLeftPoint(NSPoint(x: frame.minX, y: frame.maxY))
            }
        }
    }
}

struct ResizeGrip: View {
    private struct Handle: NSViewRepresentable {
        func makeNSView(context: Context) -> ResizeGripView { ResizeGripView() }
        func updateNSView(_ nsView: ResizeGripView, context: Context) {}
    }

    var body: some View {
        Canvas { ctx, size in
            for inset in [CGFloat(4), 8] {
                var line = Path()
                line.move(to: CGPoint(x: size.width - 4, y: inset))
                line.addLine(to: CGPoint(x: inset, y: size.height - 4))
                ctx.stroke(line, with: .color(.white.opacity(0.32)), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
            }
        }
        .frame(width: 18, height: 18)
        .background(Handle())
        .padding(4)
    }
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
