import SwiftUI
import StoreKit

public struct ClipTrainDetailView: View {
    let train: Train
    let currentStation: Station?
    var onSelectStation: ((Station) -> Void)? = nil
    
    @Environment(\.dismiss) private var dismiss
    @State private var stopsResult: StopsResult?
    @State private var isLoading = true
    @State private var showStoreOverlay = false
    @State private var selectedStationToPush: Station? = nil
    
    public init(train: Train, currentStation: Station? = nil, onSelectStation: ((Station) -> Void)? = nil) {
        self.train = train
        self.currentStation = currentStation
        self.onSelectStation = onSelectStation
    }
    
    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if isLoading {
                        VStack(spacing: 16) {
                            ProgressView()
                                .scaleEffect(1.2)
                            Text("Recupero fermate e andamento live...")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                    } else if let result = stopsResult {
                        // Header con Partenza e Arrivo (su due righe, grafica esatta dell'app)
                        HStack(alignment: .center) {
                            VStack(alignment: .leading, spacing: 4) {
                                let origin = result.stops.first?.stationName ?? (train.origin ?? "")
                                let destination = result.stops.last?.stationName ?? train.destination
                                
                                if origin.isEmpty {
                                    Text(SharedFormatters.formatDestination(destination))
                                        .font(.title2)
                                        .bold()
                                        .foregroundColor(.primary)
                                } else {
                                    Text(SharedFormatters.formatDestination(origin))
                                        .font(.title2)
                                        .bold()
                                        .foregroundColor(.secondary)
                                    Text(SharedFormatters.formatDestination(destination))
                                        .font(.title2)
                                        .bold()
                                        .foregroundColor(.primary)
                                }
                            }
                            
                            Spacer()
                        }
                        .padding([.horizontal, .top])
                        
                        // Cartella dello Stato (ritardo, ultima fermata, ecc.) - Sfondo Bianco / Secondario
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Circle()
                                    .fill(result.status.statusMessage.lowercased().contains("in orario") ? Color.green : (result.status.isDeparted ? Color.red : Color.gray))
                                    .frame(width: 12, height: 12)
                                Text(result.status.statusMessage)
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                Spacer()
                            }
                            
                            if let note = result.status.cancellationNote {
                                Text(note)
                                    .font(.caption)
                                    .bold()
                                    .padding(6)
                                    .background(Color.red.opacity(0.2))
                                    .foregroundColor(.red)
                                    .cornerRadius(4)
                            }
                            
                            if result.status.isDeparted && result.status.lastStation != "--" {
                                HStack {
                                    Image(systemName: "location.fill")
                                        .foregroundColor(.secondary)
                                    Text("Ultimo rilevamento: ")
                                        .foregroundColor(.secondary)
                                    Text(result.status.lastStation)
                                        .bold()
                                    Text("alle \(result.status.lastTime)")
                                        .foregroundColor(.secondary)
                                }
                                .font(.caption)
                            } else {
                                Text("Il treno non ha ancora lasciato la stazione di partenza.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding()
                        .background(Color(.secondarySystemGroupedBackground))
                        .cornerRadius(12)
                        .padding()
                        
                        // Lista fermate richiusa in un rettangolo bianco dagli angoli smussati (Grafica esatta dell'app)
                        VStack(spacing: 0) {
                            ForEach(Array(result.stops.enumerated()), id: \.element.id) { index, stop in
                                let isCurrentStation = (currentStation != nil) && stop.stationName.lowercased().contains(currentStation!.name.lowercased())
                                
                                let currentIndex = index
                                let anyLaterHasActual = result.stops.dropFirst(currentIndex + 1).contains { $0.actualTime != nil }
                                let isPast = (stop.actualTime != nil || anyLaterHasActual) && !isCurrentStation
                                
                                Button {
                                    Haptics.play(.light)
                                    if let station = resolveStationForStop(stop.stationName) {
                                        selectedStationToPush = station
                                    }
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(SharedFormatters.formatDestination(stop.stationName))
                                                .font(.headline)
                                                .foregroundColor(isCurrentStation ? .blue : (isPast ? .secondary : .primary))
                                        }
                                        
                                        Spacer()
                                        
                                        HStack(spacing: 8) {
                                            // Binario con icona treno verde SF Symbols
                                            if let actualBin = stop.actualPlatform, !actualBin.isEmpty, actualBin != "--" {
                                                HStack(spacing: 2) {
                                                    Image(systemName: "tram.fill")
                                                        .font(.caption2)
                                                        .foregroundColor(.green)
                                                    
                                                    if let plannedBin = stop.plannedPlatform, plannedBin != actualBin, !plannedBin.isEmpty {
                                                        Text(plannedBin)
                                                            .font(.caption2)
                                                            .strikethrough()
                                                            .foregroundColor(.secondary)
                                                    }
                                                    Text(actualBin)
                                                        .font(.caption2)
                                                        .bold()
                                                        .foregroundColor(.green)
                                                }
                                            } else if let plannedBin = stop.plannedPlatform, !plannedBin.isEmpty, plannedBin != "--" {
                                                HStack(spacing: 2) {
                                                    Image(systemName: "tram.fill")
                                                        .font(.caption2)
                                                        .foregroundColor(.secondary)
                                                    Text(plannedBin)
                                                        .font(.caption2)
                                                        .foregroundColor(.secondary)
                                                }
                                            }
                                            
                                            // Orario programmato ed effettivo
                                            if let actualTime = stop.actualTime, actualTime != stop.time {
                                                Text(stop.time)
                                                    .font(.subheadline)
                                                    .strikethrough()
                                                    .foregroundColor(.secondary)
                                                
                                                Text(actualTime)
                                                    .font(.subheadline)
                                                    .bold()
                                                    .foregroundColor(stop.delay > 0 ? .red : .orange)
                                            } else if let est = stop.estimatedTime, est != stop.time {
                                                Text(stop.time)
                                                    .font(.subheadline)
                                                    .strikethrough()
                                                    .foregroundColor(.secondary)
                                                
                                                Text(est)
                                                    .font(.subheadline)
                                                    .bold()
                                                    .foregroundColor(stop.delay > 0 ? .red : .orange)
                                            } else {
                                                Text(stop.time)
                                                    .font(.subheadline)
                                                    .foregroundColor(isPast ? .secondary : .primary)
                                            }
                                            
                                            Image(systemName: "chevron.right")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(PlainButtonStyle())
                                
                                if index < result.stops.count - 1 {
                                    Divider()
                                        .padding(.leading, 16)
                                }
                            }
                        }
                        .background(Color(.secondarySystemGroupedBackground))
                        .cornerRadius(12)
                        .padding(.horizontal)
                        
                        // Card promozionale per Live Activity (solo per Trenitalia / Trenord)
                        if !train.isItalo {
                            appUpsellCard
                                .padding()
                        } else {
                            VStack(spacing: 6) {
                                HStack(spacing: 8) {
                                    Image(systemName: "info.circle.fill")
                                        .foregroundColor(.secondary)
                                    Text("Monitoraggio Live Activity e notifiche non disponibili per i treni Italo.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .center)
                                .background(Color(.secondarySystemGroupedBackground))
                                .cornerRadius(12)
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 12)
                        }
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("\(train.isItalo ? "Italo" : train.category) \(train.number)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundColor(.secondary)
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        loadStops()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.subheadline.bold())
                    }
                }
            }
            .task {
                loadStops()
            }
            .sheet(item: $selectedStationToPush) { st in
                ClipStationModalView(station: st) { newlySelectedStation in
                    onSelectStation?(newlySelectedStation)
                    dismiss()
                }
            }
        }
    }
    
    private func resolveStationForStop(_ stopName: String) -> Station? {
        if let found = ClipLinkHandler.shared.findStation(byCodeOrName: stopName) {
            return found
        }
        return Station(name: stopName.uppercased(), rfiID: nil, vtID: nil)
    }
    
    private var appUpsellCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "bell.badge.fill")
                    .font(.title2)
                    .foregroundColor(.orange)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Segui il treno in tempo reale")
                        .font(.subheadline.bold())
                        .foregroundColor(.primary)
                    Text("Scarica l'app completa per notifiche push sui ritardi e Live Activity sulla Lock Screen.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Button {
                Haptics.play(.medium)
                openInOrarioAppStore()
            } label: {
                Text("Scarica In Orario dall'App Store")
                    .font(.subheadline.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.orange)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
    
    private func loadStops() {
        isLoading = true
        // Salva nei treni recenti
        ClipRecentTrainsManager.shared.addTrain(train)
        Task {
            let res = await ClipService.shared.fetchLiveStops(for: train)
            await MainActor.run {
                self.stopsResult = res
                self.isLoading = false
            }
        }
    }
}

// MARK: - Modale Stazione (aperta da una fermata)

public struct ClipStationModalView: View {
    @State var station: Station
    var onSelectStation: ((Station) -> Void)? = nil
    
