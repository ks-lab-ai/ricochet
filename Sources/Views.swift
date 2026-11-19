import Cocoa
import SwiftUI

// MARK: Rejoindre l'équipe

struct JoinView: View {
    @ObservedObject var store: Store
    var onClose: () -> Void
    var onDone: () -> Void
    @State private var name = Config.team[0]
    @State private var code = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            GlassHeader(title: "Rejoindre Ricochet") {
                SquareButton(icon: "xmark", action: onClose)
            }
            Text("Choisissez votre prénom et entrez le code d'équipe donné par Noé.")
                .font(.system(size: 12))
                .foregroundStyle(Glass.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Pills(items: Config.team, selection: $name) { $0 }
            SecureField("Code d'équipe", text: $code)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                .padding(.horizontal, 10)
                .frame(height: 32)
                .glassField()
            if let error {
                Text(error).font(.system(size: 11.5)).foregroundStyle(Glass.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button(busy ? "Connexion…" : "Rejoindre") {
                    busy = true
                    error = nil
                    Task {
                        do {
                            try await store.join(name: name, code: code)
                            onDone()
                        } catch {
                            self.error = error.localizedDescription
                        }
                        busy = false
                    }
                }
                .buttonStyle(GlassButton(primary: true))
                .keyboardShortcut(.defaultAction)
                .disabled(busy || code.isEmpty)
            }
        }
        .padding(18)
        .frame(width: 360)
        .fixedSize(horizontal: false, vertical: true)
        .glassWindow()
    }
}

// MARK: Fenêtre de la barre de menus

struct MainView: View {
    @ObservedObject var store: Store
    var onReview: (String) -> Void
    var onClose: () -> Void
    var onShowWidget: () -> Void = {}
    @AppStorage("widgetHidden") private var widgetHidden = false
    @State private var recipient: Member?
    /// Dernier mode choisi, gardé d'un envoi à l'autre
    @AppStorage("mode") private var mode: PromptMode = .chat
    @State private var text = ""
    @State private var sending = false
    @State private var trusted = AXIsProcessTrusted()
    private let tick = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    private var tooLong: Bool { text.count > Config.maxPromptLength }
    private var empty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GlassHeader(title: "Ricochet") {
                Text(store.me ?? "").font(.system(size: 12, weight: .medium)).foregroundStyle(Glass.secondary)
                SquareButton(icon: "xmark", action: onClose)
            }

            if !trusted {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Pour lancer les prompts reçus, autorisez Ricochet dans Accessibilité.")
                        .font(.system(size: 12))
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Ouvrir les réglages") { Permissions.openSettings() }
                    .buttonStyle(GlassButton())
                }
                .glassCard()
            }

            if !store.pending.isEmpty {
                label("À traiter")
                ForEach(store.pending) { p in
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(store.name(p.sender_id)).font(.system(size: 13, weight: .semibold))
                            Text(p.summary).font(.system(size: 12)).foregroundStyle(Glass.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        ModeTag(mode: p.launchMode)
                        Button("Regarder") { onReview(p.id) }.buttonStyle(GlassButton())
                    }
                    .glassCard(padding: 10)
                }
            }

            label("Envoyer un prompt")
            Pills(items: store.others.map(Optional.some), selection: $recipient) { $0?.name ?? "" }
            label("Lancé dans")
            Pills(items: PromptMode.allCases, selection: $mode) { $0.label }
            ZStack(alignment: .topLeading) {
                TextEditor(text: $text)
                    .font(.system(size: 13))
                    .scrollContentBackground(.hidden)
                    .padding(6)
                if text.isEmpty {
                    Text("Votre prompt…")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.35))
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .allowsHitTesting(false)
                }
            }
            .frame(minHeight: 110, maxHeight: .infinity)
            .glassField()

            HStack(spacing: 8) {
                if tooLong {
                    Text("Trop long : \(text.count) sur \(Config.maxPromptLength)")
                        .font(.system(size: 11)).foregroundStyle(Glass.red)
                }
                Spacer()
                Button(sending ? "Envoi…" : "Envoyer") {
                    guard let recipient else { return }
                    sending = true
                    Task {
                        if await store.send(to: recipient, text: text, mode: mode) { text = "" }
                        sending = false
                    }
                }
                .buttonStyle(GlassButton(primary: true))
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(sending || recipient == nil || empty || tooLong)
            }

            if let m = store.message {
                Text(m).font(.system(size: 11)).foregroundStyle(Glass.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !store.sent.isEmpty {
                label("Envoyés")
                VStack(spacing: 6) {
                    ForEach(store.sent.prefix(4)) { p in
                        HStack(spacing: 8) {
                            Text(store.name(p.recipient_id)).font(.system(size: 12, weight: .semibold))
                            Text(p.summary).font(.system(size: 12)).foregroundStyle(Glass.secondary).lineLimit(1)
                            Spacer(minLength: 4)
                            statusTag(p.status)
                        }
                    }
                }
                .glassCard(padding: 10)
            }

            HStack {
                if widgetHidden {
                    Button("Afficher le widget sur le bureau", action: onShowWidget)
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Glass.orange)
                        .handCursor()
                }
                Spacer()
                Button("Quitter Ricochet") { NSApp.terminate(nil) }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.4))
                    .handCursor()
            }
        }
        .padding(18)
        .frame(minWidth: 340, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay(alignment: .bottomTrailing) { ResizeGrip() }
        .glassWindow()
        .onReceive(tick) { _ in trusted = AXIsProcessTrusted() }
    }

    private func label(_ t: String) -> some View {
        Text(t).font(.system(size: 11, weight: .semibold)).foregroundStyle(Glass.secondary)
    }

    @ViewBuilder private func statusTag(_ s: String) -> some View {
        switch s {
        case "launched": StatusTag(text: "Lancé", color: Glass.green)
        case "refused": StatusTag(text: "Refusé", color: Glass.red)
        default: StatusTag(text: "En attente", color: .white.opacity(0.6))
        }
    }
}

