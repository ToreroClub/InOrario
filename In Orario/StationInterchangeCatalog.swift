import SwiftUI

struct InterchangeBadge: Identifiable, Hashable, Sendable {
    var id: String { code }
    let code: String
    let hexColor: String

    var color: Color {
        Color(hex: hexColor)
    }

    var textColor: Color {
        PersonalRailwayLine.isLightHexColor(hexColor) ? .black : .white
    }
}

enum StationInterchangeCatalog {
    // Colori ufficiali linee metropolitane, suburbane e servizi principali
    private static let palette: [String: String] = [
        // Milano Metro
        "M1": "#E30613",
        "M2": "#00853E",
        "M3": "#F5A600",
        "M4": "#004684",
        "M5": "#8A59A3",
        // Milano Suburbane
        "S1": "#E30613",
        "S2": "#009640",
        "S3": "#E51937",
        "S4": "#C8102E",
        "S5": "#F39200",
        "S6": "#FFD60A",
        "S7": "#8E24AA",
        "S8": "#00796B",
        "S9": "#5C6BC0",
        "S11": "#8A8BBF",
        "S12": "#005A2B",
        "S13": "#A37A3E",
        "S19": "#00A0DF",
        // Servizi speciali, TILO & altre città
        "S10": "#E30613",
        "S40": "#0072BC",
        "S50": "#0072BC",
        "MXP": "#A6192E",
        "LEO": "#880E4F",
        "AV": "#B71C1C",
        "✈": "#0288D1",
        "M": "#0072BC",
        "MA": "#E65100",
        "MB": "#0277BD",
        "L1": "#F9A825",
        "L2": "#0288D1",
        "L6": "#00695C",
        "T1": "#00897B",
        "T2": "#3949AB",
        "SFM1": "#D81B60",
        "SFM2": "#E53935",
        "SFM3": "#FB8C00",
        "SFM4": "#8E24AA",
        "SFM6": "#43A047",
        "SFM7": "#039BE5",
        "S2A": "#00897B",
        "S2B": "#00796B",
        "S4A": "#7B1FA2",
        "S4B": "#8E24AA",
        "5T": "#00897B",
        "GE-MET": "#0288D1",
        "M-SA": "#005596",
        "BA-MET": "#0288D1",
        "RC-MET": "#039BE5",
        "PA-AERO": "#D81B60",
        "PA-AN": "#8E24AA",
        "ME-MET": "#0288D1",
        "CA-MET": "#00897B",
        "FL1": "#00897B",
        "FL2": "#3949AB",
        "FL3": "#5E35B1",
        "FL4": "#C0CA33",
        "FL5": "#6D4C41",
        "FL6": "#F4511E",
        "FL7": "#D81B60",
        "FL8": "#1E88E5"
    ]

