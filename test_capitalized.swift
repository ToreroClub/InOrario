import Foundation

extension String {
    var precomposedStringWithCanonicalMapping: String { self }
    var normalizedForDisplay: String {
        var str = self.precomposedStringWithCanonicalMapping
        if str.contains("Ã") || str.contains("©") || str.contains("¨") || str.contains("¬") || str.contains("³") {
            if let data = str.data(using: .isoLatin1), let utf8Str = String(data: data, encoding: .utf8) {
                str = utf8Str
            }
        }
        return str
    }
    var formattedStationName: String {
        let normalized = self.normalizedForDisplay
        let lower = normalized.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if lower.isEmpty { return normalized }
        
        var formatted = lower
            .replacingOccurrences(of: "p.ta ", with: "Porta ")
            .replacingOccurrences(of: "p. ", with: "Porta ")
            .replacingOccurrences(of: "staz.ne ", with: "Stazione ")
            .replacingOccurrences(of: "milano p.garibaldi", with: "Milano P. Garibaldi")
            .replacingOccurrences(of: "p. garibaldi passante", with: "Milano P. Garibaldi")
            .replacingOccurrences(of: "p.garibaldi passante", with: "Milano P. Garibaldi")
            .replacingOccurrences(of: "milano p. garibaldi", with: "Milano P. Garibaldi")
            .replacingOccurrences(of: "milano porta garibaldi passante", with: "Milano P. Garibaldi")
            .replacingOccurrences(of: "milano porta garibaldi", with: "Milano P. Garibaldi")
            .replacingOccurrences(of: "milano centrale", with: "Milano Centrale")
            .replacingOccurrences(of: "m.centrale", with: "Milano Centrale")
            .replacingOccurrences(of: "m. centrale", with: "Milano Centrale")
            
        // Capitalize words
        formatted = formatted.capitalized
        return formatted
    }
}

let bytes: [UInt8] = [70, 111, 114, 108, 195, 172] // ForlÃ¬
let str = String(bytes: bytes, encoding: .isoLatin1)!
print("Original: \(str)")
print("Formatted: \(str.formattedStationName)")

let s2 = "Santhià"
print("Original 2: \(s2)")
print("Formatted 2: \(s2.formattedStationName)")

