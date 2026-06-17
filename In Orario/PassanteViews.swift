import SwiftUI
import Combine

struct PassanteTunnelThermometerView: View {
    let statusMessage: String
    let statusColorHex: String
    let avgDelay: Int
    
    @EnvironmentObject var manager: TrainManager
    @AppStorage("showOuterSuburbanStations") var showOuterSuburbanStations = false
    
    var color: Color {
        resolvedTrackColor
    }
    
    var resolvedTrackColor: Color {
        let activeLinesForTrack = manager.selectedSuburbanLines.filter { ["S1", "S2", "S5", "S6", "S12", "S13"].contains($0) }
        if activeLinesForTrack.count == 1, let singleLine = activeLinesForTrack.first {
            let trainsOfLine = manager.passanteTunnelTrains.filter { train in
                let cat = train.category.uppercased()
                let dest = train.destination.lowercased()
                if cat == singleLine { return true }
                if singleLine == "S1" { return dest.contains("saronno") || dest.contains("lodi") }
                if singleLine == "S2" { return dest.contains("mariano") || dest.contains("seveso") || dest.contains("camnago") }
                if singleLine == "S5" { return dest.contains("varese") || dest.contains("treviglio") || dest.contains("gallarate") }
                if singleLine == "S6" { return dest.contains("novara") || dest.contains("pioltello") }
                if singleLine == "S12" { return dest.contains("melegnano") || dest.contains("cormano") }
                if singleLine == "S13" { return dest.contains("pavia") || dest.contains("bovisa") }
                return false
            }
            
            var cancellations = 0
            var delays: [Int] = []
            for t in trainsOfLine {
                let isCancelled = t.delay.lowercased().contains("soppresso") || t.delay.lowercased().contains("cancellato")
                if isCancelled {
                    cancellations += 1
                } else {
                    let delayStr = t.delay.replacingOccurrences(of: "+", with: "").replacingOccurrences(of: "'", with: "")
                    let delayVal = delayStr.lowercased().contains("orario") ? 0 : (Int(delayStr) ?? 0)
                    delays.append(delayVal)
                }
            }
            
            let avgDelay = delays.isEmpty ? 0 : (delays.reduce(0, +) / delays.count)
            
            if cancellations > 0 || avgDelay >= 8 { return .red }
            else if avgDelay >= 3 { return .orange }
            else { return .green }
        } else {
            return Color(hex: statusColorHex)
        }
    }
    
    func shortDestination(_ dest: String) -> String {
        let d = dest.lowercased()
        if d.contains("novara") { return "NOV" }
        if d.contains("pioltello") { return "PIOLT" }
        if d.contains("treviglio") { return "TREV" }
        if d.contains("varese") { return "VAR" }
        if d.contains("gallarate") { return "GALL" }
        if d.contains("saronno") { return "SAR" }
        if d.contains("lodi") { return "LODI" }
        if d.contains("mariano") { return "MAR" }
        if d.contains("seveso") { return "SEV" }
        if d.contains("camnago") { return "CAMN" }
        if d.contains("pavia") { return "PAV" }
        if d.contains("bovisa") { return "BOV" }
        if d.contains("rogoredo") { return "ROG" }
        if d.contains("melegnano") { return "MEL" }
        if d.contains("cadorna") { return "CAD" }
        if d.contains("garibaldi") { return "GAR" }
        if d.contains("certosa") { return "CRT" }
        if d.contains("rho") { return "RHO" }
        if d.contains("piolt") { return "PIO" }
        if d.contains("novara") { return "NOV" }
        return dest.prefix(5).uppercased()
    }

    
    let stations = [
        "Varese", "Gazzada-Schianno-Morazzone", "Gazzada-Schianno", "Castronno", 
        "Albizzate-Solbiate Arno", "Albizzate-Solbiate A.", "Cavaria-Oggiona-Jerago", 
        "Cavaria-Oggiona-J.", "Gallarate", "Busto Arsizio", "Legnano", "Canegrate", 
        "Parabiago", "Vanzago-Pogliano",
        
        "Novara", "Trecate", "Magenta", "Corbetta-S.Stefano Ticino", "Vittuone-Arluno", "Pregnana Milanese", "Rho",
        
        "Saronno", "Caronno Pertusella", "Cesate", "Garbagnate Milanese", 
        "Garbagnate Parco delle Groane", "Garbagnate Parco Groane", "Bollate Nord", 
        "Bollate Centro", "Novate Milanese", "Milano Quarto Oggiaro",
        
        "Mariano Comense", "Cabiate", "Meda", "Seveso", "Cesano Maderno", 
        "Bovisio Masciago-Mombello", "Varedo", "Palazzolo Milanese", "Paderno Dugnano", 
        "Cormano-Cusano Milanino", "Cusano Milanino", "Milano Bruzzano",
        
        "Rho Fiera", "Certosa", "Villapizzone", "Milano Bovisa", "Lancetti", 
        "P. Garibaldi Passante", "Repubblica", "Porta Venezia", "Dateo", "Porta Vittoria",
        
        "Forlanini", "Segrate", "Pioltello-Limito", "Melzo", "Pozzuolo Martesana", 
        "Trecella", "Cassano d'Adda", "Treviglio",
        
        "Milano Rogoredo", "San Donato Milanese", "Borgolombardo", "San Giuliano Milanese", 
        "Melegnano", "Tavazzano", "Lodi",
        
        "Locate Triulzi", "Pieve Emanuele", "Villamaggiore", "Certosa di Pavia", "Pavia"
    ]
    
