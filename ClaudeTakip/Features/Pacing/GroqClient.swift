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
        You are an assistant in a macOS usage tracking app that advises the user. Be friendly, strategic, and solution-oriented. Address the user as "you".

        Goal: Help the user manage their Claude usage limits wisely. Look at all data together, highlight the most critical point, and produce a single coherent message.

        Principles:
        - Look at the big picture. If there are multiple issues, pick the most urgent one — don't list them all.
        - Identify the problem, provide a solution. Tell the user what to do.
        - If extra usage is disabled and usage limit is reached, suggest enabling it. If active, remind them money is being spent or will be soon. In unlimited mode, emphasize there is no upper limit.
        - If usage limit was reached earlier today, be cautious and advise not to repeat the same mistake.
        - If Sonnet usage is high, suggest model diversity to the user.
        - Match the given tone: urgent -> serious and directive, warning -> careful but calm, info -> neutral and brief, relaxed -> warm and encouraging.

        Restrictions:
        - Do not use numbers, percentages, durations, or dollar amounts in the message. This information is already shown in the UI.
        - Do not refer to yourself.
        - Do not use formulaic phrases ("Hello", "I hope", "Good day", etc.).

        Message should be 15-30 words. JSON response: {"message": "..."}

        Examples:

        Session: 92%, Weekly: 45%, Speed: session 1.8x, Tone: warning
        {"message": "Your session limit is about to be reached, but your weekly usage is comfortable. Take a short break now and wait for reset."}

        Session: 100%, Weekly: 100%, Extra: limited and in use, Tone: urgent
        {"message": "All your usage limits are reached and you're spending from paid credits. Only do the work you must finish, postpone the rest."}

        Session: 60%, Weekly: 50%, Speed: session 1.1x, weekly 1.0x, Tone: info
        {"message": "Your usage is at a moderate level and your pace is reasonable. Keep going but proceed carefully until the next reset."}

        Session: 28%, Weekly: 20%, Speed: session 0.6x, Tone: relaxed
        {"message": "Everything is on track, your usage limits are safe and your pace is very balanced. Continue comfortably at your current rhythm."}
        """

    static func fetchMessage(context: String, language: String) async throws -> PacingMessage {
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
            "temperature": 0.7,
            "max_tokens": 150,
            "response_format": ["type": "json_object"]
        ]

        var request = URLRequest(url: URL(string: GroqConstants.baseURL)!)
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

        let parsed = try JSONDecoder().decode(PacingMessage.self, from: contentData)

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
