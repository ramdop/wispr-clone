import Foundation

struct PromptTemplate {
    let rawValue: String
    
    static let smartList = PromptTemplate(rawValue: """
    You are a text formatter that cleans up voice transcriptions.
    
    INSTRUCTIONS:
    1. Fix punctuation and capitalization.
    2. Do NOT change, add, or remove words. Preserve the user's original phrasing and word choice.
    3. Be EXTREMELY CONSERVATIVE with technical replacements; only change terms if it is a clear phonetic mismatch (e.g., "rock" -> "groq" in a tech context).
    4. INTELLIGENTLY FORMAT the structure based on context (this does NOT count as changing words):
       - Use double quotes (" ") when the user says "in double quotes", "quotes", or clearly references a specific string.
       - Use parentheses ( ) for asides or when the user says "in parentheses". Apply them specifically to the word or phrase described.
       - EXECUTE formatting instructions (e.g., if user says "list these", use bullets; if user says "in quotes", use quotes; if user says "in parentheses", use parentheses) instead of outputting the instruction itself.
       - BREAK run-on sentences into bullet points if they contain sequential steps or items.
       - Use bullet points for lists (if the user is listing items, even implied).
       - Use code blocks (```) for code snippets.
    5. Wrap your ENTIRE output in <formatted_text> tags.
    6. Do NOT output anything outside these tags.
    7. Do NOT use HTML tags (e.g. <b>, <i>) inside the formatted text. Use Markdown only.
    
    Examples:
    
    Input: "one apples two bananas three oranges"
    Output:
    <formatted_text>
    1. Apples
    2. Bananas
    3. Oranges
    </formatted_text>
    
    Input: "I'm seeing that a lot of the transcriptions now are just bulletised aggressively"
    Output:
    <formatted_text>
    I'm seeing that a lot of the transcriptions now are just bulletised aggressively.
    </formatted_text>
    
    Input: "hey john hope you're doing well wanted to check in about the project"
    Output:
    <formatted_text>
    Hey John, hope you're doing well. Wanted to check in about the project.
    </formatted_text>
    
    Input: "what did you mean by app is fully signed and active"
    Output:
    <formatted_text>
    What did you mean by "app is fully signed and active"?
    </formatted_text>
    
    Input: "let me try again and see in double quotes if all this works"
    Output:
    <formatted_text>
    Let me try again and see "if all this works".
    </formatted_text>
    
    Input:
    """)
    
    
    static let command = PromptTemplate(rawValue: """
    You are an intelligent text editor.
    
    INSTRUCTIONS:
    1. Read the "Selected Text".
    2. Read the "User Instruction" (the user's voice command).
    3. Modify the "Selected Text" strictly according to the "User Instruction".
    4. Output ONLY the final modified text wrapped in <formatted_text> tags.
    
    Examples:
    
    Input Selection: "Hi bob, i hate u"
    Input Instruction: "Make this polite"
    Output:
    <formatted_text>
    Hi Bob, I wanted to express my dissatisfaction.
    </formatted_text>
    
    Input Selection: "function foo() { print("hello") }"
    Input Instruction: "Convert to python"
    Output:
    <formatted_text>
    def foo():
        print("hello")
    </formatted_text>
    """)
    
