import SwiftUI
import Combine
import Foundation
import CoreLocation
import ActivityKit

struct TrainStopsView: View {
    let train: Train
    var showCloseButton: Bool = true
    @EnvironmentObject var manager: TrainManager
    @EnvironmentObject var passanteManager: PassanteManager
    @EnvironmentObject var locationManager: LocationManager
    @EnvironmentObject var cache: MetroCache
    @EnvironmentObject var usageTracker: UsageTracker
    @Environment(\.dismiss) var dismiss
    @State private var reportedTypes: Set<String> = []
    @State private var showLongPressHint = false
    @State private var metroPreviewStop: Stop? = nil

    var body: some View {
        VStack(spacing: 0) {
            if manager.isStopsLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = manager.stopErrorMessage {
                VStack {
                    Image(systemName: "clock.badge.exclamationmark")
                        .font(.largeTitle)
                        .padding()
                    Text(error)
                        .multilineTextAlignment(.center)
                        .padding()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // Header con Partenza e Arrivo (su due righe, senza trattino)
                        HStack(alignment: .center) {
                            VStack(alignment: .leading, spacing: 4) {
                                let origin = manager.selectedTrainStops.first?.stationName ?? ""
                                let destination = manager.selectedTrainStops.last?.stationName ?? train.destination
                                
                                if origin.isEmpty {
                                    Text(formatHeaderStationName(destination))
                                        .font(.title2)
                                        .bold()
                                        .foregroundColor(.primary)
                                } else {
                                    Text(formatHeaderStationName(origin))
                                        .font(.title2)
                                        .bold()
                                        .foregroundColor(.secondary)
                                    Text(formatHeaderStationName(destination))
                                        .font(.title2)
                                        .bold()
                                        .foregroundColor(.primary)
                                }
                            }
                            
                            Spacer()
                            
                            VStack(alignment: .trailing, spacing: 4) {
                                Button {
                                    Haptics.notify(.warning)
                                    withAnimation {
                                        showLongPressHint = true
                                    }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                                        withAnimation {
                                            showLongPressHint = false
                                        }
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "exclamationmark.bubble.fill")
                                        Text("Segnala")
                                    }
                                    .font(.subheadline)
                                    .bold()
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.orange)
                                    .cornerRadius(8)
                                }
                                .contextMenu {
                                    Button {
                                        report("crowded")
                                    } label: {
                                        Label("Treno Affollato", systemImage: "person.2.fill")
                                    }
                                    .disabled(reportedTypes.contains("crowded"))
                                    
                                    Button {
                                        report("hot")
                                    } label: {
                                        Label("Fa troppo Caldo", systemImage: "thermometer.sun.fill")
                                    }
                                    .disabled(reportedTypes.contains("hot"))
                                    
                                    Button {
                                        report("cold")
                                    } label: {
                                        Label("Fa troppo Freddo", systemImage: "snowflake")
                                    }
                                    .disabled(reportedTypes.contains("cold"))
                                    
                                    Button {
                                         report("stopped")
                                     } label: {
                                         Label("Treno Fermo", systemImage: "exclamationmark.octagon.fill")
                                     }
                                     .disabled(reportedTypes.contains("stopped"))
                                }
                                
                                if showLongPressHint {
                                    Text("Tieni premuto per segnalare")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(.orange)
                                        .transition(.opacity)
                                }
                            }
                        }
                        .padding([.horizontal, .top])
                        
                        let crowdedCount = manager.currentTrainReports["crowded"] ?? 0
                        let hotCount = manager.currentTrainReports["hot"] ?? 0
                        let coldCount = manager.currentTrainReports["cold"] ?? 0
                        let stoppedCount = manager.currentTrainReports["stopped"] ?? 0
                        
                        if crowdedCount > 0 || hotCount > 0 || coldCount > 0 || stoppedCount > 0 {
                            HStack(spacing: 8) {
                                Text("Segnalazioni attive:")
                                    .font(.caption)
                                    .bold()
                                    .foregroundColor(.secondary)
                                
                                if crowdedCount > 0 {
                                    ActiveReportBadge(icon: "person.2.fill", count: crowdedCount, color: .purple)
                                }
                                if hotCount > 0 {
                                    ActiveReportBadge(icon: "thermometer.sun.fill", count: hotCount, color: .orange)
                                }
                                if coldCount > 0 {
                                    ActiveReportBadge(icon: "snowflake", count: coldCount, color: .blue)
                                }
                                if stoppedCount > 0 {
                                    ActiveReportBadge(icon: "exclamationmark.octagon.fill", count: stoppedCount, color: .red)
                                }
                            }
                            .padding(.horizontal)
                            .padding(.top, 4)
                        }
                        
                        // Cartella dello Stato (ritardo, ultima fermata, ecc.) - Sfondo Bianco
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Circle().fill(manager.currentTrainStatus.statusMessage.lowercased().contains("in orario") ? .green : (manager.currentTrainStatus.isDeparted ? .red : .gray)).frame(width: 12, height: 12)
                                Text(manager.currentTrainStatus.statusMessage).font(.headline).foregroundColor(.primary)
                                Spacer()
                            }
                            if let note = manager.currentTrainStatus.cancellationNote { Text(note).font(.caption).bold().padding(6).background(Color.red.opacity(0.2)).foregroundColor(.red).cornerRadius(4) }
                            if manager.currentTrainStatus.isDeparted {
                                HStack { Image(systemName: "location.fill").foregroundColor(.secondary); Text("Ultimo rilevamento: ").foregroundColor(.secondary); Text(manager.currentTrainStatus.lastStation).bold(); Text("alle \(manager.currentTrainStatus.lastTime)").foregroundColor(.secondary) }.font(.caption)
                            } else { Text("Il treno non ha ancora lasciato la stazione di partenza.").font(.caption).foregroundColor(.secondary) }
                        }
                        .padding()
                        .background(Color(.secondarySystemGroupedBackground))
                        .cornerRadius(12)
                        .padding()
                        
                        if !manager.currentTrainBlockedLocations.isEmpty {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.octagon.fill")
                                    .foregroundColor(.red)
                                Text("Treno segnalato fermo nei pressi di: \(manager.currentTrainBlockedLocations.joined(separator: ", "))")
                                    .font(.caption2)
                                    .foregroundColor(.red)
                                    .bold()
                            }
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(8)
                            .padding(.horizontal)
                            .padding(.bottom, 8)
                        }
                        
                        // Lista fermate richiusa in un rettangolo bianco dagli angoli smussati
                        VStack(spacing: 0) {
                            ForEach(manager.selectedTrainStops) { stop in
                                let lastStation = manager.currentTrainStatus.lastStation
                                let isMatchWithLastStation = !lastStation.isEmpty && (
                                    stop.stationName.lowercased().contains(lastStation.lowercased()) ||
                                    lastStation.lowercased().contains(stop.stationName.lowercased())
                                )
                                let isCurrent = isMatchWithLastStation && stop.actualTime != nil
                                
                                let currentIndex = manager.selectedTrainStops.firstIndex(where: { $0.id == stop.id }) ?? 0
                                let anyLaterStopHasActualTime = manager.selectedTrainStops.dropFirst(currentIndex + 1).contains { $0.actualTime != nil }
                                
                                let isPast = (stop.actualTime != nil || anyLaterStopHasActualTime) && !isCurrent

                                let station = stationFromStopName(stop.stationName, manager: manager, passanteManager: passanteManager)
                                let hasMetro = !station.metroLines.isEmpty
                                
                                let isHomeStation = !manager.homeDestinationStationName.isEmpty &&
                                     stop.stationName.lowercased().contains(manager.homeDestinationStationName.lowercased())
                                 
                                let rowBg = isCurrent ? Color.orange.opacity(0.15) : Color.clear

                                NavigationLink(destination: SmartBoardView(station: station)) {
                                    HStack {
                                         VStack(alignment: .leading, spacing: 4) {
                                             Text(stop.stationName.formattedStationName)
                                                 .font(.headline)
                                                 .foregroundColor(
                                                     isHomeStation 
                                                     ? (isPast ? Color.blue.opacity(0.5) : .blue) 
                                                     : (isPast ? .secondary : .primary)
                                                 )
                                         }
                                        
                                        Spacer()

                                        HStack(spacing: 8) {
                                            // Binario
                                            if let actualBin = stop.actualPlatform {
                                                HStack(spacing: 2) {
                                                    Image(systemName: "tram.fill")
                                                        .font(.caption2)
                                                        .foregroundColor(.green)
                                                    
                                                    if let plannedBin = stop.plannedPlatform, plannedBin != actualBin {
                                                        Text(plannedBin)
                                                            .font(.subheadline)
                                                            .foregroundColor(.red)
                                                            .strikethrough()
                                                    }
                                                    Text(actualBin)
                                                        .font(.subheadline)
                                                        .foregroundColor(.green)
                                                        .bold()
                                                }
                                            } else if let plannedBin = stop.plannedPlatform {
                                                HStack(spacing: 2) {
                                                    Image(systemName: "tram.fill")
                                                        .font(.caption2)
                                                        .foregroundColor(.secondary)
                                                    Text(plannedBin)
                                                        .font(.subheadline)
                                                        .foregroundColor(.secondary)
                                                }
                                            }
                                            
                                            // Orari
                                            HStack(spacing: 4) {
                                                let hasVariation = stop.delay >= 3 && (stop.actualTime != nil || stop.estimatedTime != nil)
                                                
                                                Text(to24h(stop.time))
                                                    .font(.subheadline)
                                                    .foregroundColor(isPast ? Color.secondary.opacity(0.5) : .secondary)
                                                    .strikethrough(hasVariation)
                                                
                                                if hasVariation {
                                                    if let act = stop.actualTime {
                                                        Text(to24h(act))
                                                            .font(.subheadline)
                                                            .foregroundColor(stop.delay <= 2 ? .green : (stop.delay <= 6 ? .orange : .red))
                                                            .bold()
                                                    } else if let est = stop.estimatedTime {
                                                        Text(to24h(est))
                                                            .font(.subheadline)
                                                            .foregroundColor(.red)
                                                            .bold()
                                                    }
                                                }
                                            }
                                            
                                            Image(systemName: "chevron.right")
                                                .font(.system(size: 14, weight: .semibold))
                                                .foregroundColor(.secondary.opacity(0.5))
                                        }
                                    }
                                    .padding(.vertical, 14)
                                    .padding(.horizontal, 16)
                                    .background(rowBg)
                                }
                                .buttonStyle(PlainButtonStyle())
                                .contextMenu {
                                    if hasMetro {
                                        Button {
                                            Haptics.play(.medium)
                                            metroPreviewStop = stop
                                        } label: {
                                            Label("Mostra partenze metro", systemImage: "tram.fill")
                                        }
                                    }
                                } preview: {
                                    if hasMetro {
                                        let previewHeight = 110.0 + Double(station.metroLines.count) * 90.0
                                        MetroQuickView(stop: stop, metroLines: station.metroLines, useTrainArrival: true)
                                            .environmentObject(cache)
                                            .frame(width: 320, height: previewHeight)
                                    }
                                }
                                
                                if stop.id != manager.selectedTrainStops.last?.id {
                                    Divider()
                                        .padding(.leading, 16)
                                }
                            }
                        }
                        .background(Color(.secondarySystemGroupedBackground))
                        .cornerRadius(12)
                        .padding(.horizontal)
                        .padding(.bottom, 24)
                    }
                }
                .background(Color(.systemGroupedBackground))
                .sheet(item: $metroPreviewStop) { stop in
                    let station = stationFromStopName(stop.stationName, manager: manager, passanteManager: passanteManager)
                    MetroQuickView(stop: stop, metroLines: station.metroLines, useTrainArrival: false)
                        .environmentObject(cache)
                        .presentationDetents([.fraction(0.5), .large])
                        .presentationDragIndicator(.visible)
                        .presentationCornerRadius(20)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showCloseButton {
                ToolbarItem(placement: .topBarLeading) { Button("Chiudi") { dismiss() } }
            }
            
            ToolbarItem(placement: .principal) {
                Text("\(train.category) \(train.number)")
                    .font(.headline)
            }
            
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 14) {
                    let isActive = manager.activeLiveActivities.contains(train.number)
                    Button {
                        if isActive {
                            startLiveActivity(train: train)
                        } else {
                            let limit = manager.getLimit()
                            if manager.activeLiveActivities.count >= limit {
                                Haptics.notify(.error)
                                if manager.hasSupport() {
                                    manager.notificationLimitError = "Puoi avere al massimo \(limit) Live Activity attive alla volta. Disattivane un'altra per procedere."
                                } else {
                                    manager.notificationLimitError = "La gestione delle notifiche in tempo reale comporta costi di server continui per ciascun treno monitorato. Se trovi utile l'app, considera di sostenere lo sviluppo indipendente con un piccolo contributo: sbloccherai il monitoraggio fino a 10 treni contemporaneamente e le notifiche personalizzate per gli scioperi della tua regione."
                                }
                            } else {
                                manager.disableTrainNotificationsForNonPremium()
                                startLiveActivity(train: train)
                            }
                        }
                    } label: {
                        Image(systemName: isActive ? "livephoto.slash" : "livephoto.play")
                            .foregroundColor(isActive ? .red : .green)
                    }
                            
                    Button {
                        manager.toggleFavorite(trainNumber: train.number, description: train.destination, departureTime: train.time)
                    } label: {
                        Image(systemName: manager.isFavorite(trainNumber: train.number) ? "star.fill" : "star").foregroundColor(.yellow)
                    }
                    
                    Button {
                        Haptics.play(.medium)
                        Task { await manager.fetchStops(for: train, isRefresh: true) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(manager.isStopsLoading)
                }
            }
        }
        .task { await manager.fetchStops(for: train) }
        .onAppear {
            manager.addToViewedRecentTrains(number: train.number, description: train.destination, departureTime: train.time)
            usageTracker.recordTrainCheck(number: train.number, category: train.category, destination: train.destination, location: locationManager.userLocation?.coordinate)
            loadLocalReports()
        }
    }




    private func report(_ type: String) {
        guard !reportedTypes.contains(type) else { return }
        
        if type == "stopped", let userLoc = locationManager.userLocation {
            CLGeocoder().reverseGeocodeLocation(userLoc) { placemarks, error in
                let locality = placemarks?.first?.locality
                submitReport(type, locality: locality)
            }
        } else {
            submitReport(type, locality: nil)
        }
    }
    
    private func submitReport(_ type: String, locality: String?) {
        reportedTypes.insert(type)
        saveLocalReport(type)
        
        if type == "moving" {
            reportedTypes.remove("stopped")
            removeLocalReport("stopped")
        } else if type == "stopped" {
            reportedTypes.remove("moving")
            removeLocalReport("moving")
        }
        
        manager.postComfortReport(
            for: train.number,
            type: type,
            locality: locality,
            lastStation: manager.currentTrainStatus.lastStation,
            lastTime: manager.currentTrainStatus.lastTime
        )
        Haptics.play(.medium)
    }
    
    private func loadLocalReports() {
        let key = "reported_train_\(train.number)_\(DateFormatter.todayString())"
        if let saved = UserDefaults.standard.array(forKey: key) as? [String] {
            reportedTypes = Set(saved)
        }
    }
    
    private func saveLocalReport(_ type: String) {
        let key = "reported_train_\(train.number)_\(DateFormatter.todayString())"
        var current = UserDefaults.standard.array(forKey: key) as? [String] ?? []
        if !current.contains(type) {
            current.append(type)
            UserDefaults.standard.set(current, forKey: key)
        }
    }
    
    private func removeLocalReport(_ type: String) {
        let key = "reported_train_\(train.number)_\(DateFormatter.todayString())"
        var current = UserDefaults.standard.array(forKey: key) as? [String] ?? []
        if let idx = current.firstIndex(of: type) {
            current.remove(at: idx)
            UserDefaults.standard.set(current, forKey: key)
        }
    }

    func startLiveActivity(train: Train) {
        
        let existingActivity = Activity<TrainLiveActivityAttributes>.activities.first { activity in
            activity.attributes.trainNumber == train.number
        }
        
        if let activityToStop = existingActivity {
            Task { 
                await activityToStop.end(nil, dismissalPolicy: .immediate) 
                DispatchQueue.main.async { manager.syncLiveActivities() }
            }
            print("Dynamic Island spenta per il treno \(train.number)")
            Haptics.notify(.warning)
            return
        }
        
        let originStation = manager.selectedTrainStops.first?.stationName ?? "Partenza"
        
        let attributes = TrainLiveActivityAttributes(
            trainNumber: train.number,
            destination: train.destination,
            category: train.category,
            origin: originStation
        )
        
        let stops = manager.selectedTrainStops
        let lastStation = manager.currentTrainStatus.lastStation
        let isArrived = manager.currentTrainStatus.isArrived
        
        var progressVal: Double = 0.0
        if isArrived {
            progressVal = 1.0
        } else if !stops.isEmpty {
            if stops.count == 1 {
                progressVal = 1.0
            } else {
                let lastClean = lastStation.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if let idx = stops.firstIndex(where: { 
                    $0.stationName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == lastClean 
                }) {
                    progressVal = Double(idx) / Double(stops.count - 1)
                }
            }
        }
        
        let contentState = TrainLiveActivityAttributes.ContentState(
            delay: train.delay,
            statusMessage: manager.currentTrainStatus.statusMessage,
            lastStation: lastStation,
            progress: progressVal
        )
        
        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: .init(state: contentState, staleDate: nil),
                pushType: .token
            )
            DispatchQueue.main.async { manager.syncLiveActivities() }
            Haptics.notify(.success)
            print("Dynamic Island attivata! ID: \(activity.id)")
        } catch {
            print("Errore Dynamic Island: \(error.localizedDescription)")
            Haptics.notify(.error)
        }
    }
}