    private static let rawCatalog: [(String, [String])] = [
        // Milano & Lombardia
        ("Milano Centrale", ["M2", "M3", "AV", "MXP"]),
        ("Milano Porta Garibaldi", ["M2", "M5", "S1", "S2", "S5", "S6", "S7", "S8", "S11", "S12", "S13", "MXP", "AV"]),
        ("P. Garibaldi Passante", ["M2", "M5", "S1", "S2", "S5", "S6", "S7", "S8", "S11", "S12", "S13", "MXP"]),
        ("Milano Porta Garibaldi Sotterranea", ["M2", "M5", "S1", "S2", "S5", "S6", "S12", "S13"]),
        ("Milano Cadorna", ["M1", "M2", "S3", "S4", "MXP"]),
        ("Milano Bovisa Politecnico", ["S1", "S2", "S3", "S4", "S12", "S13", "MXP"]),
        ("Milano Domodossola", ["M5", "S3", "S4"]),
        ("Milano Affori", ["M3", "S2", "S4", "S12"]),
        ("Lancetti", ["S1", "S2", "S5", "S6", "S12", "S13"]),
        ("Milano Lancetti", ["S1", "S2", "S5", "S6", "S12", "S13"]),
        ("Repubblica", ["M3", "S1", "S2", "S5", "S6", "S12", "S13"]),
        ("Milano Repubblica", ["M3", "S1", "S2", "S5", "S6", "S12", "S13"]),
        ("Porta Venezia", ["M1", "S1", "S2", "S5", "S6", "S12", "S13"]),
        ("Milano Porta Venezia", ["M1", "S1", "S2", "S5", "S6", "S12", "S13"]),
        ("Dateo", ["M4", "S1", "S2", "S5", "S6", "S12", "S13"]),
        ("Milano Dateo", ["M4", "S1", "S2", "S5", "S6", "S12", "S13"]),
        ("Porta Vittoria", ["S1", "S2", "S5", "S6", "S12", "S13"]),
        ("Milano Porta Vittoria", ["S1", "S2", "S5", "S6", "S12", "S13"]),
        ("Milano Forlanini", ["M4", "S5", "S6", "S9"]),
        ("Milano Rogoredo", ["M3", "S1", "S2", "S12", "S13", "S19", "AV"]),
        ("Milano Lambrate", ["M2", "S9"]),
        ("Milano Romolo", ["M2", "S9", "S19"]),
        ("Milano Scalo Romana", ["M3", "S9", "S19"]),
        ("Milano Tibaldi Universita' Bocconi", ["S9", "S19"]),
        ("Milano S.Cristoforo", ["M4", "S9", "S19"]),
        ("Milano Greco Pirelli", ["S7", "S8", "S9", "S11"]),
        ("Milano Certosa", ["S5", "S6", "S11"]),
        ("Milano Villapizzone", ["S5", "S6", "S11"]),
        ("Milano Bruzzano Parco Nord", ["S2", "S4", "S12"]),
        ("Rho Fiera", ["M1", "S5", "S6", "S11", "AV"]),
        ("Rho", ["S5", "S6", "S11"]),
        ("Sesto S.Giovanni", ["M1", "S7", "S8", "S9", "S11"]),
        ("Saronno", ["S1", "S3", "S9", "MXP"]),
        ("Monza", ["S7", "S8", "S9", "S11"]),
        ("Seregno", ["S9", "S11"]),
        ("Seveso", ["S2", "S4"]),
        ("Cesano Maderno", ["S2", "S4", "S9"]),
        ("Albairate-Vermezzo", ["S9", "S19"]),
        ("Pioltello Limito", ["S5", "S6"]),
        ("Treviglio", ["S5", "S6"]),
        ("Novara", ["S6"]),
        ("Gallarate", ["S5", "S50"]),
        ("Varese", ["S5", "S40", "S50"]),
        ("Como S.Giovanni", ["S10", "S11", "S40"]),
        ("Chiasso", ["S10", "S11", "S40"]),
        ("Mendrisio", ["S10", "S40", "S50"]),
        ("Lugano", ["S10", "S50"]),
        ("Bellinzona", ["S10", "S50"]),
        ("Lecco", ["S7", "S8"]),
        ("Brescia", ["M", "AV"]),
        ("Pavia", ["S13"]),
        ("Lodi", ["S1"]),
        ("Busto Arsizio Nord", ["MXP"]),
        ("Malpensa Aeroporto Terminal 1", ["✈", "MXP", "S50"]),
        ("Malpensa Aeroporto Terminal 2", ["✈", "MXP", "S50"]),

        // Torino & Piemonte
        ("Torino Porta Nuova", ["M1", "SFM3", "AV"]),
        ("Torino Porta Susa", ["M1", "SFM1", "SFM2", "SFM4", "SFM6", "SFM7", "AV"]),
        ("Torino Lingotto", ["M1", "SFM1", "SFM2", "SFM4", "SFM6", "SFM7"]),
        ("Torino Stura", ["SFM1", "SFM2"]),
        ("Torino Rebaudengo Fossata", ["SFM1", "SFM2", "SFM4", "SFM6", "SFM7"]),
        ("Settimo Torinese", ["SFM1", "SFM2"]),
        ("Trofarello", ["SFM1", "SFM4", "SFM6", "SFM7"]),
        ("Chivasso", ["SFM2"]),
        ("Torino Aeroporto", ["✈", "SFM4", "SFM6", "SFM7"]),
        ("Torino Aeroporto di Caselle", ["✈", "SFM4", "SFM6", "SFM7"]),

        // Roma
        ("Roma Termini", ["MA", "MB", "FL4", "FL5", "FL6", "FL7", "FL8", "LEO", "AV"]),
        ("Roma Tiburtina", ["MB", "FL1", "FL2", "FL3", "AV"]),
        ("Roma Ostiense", ["MB", "FL1", "FL3", "FL5"]),
        ("Roma Tuscolana", ["MA", "FL1", "FL3"]),
        ("Roma Trastevere", ["FL1", "FL3", "FL5"]),
        ("Roma S.Pietro", ["FL3", "FL5"]),
        ("Ciampino", ["FL4", "FL6"]),
        ("Fiumicino Aeroporto", ["✈", "FL1", "LEO"]),

        // Napoli, Sud & Isole & Principali
        ("Napoli Centrale", ["L1", "L2", "AV"]),
        ("Napoli Piazza Garibaldi", ["L1", "L2"]),
        ("Napoli Campi Flegrei", ["L2", "L6"]),
        ("Napoli Mergellina", ["L2", "L6"]),
        ("Napoli Montesanto", ["L2"]),
        ("Napoli Piazza Cavour", ["L1", "L2"]),
        ("Napoli Afragola", ["AV"]),
        ("Salerno", ["AV", "M-SA"]),
        ("Bologna Centrale", ["AV", "S1", "S2A", "S2B", "S3", "S4A", "S4B", "S5"]),
        ("Bologna C.le/AV", ["AV"]),
        ("Casalecchio Garibaldi", ["S1", "S2A"]),
        ("S.Pietro in Casale", ["S3", "S4A"]),
        ("Imola", ["S4B"]),
        ("Modena", ["S5"]),
        ("Ferrara", ["S4A"]),
        ("Reggio Emilia AV Mediopadana", ["AV"]),
        ("Firenze Santa Maria Novella", ["T1", "T2", "AV"]),
        ("Pisa Centrale", ["✈"]),
        ("Genova Piazza Principe", ["M", "GE-MET"]),
        ("Genova Brignole", ["M", "GE-MET"]),
        ("Genova Sestri Ponente Aeroporto", ["✈", "GE-MET"]),
        ("La Spezia Centrale", ["5T"]),
        ("Levanto", ["5T"]),
        ("Venezia S.Lucia", ["AV"]),
        ("Venezia Mestre", ["AV"]),
        ("Padova", ["AV"]),
        ("Vicenza", ["AV"]),
        ("Verona Porta Nuova", ["AV"]),
        ("Trieste Airport", ["✈"]),
        ("Bari Centrale", ["AV", "BA-MET"]),
        ("Lamezia Terme Centrale", ["AV"]),
        ("Villa S.Giovanni", ["AV", "RC-MET"]),
        ("Reggio di Calabria Centrale", ["AV", "RC-MET"]),
        ("Reggio di Calabria Aeroporto", ["✈", "RC-MET"]),
        ("Palermo Centrale", ["PA-AERO"]),
        ("Palermo Notarbartolo", ["PA-AERO", "PA-AN"]),
        ("Punta Raisi", ["✈", "PA-AERO"]),
        ("Palermo Aeroporto", ["✈", "PA-AERO"]),
        ("Catania Centrale", ["M"]),
        ("Catania Aeroporto Fontanarossa", ["✈"]),
        ("Messina Centrale", ["ME-MET"]),
        ("Cagliari", ["CA-MET"]),
        ("Elmas Aeroporto", ["✈", "CA-MET"]),
        ("Decimomannu", ["CA-MET"])
    ]

    private static let catalogByNormalizedName: [String: [String]] = {
        var map: [String: [String]] = [:]
        for (station, codes) in rawCatalog {
            let key = RailwayLineCatalog.normalizeStationToken(station)
            if map[key] == nil {
                map[key] = codes
            }
        }
        return map
    }()

    static func interchanges(for stationName: String, excludingLineCode currentCode: String? = nil) -> [InterchangeBadge] {
        let key = RailwayLineCatalog.normalizeStationToken(stationName)
        guard let codes = catalogByNormalizedName[key] else { return [] }

        let excludedUpper = currentCode?.uppercased().trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let isAVLine = excludedUpper.hasPrefix("AV")

        return codes.compactMap { code in
            let upper = code.uppercased()
            if !excludedUpper.isEmpty && upper == excludedUpper {
                return nil
            }
            if isAVLine && upper == "AV" {
                return nil
            }
            let hex = palette[code] ?? "#64748B"
            return InterchangeBadge(code: code, hexColor: hex)
        }
    }
}