    /// Smart Flow with learned dictionary - LLM decides context-appropriate replacements
    /// Use %DICTIONARY_ENTRIES% placeholder for dictionary, replaced at runtime
    static let smartFlowWithDictionary = PromptTemplate(rawValue: """
    You are a text formatter that cleans up voice transcriptions.
    
    INSTRUCTIONS:
    1. Fix punctuation and capitalization.
    2. Do NOT change, add, or remove words. Preserve the user's original phrasing and word choice.
    3. Be EXTREMELY CONSERVATIVE with technical replacements; only change terms if it is a clear phonetic mismatch (e.g., "rock" -> "groq" in a tech context).
    4. INTELLIGENTLY FORMAT the structure based on context (this does NOT count as changing words):
       - Use double quotes (" ") when the user says "in double quotes", "quotes", or clearly references a specific string.
       - Use parentheses ( ) for asides or when the user says "in parentheses". Apply them specifically to the word or phrase described.
       - EXECUTE formatting instructions (e.g., if user says "list these", use bullets; if user says "in quotes", use quotes; if user says "in parentheses", use parentheses) instead of outputting the instruction itself.
       - BREAK run-on sentences into bullet points if they contain sequential steps or items.
       - Use bullet points for lists (if the user is listing items, even implied).
       - Use code blocks (```) for code snippets.
    5. Apply learned corrections ONLY if the word sounds like the alias AND context suggests a transcription error.
    6. Apply CUSTOM VOCABULARY BIAS to correct misheard words if they sound similar to the target word and fit the context (e.g., identity documents).
    7. Do NOT simply insert dictionary words if they are not present. Replacement must be phonetically justified.
    8. Do NOT use HTML tags (e.g. <b>, <i>) inside the formatted text. Use Markdown only.
    
    LEARNED CORRECTIONS (apply only if context suggests transcription error AND word sounds similar):
    %DICTIONARY_ENTRIES%
    
    CUSTOM VOCABULARY BIAS (words the user cares about, bias towards these if phonetic mismatch occurs):
    %CUSTOM_VOCABULARIES%
    
    EXAMPLES of when to apply vs NOT apply:
    - "I want to use alarm for processing" → Replace "alarm" with "ollama" (sounds similar + tech context)
    - "Set an alarm for morning" → Keep "alarm" (sounds similar but intentional usage)
    - "I like rock music" → Keep "rock" (do NOT replace with "groq" just because "groq" is in dictionary, unless user clearly meant "groq")
    - "I am using rock api" -> Replace "rock" with "groq" (sounds similar + tech context)
    - "I finally got my other guard processed" -> Replace "guard" with "aadhar" (if aadhar is in custom vocabulary + context of processing/documents)
    
    9. Wrap your ENTIRE output in <formatted_text> tags.
    10. Do NOT output anything outside these tags.
    
    Input:
    """)
    
    // Add more templates here (e.g., Email, Summary)
}

enum LLMProviderType: String, CaseIterable, Codable {
    case ollama = "Ollama (Local)"
    case openai = "OpenAI (Cloud)"
    case groq = "Groq (Cloud)"
}

protocol LLMProvider {
    func isAvailable() async -> Bool
    func analyze(text: String, template: PromptTemplate, apiKey: String?) async throws -> String
}

actor OllamaProvider: LLMProvider {
    private let baseUrl = URL(string: "http://localhost:11434/api/generate")!
    private let modelName: String
    
    // Use llama3.2:3b for faster local inference (vs llama3 8B which is slow)
    init(modelName: String = "llama3.2:3b") {
        self.modelName = modelName
    }
    
    func isAvailable() async -> Bool {
        // Check if the specific model is available in Ollama
        guard let url = URL(string: "http://localhost:11434/api/tags") else { return false }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return false }
            
            // Parse the response to check if our model exists
            struct OllamaTagsResponse: Decodable {
                struct Model: Decodable {
                    let name: String
                }
                let models: [Model]?
            }
            
            let decoded = try JSONDecoder().decode(OllamaTagsResponse.self, from: data)
            let modelExists = decoded.models?.contains { $0.name == modelName || $0.name.hasPrefix(modelName.split(separator: ":").first.map(String.init) ?? modelName) } ?? false
            
            if !modelExists {
                Logger.debug("[Ollama] Model '\(modelName)' not found. Available: \(decoded.models?.map { $0.name }.joined(separator: ", ") ?? "none")")
            }
            return modelExists
        } catch {
            Logger.error("[Ollama] Availability check failed: \(error)")
            return false
        }
    }
    
    func analyze(text: String, template: PromptTemplate, apiKey: String?) async throws -> String {
        let wrappedInput = "Transcript to process:\n" + text
        let prompt = template.rawValue + "\n\n" + wrappedInput
        
        Logger.debug("[Ollama] Prompt: \(prompt.prefix(50))...")
        
        let payload: [String: Any] = [
            "model": modelName,
            "prompt": prompt,
            "stream": false
        ]
        
        // Increase timeout to 20s for local LLM inference
        var request = URLRequest(url: baseUrl, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 20.0)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw NSError(domain: "OllamaProvider", code: 1, userInfo: [NSLocalizedDescriptionKey: "Ollama request failed"])
        }
        
        struct OllamaResponse: Decodable {
            let response: String
        }
        
        let decoded = try JSONDecoder().decode(OllamaResponse.self, from: data)
        if let responseString = String(data: data, encoding: .utf8) {
            Logger.debug("[Ollama] Response: \(responseString.prefix(100))...")
        }
        return decoded.response.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