    @Environment(\.dismiss) private var dismiss
    @State private var showingDepartures = true
    @State private var trains: [Train] = []
    @State private var alerts: String? = nil
    @State private var isLoading = false
    @State private var selectedChildTrain: Train? = nil
    @State private var isAlertExpanded = false
    
    public init(station: Station, onSelectStation: ((Station) -> Void)? = nil) {
        self._station = State(initialValue: station)
        self.onSelectStation = onSelectStation
    }
    
    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header Stazione compatto con selettore circolare P / A
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(station.formattedName)
                            .font(.system(size: 26, weight: .bold))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    Spacer()
                    HStack(spacing: 6) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) { showingDepartures = true }
                            Haptics.selection()
                        } label: {
                            Text("P")
                                .font(.system(size: 14, weight: .bold))
                                .frame(width: 34, height: 34)
                                .background(showingDepartures ? Color.orange : Color(.tertiarySystemFill))
                                .foregroundColor(showingDepartures ? .white : .primary)
                                .clipShape(Circle())
                        }
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) { showingDepartures = false }
                            Haptics.selection()
                        } label: {
                            Text("A")
                                .font(.system(size: 14, weight: .bold))
                                .frame(width: 34, height: 34)
                                .background(!showingDepartures ? Color.orange : Color(.tertiarySystemFill))
                                .foregroundColor(!showingDepartures ? .white : .primary)
                                .clipShape(Circle())
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                
                List {
                    // Avvisi di stazione (se presenti)
                    if let alertText = alerts, !alertText.isEmpty {
                        Section {
                            VStack(alignment: .leading, spacing: 6) {
                                Button {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        isAlertExpanded.toggle()
                                        Haptics.play(.light)
                                    }
                                } label: {
                                    HStack(spacing: 8) {
                                        Circle()
                                            .fill(Color.red)
                                            .frame(width: 8, height: 8)
                                        Text("Avvisi di stazione")
                                            .font(.subheadline.bold())
                                            .foregroundColor(.red)
                                        Spacer()
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .font(.caption)
                                            .foregroundColor(.orange)
                                        Image(systemName: isAlertExpanded ? "chevron.up" : "chevron.down")
                                            .font(.caption.bold())
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .buttonStyle(PlainButtonStyle())
                                
                                if isAlertExpanded {
                                    Text(alertText)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .padding(.top, 4)
                                }
                            }
                        }
                    }
                    
                    // Sezione Tabellone Treni
                    Section(header: Text(showingDepartures ? "Partenze" : "Arrivi")) {
                        if isLoading && trains.isEmpty {
                            HStack {
                                Spacer()
                                ProgressView()
                                    .padding(.vertical, 20)
                                Spacer()
                            }
                        } else if trains.isEmpty {
                            Text("Nessun treno in programma al momento.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .padding(.vertical, 10)
                        } else {
                            ForEach(trains) { train in
                                Button {
                                    self.selectedChildTrain = train
                                    Haptics.play(.light)
                                } label: {
                                    ClipTrainRowView(train: train, currentStationName: station.name)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .refreshable {
                    Haptics.play(.light)
                    await loadBoard()
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundColor(.secondary)
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Imposta come stazione") {
                        Haptics.play(.medium)
                        onSelectStation?(station)
                        dismiss()
                    }
                    .font(.subheadline.bold())
                    .foregroundColor(.orange)
                }
            }
            .sheet(item: $selectedChildTrain) { childTrain in
                ClipTrainDetailView(train: childTrain, currentStation: station) { newlyChosen in
                    onSelectStation?(newlyChosen)
                    dismiss()
                }
            }
            .task(id: "\(station.id)_\(showingDepartures)") {
                await loadBoard()
            }
        }
    }
    
    private func loadBoard() async {
        isLoading = true
        let result = await ClipService.shared.fetchBoard(for: station, isDepartures: showingDepartures)
        await MainActor.run {
            self.trains = result.trains
            self.alerts = result.alerts
            self.isLoading = false
        }
    }
}