/// Risolve il nome di una fermata (proveniente da dati Trenitalia/RFI) in una `Station` navigabile.
/// Priorità:
///   1. Match esatto su `allRFIStations.name`  → preferisce `rfiID` (Trenitalia)
///   2. Match parziale su `allRFIStations.name` → idem
///   3. Fallback su `passanteOuterStationLookup` (vtID ViaggiaTreno) per stazioni non coperte dal DB RFI
private func stationFromStopName(_ name: String, manager: TrainManager, passanteManager: PassanteManager) -> Station {
    let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)

    // 1. Corrispondenza esatta (case-insensitive)
    if let rfi = manager.allRFIStations.first(where: { $0.name.lowercased() == clean.lowercased() }) {
        return Station(name: rfi.name, rfiID: rfi.rfiID, vtID: rfi.vtID, lat: nil, lon: nil)
    }

    // 2. Corrispondenza parziale (il nome della fermata contiene o è contenuto nel DB)
    if let rfi = manager.allRFIStations.first(where: {
        $0.name.lowercased().contains(clean.lowercased()) ||
        clean.lowercased().contains($0.name.lowercased())
    }) {
        return Station(name: rfi.name, rfiID: rfi.rfiID, vtID: rfi.vtID, lat: nil, lon: nil)
    }

    // 3. Fallback: lookup del Passante (vtID ViaggiaTreno)
    return stationForName(clean, manager: manager, passanteManager: passanteManager)
}