    let s1Stations: Set<String> = ["Saronno", "Caronno Pertusella", "Cesate", "Garbagnate Milanese", "Garbagnate Parco delle Groane", "Garbagnate Parco Groane", "Bollate Nord", "Bollate Centro", "Novate Milanese", "Milano Quarto Oggiaro", "Milano Bovisa", "Lancetti", "P. Garibaldi Passante", "Repubblica", "Porta Venezia", "Dateo", "Porta Vittoria", "Milano Rogoredo", "San Donato Milanese", "Borgolombardo", "San Giuliano Milanese", "Melegnano", "Tavazzano", "Lodi"]
    let s2Stations: Set<String> = ["Mariano Comense", "Cabiate", "Meda", "Seveso", "Cesano Maderno", "Bovisio Masciago-Mombello", "Varedo", "Palazzolo Milanese", "Paderno Dugnano", "Cormano-Cusano Milanino", "Milano Bruzzano", "Milano Bovisa", "Lancetti", "P. Garibaldi Passante", "Repubblica", "Porta Venezia", "Dateo", "Porta Vittoria", "Milano Rogoredo"]
    let s5Stations: Set<String> = ["Varese", "Gazzada-Schianno-Morazzone", "Gazzada-Schianno", "Castronno", "Albizzate-Solbiate Arno", "Albizzate-Solbiate A.", "Cavaria-Oggiona-Jerago", "Cavaria-Oggiona-J.", "Gallarate", "Busto Arsizio", "Legnano", "Canegrate", "Parabiago", "Vanzago-Pogliano", "Rho", "Rho Fiera", "Certosa", "Villapizzone", "Lancetti", "P. Garibaldi Passante", "Repubblica", "Porta Venezia", "Dateo", "Porta Vittoria", "Forlanini", "Segrate", "Pioltello-Limito", "Melzo", "Pozzuolo Martesana", "Trecella", "Cassano d'Adda", "Treviglio"]
    let s6Stations: Set<String> = ["Novara", "Trecate", "Magenta", "Corbetta-S.Stefano Ticino", "Vittuone-Arluno", "Pregnana Milanese", "Rho", "Rho Fiera", "Certosa", "Villapizzone", "Lancetti", "P. Garibaldi Passante", "Repubblica", "Porta Venezia", "Dateo", "Porta Vittoria", "Forlanini", "Segrate", "Pioltello-Limito"]
    let s12Stations: Set<String> = ["Cormano-Cusano Milanino", "Milano Bruzzano", "Milano Bovisa", "Lancetti", "P. Garibaldi Passante", "Repubblica", "Porta Venezia", "Dateo", "Porta Vittoria", "Milano Rogoredo", "San Donato Milanese", "Borgolombardo", "San Giuliano Milanese", "Melegnano"]
    let s13Stations: Set<String> = ["Milano Bovisa", "Lancetti", "P. Garibaldi Passante", "Repubblica", "Porta Venezia", "Dateo", "Porta Vittoria", "Milano Rogoredo", "Locate Triulzi", "Pieve Emanuele", "Villamaggiore", "Certosa di Pavia", "Pavia"]