actor OpenAIProvider: LLMProvider {
    private let baseUrl = URL(string: "https://api.openai.com/v1/chat/completions")!
    private let modelName: String
    
    init(modelName: String = "gpt-4o") {
        self.modelName = modelName
    }
    
    func isAvailable() async -> Bool {
        return true // Always available, connectivity checked during request
    }
    
    func analyze(text: String, template: PromptTemplate, apiKey: String?) async throws -> String {
        guard let apiKey = apiKey, !apiKey.isEmpty else {
            throw NSError(domain: "OpenAIProvider", code: 401, userInfo: [NSLocalizedDescriptionKey: "Missing API Key"])
        }
        
        let messages: [[String: String]] = [
            ["role": "system", "content": template.rawValue],
            ["role": "user", "content": "Transcript to process:\n" + text]
        ]
        
        let payload: [String: Any] = [
            "model": modelName,
            "messages": messages,
            "temperature": 0.0
        ]
        
        let prompt = template.rawValue + "\n\n" + "Transcript to process:\n" + text // Reconstruct prompt for logging
        Logger.debug("[OpenAI] Prompt: \(prompt.prefix(50))...")
        Logger.debug("[OpenAI] API Key: \(apiKey.prefix(5))...")
        
        var request = URLRequest(url: baseUrl, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 10.0)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
             throw NSError(domain: "OpenAIProvider", code: 0, userInfo: [NSLocalizedDescriptionKey: "Network error"])
        }

        guard httpResponse.statusCode == 200 else {
             if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let errorObj = errorJson["error"] as? [String: Any],
                let message = errorObj["message"] as? String {
                 Logger.error("[OpenAI] Request failed with status \(httpResponse.statusCode): \(message)")
                 throw NSError(domain: "OpenAIProvider", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: message])
             }
            Logger.error("[OpenAI] Request failed with status \(httpResponse.statusCode)")
            throw NSError(domain: "OpenAIProvider", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "OpenAI request failed: \(httpResponse.statusCode)"])
        }
        
        struct OpenAIResponse: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable {
                    let content: String
                }
                let message: Message
            }
            let choices: [Choice]
        }
        
        let decoded = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        if let responseString = String(data: data, encoding: .utf8) {
            Logger.debug("[OpenAI] Response: \(responseString.prefix(100))...")
        }
        return decoded.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines) ?? text
    }
}

actor GroqProvider: LLMProvider {
    /// Groq retires models aggressively (llama3-8b-8192, then llama-3.1-8b-instant on 2026-08-16).
    /// The model is user-configurable in the menu; this is the default.
    static let defaultModel = "openai/gpt-oss-20b"
    
    private let baseUrl = URL(string: "https://api.groq.com/openai/v1/chat/completions")!
    private let modelName: String
    
    init(modelName: String = GroqProvider.defaultModel) {
        self.modelName = modelName
    }
    
    func isAvailable() async -> Bool {
        return true
    }
    
    func analyze(text: String, template: PromptTemplate, apiKey: String?) async throws -> String {
        guard let apiKey = apiKey, !apiKey.isEmpty else {
             throw NSError(domain: "GroqProvider", code: 401, userInfo: [NSLocalizedDescriptionKey: "Missing API Key"])
        }
        
        let messages: [[String: String]] = [
            ["role": "system", "content": template.rawValue],
            ["role": "user", "content": "Transcript to process:\n" + text]
        ]
        
        var payload: [String: Any] = [
             "model": modelName,
             "messages": messages,
             "temperature": 0.3
         ]
         // gpt-oss models reason before answering: keep it minimal for latency and
         // leave the reasoning out of the response (the answer stays in message.content)
         if modelName.hasPrefix("openai/gpt-oss") {
             payload["reasoning_effort"] = "low"
             payload["include_reasoning"] = false
         }
         
        let prompt = template.rawValue + "\n\n" + "Transcript to process:\n" + text // Reconstruct prompt for logging
        Logger.debug("[Groq] Model: \(modelName) | Prompt: \(prompt.prefix(50))...")
        Logger.debug("[Groq] API Key: \(apiKey.prefix(5))...")
         
         var request = URLRequest(url: baseUrl, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 10.0)
         request.httpMethod = "POST"
         request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
         request.setValue("application/json", forHTTPHeaderField: "Content-Type")
         request.httpBody = try JSONSerialization.data(withJSONObject: payload)
         
         let (data, response) = try await URLSession.shared.data(for: request)
         
          guard let httpResponse = response as? HTTPURLResponse else {
              throw NSError(domain: "GroqProvider", code: 0, userInfo: [NSLocalizedDescriptionKey: "Network error"])
         }

         guard httpResponse.statusCode == 200 else {
              if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                 let errorObj = errorJson["error"] as? [String: Any],
                 let message = errorObj["message"] as? String {
                  Logger.error("[Groq] Request failed with status \(httpResponse.statusCode): \(message)")
                  throw NSError(domain: "GroqProvider", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: message])
              }
             Logger.error("[Groq] Request failed with status \(httpResponse.statusCode)")
             throw NSError(domain: "GroqProvider", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Groq request failed: \(httpResponse.statusCode)"])
         }
         
         struct OpenAIResponse: Decodable {
             struct Choice: Decodable {
                 struct Message: Decodable {
                     let content: String
                 }
                 let message: Message
             }
             let choices: [Choice]
         }
         
         let decoded = try JSONDecoder().decode(OpenAIResponse.self, from: data)
         if let responseString = String(data: data, encoding: .utf8) {
             Logger.debug("[Groq] Response: \(responseString.prefix(100))...")
         }
         return decoded.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines) ?? text
     }
}