// MARK: Fenêtre Regarder

struct ReviewView: View {
    @ObservedObject var store: Store
    let promptID: String
    var onClose: () -> Void

    var body: some View {
        let p = store.prompt(promptID)
        VStack(alignment: .leading, spacing: 12) {
            GlassHeader(title: p.map { store.name($0.sender_id) } ?? "Prompt") {
                SquareButton(icon: "xmark", action: onClose)
            }
            HStack(spacing: 8) {
                Text(p?.summary ?? "Prompt introuvable")
                    .font(.system(size: 12))
                    .foregroundStyle(Glass.secondary)
                Spacer(minLength: 4)
                if let p { ModeTag(mode: p.launchMode, always: true) }
            }
            ScrollView {
                Text(p?.body ?? "")
                    .font(.system(size: 13))
                    .lineSpacing(2)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.07)))
            if let m = store.message, p?.status == "pending" {
                Text(m).font(.system(size: 11)).foregroundStyle(Glass.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Spacer()
                Button("Refuser") {
                    Task {
                        await store.refuse(promptID)
                        onClose()
                    }
                }
                .buttonStyle(GlassButton())
                .disabled(p?.status != "pending" || store.launching != nil)
                Button(store.launching == promptID ? "Lancement…" : "Lancer") {
                    store.message = nil
                    Task {
                        await store.launch(promptID)
                        if store.prompt(promptID)?.status != "pending" { onClose() }
                    }
                }
                .buttonStyle(GlassButton(primary: true))
                .keyboardShortcut(.defaultAction)
                .disabled(p?.status != "pending" || store.launching != nil)
            }
        }
        .padding(18)
        .frame(minWidth: 380, maxWidth: .infinity, minHeight: 280, maxHeight: .infinity)
        .overlay(alignment: .bottomTrailing) { ResizeGrip() }
        .glassWindow()
    }
}

/// « Claude Code » (ou « Claude » si always) : où le prompt sera lancé
struct ModeTag: View {
    let mode: PromptMode
    var always = false
    var body: some View {
        if mode == .code || always {
            StatusTag(text: mode.label, color: mode == .code ? Glass.orange : .white.opacity(0.6))
        }
    }
}

// MARK: Widget de bureau

/// Pastilles rouge et jaune façon macOS : le symbole apparaît au survol du groupe
struct TrafficLights: View {
    var onClose: () -> Void
    var onMinimize: () -> Void
    @State private var hover = false

    var body: some View {
        HStack(spacing: 8) {
            light(Color(red: 1, green: 0.373, blue: 0.341), symbol: "xmark", label: "Fermer le widget", action: onClose)
            light(Color(red: 0.996, green: 0.737, blue: 0.180), symbol: "minus", label: "Réduire le widget", action: onMinimize)
        }
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hover = h } }
        .help("Masque le widget. Ricochet continue de tourner et les notifications arrivent toujours.")
    }

    private func light(_ color: Color, symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Circle().fill(color)
                Circle().stroke(.black.opacity(0.18), lineWidth: 0.5)
                Image(systemName: symbol)
                    .font(.system(size: 7.5, weight: .black))
                    .foregroundStyle(.black.opacity(0.55))
                    .opacity(hover ? 1 : 0)
            }
            .frame(width: 12, height: 12)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .handCursor()
        .accessibilityLabel(label)
    }
}

struct DesktopWidgetView: View {
    @ObservedObject var store: Store
    var onCompose: () -> Void
    var onReview: (String) -> Void
    var onHide: () -> Void = {}

    static let baseSize = CGSize(width: 320, height: 220)

    var body: some View {
        // Contenu dessiné à sa taille de référence puis mis à l'échelle de la fenêtre :
        // tout grandit ensemble, et la place en plus dans l'autre sens est occupée par la liste.
        GeometryReader { g in
            let b = Self.baseSize
            let s = min(max(min(g.size.width / b.width, g.size.height / b.height), 0.8), 2.5)
            content
                .padding(18)
                .frame(width: g.size.width / s, height: g.size.height / s, alignment: .topLeading)
                .scaleEffect(s, anchor: .topLeading)
                .frame(width: g.size.width, height: g.size.height, alignment: .topLeading)
        }
        .frame(minWidth: Self.baseSize.width * 0.8, minHeight: Self.baseSize.height * 0.8)
        .overlay(alignment: .bottomTrailing) { ResizeGrip() }
        .glassWindow(dim: 0.68)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                TrafficLights(onClose: onHide, onMinimize: onHide)
                GlassHeader(title: "Ricochet") {
                if !store.pending.isEmpty {
                    StatusTag(text: "\(store.pending.count) à traiter", color: Glass.orange)
                }
                    SquareButton(icon: "plus", filled: true, action: onCompose)
                }
            }
            if store.pending.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 22))
                        .foregroundStyle(Glass.green)
                    Text("Aucun prompt à traiter")
                        .font(.system(size: 12))
                        .foregroundStyle(Glass.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(store.pending) { p in
                            HStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(store.name(p.sender_id)).font(.system(size: 13, weight: .semibold))
                                    Text(p.summary).font(.system(size: 12)).foregroundStyle(Glass.secondary).lineLimit(1)
                                }
                                Spacer(minLength: 4)
                                Button("Regarder") { onReview(p.id) }.buttonStyle(GlassButton())
                            }
                            .glassCard(padding: 10)
                        }
                    }
                }
                .scrollIndicators(.never)
            }
        }
    }
}