    func getEstimatedStationName(for train: Train) -> String? {
        guard let status = manager.passanteLiveStatuses[train.number] else {
            return nil
        }
        
        let isCancelled = train.delay.lowercased().contains("soppresso") || train.delay.lowercased().contains("cancellato") || status.cancellationNote != nil
        if isCancelled || status.isArrived { return nil }
        
        let last = status.lastStation.lowercased()
        let category = train.category.uppercased()
        
        let isCertosaAxis = ["S5", "S6"].contains(category)
        let isBovisaAxis = ["S1", "S2", "S12", "S13"].contains(category)
        
        var matchedStation: String? = nil
        for st in stations {
            let stName = st.lowercased()
            if stName.contains("garibaldi") && last.contains("garibaldi") { matchedStation = st; break }
            if stName.contains("venezia") && last.contains("venezia") { matchedStation = st; break }
            if stName.contains("vittoria") && last.contains("vittoria") { matchedStation = st; break }
            if stName.contains("bovisa") && last.contains("bovisa") { matchedStation = st; break }
            if stName.contains("rho") && last.contains("rho") { matchedStation = st; break }
            if last.contains(stName) || stName.contains(last) { matchedStation = st; break }
        }
        
        guard let candidate = matchedStation else { return nil }
        
        if candidate == "Milano Bovisa" && isCertosaAxis { return nil }
        if (candidate == "Certosa" || candidate == "Villapizzone") && isBovisaAxis { return nil }
        
        if category == "S1" && !s1Stations.contains(candidate) { return nil }
        if category == "S2" && !s2Stations.contains(candidate) { return nil }
        if category == "S5" && !s5Stations.contains(candidate) { return nil }
        if category == "S6" && !s6Stations.contains(candidate) { return nil }
        if category == "S12" && !s12Stations.contains(candidate) { return nil }
        if category == "S13" && !s13Stations.contains(candidate) { return nil }
        
        return candidate
    }

    
    func directCountdown(for train: Train) -> String? {
        let isCancelled = train.delay.lowercased().contains("soppresso") || train.delay.lowercased().contains("cancellato")
        if isCancelled { return nil }
        
        let timeString = train.time
        let delayMinutes = Int(train.delay.replacingOccurrences(of: "+", with: "").replacingOccurrences(of: "'", with: "").replacingOccurrences(of: "R: ", with: "")) ?? 0
        
        let calendar = Calendar.current
        let now = Date()
        
        let parts = timeString.split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]) else { return nil }
              
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = hour
        components.minute = minute
        components.second = 0
        
        guard let baseDate = calendar.date(from: components) else { return nil }
        guard var targetDate = calendar.date(byAdding: .minute, value: delayMinutes, to: baseDate) else { return nil }
        
        let diffWithNow = targetDate.timeIntervalSince(now)
        if diffWithNow < -43200 { 
            if let adjustedDate = calendar.date(byAdding: .day, value: 1, to: targetDate) { targetDate = adjustedDate }
        } else if diffWithNow > 43200 { 
            if let adjustedDate = calendar.date(byAdding: .day, value: -1, to: targetDate) { targetDate = adjustedDate }
        }
        
        let diffInSeconds = targetDate.timeIntervalSince(now)
        let diffInMinutes = Int(round(diffInSeconds / 60.0))
        
        if diffInMinutes < 0 {
            return nil
        } else if diffInMinutes == 0 {
            return "ora"
        } else {
            return "\(diffInMinutes)m"
        }
    }
    
    var body: some View {
        let refStationName = manager.selectedPassanteStation.name
        let cleanRefName: String = {
            let lower = refStationName.lowercased()
            if lower.contains("venezia") { return "Porta Venezia" }
            if lower.contains("garibaldi") { return "P. Garibaldi Passante" }
            if lower.contains("lancetti") { return "Lancetti" }
            if lower.contains("repubblica") { return "Repubblica" }
            if lower.contains("dateo") { return "Dateo" }
            if lower.contains("vittoria") { return "Porta Vittoria" }
            if lower.contains("bovisa") { return "Milano Bovisa" }
            if lower.contains("certosa") { return "Certosa" }
            if lower.contains("villapizzone") { return "Villapizzone" }
            if lower.contains("rho") { return "Rho Fiera" }
            if lower.contains("forlanini") { return "Forlanini" }
            if lower.contains("rogoredo") { return "Milano Rogoredo" }
            return refStationName
        }()
        
        let trackColor = resolvedTrackColor
        
        let isCongested = trackColor == .red
        
        let activeStationsList: [String] = {
            let activeLines = manager.selectedSuburbanLines.filter { ["S1", "S2", "S5", "S6", "S12", "S13"].contains($0) }
            let onlyCertosa = !activeLines.isEmpty && activeLines.allSatisfy { ["S5", "S6"].contains($0) }
            let onlyBovisa = !activeLines.isEmpty && activeLines.allSatisfy { ["S1", "S2", "S12", "S13"].contains($0) }
            
            if showOuterSuburbanStations {
                if onlyCertosa {
                    var certosaStations = Set<String>()
                    if activeLines.contains("S5") { certosaStations.formUnion(s5Stations) }
                    if activeLines.contains("S6") { certosaStations.formUnion(s6Stations) }
                    
                    let filtered = certosaStations.filter { stationName in
                        for lineId in activeLines {
                            let lineStations = lineId == "S5" ? s5Stations : s6Stations
                            if lineStations.contains(stationName) {
                                let hidden = manager.hiddenSuburbanStations[lineId] ?? []
                                if !hidden.contains(stationName) {
                                    return true
                                }
                            }
                        }
                        return false
                    }
                    return stations.filter { filtered.contains($0) }
                } else if onlyBovisa {
                    var bovisaStations = Set<String>()
                    if activeLines.contains("S1") { bovisaStations.formUnion(s1Stations) }
                    if activeLines.contains("S2") { bovisaStations.formUnion(s2Stations) }
                    if activeLines.contains("S12") { bovisaStations.formUnion(s12Stations) }
                    if activeLines.contains("S13") { bovisaStations.formUnion(s13Stations) }
                    
                    let filtered = bovisaStations.filter { stationName in
                        for lineId in activeLines {
                            let lineStations: Set<String>
                            switch lineId {
                            case "S1": lineStations = s1Stations
                            case "S2": lineStations = s2Stations
                            case "S12": lineStations = s12Stations
                            default: lineStations = s13Stations
                            }
                            if lineStations.contains(stationName) {
                                let hidden = manager.hiddenSuburbanStations[lineId] ?? []
                                if !hidden.contains(stationName) {
                                    return true
                                }
                            }
                        }
                        return false
                    }
                    return stations.filter { filtered.contains($0) }
                }
            }
            
            if onlyCertosa {
                return [
                    "Rho Fiera",
                    "Certosa",
                    "Villapizzone",
                    "Lancetti",
                    "P. Garibaldi Passante",
                    "Repubblica",
                    "Porta Venezia",
                    "Dateo",
                    "Porta Vittoria",
                    "Forlanini"
                ]
            } else if onlyBovisa {
                return [
                    "Milano Bovisa",
                    "Lancetti",
                    "P. Garibaldi Passante",
                    "Repubblica",
                    "Porta Venezia",
                    "Dateo",
                    "Porta Vittoria",
                    "Milano Rogoredo"
                ]
            } else {
                return [
                    "Lancetti",
                    "P. Garibaldi Passante",
                    "Repubblica",
                    "Porta Venezia",
                    "Dateo",
                    "Porta Vittoria"
                ]
            }
        }()
        
        let linesToProcess: [String] = {
            let activeLines = manager.selectedSuburbanLines.filter { ["S1", "S2", "S5", "S6", "S12", "S13"].contains($0) }
            if activeLines.isEmpty {
                return ["S5", "S6"]
            }
            return Array(activeLines).sorted()
        }()
        
        
        let lineArrivals: [LineArrivalInfo] = {
            var result: [LineArrivalInfo] = []
            for lineId in linesToProcess {
                let trainsOfLine = manager.passanteTrains.filter { $0.category.uppercased() == lineId.uppercased() }
                
                var destMinMins: [String: Int] = [:]
                for train in trainsOfLine {
                    if let countdownStr = directCountdown(for: train) {
                        let mins: Int
                        if countdownStr == "ora" {
                            mins = 0
                        } else {
                            let numStr = countdownStr.replacingOccurrences(of: "m", with: "")
                            mins = Int(numStr) ?? 999
                        }
                        let shortDest = shortDestination(train.destination)
                        if mins >= 0 {
                            let currentMin = destMinMins[shortDest] ?? Int.max
                            if mins < currentMin {
                                destMinMins[shortDest] = mins
                            }
                        }
                    }
                }
                
                if !destMinMins.isEmpty {
                    let sortedDests = destMinMins.sorted { $0.value < $1.value }
                    let arrivalStrings = sortedDests.map { dest, mins in
                        let timeText = mins == 0 ? "ora" : "\(mins)m"
                        return "\(dest) \(timeText)"
                    }
                    result.append(LineArrivalInfo(id: lineId, arrivals: arrivalStrings))
                }
            }
            return result
        }()
        
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Circle()
                    .fill(color)
                    .frame(width: 10, height: 10)
                    .padding(.top, 4)
                
                VStack(alignment: .leading, spacing: 6) {
                    Text(statusMessage)
                        .font(.caption.bold())
                        .foregroundColor(color)
                    
                    if !lineArrivals.isEmpty {
                        ForEach(lineArrivals) { info in
                            HStack(spacing: 8) {
                                SuburbanLineBadge(id: info.id)
                                
                                Text(info.arrivals.joined(separator: "   ·   "))
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundColor(.primary)
                            }
                        }
                    }
                }
                
                Spacer()
                
                Text("Ritardo medio: \(avgDelay)'")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(8)
            }
            
            if isCongested {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                        .font(.caption)
                    Text("Possibile accodamento dovuto a forti ritardi. Valuta metropolitane (M3/M4) per attraversare Milano.")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.red)
                        .multilineTextAlignment(.leading)
                    Spacer()
                }
                .padding(8)
                .background(Color.red.opacity(0.08))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.red.opacity(0.2), lineWidth: 1)
                )
            }
            
            VStack(spacing: 0) {
                ForEach(activeStationsList, id: \.self) { stationName in
                    let isSelected = (stationName == cleanRefName)
                    
                    let trainsAtStation = manager.passanteTunnelTrains.filter { train in
                        let line = train.category.uppercased()
                        if !manager.selectedSuburbanLines.isEmpty && !manager.selectedSuburbanLines.contains(line) {
                            return false
                        }
                        return getEstimatedStationName(for: train) == stationName
                    }
                    
                    HStack(alignment: .center, spacing: 12) {
                        VStack(spacing: 0) {
                            if stationName != activeStationsList.first {
                                Rectangle()
                                    .fill(trackColor.opacity(0.8))
                                    .frame(width: 4, height: 16)
                            } else {
                                Spacer()
                                    .frame(height: 16)
                            }
                            
                            ZStack {
                                Circle()
                                    .fill(Color(.systemBackground))
                                    .frame(width: 20, height: 20)
                                    .overlay(
                                        Circle()
                                            .stroke(trainsAtStation.isEmpty ? trackColor.opacity(0.4) : (isSelected ? .orange : trackColor), lineWidth: isSelected ? 4 : 3)
                                    )
                                    .shadow(color: trackColor.opacity(0.2), radius: 2)
                                
                                if isSelected {
                                    Image(systemName: "mappin.circle.fill")
                                        .font(.system(size: 10))
                                        .foregroundColor(.orange)
                                } else if !trainsAtStation.isEmpty {
                                    PulsingCircle(color: trackColor)
                                        .frame(width: 10, height: 10)
                                } else {
                                    Circle()
                                        .fill(trackColor.opacity(0.3))
                                        .frame(width: 8, height: 8)
                                }
                            }
                            
                            if stationName != activeStationsList.last {
                                Rectangle()
                                    .fill(trackColor.opacity(0.8))
                                    .frame(width: 4, height: 16)
                            } else {
                                Spacer()
                                    .frame(height: 16)
                            }
                        }
                        .frame(width: 24)
                        
                        HStack(spacing: 6) {
                            if isSelected {
                                Text("📍")
                                    .font(.caption)
                            }
                            Text(stationName.replacingOccurrences(of: "Passante", with: "").replacingOccurrences(of: "Milano ", with: ""))
                                .font(.system(size: 13, weight: isSelected ? .black : .bold, design: .rounded))
                                .foregroundColor(.primary)
                        }
                        .frame(width: 150, alignment: .leading)
                        
                        Spacer()
                        
                        if !trainsAtStation.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    ForEach(trainsAtStation, id: \.id) { train in
                                        let direction = manager.getPassanteDirection(for: train) ?? "Est"
                                        let isWest = direction == "Ovest"
                                        let line = train.category.uppercased()
                                        let lineColorHex = SuburbanData.shared.allLines.first(where: { $0.id == line })?.hexColor ?? "#8e8e93"
                                        let isLight = ["S4", "S5", "S6", "S8"].contains(line)
                                        let textColor: Color = isLight ? .black : .white
                                        
                                        HStack(spacing: 3) {
                                            if isWest {
                                                Text("←")
                                                    .font(.system(size: 8, weight: .bold))
                                            }
                                            Text(line)
                                                .font(.system(size: 8, weight: .black, design: .rounded))
                                            if !isWest {
                                                Text("→")
                                                    .font(.system(size: 8, weight: .bold))
                                            }
                                            

                                        }
                                        .foregroundColor(textColor)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 4)
                                        .background(Color(hex: lineColorHex))
                                        .cornerRadius(6)
                                        .shadow(color: Color(hex: lineColorHex).opacity(0.3), radius: 2)
                                    }
                                }
                            }
                        } else {
                            Spacer()
                        }
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(isSelected ? Color.orange.opacity(0.06) : Color.clear)
                    .cornerRadius(8)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if !isSelected {
                            let newStation = stationForName(stationName, manager: manager)
                            manager.selectPassanteStation(newStation)
                            Haptics.play(.medium)
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground).opacity(0.5))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}

