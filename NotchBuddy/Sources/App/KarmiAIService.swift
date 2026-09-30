import Foundation

@MainActor
final class KarmiAIService {
    static let shared = KarmiAIService()

    private let endpoint = URL(string: "https://api.openai.com/v1/responses")!
    private let model = "gpt-5.6-luna"
    private var previousResponseID: String?

    private init() {}

    var apiKey: String? {
        KeychainStore.shared.get("openai-api-key")
    }

    func clearConversation() {
        previousResponseID = nil
    }

    func testConnection() async -> Result<String, Error> {
        do {
            guard let key = apiKey, !key.isEmpty else {
                throw NSError(domain: "KarmiAI", code: 1, userInfo: [NSLocalizedDescriptionKey: "Falta la API key de OpenAI."])
            }
            let body: [String: Any] = [
                "model": model,
                "input": "Responde solo con OK.",
                "max_output_tokens": 20
            ]
            let json = try await callAPI(body: body, key: key)
            let text = extractText(json) ?? "OK"
            return .success(text)
        } catch {
            return .failure(error)
        }
    }

    func chat(query: String, context: PromptContext?, state: AppState) async {
        guard let key = apiKey, !key.isEmpty else {
            showError("Falta la API key de OpenAI. Abre Settings → Karma AI.", state: state)
            return
        }

        var input = query
        if let context {
            switch context {
            case .window(let app, let title, let url):
                input = "Contexto de ventana — App: \(app), título: \(title)\(url.map { ", URL: \($0)" } ?? "")\n\nUsuario: \(query)"
            case .file(let name, _):
                input = "Contexto de archivo — \(name)\n\nUsuario: \(query)"
            }
        }

        do {
            var body: [String: Any] = [
                "model": model,
                "reasoning": ["effort": "low"],
                "instructions": systemPrompt,
                "input": input,
                "tools": tools,
                "tool_choice": "auto"
            ]
            if let previousResponseID { body["previous_response_id"] = previousResponseID }

            let first = try await callAPI(body: body, key: key)
            guard let responseID = first["id"] as? String else {
                throw NSError(domain: "KarmiAI", code: 2, userInfo: [NSLocalizedDescriptionKey: "Respuesta inválida de OpenAI."])
            }

            let calls = extractFunctionCalls(first)
            if calls.isEmpty {
                previousResponseID = responseID
                let text = extractText(first) ?? "Hecho."
                appendAssistant(text, state: state)
                return
            }

            var outputs: [[String: Any]] = []
            for call in calls {
                let result = await execute(call: call)
                outputs.append([
                    "type": "function_call_output",
                    "call_id": call.callID,
                    "output": result
                ])
            }

            let secondBody: [String: Any] = [
                "model": model,
                "reasoning": ["effort": "low"],
                "instructions": systemPrompt,
                "previous_response_id": responseID,
                "input": outputs,
                "tools": tools,
                "tool_choice": "auto"
            ]

            let second = try await callAPI(body: secondBody, key: key)
            previousResponseID = second["id"] as? String ?? responseID
            let text = extractText(second) ?? "Hecho."
            appendAssistant(text, state: state)
        } catch {
            showError("Karmi: \(error.localizedDescription)", state: state)
        }
    }

    private let systemPrompt = """
    Eres Karmi, el asistente interno de Karma.
    Responde siempre en español salvo que el usuario pida otro idioma.
    Sé breve, práctico y natural.

    Puedes ejecutar acciones reales en el ecosistema Karma usando herramientas.

    Reglas:
    - Para crear un gasto, un ingreso o una tarea, usa la herramienta correspondiente.
    - No inventes importes, fechas, clientes, proveedores ni proyectos.
    - Si falta un dato imprescindible, pregunta antes de ejecutar.
    - Interpreta "hoy" con la fecha local del usuario solo cuando la app la haya incluido explícitamente en el texto.
    - Si el usuario no menciona IVA/IRPF, usa los valores por defecto de la herramienta.
    - Después de ejecutar una acción, confirma brevemente qué has hecho.
    - No digas que algo se ha guardado si la herramienta devuelve error.
    """

    private var tools: [[String: Any]] {
        [
            [
                "type": "function",
                "name": "create_expense",
                "description": "Crear un gasto real en Karma App.",
                "strict": true,
                "parameters": [
                    "type": "object",
                    "properties": [
                        "description": ["type": "string"],
                        "base_amount": ["type": "number"],
                        "date": ["type": ["string", "null"], "description": "Fecha YYYY-MM-DD o null"],
                        "scope": ["type": "string", "enum": ["A", "B"]],
                        "vat_rate": ["type": "number"],
                        "withholding_rate": ["type": "number"],
                        "payment_status": ["type": "string", "enum": ["paid", "unpaid"]],
                        "supplier_name": ["type": ["string", "null"]],
                        "category_name": ["type": ["string", "null"]],
                        "payment_method_name": ["type": ["string", "null"]],
                        "notes": ["type": ["string", "null"]]
                    ],
                    "required": ["description", "base_amount", "date", "scope", "vat_rate", "withholding_rate", "payment_status", "supplier_name", "category_name", "payment_method_name", "notes"],
                    "additionalProperties": false
                ]
            ],
            [
                "type": "function",
                "name": "create_income",
                "description": "Crear un ingreso real en Karma App.",
                "strict": true,
                "parameters": [
                    "type": "object",
                    "properties": [
                        "description": ["type": "string"],
                        "base_amount": ["type": "number"],
                        "date": ["type": ["string", "null"], "description": "Fecha YYYY-MM-DD o null"],
                        "scope": ["type": "string", "enum": ["A", "B"]],
                        "vat_rate": ["type": "number"],
                        "withholding_rate": ["type": "number"],
                        "payment_status": ["type": "string", "enum": ["paid", "partial", "unpaid"]],
                        "amount_received": ["type": "number"],
                        "client_name": ["type": ["string", "null"]],
                        "business_line_name": ["type": ["string", "null"]],
                        "notes": ["type": ["string", "null"]]
                    ],
                    "required": ["description", "base_amount", "date", "scope", "vat_rate", "withholding_rate", "payment_status", "amount_received", "client_name", "business_line_name", "notes"],
                    "additionalProperties": false
                ]
            ],
            [
                "type": "function",
                "name": "create_task",
                "description": "Crear una tarea real en Karma Work.",
                "strict": true,
                "parameters": [
                    "type": "object",
                    "properties": [
                        "title": ["type": "string"],
                        "project_name": ["type": ["string", "null"]],
                        "priority": ["type": "string", "enum": ["Alta", "Media", "Baja"]],
                        "due_date": ["type": ["string", "null"], "description": "Fecha YYYY-MM-DD o null"]
                    ],
                    "required": ["title", "project_name", "priority", "due_date"],
                    "additionalProperties": false
                ]
            ]
        ]
    }

