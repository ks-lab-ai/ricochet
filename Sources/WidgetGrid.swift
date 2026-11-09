import Cocoa
import SwiftUI

/// Placement du widget de bureau : mêmes règles que les autres widgets de l'équipe.
/// Pas de 20 pt, marge de 20 pt, écart de 16 pt, aimants sur les bords de l'écran et sur les
/// autres fenêtres posées au même niveau du bureau, même si elles viennent d'une autre app.
enum WidgetGrid {
    static let grid: CGFloat = 20, margin: CGFloat = 20, gap: CGFloat = 16, magnet: CGFloat = 14
    private static let positionKey = "widgetOrigin"
    static let level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)

    /// Glisser natif, puis calage sur la grille au lâcher du bouton.
    static func beginDrag(_ w: NSWindow, event: NSEvent) {
        w.performDrag(with: event)
        Timer.scheduledTimer(withTimeInterval: 1.0 / 120, repeats: true) { t in
            guard NSEvent.pressedMouseButtons & 1 == 0 else { return }
            t.invalidate()
            settle(w, animated: true)
        }
    }

    static func settle(_ w: NSWindow, animated: Bool) {
        let target = snap(w)
        UserDefaults.standard.set(NSStringFromPoint(target), forKey: positionKey)
        guard target != w.frame.origin else { return }
        guard animated else {
            w.setFrameOrigin(target)
            return
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.28
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1)
            w.animator().setFrame(NSRect(origin: target, size: w.frame.size), display: true)
        }
    }

    /// Position mémorisée si elle est encore sur un écran, sinon la première place libre.
    static func initialOrigin(for w: NSWindow, size: CGSize) -> NSPoint {
        if let s = UserDefaults.standard.string(forKey: positionKey) {
            let p = NSPointFromString(s)
            let rect = NSRect(origin: p, size: size).insetBy(dx: 40, dy: 40)
            if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(rect) }) { return p }
        }
        let f = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        let taken = neighbors(of: w).map { $0.insetBy(dx: -gap + 1, dy: -gap + 1) }
        // De la droite vers la gauche, puis du haut vers le bas.
        var x = f.maxX - margin - size.width
        while x >= f.minX + margin {
            var y = f.maxY - margin - size.height
            while y >= f.minY + margin {
                let r = NSRect(origin: NSPoint(x: x, y: y), size: size)
                if !taken.contains(where: { $0.intersects(r) }) { return r.origin }
                y -= grid
            }
            x -= grid
        }
        return NSPoint(x: f.maxX - margin - size.width, y: f.maxY - margin - size.height)
    }

    /// Les autres widgets posés sur le bureau, en coordonnées d'écran AppKit.
    private static func neighbors(of w: NSWindow) -> [NSRect] {
        let infos = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return infos.compactMap { i in
            guard (i[kCGWindowLayer as String] as? Int) == level.rawValue,
                  (i[kCGWindowNumber as String] as? Int) != w.windowNumber,
                  let b = i[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = b["X"], let y = b["Y"], let width = b["Width"], let height = b["Height"],
                  width > 100, height > 100 else { return nil }
            return NSRect(x: x, y: primaryHeight - y - height, width: width, height: height)
        }
    }

    private static func snap(_ win: NSWindow) -> NSPoint {
        let p = win.frame.origin, size = win.frame.size
        let center = NSPoint(x: p.x + size.width / 2, y: p.y + size.height / 2)
        let screen = NSScreen.screens.first { $0.frame.contains(center) } ?? NSScreen.main ?? NSScreen.screens[0]
        let f = screen.visibleFrame
        let top = p.y + size.height

        // Grille calée sur la marge en haut à gauche de l'écran
        var x = f.minX + margin + ((p.x - f.minX - margin) / grid).rounded() * grid
        var t = f.maxY - margin - ((f.maxY - margin - top) / grid).rounded() * grid

        // Aimants : bords de l'écran et des autres widgets (alignés ou espacés de 16 pt)
        var xs: [CGFloat] = [f.minX + margin, f.maxX - margin - size.width]
        var ts: [CGFloat] = [f.maxY - margin, f.minY + margin + size.height]
        for r in neighbors(of: win) {
            xs += [r.minX, r.maxX - size.width, r.maxX + gap, r.minX - gap - size.width]
            ts += [r.maxY, r.minY + size.height, r.minY - gap, r.maxY + gap + size.height]
        }
        if let bx = xs.min(by: { abs($0 - p.x) < abs($1 - p.x) }), abs(bx - p.x) < magnet { x = bx }
        if let bt = ts.min(by: { abs($0 - top) < abs($1 - top) }), abs(bt - top) < magnet { t = bt }

        x = min(max(x, f.minX), f.maxX - size.width)
        t = min(max(t, f.minY + size.height), f.maxY)
        return NSPoint(x: x, y: t - size.height)
    }
}

/// Zone de prise du widget, placée sous son contenu.
final class DragHandleView: NSView {
    override func mouseDown(with event: NSEvent) {
        if let window { WidgetGrid.beginDrag(window, event: event) }
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

struct DragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> DragHandleView { DragHandleView() }
    func updateNSView(_ nsView: DragHandleView, context: Context) {}
}

/// Le premier clic agit tout de suite, sans devoir d'abord activer la fenêtre.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
