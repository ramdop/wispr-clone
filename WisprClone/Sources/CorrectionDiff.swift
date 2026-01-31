import Foundation

/// A candidate replacement extracted from a correction
struct ReplacementCandidate {
    let from: String
    let to: String
}

/// Diff and learning heuristics for correction extraction
struct CorrectionDiff {
    
    /// Extract a replacement candidate from injected vs corrected text
    /// Returns nil if diff is ambiguous, too large, or not learnable
    // List of common words that should NEVER be learned as aliases
    static let STOP_WORDS: Set<String> = [
        "other", "the", "and", "a", "to", "of", "in", "is", "it", "that", "for",
        "you", "he", "she", "with", "on", "at", "by", "but", "myself", "this",
        "so", "some", "be", "or", "as", "from", "what", "can", "will", "if",
        "my", "we", "all", "would", "there", "their", "an"
    ]

    static func extractReplacement(injected: String, corrected: String) -> ReplacementCandidate? {
        let injectedTokens = tokenize(injected)
        let correctedTokens = tokenize(corrected)
        
        // Log for debugging
        Logger.debug("[CorrectionDiff] Injected tokens: \(injectedTokens)")
        Logger.debug("[CorrectionDiff] Corrected tokens (first 15): \(Array(correctedTokens.prefix(15)))")
        
        // Find words in injected that are NOT in corrected (potential "from" words)
        let injectedSet = Set(injectedTokens.map { $0.lowercased() })
        let correctedSet = Set(correctedTokens.map { $0.lowercased() })
        
        let missingFromCorrected = injectedSet.subtracting(correctedSet)  // Words in injected but not corrected
        let addedInCorrected = correctedSet.subtracting(injectedSet)       // Words in corrected but not injected
        
        Logger.debug("[CorrectionDiff] Missing from corrected: \(missingFromCorrected)")
        Logger.debug("[CorrectionDiff] Added in corrected: \(addedInCorrected)")
        
        // M-to-1 Case: Phrase replaced by single word (e.g., "Sequel Light" -> "SQLite")
        if missingFromCorrected.count > 1 && addedInCorrected.count == 1 {
             Logger.debug("[CorrectionDiff] Detected potential M-to-1 replacement")
             // We fallback to extractByPrefixSuffix which handles contiguous spans well.
        }
        
        // Simple case: exactly one word was replaced (1-to-1 or 1-to-M)
        if missingFromCorrected.count == 1 && addedInCorrected.count >= 1 {
            let fromWord = missingFromCorrected.first!
            
            // Find the position of the missing word in the original
            guard let injectedIdx = injectedTokens.firstIndex(where: { $0.lowercased() == fromWord }) else {
                return nil
            }
            
            // Look for the replacement word near the same position in corrected
            // First, find any surrounding context words
            let contextBefore = injectedIdx > 0 ? injectedTokens[injectedIdx - 1].lowercased() : nil
            let contextAfter = injectedIdx < injectedTokens.count - 1 ? injectedTokens[injectedIdx + 1].lowercased() : nil
            
            // Search for the new word(s) between context words in corrected
            var toWord: String? = nil
            for (i, token) in correctedTokens.enumerated() {
                // Check if this is one of the added words
                if addedInCorrected.contains(token.lowercased()) {
                    // Verify context matches
                    let prevMatches = (contextBefore == nil) || 
                                       (i > 0 && correctedTokens[i-1].lowercased() == contextBefore)
                    let nextMatches = (contextAfter == nil) || 
                                       (i < correctedTokens.count - 1 && 
                                        correctedTokens[i+1].lowercased() == contextAfter)
                    
                    if prevMatches || nextMatches {
                        toWord = correctedTokens[i]  // Use actual case from corrected
                        break
                    }
                }
            }
            
            if let to = toWord {
                // Get the original cased version
                let from = injectedTokens[injectedIdx]
                Logger.info("[CorrectionDiff] Found replacement: '\(from)' → '\(to)'")
                return ReplacementCandidate(from: from, to: to)
            }
        }
        
        // Complex case: try traditional prefix/suffix matching on narrowed region
        // Only if relatively similar lengths
        if abs(injectedTokens.count - correctedTokens.count) <= 3 {
            return extractByPrefixSuffix(injectedTokens: injectedTokens, correctedTokens: correctedTokens)
        }
        
        // Try to find the injected region within corrected
        if correctedTokens.count > injectedTokens.count + 2 {
            if let matchRange = findBestMatchRange(injectedTokens: injectedTokens, in: correctedTokens) {
                let narrowed = Array(correctedTokens[matchRange])
                Logger.debug("[CorrectionDiff] Narrowed to: \(narrowed.joined(separator: " "))")
                return extractByPrefixSuffix(injectedTokens: injectedTokens, correctedTokens: narrowed)
            }
        }
        
        Logger.debug("[CorrectionDiff] Could not extract replacement")
        return nil
    }
    