    private struct FunctionCall {
        let callID: String
        let name: String
        let arguments: [String: Any]
    }

    private func execute(call: FunctionCall) async -> String {
        switch call.name {
        case "create_expense":
            let result = await KarmiSupabaseClient.shared.createExpense(
                description: call.arguments["description"] as? String ?? "",
                baseAmount: number(call.arguments["base_amount"]),
                date: call.arguments["date"] as? String,
                scope: call.arguments["scope"] as? String ?? "A",
                vatRate: number(call.arguments["vat_rate"], fallback: 21),
                withholdingRate: number(call.arguments["withholding_rate"]),
                paymentStatus: call.arguments["payment_status"] as? String ?? "paid",
                notes: call.arguments["notes"] as? String,
                supplierName: call.arguments["supplier_name"] as? String,
                categoryName: call.arguments["category_name"] as? String,
                paymentMethodName: call.arguments["payment_method_name"] as? String
            )
            return toolOutput(result)

        case "create_income":
            let result = await KarmiSupabaseClient.shared.createIncome(
                description: call.arguments["description"] as? String ?? "",
                baseAmount: number(call.arguments["base_amount"]),
                date: call.arguments["date"] as? String,
                scope: call.arguments["scope"] as? String ?? "A",
                vatRate: number(call.arguments["vat_rate"], fallback: 21),
                withholdingRate: number(call.arguments["withholding_rate"], fallback: 15),
                paymentStatus: call.arguments["payment_status"] as? String ?? "unpaid",
                amountReceived: number(call.arguments["amount_received"]),
                clientName: call.arguments["client_name"] as? String,
                businessLineName: call.arguments["business_line_name"] as? String,
                notes: call.arguments["notes"] as? String
            )
            return toolOutput(result)

        case "create_task":
            let result = await KarmiSupabaseClient.shared.createTask(
                title: call.arguments["title"] as? String ?? "",
                projectName: call.arguments["project_name"] as? String,
                priority: call.arguments["priority"] as? String ?? "Media",
                dueDate: call.arguments["due_date"] as? String
            )
            return toolOutput(result)

        default:
            return #"{"ok":false,"message":"Herramienta desconocida."}"#
        }
    }

    private func toolOutput(_ result: KarmiActionResult) -> String {
        let obj: [String: Any] = [
            "ok": result.ok,
            "message": result.message,
            "payload": result.payload ?? [:]
        ]
        if let data = try? JSONSerialization.data(withJSONObject: obj),
           let string = String(data: data, encoding: .utf8) {
            return string
        }
        return #"{"ok":false,"message":"No se pudo serializar el resultado."}"#
    }

    private func number(_ value: Any?, fallback: Double = 0) -> Double {
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        if let n = value as? NSNumber { return n.doubleValue }
        return fallback
    }

    private func callAPI(body: [String: Any], key: String) async throws -> [String: Any] {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 45

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(status)"
            throw NSError(domain: "KarmiAI", code: status, userInfo: [NSLocalizedDescriptionKey: message])
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "KarmiAI", code: 3, userInfo: [NSLocalizedDescriptionKey: "Respuesta JSON inválida."])
        }
        return json
    }

    private func extractFunctionCalls(_ json: [String: Any]) -> [FunctionCall] {
        guard let output = json["output"] as? [[String: Any]] else { return [] }
        return output.compactMap { item in
            guard item["type"] as? String == "function_call",
                  let callID = item["call_id"] as? String,
                  let name = item["name"] as? String,
                  let argumentsString = item["arguments"] as? String,
                  let data = argumentsString.data(using: .utf8),
                  let arguments = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }
            return FunctionCall(callID: callID, name: name, arguments: arguments)
        }
    }

    private func extractText(_ json: [String: Any]) -> String? {
        guard let output = json["output"] as? [[String: Any]] else { return nil }
        var pieces: [String] = []

        for item in output where item["type"] as? String == "message" {
            guard let content = item["content"] as? [[String: Any]] else { continue }
            for block in content {
                if block["type"] as? String == "output_text",
                   let text = block["text"] as? String {
                    pieces.append(text)
                }
            }
        }

        let joined = pieces.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return joined.isEmpty ? nil : joined
    }

    private func appendAssistant(_ text: String, state: AppState) {
        state.chatHistory.append(ChatMessage(role: .assistant, content: text))
        state.stateOverride = nil
        state.view = .prompt
        NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.happy)
    }

    private func showError(_ message: String, state: AppState) {
        state.stateOverride = nil
        state.chatHistory.append(ChatMessage(role: .assistant, content: message))
        state.view = .prompt
    }
}
