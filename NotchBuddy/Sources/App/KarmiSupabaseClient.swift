import Foundation

struct KarmiActionResult {
    let ok: Bool
    let message: String
    let payload: [String: Any]?
}

final class KarmiSupabaseClient: @unchecked Sendable {
    static let shared = KarmiSupabaseClient()

    private let baseURL = URL(string: "https://vjsmsekbsjngdtuxfbmu.supabase.co")!
    private let publishableKey = "sb_publishable_QQ_ZXbIAGm6_5bht6gWeMg_5kmk6oOW"

    private init() {}

    private var email: String? { KeychainStore.shared.get("karmi-supabase-email") }
    private var password: String? { KeychainStore.shared.get("karmi-supabase-password") }
    private var accessToken: String? { KeychainStore.shared.get("karmi-supabase-access-token") }
    private var refreshToken: String? { KeychainStore.shared.get("karmi-supabase-refresh-token") }

    var hasCredentials: Bool {
        guard let email, !email.isEmpty, let password, !password.isEmpty else { return false }
        return true
    }

    func signIn() async throws {
        guard let email, let password, !email.isEmpty, !password.isEmpty else {
            throw NSError(domain: "KarmiSupabase", code: 1, userInfo: [NSLocalizedDescriptionKey: "Falta el email o la contraseña de Karma."])
        }

        let url = baseURL.appendingPathComponent("auth/v1/token")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "grant_type", value: "password")]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue(publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "email": email,
            "password": password
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "No se ha podido iniciar sesión."
            throw NSError(domain: "KarmiSupabase", code: 2, userInfo: [NSLocalizedDescriptionKey: body])
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = json["access_token"] as? String,
              let refresh = json["refresh_token"] as? String else {
            throw NSError(domain: "KarmiSupabase", code: 3, userInfo: [NSLocalizedDescriptionKey: "Respuesta de autenticación inválida."])
        }

        KeychainStore.shared.set("karmi-supabase-access-token", value: access)
        KeychainStore.shared.set("karmi-supabase-refresh-token", value: refresh)
    }

    private func refreshSession() async throws {
        guard let refreshToken, !refreshToken.isEmpty else {
            try await signIn()
            return
        }

        let url = baseURL.appendingPathComponent("auth/v1/token")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "grant_type", value: "refresh_token")]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue(publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["refresh_token": refreshToken])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = json["access_token"] as? String else {
            try await signIn()
            return
        }

        KeychainStore.shared.set("karmi-supabase-access-token", value: access)
        if let refresh = json["refresh_token"] as? String {
            KeychainStore.shared.set("karmi-supabase-refresh-token", value: refresh)
        }
    }

    private func authorizedRequest(url: URL) async throws -> URLRequest {
        if accessToken == nil { try await signIn() }
        guard let token = accessToken else {
            throw NSError(domain: "KarmiSupabase", code: 4, userInfo: [NSLocalizedDescriptionKey: "No hay sesión de Supabase."])
        }

        var request = URLRequest(url: url)
        request.setValue(publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15
        return request
    }

    private func rpc(_ function: String, payload: [String: Any]) async throws -> [String: Any] {
        let url = baseURL.appendingPathComponent("rest/v1/rpc/\(function)")
        var request = try await authorizedRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        var (data, response) = try await URLSession.shared.data(for: request)
        var status = (response as? HTTPURLResponse)?.statusCode ?? 0

        if status == 401 {
            try await refreshSession()
            request = try await authorizedRequest(url: url)
            request.httpMethod = "POST"
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            (data, response) = try await URLSession.shared.data(for: request)
            status = (response as? HTTPURLResponse)?.statusCode ?? 0
        }

        guard (200..<300).contains(status) else {
            let body = String(data: data, encoding: .utf8) ?? "Error HTTP \(status)"
            throw NSError(domain: "KarmiSupabase", code: status, userInfo: [NSLocalizedDescriptionKey: body])
        }

        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return json
        }
        return [:]
    }

    func testConnection() async -> KarmiActionResult {
        do {
            try await signIn()
            return KarmiActionResult(ok: true, message: "Supabase conectado.", payload: nil)
        } catch {
            return KarmiActionResult(ok: false, message: error.localizedDescription, payload: nil)
        }
    }

    func createExpense(
        description: String,
        baseAmount: Double,
        date: String? = nil,
        scope: String = "A",
        vatRate: Double = 21,
        withholdingRate: Double = 0,
        paymentStatus: String = "paid",
        notes: String? = nil,
        supplierName: String? = nil,
        categoryName: String? = nil,
        paymentMethodName: String? = nil
    ) async -> KarmiActionResult {
        do {
            var payload: [String: Any] = [
                "p_description": description,
                "p_base_amount": baseAmount,
                "p_accounting_scope": scope,
                "p_vat_rate": vatRate,
                "p_withholding_rate": withholdingRate,
                "p_payment_status": paymentStatus
            ]
            if let date { payload["p_expense_date"] = date }
            if let notes { payload["p_notes"] = notes }
            if let supplierName { payload["p_supplier_name"] = supplierName }
            if let categoryName { payload["p_category_name"] = categoryName }
            if let paymentMethodName { payload["p_payment_method_name"] = paymentMethodName }

            let result = try await rpc("karmi_create_expense", payload: payload)
            let number = result["expense_number"].map { String(describing: $0) } ?? ""
            return KarmiActionResult(ok: true, message: "Gasto creado \(number.isEmpty ? "" : "GAS-\(number)").", payload: result)
        } catch {
            return KarmiActionResult(ok: false, message: error.localizedDescription, payload: nil)
        }
    }

    func createTask(
        title: String,
        projectName: String? = nil,
        priority: String = "Media",
        dueDate: String? = nil
    ) async -> KarmiActionResult {
        do {
            var payload: [String: Any] = [
                "p_title": title,
                "p_priority": priority
            ]
            if let projectName { payload["p_project_name"] = projectName }
            if let dueDate { payload["p_due_date"] = dueDate }

            let result = try await rpc("karmi_create_task", payload: payload)
            return KarmiActionResult(ok: true, message: "Tarea creada.", payload: result)
        } catch {
            return KarmiActionResult(ok: false, message: error.localizedDescription, payload: nil)
        }
    }
}
