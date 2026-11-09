import ApplicationServices
import Cocoa

enum LaunchError: LocalizedError {
    case permission, noComposer, draft, mismatch, notSent

    var errorDescription: String? {
        switch self {
        case .permission:
            return "Autorisez Ricochet dans Réglages Système > Confidentialité et sécurité > Accessibilité, puis réessayez."
        case .noComposer:
            return "Claude ne répond pas : vérifiez que l'app est ouverte et connectée, puis réessayez."
        case .draft:
            return "Un brouillon est déjà présent dans une nouvelle conversation de Claude. Envoyez-le ou effacez-le, puis réessayez."
        case .mismatch:
            return "Le champ de Claude ne contient pas exactement le prompt, rien n'a été envoyé. Effacez le texte du champ, puis réessayez."
        case .notSent:
            return "Le prompt est resté dans le champ de Claude : vérifiez, puis envoyez-le à la main."
        }
    }
}

/// Lance un prompt dans une nouvelle conversation de Claude Desktop.
/// 1) Lien claude://claude.ai/new?q=… qui ouvre l'app et pré-remplit le champ.
/// 2) Lecture du champ via l'Accessibilité : on n'envoie que si la page est /new et le contenu exact.
/// 3) Clic du bouton d'envoi via l'Accessibilité, sans souris, clavier ni presse-papiers.
/// Ce lien et ce bouton ne sont pas une API documentée : une mise à jour de Claude peut les casser.
/// Bloquant : à appeler hors du fil principal.
enum ClaudeLauncher {
    private static let bundleID = "com.anthropic.claudefordesktop"

    private static func attr(_ e: AXUIElement, _ a: String) -> AnyObject? {
        var v: AnyObject?
        return AXUIElementCopyAttributeValue(e, a as CFString, &v) == .success ? v : nil
    }
    private static func text(_ e: AXUIElement, _ a: String) -> String { (attr(e, a) as? String) ?? "" }
    private static func element(_ e: AXUIElement, _ a: String) -> AXUIElement? {
        attr(e, a).map { $0 as! AXUIElement }
    }
    private static func normalize(_ s: String) -> String {
        s.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
    }

    private static func search(_ root: AXUIElement, all: Bool = false, _ test: (AXUIElement) -> Bool) -> [AXUIElement] {
        var found: [AXUIElement] = []
        var visited = 0
        func visit(_ e: AXUIElement, _ depth: Int) {
            visited += 1
            if visited > 60_000 || depth > 80 || (!all && !found.isEmpty) { return }
            if test(e) { found.append(e) }
            for c in (attr(e, "AXChildren") as? [AXUIElement]) ?? [] { visit(c, depth + 1) }
        }
        visit(root, 0)
        return found
    }

    private static func runningApp() -> AXUIElement? {
        guard let a = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else { return nil }
        let app = AXUIElementCreateApplication(a.processIdentifier)
        // Electron n'expose ses pages à l'Accessibilité que sur demande.
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        return app
    }

    private static func composers(_ app: AXUIElement) -> [AXUIElement] {
        ((attr(app, "AXWindows") as? [AXUIElement]) ?? []).flatMap { w in
            search(w, all: true) { text($0, "AXRole") == "AXTextArea" }
        }
    }

    private static func pageURL(of e: AXUIElement) -> String {
        var cur: AXUIElement? = e
        var n = 0
        while let x = cur, n < 80 {
            if text(x, "AXRole") == "AXWebArea", let u = attr(x, "AXURL") { return "\(u)" }
            cur = element(x, "AXParent")
            n += 1
        }
        return ""
    }

    private static func isNewChat(_ url: String) -> Bool { URLComponents(string: url)?.path == "/new" }

    private static func sendButton(near composer: AXUIElement) -> AXUIElement? {
        var cur = element(composer, "AXParent")
        var n = 0
        while let x = cur, n < 12 {
            let hit = search(x) { e in
                guard text(e, "AXRole") == "AXButton", (attr(e, "AXEnabled") as? Bool) == true else { return false }
                let l = (text(e, "AXTitle") + " " + text(e, "AXDescription")).lowercased()
                return l.contains("envoy") || l.contains("send")
            }
            if let b = hit.first { return b }
            cur = element(x, "AXParent")
            n += 1
        }
        return nil
    }

    private static func link(for prompt: String) -> URL {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=;?/:#")
        var c = URLComponents()
        c.scheme = "claude"
        c.host = "claude.ai"
        c.path = "/new"
        c.percentEncodedQueryItems = [
            URLQueryItem(name: "q", value: prompt.addingPercentEncoding(withAllowedCharacters: allowed)),
            URLQueryItem(name: "surface", value: "chat"),
        ]
        return c.url!
    }

    static func launch(_ raw: String) throws {
        guard AXIsProcessTrusted() else { throw LaunchError.permission }
        let prompt = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let expected = normalize(prompt)

        // Le lien AJOUTE au brouillon d'une nouvelle conversation : on refuse avant de l'ouvrir.
        if let app = runningApp() {
            var seen: [AXUIElement] = []
            for _ in 0..<8 where seen.isEmpty {
                Thread.sleep(forTimeInterval: 0.25)
                seen = composers(app)
            }
            if seen.contains(where: { isNewChat(pageURL(of: $0)) && !normalize(text($0, "AXValue")).isEmpty }) {
                throw LaunchError.draft
            }
        }

        guard NSWorkspace.shared.open(link(for: prompt)) else { throw LaunchError.noComposer }

        var app: AXUIElement?
        var composer: AXUIElement?
        let deadline = Date().addingTimeInterval(45)
        while Date() < deadline, composer == nil {
            if let a = runningApp() {
                app = a
                composer = composers(a).first { normalize(text($0, "AXValue")) == expected && isNewChat(pageURL(of: $0)) }
            }
            if composer == nil { Thread.sleep(forTimeInterval: 0.25) }
        }
        guard let app, let composer else {
            let any = app.map { !composers($0).isEmpty } ?? false
            throw any ? LaunchError.mismatch : LaunchError.noComposer
        }

        // Le contenu doit rester exact un instant : une frappe peut s'y ajouter au passage au premier plan.
        Thread.sleep(forTimeInterval: 0.6)
        guard normalize(text(composer, "AXValue")) == expected else { throw LaunchError.mismatch }

        guard let button = sendButton(near: composer),
              AXUIElementPerformAction(button, "AXPress" as CFString) == .success else { throw LaunchError.notSent }

        let end = Date().addingTimeInterval(8)
        while Date() < end {
            if !composers(app).contains(where: { normalize(text($0, "AXValue")) == expected }) { return }
            Thread.sleep(forTimeInterval: 0.2)
        }
        throw LaunchError.notSent
    }
}
