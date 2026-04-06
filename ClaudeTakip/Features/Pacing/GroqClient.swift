import Foundation

struct PacingMessage: Codable, Sendable {
    let message: String
}

enum GroqError: Error {
    case invalidResponse
    case rateLimited
    case serverError(Int)
    case parseFailed
}

enum GroqClient: Sendable {
    private static let systemPrompt = """
        You write short tips for a macOS Claude usage tracker. Talk like a helpful friend, not a robot. Be direct and natural.

        Rules:
        - One clear point per message. Pick what matters most right now.
        - Write 15-25 words. Sound human — vary your sentence structure, don't repeat patterns.
        - Never use numbers, percentages, durations, or dollar amounts (the UI already shows them).
        - Never start with "Your usage" or "Your session" — find a more interesting way in.
        - No greetings, no self-references, no filler.
        - Extra usage context: "has spending cap, X% of cap used" means the user set a monthly budget. Low % = plenty of room, don't warn about it. "cap almost reached" = actually running low. "unlimited" = no cap at all. "disabled" = not turned on.

        Tone guide (match exactly):
        - urgent: Be serious and direct. Something needs immediate action.
        - warning: Calm but clear. Heads up, pay attention.
        - info: Casual and brief. Nothing alarming, just awareness.
        - relaxed: Warm and encouraging. Things are going great.

        JSON response: {"message": "..."}

        Examples:

        Session: 92%, Weekly: 45%, Speed: 1.8x, Visual: red, Tone: urgent
        {"message": "Almost out of session quota — wrap up what you're doing and let it reset. Weekly is fine, no rush there."}

        Session: 100%, Weekly: 100%, Extra: unlimited, Visual: red, Tone: urgent
        {"message": "Both limits hit. You're on paid credits now with no cap — finish only what's urgent and step away."}

        Session: 35%, Weekly: 75%, Speed: weekly 1.2x, Visual: orange, Tone: warning
        {"message": "Weekly is climbing faster than ideal. Maybe save the big tasks for after the reset and keep it light for now."}

        Session: 60%, Weekly: 50%, Speed: 1.4x, Visual: orange, Tone: warning
        {"message": "Burning through this session a bit fast. Shorter prompts and a quick break would help stretch what's left."}

        Session: 45%, Weekly: 40%, Speed: 0.8x, Visual: green, Tone: info
        {"message": "Solid pace so far. Plenty of room in both session and weekly — just keep an eye on it."}

        Session: 28%, Weekly: 20%, Speed: 0.6x, Visual: green, Tone: relaxed
        {"message": "Looking good — you've got tons of headroom. Use Claude freely, you're well within limits."}

        Session: 77%, Weekly: 56%, Extra: has spending cap, 0% used, Visual: red, Tone: urgent
        {"message": "Session is running hot with barely any time left. Pause and let it reset — your spending cap is barely touched if you need it."}
        """

    static func fetchMessage(context: String, language: String) async throws -> PacingMessage {
        guard !GroqConstants.apiKey.isEmpty else { throw GroqError.invalidResponse }

        let languageInstruction: String
        switch language {
        case "tr": languageInstruction = "You MUST respond in Turkish."
        case "es": languageInstruction = "You MUST respond in Spanish."
        case "fr": languageInstruction = "You MUST respond in French."
        case "de": languageInstruction = "You MUST respond in German."
        case "it": languageInstruction = "You MUST respond in Italian."
        case "nl": languageInstruction = "You MUST respond in Dutch."
        case "ja": languageInstruction = "You MUST respond in Japanese."
        case "ko": languageInstruction = "You MUST respond in Korean."
        case "zh-Hans": languageInstruction = "You MUST respond in Simplified Chinese."
        case "zh-Hant": languageInstruction = "You MUST respond in Traditional Chinese."
        case "ru": languageInstruction = "You MUST respond in Russian."
        case "ar": languageInstruction = "You MUST respond in Arabic."
        case "pt-BR": languageInstruction = "You MUST respond in Brazilian Portuguese."
        default: languageInstruction = "You MUST respond in English."
        }

        let fullSystemPrompt = systemPrompt + "\n\n" + languageInstruction

        let body: [String: Any] = [
            "model": GroqConstants.model,
            "messages": [
                ["role": "system", "content": fullSystemPrompt],
                ["role": "user", "content": context]
            ],
            "temperature": 0.85,
            "max_tokens": 150,
            "response_format": ["type": "json_object"]
        ]

        guard let url = URL(string: GroqConstants.baseURL) else { throw GroqError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(GroqConstants.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 10

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw GroqError.invalidResponse
        }

        if http.statusCode == 429 {
            throw GroqError.rateLimited
        }

        guard http.statusCode == 200 else {
            throw GroqError.serverError(http.statusCode)
        }

        return try parseResponse(data)
    }

    private static func parseResponse(_ data: Data) throws -> PacingMessage {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String,
              let contentData = content.data(using: .utf8)
        else {
            throw GroqError.parseFailed
        }

        let raw = try JSONDecoder().decode(PacingMessage.self, from: contentData)
        let parsed = PacingMessage(message: raw.message.trimmingCharacters(in: .whitespacesAndNewlines))

        guard !parsed.message.isEmpty else {
            throw GroqError.parseFailed
        }

        let wordCount = parsed.message.split(separator: " ").count
        guard wordCount >= 10 else {
            throw GroqError.parseFailed
        }

        return parsed
    }
}
