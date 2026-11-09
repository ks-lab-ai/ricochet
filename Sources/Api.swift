import Foundation

/// Paramètres publics du projet. La clé publishable peut figurer dans un dépôt public :
/// c'est la politique d'accès de la base (voir supabase/migrations) qui protège les données.
enum Config {
    static let supabaseURL = "https://ilqytgziqznimzpxbkub.supabase.co"
    static let publishableKey = "sb_publishable_yRreFkL9wC198stt3OZmQg_Fw-82z_4"
    static let team = ["Noé", "Alban", "Raphael", "Paul", "Louis"]
    static let maxPromptLength = 14_000
}

struct Member: Codable, Identifiable, Hashable {
    let id: String
    let name: String
}

struct Prompt: Codable, Identifiable, Hashable {
    let id: String
    let sender_id: String
    let recipient_id: String
    let body: String
    let summary: String
    let status: String
    let created_at: String
}

struct Session: Codable {
    var access_token: String
    var refresh_token: String
    var expires_at: Double
    var member_id: String?
    var member_name: String?
}

enum ApiError: LocalizedError {
    case server(String)
    case sessionLost

    var errorDescription: String? {
        switch self {
        case .sessionLost: return "Session expirée : rejoignez l'équipe à nouveau."
        case .server(let m):
            if m.contains("code_invalide") { return "Code d'équipe incorrect." }
            if m.contains("prenom_deja_pris") { return "Ce prénom est déjà pris. Demandez à Noé de le libérer." }
            if m.contains("decision_impossible") { return "Ce prompt a déjà été traité." }
            return m
        }
    }
}

/// Dossier local de l'app.
enum Paths {
    static let dir: URL = {
        let d = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Ricochet", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()
    static let session = dir.appendingPathComponent("session.json")
    static let seen = dir.appendingPathComponent("seen.json")
    static let log = dir.appendingPathComponent("ricochet.log")
}

/// Client minimal de Supabase (Auth et REST), sans dépendance externe.
actor Api {
    private(set) var session: Session?
    private let json = JSONEncoder()

    init() {
        if let d = try? Data(contentsOf: Paths.session) {
            session = try? JSONDecoder().decode(Session.self, from: d)
        }
    }

    private func persist() {
        guard let session, let d = try? json.encode(session) else {
            try? FileManager.default.removeItem(at: Paths.session)
            return
        }
        try? d.write(to: Paths.session, options: [.atomic])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: Paths.session.path)
    }

    func clear() {
        session = nil
        persist()
    }

    private func send(_ method: String, _ path: String, body: Any? = nil, token: String? = nil) async throws -> Data {
        var r = URLRequest(url: URL(string: Config.supabaseURL + path)!)
        r.httpMethod = method
        r.timeoutInterval = 20
        r.setValue(Config.publishableKey, forHTTPHeaderField: "apikey")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body { r.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (data, resp) = try await URLSession.shared.data(for: r)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let m = (o?["message"] ?? o?["msg"] ?? o?["error_description"]) as? String
            if code == 400 || code == 401, path.contains("grant_type=refresh_token") { throw ApiError.sessionLost }
            throw ApiError.server(m ?? "Erreur serveur (\(code))")
        }
        return data
    }

    private func apply(_ data: Data) throws {
        let o = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        guard let a = o["access_token"] as? String, let r = o["refresh_token"] as? String else {
            throw ApiError.server("Réponse d'authentification invalide")
        }
        let exp = (o["expires_at"] as? Double) ?? Date().timeIntervalSince1970 + ((o["expires_in"] as? Double) ?? 3600)
        session = Session(access_token: a, refresh_token: r, expires_at: exp,
                          member_id: session?.member_id, member_name: session?.member_name)
        persist()
    }

    /// Jeton valide, renouvelé si besoin.
    func token() async throws -> String {
        guard let s = session else { throw ApiError.sessionLost }
        if s.expires_at - 60 > Date().timeIntervalSince1970 { return s.access_token }
        let d = try await send("POST", "/auth/v1/token?grant_type=refresh_token", body: ["refresh_token": s.refresh_token])
        try apply(d)
        return session!.access_token
    }

    func join(name: String, code: String) async throws {
        if session == nil { try apply(try await send("POST", "/auth/v1/signup", body: [String: String]())) }
        let d = try await send("POST", "/rest/v1/rpc/join_team", body: ["p_name": name, "p_code": code], token: try await token())
        guard let id = try JSONSerialization.jsonObject(with: d, options: .fragmentsAllowed) as? String else {
            throw ApiError.server("Réponse invalide")
        }
        session?.member_id = id
        session?.member_name = name
        persist()
    }

    func allMembers() async throws -> [Member] {
        let d = try await send("GET", "/rest/v1/members?select=id,name&order=name", token: try await token())
        return try JSONDecoder().decode([Member].self, from: d)
    }

    func prompts() async throws -> [Prompt] {
        let d = try await send(
            "GET",
            "/rest/v1/prompts?select=id,sender_id,recipient_id,body,summary,status,created_at&order=created_at.desc&limit=100",
            token: try await token())
        return try JSONDecoder().decode([Prompt].self, from: d)
    }

    func sendPrompt(to recipient: String, body: String, summary: String) async throws {
        guard let me = session?.member_id else { throw ApiError.sessionLost }
        _ = try await send("POST", "/rest/v1/prompts",
                           body: ["sender_id": me, "recipient_id": recipient, "body": body, "summary": summary],
                           token: try await token())
    }

    func decide(_ id: String, status: String) async throws {
        _ = try await send("POST", "/rest/v1/rpc/decide_prompt", body: ["p_id": id, "p_status": status], token: try await token())
    }
}

/// Petit journal local pour diagnostiquer une installation. Ne contient jamais le texte des prompts.
func logLine(_ text: String) {
    let line = "\(ISO8601DateFormatter().string(from: Date())) \(text)\n"
    if let h = try? FileHandle(forWritingTo: Paths.log) {
        h.seekToEndOfFile()
        h.write(Data(line.utf8))
        try? h.close()
    } else {
        try? Data(line.utf8).write(to: Paths.log)
    }
}
