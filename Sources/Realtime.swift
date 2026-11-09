import Foundation

/// Connexion temps réel à Supabase. Elle sert seulement de signal : à chaque changement sur
/// la table prompts, l'app relit la base (la politique d'accès filtre ce que chacun reçoit).
/// Un relevé périodique dans Store rattrape toute coupure.
final class Realtime: NSObject, URLSessionWebSocketDelegate, @unchecked Sendable {
    var onChange: (@Sendable () -> Void)?
    private var task: URLSessionWebSocketTask?
    private var heartbeat: Timer?
    private var token: String?
    private var ref = 0
    private let topic = "realtime:ricochet"

    func connect(token: String) {
        self.token = token
        disconnect()
        var c = URLComponents(string: Config.supabaseURL)!
        c.scheme = "wss"
        c.path = "/realtime/v1/websocket"
        c.queryItems = [URLQueryItem(name: "apikey", value: Config.publishableKey), URLQueryItem(name: "vsn", value: "1.0.0")]
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        let t = session.webSocketTask(with: c.url!)
        task = t
        t.resume()
        join()
        listen(t)
        DispatchQueue.main.async { [weak self] in
            self?.heartbeat = Timer.scheduledTimer(withTimeInterval: 25, repeats: true) { _ in
                self?.push(topic: "phoenix", event: "heartbeat", payload: [:])
            }
        }
    }

    func disconnect() {
        DispatchQueue.main.async { [weak self] in
            self?.heartbeat?.invalidate()
            self?.heartbeat = nil
        }
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
    }

    /// À appeler quand le jeton est renouvelé, sinon le serveur coupe le canal à l'expiration.
    func update(token: String) {
        guard token != self.token else { return }
        self.token = token
        push(topic: topic, event: "access_token", payload: ["access_token": token])
    }

    private func join() {
        push(topic: topic, event: "phx_join", payload: [
            "config": [
                "broadcast": ["self": false],
                "presence": ["key": ""],
                "private": false,
                "postgres_changes": [["event": "*", "schema": "public", "table": "prompts"]],
            ],
            "access_token": token ?? "",
        ])
    }

    private func push(topic: String, event: String, payload: [String: Any]) {
        ref += 1
        let m: [String: Any] = ["topic": topic, "event": event, "payload": payload, "ref": String(ref)]
        guard let d = try? JSONSerialization.data(withJSONObject: m), let s = String(data: d, encoding: .utf8) else { return }
        task?.send(.string(s)) { _ in }
    }

    private func listen(_ t: URLSessionWebSocketTask) {
        t.receive { [weak self] result in
            guard let self, t === self.task else { return }
            switch result {
            case .failure:
                self.reconnect()
            case .success(let message):
                if case .string(let s) = message, s.contains("\"postgres_changes\""), !s.contains("phx_reply") {
                    self.onChange?()
                }
                self.listen(t)
            }
        }
    }

    private func reconnect() {
        task = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self, self.task == nil, let token = self.token else { return }
            self.connect(token: token)
        }
    }
}