class LLMService {
    private var providers: [LLMProviderType: LLMProvider] = [:]
    private var availabilityCache: [LLMProviderType: Bool] = [:]
    
    /// - Parameter model: Groq model override; nil or empty uses `GroqProvider.defaultModel`
    func process(_ text: String, provider: LLMProviderType, apiKey: String?, template: PromptTemplate = .smartList, model: String? = nil) async throws -> String {
        let llm: LLMProvider
        if provider == .groq {
            // Not cached: the model can change from the menu at any time (cheap to create)
            let trimmed = model?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            llm = GroqProvider(modelName: trimmed.isEmpty ? GroqProvider.defaultModel : trimmed)
        } else {
            llm = getProvider(for: provider)
        }
        
        // Connectivity check only for Ollama, but cached
        if provider == .ollama {
            if availabilityCache[provider] != true {
                guard await llm.isAvailable() else {
                    throw NSError(domain: "LLMService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Ollama not running"])
                }
                availabilityCache[provider] = true
            }
        }
        
        let result = try await llm.analyze(text: text, template: template, apiKey: apiKey)
        return cleanResponse(result)
    }
    
    private func getProvider(for type: LLMProviderType) -> LLMProvider {
        if let existing = providers[type] {
            return existing
        }
        
        let new: LLMProvider
        switch type {
        case .ollama: new = OllamaProvider()
        case .openai: new = OpenAIProvider()
        case .groq: new = GroqProvider()
        }
        providers[type] = new
        return new
    }
    
    // Helper to check availability mainly for Ollama
    func isProviderAvailable(_ provider: LLMProviderType) async -> Bool {
        if provider == .ollama {
            let available = await getProvider(for: .ollama).isAvailable()
            availabilityCache[provider] = available
            return available
        }
        return true
    }
    
    private func cleanResponse(_ text: String) -> String {
        Logger.debug("[LLMService] Raw Response: \(text)")
        
        let cleaned: String
        
        // 1. Try formatted_text extraction
        let extractPattern = "<formatted_text>(.*?)</formatted_text>"
        if let regex = try? NSRegularExpression(pattern: extractPattern, options: [.dotMatchesLineSeparators, .caseInsensitive]),
           let match = regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count)),
           let range = Range(match.range(at: 1), in: text) {
            cleaned = String(text[range])
        } else {
            // 2. Fallback: Strip tags if extraction failed
            // Matches <formatted_text>, </formatted_text>, <formatted_text style="...">, etc.
            // Also handles missing closing bracket if truncated or anything starting with formatted_text tag
            let tagPattern = "</?formatted_text[^>]*>"
            if let tagRegex = try? NSRegularExpression(pattern: tagPattern, options: [.caseInsensitive]) {
                let range = NSRange(location: 0, length: text.utf16.count)
                cleaned = tagRegex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
            } else {
                cleaned = text
            }
        }
        
        // 3. Final cleanup
        // Remove known refusal prefixes if present
        if cleaned.hasPrefix("I cannot") { return text } 
        
        let final = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        Logger.debug("[LLMService] Cleaned Response: \(final)")
        return final
    }
}
