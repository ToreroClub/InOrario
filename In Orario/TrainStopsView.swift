import SwiftUI
import Combine
import Foundation
import CoreLocation
import ActivityKit

struct TrainStopsView: View {
    let train: Train
    var showCloseButton: Bool = true
    @EnvironmentObject var manager: TrainManager
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            if manager.isStopsLoading { ProgressView().padding() }
            else if let error = manager.stopErrorMessage {
                VStack { Image(systemName: "clock.badge.exclamationmark").font(.largeTitle).padding(); Text(error).multilineTextAlignment(.center).padding() }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Circle().fill(manager.currentTrainStatus.statusMessage.contains("In orario") ? .green : (manager.currentTrainStatus.isDeparted ? .red : .gray)).frame(width: 12, height: 12)
                        Text(manager.currentTrainStatus.statusMessage).font(.headline).foregroundColor(.primary)
                        Spacer()
                    }
                    if let note = manager.currentTrainStatus.cancellationNote { Text(note).font(.caption).bold().padding(6).background(Color.red.opacity(0.2)).foregroundColor(.red).cornerRadius(4) }
                    if manager.currentTrainStatus.isDeparted {
                        HStack { Image(systemName: "location.fill").foregroundColor(.secondary); Text("Ultimo rilevamento: ").foregroundColor(.secondary); Text(manager.currentTrainStatus.lastStation).bold(); Text("alle \(manager.currentTrainStatus.lastTime)").foregroundColor(.secondary) }.font(.caption)
                    } else { Text("Il treno non ha ancora lasciato la stazione di partenza.").font(.caption).foregroundColor(.secondary) }
                }
                .padding().background(Color(.secondarySystemBackground)).cornerRadius(12).padding()
                
                List(manager.selectedTrainStops) { stop in
                    NavigationLink(destination: SmartBoardView(station: stationFromStopName(stop.stationName, manager: manager))) {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(stop.stationName).font(.headline)
                                
                                if let act = stop.actualTime {
                                    Text("Effettivo: \(act)")
                                        .font(.caption)
                                        .foregroundColor(stop.delay <= 2 ? .green : (stop.delay <= 6 ? .orange : .red))
                                }
                                else if let est = stop.estimatedTime {
                                    Text("Previsto: \(est)")
                                        .font(.caption)
                                        .foregroundColor(.red)
                                        .bold()
                                }
                            }
                            Spacer()
                            
                            if stop.actualTime == nil && stop.estimatedTime != nil {
                                Text(stop.time)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .strikethrough()
                            } else {
                                Text(stop.time).font(.subheadline).foregroundColor(.secondary)
                            }
                        }
                    }
                    .listRowBackground(
                        (!manager.homeDestinationStationName.isEmpty &&
                         stop.stationName.lowercased().contains(manager.homeDestinationStationName.lowercased()))
                        ? Color.orange.opacity(0.1)
                        : Color.clear
                    )
                }
            }
        }
        .navigationTitle("\(train.category) \(train.number)")
        .toolbar {
            if showCloseButton {
                ToolbarItem(placement: .topBarLeading) { Button("Chiudi") { dismiss() } }
            }
            ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 16) {
                        let isActive = manager.activeLiveActivities.contains(train.number)
                        Button {
                            if isActive {
                                // Se è già attiva, la chiamata la spegne (comportamento predefinito)
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
                        
                        let delayMinutes = train.delay.replacingOccurrences(of: "+", with: "").replacingOccurrences(of: "'", with: "")
                        let isDelayed = !train.delay.contains("In orario")
                        let shareText = isDelayed
                            ? "Il treno \(train.number) è in ritardo di \(delayMinutes) minuti, ci vediamo dopo! 🐌"
                            : "Il treno \(train.number) è in perfetto orario, a tra poco! 🚄"
                        
                        ShareLink(item: shareText) {
                            Image(systemName: "square.and.arrow.up").foregroundColor(.blue)
                        }
                        .simultaneousGesture(TapGesture().onEnded { Haptics.play(.light) })
                        
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
        
        let attributes = TrainLiveActivityAttributes(
            trainNumber: train.number,
            destination: train.destination,
            category: train.category
        )
        
        let contentState = TrainLiveActivityAttributes.ContentState(
            delay: train.delay,
            statusMessage: manager.currentTrainStatus.statusMessage,
            lastStation: manager.currentTrainStatus.lastStation
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
private func stationFromStopName(_ name: String, manager: TrainManager) -> Station {
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
    return stationForName(clean, manager: manager)
}