struct SuburbanLineBadge: View {
    let id: String
    
    var color: Color {
        if let line = SuburbanData.shared.allLines.first(where: { $0.id == id }) {
            return line.color
        }
        return .orange
    }
    
    var textColor: Color {
        let line = id.uppercased()
        let isLight = ["S4", "S5", "S6", "S8"].contains(line)
        return isLight ? .black : .white
    }
    
    var body: some View {
        Text(id)
            .font(.system(size: 10, weight: .black, design: .rounded))
            .foregroundColor(textColor)
            .frame(width: 28, height: 18)
            .background(color)
            .cornerRadius(4)
    }
}

fileprivate let passanteOuterStationLookup: [String: (rfiID: String?, vtID: String?)] = [
    "Novara": ("1917", "S00248"),
    "Trecate": ("2909", "S00252"),
    "Magenta": ("1618", "S01040"),
    "Corbetta-S.Stefano Ticino": ("1174", "S01041"),
    "Vittuone-Arluno": ("3119", "S01042"),
    "Pregnana Milanese": ("381", "S01058"),
    "Rho": ("2345", "S01037"),
    "Segrate": ("3507", "S01715"),
    "Pioltello-Limito": ("2147", "S01703"),
    
    "Varese": ("2994", "S01205"),
    "Gazzada-Schianno-Morazzone": ("1413", "S01207"),
    "Castronno": ("1029", "S01208"),
    "Albizzate-Solbiate Arno": ("405", "S01209"),
    "Cavaria-Oggiona-Jerago": ("1046", "S01210"),
    "Gallarate": ("1393", "S01030"),
    "Busto Arsizio": ("766", "S01031"),
    "Legnano": ("1554", "S01033"),
    "Canegrate": ("858", "S01034"),
    "Parabiago": ("2033", "S01035"),
    "Vanzago-Pogliano": ("2987", "S01036"),
    "Melzo": ("1690", "S01705"),
    "Pozzuolo Martesana": ("380", "S01722"),
    "Trecella": ("2910", "S01706"),
    "Cassano d'Adda": ("951", "S01707"),
    "Treviglio": ("2919", "S01708"),
    
    "Saronno": (nil, "S01933"),
    "Caronno Pertusella": (nil, "S01076"),
    "Cesate": (nil, "S01075"),
    "Garbagnate Milanese": (nil, "S01074"),
    "Garbagnate Parco delle Groane": (nil, "S01073"),
    "Garbagnate Parco Groane": (nil, "S01073"),
    "Bollate Nord": (nil, "S01072"),
    "Bollate Centro": (nil, "S01071"),
    "Novate Milanese": (nil, "S01070"),
    "Milano Quarto Oggiaro": (nil, "S01069"),
    "San Donato Milanese": ("2487", "S01624"),
    "Borgolombardo": ("710", "S01830"),
    "San Giuliano Milanese": ("2520", "S01821"),
    "Tavazzano": ("2820", "S01824"),
    "Lodi": ("1584", "S01825"),
    
    "Mariano Comense": (nil, "S01089"),
    "Cabiate": (nil, "S01088"),
    "Meda": (nil, "S01087"),
    "Seveso": (nil, "S01925"),
    "Cesano Maderno": (nil, "S01086"),
    "Bovisio Masciago-Mombello": (nil, "S01085"),
    "Varedo": (nil, "S01084"),
    "Palazzolo Milanese": (nil, "S01083"),
    "Paderno Dugnano": (nil, "S01082"),
    "Cormano-Cusano Milanino": (nil, "S01109"),
    "Milano Bruzzano": (nil, "S01079"),
    
    "Locate Triulzi": ("1583", "S01801"),
    "Pieve Emanuele": ("1749", "S01104"),
    "Villamaggiore": ("3092", "S01802"),
    "Certosa di Pavia": ("1069", "S01803"),
    "Pavia": ("2046", "S01860"),
    
    "Melegnano": ("1688", "S01822")
]

func stationForName(_ name: String, manager: TrainManager) -> Station {
    let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
    if let ids = passanteOuterStationLookup[cleanName] {
        return Station(name: cleanName, rfiID: ids.rfiID, vtID: ids.vtID, lat: nil, lon: nil)
    }
    if cleanName.contains("Garibaldi") {
        return Station(name: cleanName, rfiID: "1714", vtID: "S01647", lat: nil, lon: nil)
    }
    if cleanName.contains("Venezia") {
        return Station(name: cleanName, rfiID: "1723", vtID: "S01649", lat: nil, lon: nil)
    }
    if cleanName.contains("Repubblica") {
        return Station(name: cleanName, rfiID: "1719", vtID: "S01648", lat: nil, lon: nil)
    }
    if cleanName.contains("Lancetti") {
        return Station(name: cleanName, rfiID: "1713", vtID: "S01643", lat: nil, lon: nil)
    }
    if cleanName.contains("Dateo") {
        return Station(name: cleanName, rfiID: "3468", vtID: "S01650", lat: nil, lon: nil)
    }
    if cleanName.contains("Vittoria") {
        return Station(name: cleanName, rfiID: "1718", vtID: "S01633", lat: nil, lon: nil)
    }
    if cleanName.contains("Bovisa") {
        return Station(name: cleanName, rfiID: nil, vtID: "S01201", lat: nil, lon: nil)
    }
    if cleanName.contains("Rogoredo") {
        return Station(name: cleanName, rfiID: "1720", vtID: "S01820", lat: nil, lon: nil)
    }

    if let rfi = manager.allRFIStations.first(where: { $0.name.lowercased() == cleanName.lowercased() }) {
        return Station(name: rfi.name, rfiID: rfi.rfiID, vtID: rfi.vtID, lat: nil, lon: nil)
    }
    if let rfi = manager.allRFIStations.first(where: { $0.name.lowercased().contains(cleanName.lowercased()) }) {
        return Station(name: rfi.name, rfiID: rfi.rfiID, vtID: rfi.vtID, lat: nil, lon: nil)
    }
    return Station(name: cleanName, rfiID: nil, vtID: nil, lat: nil, lon: nil)
}