extension DateFormatter {
    static func todayString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "Europe/Rome")
        return formatter.string(from: Date())
    }
}

struct ActiveReportBadge: View {
    let icon: String
    let count: Int
    let color: Color
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
            Text("\(count)")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
        }
        .foregroundColor(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.12))
        .cornerRadius(6)
    }
}

// MARK: - Metro Quick Preview

fileprivate func to24h(_ timeStr: String) -> String {
    let f12 = DateFormatter()
    f12.dateFormat = "h:mm a"
    f12.locale = Locale(identifier: "en_US_POSIX")
    let f24 = DateFormatter()
    f24.locale = Locale(identifier: "en_US_POSIX")
    f24.dateFormat = "HH:mm"
    if let d = f12.date(from: timeStr) { return f24.string(from: d) }
    return timeStr
}

fileprivate func formatHeaderStationName(_ name: String) -> String {
    var cleaned = name.formattedStationName
    

    // Sostituzione "Porta Nuova" -> "PN"
    cleaned = cleaned.replacingOccurrences(of: "Porta Nuova", with: "PN", options: .caseInsensitive)
    
    // Gestione specifica per Milano Porta Garibaldi, Milano Porta Venezia, Milano Porta Vittoria
    let replacementPairs = [
        ("Milano Porta Garibaldi Passante", "Milano P. Garibaldi"),
        ("Milano Porta Garibaldi", "Milano P. Garibaldi"),
        ("Porta Garibaldi Passante", "Milano P. Garibaldi"),
        ("Porta Garibaldi", "Milano P. Garibaldi"),
        
        ("Milano Porta Venezia", "Milano P. Venezia"),
        ("Porta Venezia", "Milano P. Venezia"),
        
        ("Milano Porta Vittoria", "Milano P. Vittoria"),
        ("Porta Vittoria", "Milano P. Vittoria")
    ]
    
    for (target, replacement) in replacementPairs {
        if cleaned.localizedCaseInsensitiveContains(target) {
            cleaned = cleaned.replacingOccurrences(of: target, with: replacement, options: .caseInsensitive)
        }
    }
    
    return cleaned
}

