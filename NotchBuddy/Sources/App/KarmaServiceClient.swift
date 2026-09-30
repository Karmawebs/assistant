import Foundation

struct KarmaServiceStatus: Sendable {
    let name: String
    let url: URL
    let reachable: Bool
    let statusCode: Int?
}

final class KarmaServiceClient: @unchecked Sendable {
    static let shared = KarmaServiceClient()

    let appURL = URL(string: "https://app.karmawebs.com")!
    let workURL = URL(string: "https://work.karmawebs.com")!
    let careURL = URL(string: "https://care.karmawebs.com")!

    private init() {}

    private var clientID: String? {
        KeychainStore.shared.get("cloudflare-access-client-id")
    }

    private var clientSecret: String? {
        KeychainStore.shared.get("cloudflare-access-client-secret")
    }

    var isConfigured: Bool {
        guard let id = clientID, !id.isEmpty,
              let secret = clientSecret, !secret.isEmpty else { return false }
        return true
    }

    func authenticatedRequest(url: URL) throws -> URLRequest {
        guard let id = clientID, !id.isEmpty,
              let secret = clientSecret, !secret.isEmpty else {
            throw NSError(
                domain: "KarmaServiceClient",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Falta configurar el Service Token de Karma Assistant."]
            )
        }

        var request = URLRequest(url: url)
        request.setValue(id, forHTTPHeaderField: "CF-Access-Client-Id")
        request.setValue(secret, forHTTPHeaderField: "CF-Access-Client-Secret")
        request.timeoutInterval = 15
        return request
    }

    func testAll() async -> [KarmaServiceStatus] {
        let services: [(String, URL)] = [
            ("APP", appURL),
            ("WORK", workURL),
            ("CARE", careURL),
        ]

        return await withTaskGroup(of: KarmaServiceStatus.self) { group in
            for (name, url) in services {
                group.addTask {
                    do {
                        let request = try self.authenticatedRequest(url: url)
                        let (_, response) = try await URLSession.shared.data(for: request)
                        let code = (response as? HTTPURLResponse)?.statusCode
                        let ok = code.map { (200..<400).contains($0) } ?? false
                        return KarmaServiceStatus(name: name, url: url, reachable: ok, statusCode: code)
                    } catch {
                        return KarmaServiceStatus(name: name, url: url, reachable: false, statusCode: nil)
                    }
                }
            }

            var result: [KarmaServiceStatus] = []
            for await item in group { result.append(item) }
            return result.sorted { $0.name < $1.name }
        }
    }
}