struct PassanteDepartureBoardView: View {
    @EnvironmentObject var manager: TrainManager
    @EnvironmentObject var locationManager: LocationManager
    @AppStorage("showOuterSuburbanStations") var showOuterSuburbanStations = false
    
    var relevantStations: [Station] {
        let allStations = manager.passanteStationsForUser
        
        let activeLines = manager.selectedSuburbanLines.filter { ["S1", "S2", "S5", "S6", "S12", "S13"].contains($0) }
        let onlyCertosa = !activeLines.isEmpty && activeLines.allSatisfy { ["S5", "S6"].contains($0) }
        let onlyBovisa = !activeLines.isEmpty && activeLines.allSatisfy { ["S1", "S2", "S12", "S13"].contains($0) }
        
        let stationsGeographicOrder = [
            "Varese", "Gazzada-Schianno-Morazzone", "Gazzada-Schianno", "Castronno", 
            "Albizzate-Solbiate Arno", "Albizzate-Solbiate A.", "Cavaria-Oggiona-Jerago", 
            "Cavaria-Oggiona-J.", "Gallarate", "Busto Arsizio", "Legnano", "Canegrate", 
            "Parabiago", "Vanzago-Pogliano",
            "Novara", "Trecate", "Magenta", "Corbetta-S.Stefano Ticino", "Vittuone-Arluno", "Pregnana Milanese", "Rho",
            "Saronno", "Caronno Pertusella", "Cesate", "Garbagnate Milanese", 
            "Garbagnate Parco delle Groane", "Garbagnate Parco Groane", "Bollate Nord", 
            "Bollate Centro", "Novate Milanese", "Milano Quarto Oggiaro",
            "Mariano Comense", "Cabiate", "Meda", "Seveso", "Cesano Maderno", 
            "Bovisio Masciago-Mombello", "Varedo", "Palazzolo Milanese", "Paderno Dugnano", 
            "Cormano-Cusano Milanino", "Cusano Milanino", "Milano Bruzzano",
            "Rho Fiera", "Certosa", "Villapizzone", "Milano Bovisa", "Lancetti", 
            "P. Garibaldi Passante", "Repubblica", "Porta Venezia", "Dateo", "Porta Vittoria",
            "Forlanini", "Segrate", "Pioltello-Limito", "Melzo", "Pozzuolo Martesana", 
            "Trecella", "Cassano d'Adda", "Treviglio",
            "Milano Rogoredo", "San Donato Milanese", "Borgolombardo", "San Giuliano Milanese", 
            "Melegnano", "Tavazzano", "Lodi",
            "Locate Triulzi", "Pieve Emanuele", "Villamaggiore", "Certosa di Pavia", "Pavia"
        ]
        
        let s1Sts: Set<String> = ["Saronno", "Caronno Pertusella", "Cesate", "Garbagnate Milanese", "Garbagnate Parco delle Groane", "Garbagnate Parco Groane", "Bollate Nord", "Bollate Centro", "Novate Milanese", "Milano Quarto Oggiaro", "Milano Bovisa", "Lancetti", "P. Garibaldi Passante", "Repubblica", "Porta Venezia", "Dateo", "Porta Vittoria", "Milano Rogoredo", "San Donato Milanese", "Borgolombardo", "San Giuliano Milanese", "Melegnano", "Tavazzano", "Lodi"]
        let s2Sts: Set<String> = ["Mariano Comense", "Cabiate", "Meda", "Seveso", "Cesano Maderno", "Bovisio Masciago-Mombello", "Varedo", "Palazzolo Milanese", "Paderno Dugnano", "Cormano-Cusano Milanino", "Milano Bruzzano", "Milano Bovisa", "Lancetti", "P. Garibaldi Passante", "Repubblica", "Porta Venezia", "Dateo", "Porta Vittoria", "Milano Rogoredo"]
        let s5Sts: Set<String> = ["Varese", "Gazzada-Schianno-Morazzone", "Gazzada-Schianno", "Castronno", "Albizzate-Solbiate Arno", "Albizzate-Solbiate A.", "Cavaria-Oggiona-Jerago", "Cavaria-Oggiona-J.", "Gallarate", "Busto Arsizio", "Legnano", "Canegrate", "Parabiago", "Vanzago-Pogliano", "Rho", "Rho Fiera", "Certosa", "Villapizzone", "Lancetti", "P. Garibaldi Passante", "Repubblica", "Porta Venezia", "Dateo", "Porta Vittoria", "Forlanini", "Segrate", "Pioltello-Limito", "Melzo", "Pozzuolo Martesana", "Trecella", "Cassano d'Adda", "Treviglio"]
        let s6Sts: Set<String> = ["Novara", "Trecate", "Magenta", "Corbetta-S.Stefano Ticino", "Vittuone-Arluno", "Pregnana Milanese", "Rho", "Rho Fiera", "Certosa", "Villapizzone", "Lancetti", "P. Garibaldi Passante", "Repubblica", "Porta Venezia", "Dateo", "Porta Vittoria", "Forlanini", "Segrate", "Pioltello-Limito"]
        let s12Sts: Set<String> = ["Cormano-Cusano Milanino", "Milano Bruzzano", "Milano Bovisa", "Lancetti", "P. Garibaldi Passante", "Repubblica", "Porta Venezia", "Dateo", "Porta Vittoria", "Milano Rogoredo", "San Donato Milanese", "Borgolombardo", "San Giuliano Milanese", "Melegnano"]
        let s13Sts: Set<String> = ["Milano Bovisa", "Lancetti", "P. Garibaldi Passante", "Repubblica", "Porta Venezia", "Dateo", "Porta Vittoria", "Milano Rogoredo", "Locate Triulzi", "Pieve Emanuele", "Villamaggiore", "Certosa di Pavia", "Pavia"]
        
        let filteredNames: [String]
        if showOuterSuburbanStations {
            if onlyCertosa {
                var certosaStations = Set<String>()
                if activeLines.contains("S5") { certosaStations.formUnion(s5Sts) }
                if activeLines.contains("S6") { certosaStations.formUnion(s6Sts) }
                
                let filtered = certosaStations.filter { stationName in
                    for lineId in activeLines {
                        let lineStations = lineId == "S5" ? s5Sts : s6Sts
                        if lineStations.contains(stationName) {
                            let hidden = manager.hiddenSuburbanStations[lineId] ?? []
                            if !hidden.contains(stationName) {
                                return true
                            }
                        }
                    }
                    return false
                }
                filteredNames = stationsGeographicOrder.filter { filtered.contains($0) }
            } else if onlyBovisa {
                var bovisaStations = Set<String>()
                if activeLines.contains("S1") { bovisaStations.formUnion(s1Sts) }
                if activeLines.contains("S2") { bovisaStations.formUnion(s2Sts) }
                if activeLines.contains("S12") { bovisaStations.formUnion(s12Sts) }
                if activeLines.contains("S13") { bovisaStations.formUnion(s13Sts) }
                
                let filtered = bovisaStations.filter { stationName in
                    for lineId in activeLines {
                        let lineStations: Set<String>
                        switch lineId {
                        case "S1": lineStations = s1Sts
                        case "S2": lineStations = s2Sts
                        case "S12": lineStations = s12Sts
                        default: lineStations = s13Sts
                        }
                        if lineStations.contains(stationName) {
                            let hidden = manager.hiddenSuburbanStations[lineId] ?? []
                            if !hidden.contains(stationName) {
                                return true
                            }
                        }
                    }
                    return false
                }
                filteredNames = stationsGeographicOrder.filter { filtered.contains($0) }
            } else {
                filteredNames = ["Lancetti", "P. Garibaldi Passante", "Repubblica", "Porta Venezia", "Dateo", "Porta Vittoria"]
            }
        } else {
            if onlyCertosa {
                filteredNames = ["Rho Fiera", "Certosa", "Villapizzone", "Lancetti", "P. Garibaldi Passante", "Repubblica", "Porta Venezia", "Dateo", "Porta Vittoria", "Forlanini"]
            } else if onlyBovisa {
                filteredNames = ["Milano Bovisa", "Lancetti", "P. Garibaldi Passante", "Repubblica", "Porta Venezia", "Dateo", "Porta Vittoria", "Milano Rogoredo"]
            } else {
                filteredNames = ["Lancetti", "P. Garibaldi Passante", "Repubblica", "Porta Venezia", "Dateo", "Porta Vittoria"]
            }
        }
        
        let filteredStations = filteredNames.map { name -> Station in
            if let existing = allStations.first(where: { $0.name == name }) {
                return existing
            }
            return stationForName(name, manager: manager)
        }
        
        return filteredStations
    }
    