private func getMarginMinutes(timeString: String, trainArrival: Date?) -> Double? {
    guard let arrival = trainArrival else { return nil }
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "HH:mm"
    f.timeZone = TimeZone(identifier: "Europe/Rome")
    guard let parsed = f.date(from: timeString) else { return nil }
    var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
    let tc = Calendar.current.dateComponents([.hour, .minute], from: parsed)
    comps.hour = tc.hour; comps.minute = tc.minute
    guard let metroTime = Calendar.current.date(from: comps) else { return nil }
    var diff = metroTime.timeIntervalSince(arrival) / 60.0
    // Handle midnight crossing (if difference is more than 12 hours)
    if diff < -720.0 {
        diff += 1440.0
    } else if diff > 720.0 {
        diff -= 1440.0
    }
    return diff
}

enum FeasibilityStatus {
    case ok // Ce la fai
    case hurry // Sbrigati
    case run // Corri!
    case miss // Non ce la fai
    
    var style: (icon: String, text: String, color: Color, bg: Color) {
        switch self {
        case .ok:
            return ("checkmark.circle.fill", "Ce la fai", .green, Color.green.opacity(0.1))
        case .hurry:
            return ("figure.walk", "Sbrigati", .orange, Color.orange.opacity(0.08))
        case .run:
            return ("bolt.fill", "Corri!", .orange, Color.orange.opacity(0.12))
        case .miss:
            return ("xmark.circle.fill", "Non ce la fai", .red, Color.red.opacity(0.1))
        }
    }
}

