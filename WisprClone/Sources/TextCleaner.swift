import Foundation

struct TextCleaner {
    static func clean(text: String, removeFillers: Bool, addPunctuation: Bool) -> String {
        Logger.debug("[TextCleaner] Input: '\(text)'")
        var processed = text
        
        if removeFillers {
            processed = Self.removeFillers(from: processed)
        }
        
        // Remove repeated words (e.g., "the the")
        processed = removeRepeatedWords(from: processed)
        
        // Normalize whitespace
        processed = processed.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        processed = processed.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Capitalize first letter
        processed = capitalizeFirst(processed)
        
        if addPunctuation {
            processed = insertCommas(processed)
            processed = ensureTerminalPunctuation(processed)
        }
        
        Logger.debug("[TextCleaner] Output: '\(processed)'")
        return processed
    }
    
    private static func removeFillers(from text: String) -> String {
        // Simple case-insensitive removal of fillers
        // "uh", "um", "erm", "ah", "you know", "I mean", "kind of", "sort of"
        // Need to be careful about word boundaries \b
        
        let fillers = [
            "uh", "um", "erm", "ah",
            "you know", "I mean",
            "kind of", "sort of"
        ]
        
        var current = text
        for filler in fillers {
            // Pattern: case insensitive, whole word
            let pattern = "\\b\(filler)\\b"
            current = current.replacingOccurrences(of: pattern, with: "", options: [.regularExpression, .caseInsensitive])
        }
        return current
    }
    
    private static func removeRepeatedWords(from text: String) -> String {
        // Regex for repeated words: (\b\w+\b)(?:\s+\1\b)+
        return text.replacingOccurrences(of: "(\\b\\w+\\b)(?:\\s+\\1\\b)+", 
                                       with: "$1", 
                                       options: [.regularExpression, .caseInsensitive])
    }
    
    private static func capitalizeFirst(_ text: String) -> String {
        guard let first = text.first else { return "" }
        return String(first).uppercased() + text.dropFirst()
    }
    
    private static func ensureTerminalPunctuation(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        let last = text.last!
        if ".?!".contains(last) {
            return text
        }
        return text + "."
    }
    
    private static func insertCommas(_ text: String) -> String {
        var processed = text
        
        // 1. Remove specific filler patterns that might have slipped through or been added by Apple's auto-punctuation
        // ", like, " -> " "
        processed = processed.replacingOccurrences(of: ", like,", with: "", options: .caseInsensitive)
        processed = processed.replacingOccurrences(of: " like,", with: "", options: .caseInsensitive) // "It was like, cool" -> "It was cool"
        
        // List of coordinating conjunctions/connectors to precede with comma
        // We use a specific pattern: Word + Space + Connector + Space
        // We ensure we don't double-comma if one exists already.
        
        let connectors = ["but", "so", "although", "though", "however", "meanwhile", "otherwise", "yet", "while"]
        
        for connector in connectors {
            // Pattern:
            // Group 1: Word character (\w+)
            // Lookbehind negative for comma: (?<!,) - Swift regex support limited in replace, implies manual handling or simpler regex.
            // Let's stick to matching (\w+)\s+connector
            
            // Let's stick to matching (\w+)\s+connector
            
            // let pattern = "(\\w+)\\s+(\(connector))\\b" // Unused, using safePattern instead
            // Replace with "$1, $2" (appends result)
            // Note: We deliberately don't match the trailing space in the group so we don't consume it for the *next* match if they are close? 
            // Actually replacingOccurrences acts on the whole string.
            
            // To avoid replacing "Word, but" with "Word, , but", we can check if it already has comma in the regex isn't easy with stdlib.
            // We can match `[^,]` before space? -> ([^,\s])\s+(connector)
            
            let safePattern = "([^,\\s])\\s+(\(connector))\\b"
            processed = processed.replacingOccurrences(of: safePattern, 
                                                     with: "$1, $2", 
                                                     options: [.regularExpression, .caseInsensitive])
        }
        
        // Special handling for "which"
        processed = processed.replacingOccurrences(of: "([^,\\s])\\s+which\\b", 
                                                 with: "$1, which", 
                                                 options: [.regularExpression, .caseInsensitive])
        
        return processed
    }
    static func formatDictation(_ text: String) -> String {
        var processed = text
        
        let replacements: [(pattern: String, replacement: String)] = [
            ("new line", "\n"),
            ("newline", "\n"),
            (" open quote", " \""),
            ("close quote", "\""),
            (" dot", "."), // Conservative
            (" full stop", "."),
            (" period", "."),
            (" comma", ","),
            (" question mark", "?"),
            (" exclamation mark", "!"),
            (" colon", ":"),
            (" semicolon", ";")
        ]
        
        for (pattern, replacement) in replacements {
            // Case insensitive replacement
            processed = processed.replacingOccurrences(of: pattern, with: replacement, options: .caseInsensitive)
        }
        
        // Fix spaces before punctuation that might result from simple replacement
        // e.g., "Hello , world" -> "Hello, world"
        let cleanupPatterns: [(pattern: String, replacement: String)] = [
            (" \\.", "."),
            (" ,", ","),
            (" \\?", "?"),
            (" !", "!"),
            (" :", ":"),
            (" ;", ";")
        ]
        
        for (pattern, replacement) in cleanupPatterns {
            processed = processed.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
        }
        
        return processed
    }
}