    var body: some View {
        VStack(spacing: 12) {
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Tabellone — seleziona stazione")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                
                ScrollView(.horizontal, showsIndicators: false) {
                    ScrollViewReader { proxy in
                        HStack(spacing: 8) {
                            ForEach(relevantStations) { station in
                                let isSelected = manager.selectedPassanteStation.name == station.name
                                Button {
                                    Haptics.play(.medium)
                                    manager.selectPassanteStation(station)
                                } label: {
                                    HStack(spacing: 4) {
                                        if isSelected {
                                            Image(systemName: "mappin.circle.fill")
                                                .font(.caption)
                                        }
                                        Text(station.name)
                                            .fontWeight(isSelected ? .bold : .medium)
                                    }
                                    .font(.subheadline)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(isSelected ? Color.orange : Color(.secondarySystemBackground))
                                    .foregroundColor(isSelected ? .white : .primary)
                                    .cornerRadius(16)
                                 }
                                .buttonStyle(PlainButtonStyle())
                                .id(station.name)
                            }
                        }
                        .padding(.vertical, 2)
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                proxy.scrollTo(manager.selectedPassanteStation.name)
                            }
                        }
                        .onChange(of: manager.selectedPassanteStation.name) { _, newName in
                            withAnimation { proxy.scrollTo(newName) }
                        }
                    }
                }
            }
            
            Divider()
            
            let allTrains = manager.passanteTrains
            if manager.isLoadingPassanteBoard && allTrains.isEmpty {
                HStack {
                    Spacer()
                    ProgressView("Caricamento treni...")
                    Spacer()
                }
                .padding(.vertical, 20)
            } else if allTrains.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 6) {
                        Image(systemName: "tram.fill")
                            .font(.title2)
                            .foregroundColor(.secondary)
                        Text("Nessun treno in partenza")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .italic()
                    }
                    Spacer()
                }
                .padding(.vertical, 20)
            } else {
                let activeLines = manager.selectedSuburbanLines
                let onlyCertosa = !activeLines.isEmpty && activeLines.allSatisfy { ["S5", "S6"].contains($0) }
                let onlyBovisa = !activeLines.isEmpty && activeLines.allSatisfy { ["S1", "S2", "S12", "S13"].contains($0) }
                
                if onlyCertosa {
                    VStack(spacing: 12) {
                        PassanteBranchView(
                            label: "← Direzione Ovest (Rho / Varese)",
                            color: .orange,
                            trains: manager.passanteTrainsViaRho.filter { t in
                                let cat = t.category.uppercased()
                                return activeLines.contains(cat) || cat == "S" || cat == "REG" || cat == "RV"
                            },
                            isLarge: true
                        )
                        PassanteBranchView(
                            label: "Direzione Est (Forlanini / Treviglio) →",
                            color: .orange,
                            trains: manager.passanteTrainsViaForlanini.filter { t in
                                let cat = t.category.uppercased()
                                return activeLines.contains(cat) || cat == "S" || cat == "REG" || cat == "RV"
                            },
                            isLarge: true
                        )
                    }
                } else if onlyBovisa {
                    VStack(spacing: 12) {
                        PassanteBranchView(
                            label: "← Direzione Ovest (Bovisa / Saronno)",
                            color: .red,
                            trains: manager.passanteTrainsViaBovisa.filter { t in
                                let cat = t.category.uppercased()
                                return activeLines.contains(cat) || cat == "S" || cat == "REG" || cat == "RV"
                            },
                            isLarge: true
                        )
                        PassanteBranchView(
                            label: "Direzione Est (Rogoredo / Pavia / Lodi) →",
                            color: .red,
                            trains: manager.passanteTrainsViaRogoredo.filter { t in
                                let cat = t.category.uppercased()
                                return activeLines.contains(cat) || cat == "S" || cat == "REG" || cat == "RV"
                            },
                            isLarge: true
                        )
                    }
                } else {
                    VStack(spacing: 10) {
                        HStack(alignment: .top, spacing: 10) {
                            PassanteBranchView(
                                label: "← Bovisa",
                                color: .red,
                                trains: manager.passanteTrainsViaBovisa.filter { t in
                                    let cat = t.category.uppercased()
                                    return manager.selectedSuburbanLines.isEmpty || manager.selectedSuburbanLines.contains(cat) || cat == "S" || cat == "REG" || cat == "RV"
                                }
                            )
                            PassanteBranchView(
                                label: "Forlanini →",
                                color: .orange,
                                trains: manager.passanteTrainsViaForlanini.filter { t in
                                    let cat = t.category.uppercased()
                                    return manager.selectedSuburbanLines.isEmpty || manager.selectedSuburbanLines.contains(cat) || cat == "S" || cat == "REG" || cat == "RV"
                                }
                            )
                        }
                        HStack(alignment: .top, spacing: 10) {
                            PassanteBranchView(
                                label: "← Rho",
                                color: .orange,
                                trains: manager.passanteTrainsViaRho.filter { t in
                                    let cat = t.category.uppercased()
                                    return manager.selectedSuburbanLines.isEmpty || manager.selectedSuburbanLines.contains(cat) || cat == "S" || cat == "REG" || cat == "RV"
                                }
                            )
                            PassanteBranchView(
                                label: "Rogoredo →",
                                color: .red,
                                trains: manager.passanteTrainsViaRogoredo.filter { t in
                                    let cat = t.category.uppercased()
                                    return manager.selectedSuburbanLines.isEmpty || manager.selectedSuburbanLines.contains(cat) || cat == "S" || cat == "REG" || cat == "RV"
                                }
                            )
                        }
                        
                        let filteredBovisa = manager.passanteTrainsViaBovisa.filter { t in manager.selectedSuburbanLines.isEmpty || manager.selectedSuburbanLines.contains(t.category.uppercased()) }
                        let filteredRho = manager.passanteTrainsViaRho.filter { t in manager.selectedSuburbanLines.isEmpty || manager.selectedSuburbanLines.contains(t.category.uppercased()) }
                        let filteredForlanini = manager.passanteTrainsViaForlanini.filter { t in manager.selectedSuburbanLines.isEmpty || manager.selectedSuburbanLines.contains(t.category.uppercased()) }
                        let filteredRogoredo = manager.passanteTrainsViaRogoredo.filter { t in manager.selectedSuburbanLines.isEmpty || manager.selectedSuburbanLines.contains(t.category.uppercased()) }
                        
                        let classified = filteredBovisa + filteredRho + filteredForlanini + filteredRogoredo
                        let unclassified = allTrains.filter { t in
                            let isPreferred = manager.selectedSuburbanLines.isEmpty || manager.selectedSuburbanLines.contains(t.category.uppercased())
                            return isPreferred && !classified.contains(where: { $0.id == t.id })
                        }
                        if !unclassified.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Altre partenze")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.secondary)
                                    .textCase(.uppercase)
                                ForEach(Array(unclassified.prefix(3).enumerated()), id: \.element.id) { _, train in
                                    PassanteTrainRowView(train: train)
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground).opacity(0.5))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}



struct PassanteBranchView: View {
    let label: String
    let color: Color
    let trains: [Train]
    var isLarge: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: isLarge ? 10 : 6) {
            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(color)
                    .frame(width: 3, height: isLarge ? 16 : 12)
                Text(label)
                    .font(.system(size: isLarge ? 12 : 9, weight: .bold))
                    .foregroundColor(color)
                    .textCase(.uppercase)
            }
            
            if trains.isEmpty {
                Text("—")
                    .font(.system(size: isLarge ? 12 : 9))
                    .foregroundColor(.secondary)
                    .italic()
                    .padding(.top, 2)
            } else {
                ForEach(Array(trains.prefix(3).enumerated()), id: \.element.id) { idx, train in
                    PassanteBranchTrainRow(train: train, isLarge: isLarge)
                    if idx < min(trains.count, 3) - 1 {
                        Divider()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(isLarge ? 16 : 8)
        .background(color.opacity(isLarge ? 0.1 : 0.07))
        .cornerRadius(isLarge ? 14 : 10)
    }
}



struct SmartConnectorRouteView: View {
    let route: SuburbanRoute
    @EnvironmentObject var manager: TrainManager
    
    var body: some View {

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.arrow.down.circle.fill")
                        .foregroundColor(.orange)
                    Text("\(route.originName) ➔ \(route.destinationName)")
                        .font(.subheadline)
                        .bold()
                }
                
                Spacer()
                
                Button {
                    Haptics.play(.medium)
                    manager.removeSmartRoute(id: route.id)
                } label: {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                        .font(.subheadline)
                }
            }
            
            let details = manager.loadedSmartRouteDetails[route.id]
            if manager.isLoadingSmartRoutes && details == nil {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .padding(.vertical, 15)
            } else if let details = details {
                if details.isDirect {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("COLLEGAMENTO DIRETTO")
                            .font(.system(size: 8, weight: .black))
                            .foregroundColor(.green)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.12))
                            .cornerRadius(4)
                        
                        if details.originTrains.isEmpty {
                            Text("Nessun treno diretto in tempo reale.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .italic()
                        } else {
                            ForEach(details.originTrains.prefix(2)) { train in
                                HStack {
                                    SuburbanLineBadge(id: train.category)
                                    Text(SharedFormatters.formatDestination(train.destination))
                                        .font(.system(size: 11, weight: .bold))
                                    Spacer()
                                    Text(train.time)
                                        .font(.system(size: 11, weight: .bold, design: .rounded))
                                    let isDelay = !train.delay.contains("In orario")
                                    Text(train.delay)
                                        .font(.system(size: 9, weight: .bold, design: .rounded))
                                        .foregroundColor(isDelay ? .red : .green)
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Text("CONNESSO CON CAMBIO")
                                .font(.system(size: 8, weight: .black))
                                .foregroundColor(.orange)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.12))
                                .cornerRadius(4)
                            
                            if let exchange = details.exchangeStation {
                                Text("Cambio a \(SharedFormatters.formatDestination(exchange.name).replacingOccurrences(of: " Passante", with: ""))")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.bottom, 2)
                        
                        if let firstTrain = details.originTrains.first {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(Color.orange)
                                    .frame(width: 6, height: 6)
                                    .background(Circle().stroke(Color.orange.opacity(0.2), lineWidth: 3))
                                
                                SuburbanLineBadge(id: firstTrain.category)
                                
                                Text(SharedFormatters.formatDestination(details.originStation.name))
                                    .font(.system(size: 11, weight: .bold))
                                
                                Spacer()
                                
                                Text(firstTrain.time)
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                
                                let isDelay = !firstTrain.delay.contains("In orario")
                                Text(firstTrain.delay)
                                    .font(.system(size: 9, weight: .bold, design: .rounded))
                                    .foregroundColor(isDelay ? .red : .green)
                            }
                        } else {
                            Text("Nessun treno da \(route.originName) in tempo reale.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .italic()
                        }
                        
                        HStack(spacing: 12) {
                            Rectangle()
                                .fill(Color.orange.opacity(0.4))
                                .frame(width: 2, height: 18)
                                .padding(.leading, 2)
                            
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.system(size: 9))
                                    .foregroundColor(.orange)
                                Text("Cambio comodo sullo stesso marciapiede (~4 min)")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.leading, 8)
                            
                            Spacer()
                        }
                        
                        if let secondTrain = details.exchangeTrains.first {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 6, height: 6)
                                    .background(Circle().stroke(Color.green.opacity(0.2), lineWidth: 3))
                                
                                SuburbanLineBadge(id: secondTrain.category)
                                
                                Text(SharedFormatters.formatDestination(details.destinationStation.name))
                                    .font(.system(size: 11, weight: .bold))
                                
                                Spacer()
                                
                                Text(secondTrain.time)
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                
                                let isDelay = !secondTrain.delay.contains("In orario")
                                Text(secondTrain.delay)
                                    .font(.system(size: 9, weight: .bold, design: .rounded))
                                    .foregroundColor(isDelay ? .red : .green)
                            }
                        } else {
                            Text("Nessun treno in coincidenza trovato.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .italic()
                        }
                    }
                }
            } else {
                Text("Trascina la home verso il basso per caricare l'itinerario live.")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                    .italic()
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground).opacity(0.5))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}

