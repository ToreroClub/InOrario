import SwiftUI
import CoreLocation

public struct ClipSearchSheetView: View {
    @Binding var selectedStation: Station
    var onSelectTrain: ((Train) -> Void)? = nil
    
    @Environment(\.dismiss) private var dismiss
    @StateObject private var locationManager = ClipLocationManager.shared
    @StateObject private var recentManager = ClipRecentTrainsManager.shared
    @StateObject private var recentStationsManager = ClipRecentStationsManager.shared
    @StateObject private var pinnedManager = ClipPinnedStationManager.shared
    @State private var searchQuery = ""
    
    public init(selectedStation: Binding<Station>, onSelectTrain: ((Train) -> Void)? = nil) {
        self._selectedStation = selectedStation
        self.onSelectTrain = onSelectTrain
    }
    
    public var body: some View {
        NavigationStack {
            List {
                let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
                
                if trimmed.isEmpty {
                    // 1. Sezione Stazioni Vicine (GPS)
                    if !locationManager.nearbyStations.isEmpty {
                        Section(header: Text("Stazioni Vicine")) {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(locationManager.nearbyStations.prefix(5)) { nearby in
                                        Button {
                                            recentStationsManager.addStation(nearby.station)
                                            self.selectedStation = nearby.station
                                            Haptics.play(.medium)
                                            dismiss()
                                        } label: {
                                            HStack(spacing: 6) {
                                                Image(systemName: "location.fill")
                                                    .font(.system(size: 11, weight: .bold))
                                                    .foregroundColor(.blue)
                                                
                                                Text(nearby.station.formattedName)
                                                    .font(.subheadline.weight(.semibold))
                                                    .foregroundColor(.primary)
                                                
                                                Text(nearby.distanceText)
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                            }
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 8)
                                            .background(Color(.secondarySystemGroupedBackground))
                                            .clipShape(Capsule())
                                            .overlay(
                                                Capsule()
                                                    .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                                            )
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                    }
                                }
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                            }
                            .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 4, trailing: 0))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }
                    } else if locationManager.authorizationStatus == .notDetermined {
                        Section {
                            Button {
                                locationManager.requestAuthorization()
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "location.circle")
                                        .foregroundColor(.blue)
                                    Text("Abilita posizione per stazioni vicine")
                                        .font(.subheadline)
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    }
                    
                    // 2. Stazioni Recenti (Riga orizzontale dedicata)
                    if !recentStationsManager.recentStations.isEmpty {
                        Section {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(recentStationsManager.recentStations) { recentStation in
                                        let isPinned = pinnedManager.isPinned(recentStation)
                                        let isCurrent = recentStation.isSameStation(as: selectedStation)
                                        Button {
                                            recentStationsManager.addStation(recentStation)
                                            self.selectedStation = recentStation
                                            Haptics.play(.medium)
                                            dismiss()
                                        } label: {
                                            HStack(spacing: 6) {
                                                Image(systemName: isPinned ? "pin.fill" : "clock.arrow.circlepath")
                                                    .font(.system(size: 11, weight: .bold))
                                                    .foregroundColor(.orange)
                                                
                                                Text(recentStation.formattedName)
                                                    .font(.subheadline.weight(.semibold))
                                                    .foregroundColor(.primary)
                                            }
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 8)
                                            .background(isCurrent ? Color.orange.opacity(0.14) : Color(.secondarySystemGroupedBackground))
                                            .clipShape(Capsule())
                                            .overlay(
                                                Capsule()
                                                    .stroke(isCurrent ? Color.orange.opacity(0.5) : Color.primary.opacity(0.08), lineWidth: isCurrent ? 1 : 0.5)
                                            )
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                    }
                                }
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                            }
                            .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 4, trailing: 0))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        } header: {
                            HStack {
                                Text("Stazioni Recenti")
                                Spacer()
                                Button("Cancella") {
                                    Haptics.play(.light)
                                    recentStationsManager.clear()
                                }
                                .font(.caption)
                                .textCase(.none)
                            }
                        }
                    }
                    
                    // 3. Cronologia Treni Recenti (Verticale, occupa tutto lo spazio)
                    if !recentManager.recentTrains.isEmpty {
                        Section {
                            ForEach(recentManager.recentTrains) { train in
                                Button {
                                    Haptics.play(.medium)
                                    dismiss()
                                    onSelectTrain?(train)
                                } label: {
                                    HStack(alignment: .center, spacing: 12) {
                                        // Badge Categoria
                                        Text(train.category)
                                            .font(.system(size: 10, weight: .bold))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 3)
                                            .background(categoryColor(train.category))
                                            .foregroundColor(.white)
                                            .cornerRadius(4)
                                        
                                        VStack(alignment: .leading, spacing: 3) {
                                            HStack(spacing: 6) {
                                                Text(train.number)
                                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                                    .foregroundColor(.primary)
                                                
                                                if let origin = train.origin, !origin.isEmpty {
                                                    Text(SharedFormatters.formatDestination(origin))
                                                        .font(.caption)
                                                        .foregroundColor(.secondary)
                                                    Image(systemName: "arrow.right")
                                                        .font(.system(size: 9, weight: .bold))
                                                        .foregroundColor(.secondary)
                                                }
                                                
                                                if !train.destination.isEmpty {
                                                    Text(SharedFormatters.formatDestination(train.destination))
                                                        .font(.system(size: 14, weight: .semibold))
                                                        .foregroundColor(.primary)
                                                        .lineLimit(1)
                                                }
                                            }
                                            
                                            HStack(spacing: 6) {
                                                if !train.time.isEmpty {
                                                    Text("Orario: \(train.time)")
                                                        .font(.caption2.bold())
                                                        .foregroundColor(.secondary)
                                                }
                                                
                                                if !train.delay.isEmpty {
                                                    Text("•")
                                                        .font(.caption2)
                                                        .foregroundColor(.secondary)
                                                    Text(train.delay)
                                                        .font(.caption2.bold())
                                                        .foregroundColor(train.delay.contains("In orario") ? .green : .red)
                                                }
                                                
                                                if !train.platform.isEmpty && train.platform != "--" {
                                                    Text("•")
                                                        .font(.caption2)
                                                        .foregroundColor(.secondary)
                                                    Text("Bin. \(train.platform)")
                                                        .font(.caption2)
                                                        .foregroundColor(.secondary)
                                                }
                                            }
                                        }
                                        
                                        Spacer()
                                        
                                        Image(systemName: "chevron.right")
                                            .font(.caption2.bold())
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                        } header: {
                            HStack {
                                Text("Treni Recenti")
                                Spacer()
                                Button("Cancella") {
                                    Haptics.play(.light)
                                    recentManager.clear()
                                }
                                .font(.caption)
                                .textCase(.none)
                            }
                        }
                    }
                } else {
                    // 2. Ricerca Treno (se l'utente inserisce cifre numeriche)
                    let digits = trimmed.filter { "0123456789".contains($0) }
                    if !digits.isEmpty && digits.count >= 2 {
                        Section(header: Text("Treni")) {
                            Button {
                                let trainToView = Train(
                                    category: "TRENO",
                                    number: digits,
                                    destination: "",
                                    time: "",
                                    delay: "",
                                    platform: ""
                                )
                                Haptics.play(.medium)
                                dismiss()
                                onSelectTrain?(trainToView)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "tram.fill")
                                        .foregroundColor(.orange)
                                        .font(.body)
                                        .frame(width: 24)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Treno \(digits)")
                                            .font(.headline)
                                            .foregroundColor(.primary)
                                        Text("Visualizza andamento, ritardo e fermate live")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption2.bold())
                                        .foregroundColor(.secondary)
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                    
                    // 3. Risultati Ricerca Stazioni
                    let results = ClipLinkHandler.shared.searchStations(query: trimmed)
                    if !results.isEmpty {
                        Section(header: Text("Stazioni")) {
                            ForEach(results) { station in
                                Button {
                                    recentStationsManager.addStation(station)
                                    self.selectedStation = station
                                    Haptics.play(.medium)
                                    dismiss()
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: "building.2.crop.circle.fill")
                                            .foregroundColor(.orange)
                                            .font(.body)
                                            .frame(width: 24)
                                        
                                        Text(station.formattedName)
                                            .font(.headline)
                                            .foregroundColor(.primary)
                                        
                                        Spacer()
                                        
                                        if station.isSameStation(as: selectedStation) {
                                            Image(systemName: "checkmark")
                                                .foregroundColor(.blue)
                                                .fontWeight(.bold)
                                        }
                                    }
                                    .padding(.vertical, 2)
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $searchQuery, prompt: "Cerca treno o stazione...")
            .navigationTitle("Cerca")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Chiudi") {
                        dismiss()
                    }
                }
            }
        }
    }
}