func getFeasibility(stationName: String, margin: Double) -> FeasibilityStatus {
    let name = stationName.lowercased()
    
    // M1 (Rossa)
    if name.contains("sesto") {
        if margin >= 3.0 { return .ok }
        if margin >= 2.0 { return .hurry }
        if margin >= 1.0 { return .run }
        return .miss
    }
    if name.contains("cadorna") {
        if margin >= 5.0 { return .ok }
        if margin >= 3.0 { return .hurry }
        if margin >= 2.0 { return .run }
        return .miss
    }
    if name.contains("venezia") {
        if margin >= 5.0 { return .ok }
        if margin >= 3.0 { return .hurry }
        if margin >= 2.0 { return .run }
        return .miss
    }
    if name.contains("rho fiera") {
        if margin >= 6.0 { return .ok }
        if margin >= 4.0 { return .hurry }
        if margin >= 3.0 { return .run }
        return .miss
    }
    
    // M2 (Verde)
    if name.contains("centrale") {
        if margin >= 6.0 { return .ok }
        if margin >= 4.0 { return .hurry }
        if margin >= 3.0 { return .run }
        return .miss
    }
    if name.contains("garibaldi") {
        if margin >= 7.0 { return .ok }
        if margin >= 5.0 { return .hurry }
        if margin >= 3.0 { return .run }
        return .miss
    }
    if name.contains("lambrate") {
        if margin >= 5.0 { return .ok }
        if margin >= 4.0 { return .hurry }
        if margin >= 3.0 { return .run }
        return .miss
    }
    if name.contains("genova") {
        if margin >= 6.0 { return .ok }
        if margin >= 4.0 { return .hurry }
        if margin >= 3.0 { return .run }
        return .miss
    }
    if name.contains("romolo") {
        if margin >= 4.0 { return .ok }
        if margin >= 3.0 { return .hurry }
        if margin >= 2.0 { return .run }
        return .miss
    }
    
    // M3 (Gialla)
    if name.contains("affori") {
        if margin >= 2.0 { return .ok }
        if margin >= 1.5 { return .hurry }
        if margin >= 1.0 { return .run }
        return .miss
    }
    if name.contains("repubblica") {
        if margin >= 5.0 { return .ok }
        if margin >= 3.0 { return .hurry }
        if margin >= 2.0 { return .run }
        return .miss
    }
    if name.contains("lodi") || name.contains("romana") || name.contains("tibb") {
        if margin >= 10.0 { return .ok }
        if margin >= 8.0 { return .hurry }
        if margin >= 6.0 { return .run }
        return .miss
    }
    if name.contains("rogoredo") {
        if margin >= 6.0 { return .ok }
        if margin >= 4.0 { return .hurry }
        if margin >= 3.0 { return .run }
        return .miss
    }
    
    // M4 (Blu)
    if name.contains("cristoforo") {
        if margin >= 5.0 { return .ok }
        if margin >= 3.0 { return .hurry }
        if margin >= 2.0 { return .run }
        return .miss
    }
    if name.contains("dateo") {
        if margin >= 5.0 { return .ok }
        if margin >= 4.0 { return .hurry }
        if margin >= 3.0 { return .run }
        return .miss
    }
    if name.contains("forlanini") {
        if margin >= 3.0 { return .ok }
        if margin >= 2.0 { return .hurry }
        if margin >= 1.0 { return .run }
        return .miss
    }
    
    // M5 (Lilla)
    if name.contains("domodossola") {
        if margin >= 3.0 { return .ok }
        if margin >= 2.0 { return .hurry }
        if margin >= 1.0 { return .run }
        return .miss
    }
    
    // Default fallback
    if margin >= 4.0 { return .ok }
    if margin >= 3.0 { return .hurry }
    if margin >= 2.0 { return .run }
    return .miss
}