struct PassanteQuickSetupView: View {
    @EnvironmentObject var manager: TrainManager
    @Environment(\.dismiss) var dismiss
    
    @State private var originName = ""
    @State private var originID = ""
    @State private var destName = ""
    @State private var destID = ""
    
    @State private var showOriginSearch = false
    @State private var showDestSearch = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Tratta")) {
                    Button(action: { showOriginSearch = true }) {
                        HStack {
                            Image(systemName: "circle.fill")
                                .foregroundColor(.orange)
                                .font(.caption2)
                            Text(originName.isEmpty ? "Seleziona Stazione di Partenza" : originName)
                                .fontWeight(originName.isEmpty ? .regular : .semibold)
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Button(action: { showDestSearch = true }) {
                        HStack {
                            Image(systemName: "mappin.circle.fill")
                                .foregroundColor(.red)
                                .font(.subheadline)
                            Text(destName.isEmpty ? "Seleziona Stazione di Arrivo" : destName)
                                .fontWeight(destName.isEmpty ? .regular : .semibold)
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Section {
                    Button(action: {
                        if !originID.isEmpty && !destID.isEmpty && originID != destID {
                            Haptics.play(.medium)
                            manager.toggleFavoriteRoute(originName: originName, originID: originID, destName: destName, destID: destID)
                            dismiss()
                        }
                    }) {
                        Text("Salva Tratta nei Preferiti")
                            .bold()
                            .frame(maxWidth: .infinity)
                            .foregroundColor(.white)
                    }
                    .listRowBackground(originID.isEmpty || destID.isEmpty || originID == destID ? Color.gray : Color.orange)
                    .disabled(originID.isEmpty || destID.isEmpty || originID == destID)
                }
            }
            .navigationTitle("Aggiungi Tratta Preferita")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
                }
            }
            .sheet(isPresented: $showOriginSearch) {
                StationSelectionSheet(selectedName: $originName, selectedID: $originID, title: "Partenza")
            }
            .sheet(isPresented: $showDestSearch) {
                StationSelectionSheet(selectedName: $destName, selectedID: $destID, title: "Arrivo")
            }
        }
    }
}