    /// Traditional prefix/suffix matching for simple diffs
    private static func extractByPrefixSuffix(injectedTokens: [String], correctedTokens: [String]) -> ReplacementCandidate? {
        // Guard: reject if token count differs too much
        let tokenDiff = abs(injectedTokens.count - correctedTokens.count)
        if tokenDiff > 2 {
            Logger.debug("[CorrectionDiff] Rejected: token count diff too large (\(tokenDiff))")
            return nil
        }
        
        // Find prefix match
        var prefixEnd = 0
        while prefixEnd < injectedTokens.count && prefixEnd < correctedTokens.count {
            if injectedTokens[prefixEnd].lowercased() == correctedTokens[prefixEnd].lowercased() {
                prefixEnd += 1
            } else {
                break
            }
        }
        
        // Find suffix match (from end)
        var suffixStart = 0
        while suffixStart < (injectedTokens.count - prefixEnd) && suffixStart < (correctedTokens.count - prefixEnd) {
            let injIdx = injectedTokens.count - 1 - suffixStart
            let corrIdx = correctedTokens.count - 1 - suffixStart
            if injectedTokens[injIdx].lowercased() == correctedTokens[corrIdx].lowercased() {
                suffixStart += 1
            } else {
                break
            }
        }
        
        // Extract mismatch span
        let injectedMismatchEnd = injectedTokens.count - suffixStart
        let correctedMismatchEnd = correctedTokens.count - suffixStart
        
        guard prefixEnd <= injectedMismatchEnd && prefixEnd <= correctedMismatchEnd else {
            return nil
        }
        
        let fromTokens = Array(injectedTokens[prefixEnd..<injectedMismatchEnd])
        let toTokens = Array(correctedTokens[prefixEnd..<correctedMismatchEnd])
        
        // Guard: only accept spans of 1-3 tokens
        if fromTokens.count > 3 || toTokens.count > 3 {
            Logger.debug("[CorrectionDiff] Rejected: span too large (from: \(fromTokens.count), to: \(toTokens.count))")
            return nil
        }
        
        // Guard: reject if both empty (no actual change)
        if fromTokens.isEmpty && toTokens.isEmpty {
            return nil
        }
        
        let from = fromTokens.joined(separator: " ")
        let to = toTokens.joined(separator: " ")
        
        // Guard: reject punctuation/casing only changes
        if from.lowercased().filter({ $0.isLetter || $0.isNumber }) == to.lowercased().filter({ $0.isLetter || $0.isNumber }) {
            return nil
        }
        
        return ReplacementCandidate(from: from, to: to)
    }
    
    /// Find the best matching range in correctedTokens that corresponds to injectedTokens
    private static func findBestMatchRange(injectedTokens: [String], in correctedTokens: [String]) -> Range<Int>? {
        let injectedLower = injectedTokens.map { $0.lowercased() }
        let correctedLower = correctedTokens.map { $0.lowercased() }
        
        var bestStart = -1
        var bestScore = 0
        
        // Slide window of injected size across corrected
        let maxStart = correctedTokens.count - injectedTokens.count
        guard maxStart >= 0 else { return nil }
        
        for start in 0...maxStart {
            var score = 0
            for i in 0..<injectedTokens.count {
                if correctedLower[start + i] == injectedLower[i] {
                    score += 1
                }
            }
            
            // Accept if at least 50% match
            if score > bestScore && Double(score) / Double(injectedTokens.count) >= 0.5 {
                bestScore = score
                bestStart = start
            }
        }
        
        if bestStart >= 0 {
            // Expand range by 2 tokens on each side for corrections
            let rangeStart = max(0, bestStart - 2)
            let rangeEnd = min(correctedTokens.count, bestStart + injectedTokens.count + 2)
            return rangeStart..<rangeEnd
        }
        
        return nil
    }
    
    /// Check if a replacement should be learned
    static func shouldLearn(_ candidate: ReplacementCandidate) -> Bool {
        let from = candidate.from.trimmingCharacters(in: .whitespacesAndNewlines)
        let to = candidate.to.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Stopword Check
        if STOP_WORDS.contains(from.lowercased()) {
            Logger.info("[CorrectionDiff] Rejected stopword: '\(from)'")
            return false
        }
        
        // Both must be non-empty
        guard !from.isEmpty, !to.isEmpty else {
            Logger.debug("[CorrectionDiff] shouldLearn: rejected empty")
            return false
        }
        
        // Length check (max 40 chars each)
        guard from.count <= 40, to.count <= 40 else {
            Logger.debug("[CorrectionDiff] shouldLearn: rejected too long")
            return false
        }
        
        // Note: We no longer block generic words here because the LLM handles
        // context-aware replacement decisions at paste time. The LLM will intelligently
        // decide when to apply learned corrections based on sentence context.
        
        // Edit distance check (normalized)
        let distance = levenshteinDistance(from.lowercased(), to.lowercased())
        let maxLen = max(from.count, to.count)
        let normalizedDistance = Double(distance) / Double(maxLen)
        
        if normalizedDistance > 0.7 {
            Logger.debug("[CorrectionDiff] shouldLearn: rejected high edit distance (\(normalizedDistance))")
            return false
        }
        
        return true
    }
    
    // MARK: - Helpers
    
    private static func tokenize(_ text: String) -> [String] {
        // Simple word tokenization
        return text.components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { !$0.isEmpty }
    }
    
    private static func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let a = Array(s1)
        let b = Array(s2)
        let m = a.count
        let n = b.count
        
        if m == 0 { return n }
        if n == 0 { return m }
        
        var matrix = [[Int]](repeating: [Int](repeating: 0, count: n + 1), count: m + 1)
        
        for i in 0...m { matrix[i][0] = i }
        for j in 0...n { matrix[0][j] = j }
        
        for i in 1...m {
            for j in 1...n {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                matrix[i][j] = min(
                    matrix[i - 1][j] + 1,
                    matrix[i][j - 1] + 1,
                    matrix[i - 1][j - 1] + cost
                )
            }
        }
        
        return matrix[m][n]
    }
}