/// Vista che appare come bottom sheet quando si tiene premuta una fermata con connessioni metro.
struct MetroQuickView: View {
    let stop: Stop
    let metroLines: [MetroLine]
    let useTrainArrival: Bool
    @EnvironmentObject var cache: MetroCache

    /// Orario di arrivo stimato del treno a questa fermata (combinato con la data odierna).
    private var estimatedArrival: Date? {
        // Priorità: orario effettivo > orario stimato (ritardo) > orario programmato
        let rawStr = stop.actualTime ?? stop.estimatedTime ?? stop.time
        let timeStr = to24h(rawStr)
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        f.timeZone = TimeZone(identifier: "Europe/Rome")
        guard let parsed = f.date(from: timeStr) else { return nil }
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        let tc = Calendar.current.dateComponents([.hour, .minute], from: parsed)
        comps.hour = tc.hour; comps.minute = tc.minute
        return Calendar.current.date(from: comps)
    }

    private var arrivalLabel: String {
        guard let d = estimatedArrival else { return "" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        f.timeZone = TimeZone(identifier: "Europe/Rome")
        return f.string(from: d)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(stop.stationName.formattedStationName)
                        .font(.title2.bold())
                    HStack(spacing: 4) {
                        Image(systemName: "tram.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text((useTrainArrival && estimatedArrival != nil) ? "Arrivo treno: \(arrivalLabel)" : "Prossime partenze metro")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 16)

            Divider()

            // Linee metro
            if metroLines.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "tram.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("Nessuna metropolitana disponibile")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(metroLines) { metro in
                            MetroQuickLineRow(metro: metro, trainArrival: useTrainArrival ? estimatedArrival : nil, stationName: stop.stationName)
                            if metro.id != metroLines.last?.id { Divider().padding(.leading, 60) }
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
        .task {
            let timeParam = (useTrainArrival && estimatedArrival != nil) ? arrivalLabel : nil
            // Carica/aggiorna i dati metro (rispetta il TTL — nessuna chiamata inutile)
            for metro in metroLines {
                if let pid = metro.pdfID {
                    await cache.sync(city: metro.city, line: String(metro.name.prefix(2)), pdfID: pid, direction: metro.direction, time: timeParam)
                }
            }
        }
    }
}

/// Riga singola per una linea metro nel quick preview.
struct MetroQuickLineRow: View {
    let metro: MetroLine
    let trainArrival: Date?
    let stationName: String
    @EnvironmentObject var cache: MetroCache

    private func cleanDestinationName(_ name: String) -> String {
        let lower = name.lowercased()
        if lower.contains("cologno nord") || lower.contains("cologno n") { return "Cologno N." }
        if lower.contains("cascina gobba") || lower.contains("c.gobba") || lower.contains("c. gobba") { return "C. Gobba" }
        if lower.contains("assago") { return "Assago" }
        if lower.contains("abbiategrasso") { return "Abbiategrasso" }
        if lower.contains("rho fiera") { return "Rho Fiera" }
        if lower.contains("bisceglie") { return "Bisceglie" }
        if lower.contains("sesto") { return "Sesto FS" }
        if lower.contains("comasina") { return "Comasina" }
        if lower.contains("donato") { return "San Donato" }
        if lower.contains("linate") { return "Linate" }
        if lower.contains("cristoforo") { return "S. Cristoforo" }
        if lower.contains("bignami") { return "Bignami" }
        if lower.contains("siro") { return "San Siro" }
        return name
    }

    private var arrivalTimeLabel: String? {
        guard let d = trainArrival else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        f.timeZone = TimeZone(identifier: "Europe/Rome")
        return f.string(from: d)
    }

    var body: some View {
        let mode = cache.getNextDepartures(metro: metro, time: arrivalTimeLabel, now: Date())

        HStack(spacing: 14) {
            // Badge linea
            Circle()
                .fill(metro.color)
                .frame(width: 36, height: 36)
                .overlay(
                    Text(String(metro.name.prefix(2)))
                        .font(.system(size: 13, weight: .black))
                        .foregroundColor(.white)
                )

            VStack(alignment: .leading, spacing: 6) {
                Text(metro.directionLabel)
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)

                switch mode {
                case .closed:
                    Text("Servizio terminato").font(.subheadline).foregroundColor(.secondary)
                case .frequency(let text):
                    Text(text).font(.subheadline)
                case .exact(let deps):
                    let showDestination = metro.name.hasPrefix("M1") || metro.name.hasPrefix("M2")
                    if let arrival = trainArrival {
                        // PREVIEW MODE: Show the first two usable departures (margin >= 0)
                        let usableDeps = deps.filter { dep in
                            if let margin = getMarginMinutes(timeString: dep.timeString, trainArrival: arrival) {
                                return margin >= 0
                            }
                            return false
                        }
                        let displayDeps = Array(usableDeps.prefix(2))
                        
                        if !displayDeps.isEmpty {
                            HStack(spacing: 8) {
                                ForEach(displayDeps, id: \.self) { dep in
                                    VStack(alignment: .leading, spacing: 4) {
                                        DepartureChip(timeString: dep.timeString, trainArrival: arrival, stationName: stationName)
                                        if showDestination, let dest = dep.destinationName {
                                            Text(cleanDestinationName(dest))
                                                .font(.system(size: 10, weight: .medium))
                                                .foregroundColor(.secondary)
                                                .lineLimit(1)
                                        }
                                    }
                                }
                            }
                        } else {
                            Text("Nessuna partenza").font(.subheadline).foregroundColor(.secondary)
                        }
                    } else {
                        // TENDINA MODE: Show up to 4 departures starting from now (independently of train arrival)
                        HStack(spacing: 12) {
                            ForEach(deps.prefix(4), id: \.self) { dep in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(dep.timeString)
                                        .font(.system(.subheadline, design: .rounded).bold())
                                        .foregroundColor(.primary)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.secondary.opacity(0.1))
                                        .cornerRadius(6)
                                    if showDestination, let dest = dep.destinationName {
                                        Text(cleanDestinationName(dest))
                                            .font(.system(size: 9))
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}

/// Chip con orario metro e indicatore visivo corri/tranquillo.
struct DepartureChip: View {
    let timeString: String
    let trainArrival: Date?
    let stationName: String

    private var marginMinutes: Double? {
        getMarginMinutes(timeString: timeString, trainArrival: trainArrival)
    }

    private var style: (icon: String, text: String, color: Color, bg: Color) {
        guard let m = marginMinutes else {
            return ("minus", "--", .secondary, Color.secondary.opacity(0.1))
        }
        let status = getFeasibility(stationName: stationName, margin: m)
        return status.style
    }

    var body: some View {
        HStack(spacing: 5) {
            Text(timeString)
                .font(.system(.subheadline, design: .rounded).bold())
                .foregroundColor(style.color == .secondary ? .primary : style.color)
            
            Image(systemName: style.icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(style.color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(style.bg)
        .cornerRadius(10)
    }
}
