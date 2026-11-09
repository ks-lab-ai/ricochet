import Cocoa
import Combine
import UserNotifications

/// État de l'app : prompts, envois, décisions et notifications.
@MainActor
final class Store: ObservableObject {
    @Published private(set) var me: String?
    @Published private(set) var meID: String?
    @Published private(set) var members: [Member] = []
    @Published private(set) var prompts: [Prompt] = []
    @Published var message: String?
    @Published private(set) var launching: String?

    let api = Api()
    private let realtime = Realtime()
    private var timer: Timer?
    private var seen: Set<String> = []
    private var firstSync = false
    /// Appelé quand le nombre de prompts en attente change.
    var onPendingChange: ((Int) -> Void)?

    var joined: Bool { meID != nil }
    var pending: [Prompt] { prompts.filter { $0.recipient_id == meID && $0.status == "pending" } }
    var sent: [Prompt] { prompts.filter { $0.sender_id == meID } }
    var others: [Member] { members.filter { $0.id != meID } }
    func name(_ id: String) -> String { members.first { $0.id == id }?.name ?? "Quelqu'un" }
    func prompt(_ id: String) -> Prompt? { prompts.first { $0.id == id } }

    func start() async {
        let s = await api.session
        me = s?.member_name
        meID = s?.member_id
        guard joined else { return }
        loadSeen()
        realtime.onChange = { [weak self] in Task { @MainActor in await self?.refresh() } }
        if let t = try? await api.token() { realtime.connect(token: t) }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if let t = try? await self.api.token() { self.realtime.connect(token: t) }
                await self.refresh()
            }
        }
        await refresh()
    }

    func join(name: String, code: String) async throws {
        try await api.join(name: name, code: code.trimmingCharacters(in: .whitespacesAndNewlines))
        await start()
    }

    func refresh() async {
        guard joined else { return }
        do {
            let m = try await api.allMembers()
            let p = try await api.prompts()
            if let t = try? await api.token() { realtime.update(token: t) }
            members = m
            prompts = p
            notifyChanges()
            onPendingChange?(pending.count)
        } catch ApiError.sessionLost {
            await api.clear()
            me = nil
            meID = nil
            message = ApiError.sessionLost.errorDescription
        } catch {
            // Réseau coupé : le relevé suivant ou le temps réel rattrapera.
        }
    }

    func send(to recipient: Member, text: String) async -> Bool {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return false }
        do {
            let summary = await Summarizer.summarize(body)
            try await api.sendPrompt(to: recipient.id, body: body, summary: summary)
            message = "Envoyé à \(recipient.name) : \(summary)"
            await refresh()
            return true
        } catch {
            message = error.localizedDescription
            return false
        }
    }

    /// Lance le prompt dans Claude, et ne prévient l'expéditeur qu'une fois l'envoi confirmé.
    func launch(_ id: String) async {
        guard launching == nil, let p = prompt(id), p.status == "pending", p.recipient_id == meID else { return }
        launching = id
        defer { launching = nil }
        let text = p.body
        if !AXIsProcessTrusted() {
            Permissions.openSettings()
            message = "Activez Ricochet dans les réglages : le prompt partira tout seul."
            var granted = false
            for _ in 0..<240 {
                try? await Task.sleep(for: .milliseconds(500))
                if AXIsProcessTrusted() {
                    granted = true
                    break
                }
            }
            guard granted else {
                fail(LaunchError.permission.errorDescription ?? "", promptID: id)
                return
            }
            message = nil
        }
        do {
            try await Task.detached { try ClaudeLauncher.launch(text) }.value
        } catch {
            fail(error.localizedDescription, promptID: id)
            return
        }
        do {
            try await api.decide(id, status: "launched")
        } catch {
            fail("Prompt lancé dans Claude, mais l'expéditeur n'a pas pu être prévenu : \(error.localizedDescription)", promptID: nil)
        }
        await refresh()
    }

    func refuse(_ id: String) async {
        do {
            try await api.decide(id, status: "refused")
        } catch {
            fail(error.localizedDescription, promptID: nil)
        }
        await refresh()
    }

    private func fail(_ text: String, promptID: String?) {
        message = text
        let c = UNMutableNotificationContent()
        c.title = "Prompt non lancé"
        c.body = text
        if let promptID { c.userInfo = ["prompt": promptID] }
        post(c, id: UUID().uuidString)
    }

    // MARK: Notifications

    private func notifyChanges() {
        var changed = false
        for p in prompts.reversed() {
            let key = "\(p.id):\(p.status)"
            if seen.contains(key) { continue }
            seen.insert(key)
            changed = true
            if p.recipient_id == meID, p.status == "pending" {
                let c = UNMutableNotificationContent()
                c.title = "\(name(p.sender_id)) vous a envoyé un prompt à exécuter"
                c.body = p.summary
                c.categoryIdentifier = AppDelegate.promptCategory
                c.userInfo = ["prompt": p.id]
                c.sound = .default
                post(c, id: p.id)
            } else if p.sender_id == meID, p.status != "pending", !firstSync {
                let c = UNMutableNotificationContent()
                let verb = p.status == "launched" ? "a lancé" : "a refusé"
                c.title = "\(name(p.recipient_id)) \(verb) votre prompt"
                c.body = p.summary
                c.sound = .default
                post(c, id: key)
            }
        }
        firstSync = false
        if changed, let d = try? JSONEncoder().encode(Array(seen)) { try? d.write(to: Paths.seen, options: .atomic) }
    }

    private func post(_ content: UNMutableNotificationContent, id: String) {
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: nil)) { error in
            logLine("notification demandée, erreur=\(error.map { String(describing: $0) } ?? "aucune")")
        }
    }

    private func loadSeen() {
        if let d = try? Data(contentsOf: Paths.seen), let a = try? JSONDecoder().decode([String].self, from: d) {
            seen = Set(a)
        } else {
            // Première installation : pas de notification pour les décisions déjà anciennes.
            firstSync = true
        }
    }
}
