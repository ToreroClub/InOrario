import Foundation
import ActivityKit

struct TrainLiveActivityAttributes: ActivityAttributes {
    
    public struct ContentState: Codable, Hashable {
        var delay: String
        var statusMessage: String
        var lastStation: String
        var progress: Double // Range 0.0 - 1.0 representing train route completion
    }

    var trainNumber: String
    var destination: String
    var category: String
    var origin: String // Depature station
}

extension String {
    func abbreviatedStationName() -> String {
        var name = self.trimmingCharacters(in: .whitespacesAndNewlines)
        
        let mappings = [
            ("Torino Porta Nuova", "Torino P.N."),
            ("Torino P.N.", "Torino P.N."),
            ("Torino Porta Susa", "Torino P.S."),
            ("Torino P.S.", "Torino P.S."),
            ("Milano Centrale", "Milano CLE"),
            ("Milano Porta Garibaldi", "Milano P.G."),
            ("Milano P. Garibaldi", "Milano P.G."),
            ("Milano Lambrate", "Milano Lambrate"),
            ("Milano Rogoredo", "Milano Rogoredo"),
            ("Roma Termini", "Roma Termini"),
            ("Roma Tiburtina", "Roma Tiburtina"),
            ("Venezia Santa Lucia", "Venezia S.L."),
            ("Venezia S. Lucia", "Venezia S.L."),
            ("Venezia Mestre", "Mestre"),
            ("Firenze Santa Maria Novella", "Firenze S.M.N."),
            ("Firenze S.M.N.", "Firenze S.M.N."),
            ("Bologna Centrale", "Bologna Cle"),
            ("Napoli Centrale", "Napoli Cle"),
            ("Genova Piazza Principe", "Genova P.P."),
            ("Genova Brignole", "Genova Brignole")
        ]
        
        for (target, replacement) in mappings {
            if name.localizedCaseInsensitiveContains(target) {
                return replacement
            }
        }
        
        name = name.replacingOccurrences(of: "Porta Nuova", with: "P.N.", options: .caseInsensitive)
        name = name.replacingOccurrences(of: "Porta Susa", with: "P.S.", options: .caseInsensitive)
        name = name.replacingOccurrences(of: "Porta Garibaldi", with: "P.G.", options: .caseInsensitive)
        name = name.replacingOccurrences(of: "Centrale", with: "CLE", options: .caseInsensitive)
        
        return name
    }
}