struct PassanteTunnelStatusButton: View {
    @EnvironmentObject var manager: TrainManager
    @EnvironmentObject var locationManager: LocationManager
    @Binding var showThermometerSheet: Bool
    
    var body: some View {
        Button {
            Haptics.play(.light)
            if let nearby = locationManager.nearbyStation,
               manager.passanteStationsForUser.contains(where: { $0.name == nearby.name }),
               let st = manager.passanteStationsForUser.first(where: { $0.name == nearby.name }) {
                manager.selectedPassanteStation = st
            }
            showThermometerSheet = true
            Task { await manager.fetchPassanteLive() }
        } label: {
            Image(systemName: "info.circle.fill")
                .foregroundColor(Color(hex: manager.passanteTunnelHealthColor).opacity(0.8))
                .font(.body)
                .padding(.vertical, 8)
                .padding(.leading, 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct PassanteTunnelStatusHeaderView: View {
    @EnvironmentObject var manager: TrainManager
    @State private var showThermometerSheet = false
    
    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color(hex: manager.passanteTunnelHealthColor))
                .frame(width: 8, height: 8)
            
            Text("\(manager.passanteTunnelHealthMessage)")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(Color(hex: manager.passanteTunnelHealthColor))
                .lineLimit(1)
            
            Spacer()
            
            PassanteTunnelStatusButton(showThermometerSheet: $showThermometerSheet)
        }
        .padding(.leading, 12)
        .padding(.trailing, 12)
        .padding(.vertical, 0)
        .background(Color(hex: manager.passanteTunnelHealthColor).opacity(0.12))
        .cornerRadius(8)
        .contentShape(Rectangle())
        .sheet(isPresented: $showThermometerSheet) {
            PassanteTunnelDetailView()
                .environmentObject(manager)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }
}

struct PassanteTunnelDetailView: View {
    @EnvironmentObject var manager: TrainManager
    @Environment(\.dismiss) var dismiss
    @AppStorage("showOuterSuburbanStations") var showOuterSuburbanStations = false
    
    @State private var currentTab = 0
    
    let timer = Timer.publish(every: 15, on: .main, in: .common).autoconnect()
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Picker("Sezione", selection: $currentTab) {
                    Text("Mappa Linea").tag(0)
                    Text("Treni in Arrivo").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 14)
                
                let activeLines = manager.selectedSuburbanLines.filter { ["S1", "S2", "S5", "S6", "S12", "S13"].contains($0) }
                let isMixed = !activeLines.isEmpty && 
                              !(activeLines.allSatisfy { ["S5", "S6"].contains($0) } || 
                                activeLines.allSatisfy { ["S1", "S2", "S12", "S13"].contains($0) })
                
                if !isMixed {
                    Toggle(isOn: $showOuterSuburbanStations) {
                        HStack(spacing: 8) {
                            Image(systemName: "map.fill")
                                .foregroundColor(.orange)
                            Text("Mostra stazioni esterne")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                        }
                    }
                    .toggleStyle(SwitchToggleStyle(tint: .orange))
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(Color(.secondarySystemBackground).opacity(0.4))
                    .cornerRadius(12)
                    .padding(.horizontal)
                }
                
                if currentTab == 0 {
                    ScrollView {
                        VStack(spacing: 16) {
                            PassanteTunnelThermometerView(
                                statusMessage: manager.passanteTunnelHealthMessage,
                                statusColorHex: manager.passanteTunnelHealthColor,
                                avgDelay: manager.passanteTunnelAverageDelay
                            )
                        }
                        .padding(.horizontal)
                        .padding(.top, 8)
                        .padding(.bottom, 24)
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            if manager.useSpecialPassanteView {
                                PassanteDepartureBoardView()
                            } else {
                                StationBoardView(station: manager.selectedPassanteStation)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.top, 8)
                        .padding(.bottom, 24)
                    }
                }
            }
            .navigationTitle("Dettagli Tunnel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Chiudi") { dismiss() }
                }
            }
            .onReceive(timer) { _ in
                Task {
                    await manager.fetchPassanteLive()
                }
            }
        }
    }
}

