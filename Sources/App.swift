import Cocoa
import ServiceManagement
import SwiftUI
import UserNotifications

@main
enum Main {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { app.run() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    static let promptCategory = "RICOCHET_PROMPT"
    private static let launchAction = "LANCER"
    private static let reviewAction = "REGARDER"

    @MainActor private lazy var store = Store()
    private var statusItem: NSStatusItem?
    private var mainPanel: GlassPanel?
    private var joinPanel: GlassPanel?
    private var desktopWidget: GlassPanel?
    private var reviewPanels: [String: GlassPanel] = [:]

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Doit être prêt avant la fin du lancement, pour les clics sur une notification quand l'app était fermée.
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.setNotificationCategories([
            UNNotificationCategory(
                identifier: Self.promptCategory,
                actions: [
                    UNNotificationAction(identifier: Self.launchAction, title: "Lancer", options: []),
                    UNNotificationAction(identifier: Self.reviewAction, title: "Regarder", options: [.foreground]),
                ],
                intentIdentifiers: [])
        ])
        installEditMenu()
    }

    /// Sans menu Édition, Cmd+C, Cmd+V et Cmd+A ne marchent pas dans les champs de texte.
    private func installEditMenu() {
        let edit = NSMenu(title: "Édition")
        edit.addItem(withTitle: "Annuler", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Rétablir", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Couper", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copier", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Coller", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Tout sélectionner", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let item = NSMenuItem(title: "Édition", action: nil, keyEquivalent: "")
        item.submenu = edit
        let appMenu = NSMenu(title: "Ricochet")
        appMenu.addItem(withTitle: "Masquer Ricochet", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quitter Ricochet", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        let bar = NSMenu()
        bar.addItem(appItem)
        bar.addItem(item)
        NSApp.mainMenu = bar
    }

    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = statusIcon()
        item.button?.target = self
        item.button?.action = #selector(toggleMain)
        statusItem = item

        store.onPendingChange = { [weak self] count in
            self?.statusItem?.button?.title = count > 0 ? " \(count)" : ""
        }
        Task {
            await store.start()
            if store.joined { self.afterJoin() } else { self.showJoin() }
        }
    }

    @MainActor
    private func afterJoin() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            logLine("notifications autorisées=\(granted) erreur=\(error.map { String(describing: $0) } ?? "aucune")")
        }
        // Ricochet doit tourner en permanence pour recevoir les prompts.
        try? SMAppService.mainApp.register()
        Permissions.askOncePerBuild()
        showDesktopWidget()
    }

    /// Même principe que les autres widgets de l'équipe : une fenêtre posée sur le bureau,
    /// sous les autres fenêtres, qui se cale sur la même grille.
    @MainActor
    private func showDesktopWidget() {
        if desktopWidget != nil { return }
        let size = NSSize(width: 320, height: 220)
        let w = GlassPanel(root: DesktopWidgetView(
            store: store,
            onCompose: { [weak self] in self?.showMain() },
            onReview: { [weak self] id in self?.review(id) }), movable: false)
        w.level = WidgetGrid.level
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        w.setContentSize(size)
        w.setFrameOrigin(WidgetGrid.initialOrigin(for: w, size: size))
        desktopWidget = w
        w.orderFrontRegardless()
        WidgetGrid.settle(w, animated: false)
    }

    @MainActor
    private func showJoin() {
        if let joinPanel {
            NSApp.activate(ignoringOtherApps: true)
            joinPanel.makeKeyAndOrderFront(nil)
            return
        }
        let w = GlassPanel(root: JoinView(
            store: store,
            onClose: { [weak self] in self?.joinPanel?.orderOut(nil) },
            onDone: { [weak self] in
                self?.joinPanel?.orderOut(nil)
                self?.joinPanel = nil
                self?.afterJoin()
                self?.showMain()
            }))
        w.center()
        joinPanel = w
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    @MainActor @objc private func toggleMain() {
        guard store.joined else {
            showJoin()
            return
        }
        if mainPanel?.isVisible == true {
            mainPanel?.orderOut(nil)
        } else {
            showMain()
        }
    }

    /// Ouvre la fenêtre principale juste sous l'icône de la barre de menus.
    @MainActor
    private func showMain() {
        guard store.joined else {
            showJoin()
            return
        }
        Task { await store.refresh() }
        let w: GlassPanel
        if let mainPanel {
            w = mainPanel
        } else {
            w = GlassPanel(root: MainView(
                store: store,
                onReview: { [weak self] id in
                    self?.mainPanel?.orderOut(nil)
                    self?.review(id)
                },
                onClose: { [weak self] in self?.mainPanel?.orderOut(nil) }), movable: false)
            w.closesOnResign = true
            mainPanel = w
        }
        if let button = statusItem?.button, let bw = button.window {
            let r = bw.convertToScreen(button.convert(button.bounds, to: nil))
            let screen = bw.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? r
            let x = min(max(r.midX - 180, screen.minX + 8), screen.maxX - 368)
            let top = NSPoint(x: x, y: r.minY - 6)
            w.anchorTop = top
            w.setFrameTopLeftPoint(top)
        }
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    @MainActor
    private func review(_ id: String) {
        if let open = reviewPanels[id] {
            NSApp.activate(ignoringOtherApps: true)
            open.makeKeyAndOrderFront(nil)
            return
        }
        Task {
            if store.prompt(id) == nil { await store.refresh() }
            let panel = GlassPanel(root: ReviewView(store: store, promptID: id) { [weak self] in
                self?.reviewPanels[id]?.orderOut(nil)
                self?.reviewPanels[id] = nil
            })
            panel.setContentSize(NSSize(width: 460, height: 380))
            panel.center()
            reviewPanels[id] = panel
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
        }
    }

    // Clic sur l'icône du Dock : ouvre la fenêtre d'envoi.
    @MainActor
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMain()
        return false
    }

    // Liens : ricochet://composer et ricochet://regarder/<id>
    @MainActor
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "ricochet" {
            if url.host == "regarder" {
                let id = url.lastPathComponent
                if !id.isEmpty, id != "/" { review(id) }
            } else {
                showMain()
            }
        }
    }

    // MARK: Notifications

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completion: @escaping (UNNotificationPresentationOptions) -> Void) {
        completion([.banner, .list, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completion: @escaping () -> Void) {
        let id = response.notification.request.content.userInfo["prompt"] as? String
        let action = response.actionIdentifier
        Task { @MainActor in
            await self.waitUntilReady()
            if let id {
                if action == Self.launchAction {
                    await self.store.refresh()
                    await self.store.launch(id)
                } else {
                    self.review(id)
                }
            }
            completion()
        }
    }

    /// Un clic sur une notification peut relancer l'app : attendre que la session soit chargée.
    @MainActor
    private func waitUntilReady() async {
        if store.joined, !store.members.isEmpty { return }
        for _ in 0..<40 {
            try? await Task.sleep(for: .milliseconds(250))
            if store.joined, !store.members.isEmpty { return }
        }
    }
}
