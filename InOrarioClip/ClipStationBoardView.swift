import SwiftUI
import StoreKit
import Combine

public struct ClipStationBoardView: View {
    @Binding var station: Station
    
    @State private var showingDepartures = true
    @State private var trains: [Train] = []
    @State private var alerts: String? = nil
    @State private var isLoading = false
    @State private var selectedTrain: Train? = nil
    @State private var showSearchSheet = false
    @State private var showStoreOverlay = false
    @State private var isAlertExpanded = false
    @State private var lastUpdated = Date()
    
    let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()
    
    public init(station: Binding<Station>) {
        self._station = station
    }
    
    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header Stazione con selettore circolare P / A
                stationHeader
                
                List {
                    // Sezione Avvisi di Stazione (mostra solo "Avvisi di stazione" in rosso con lo chevron)
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
                                            .foregroundColor(.orange)
                                        Image(systemName: isAlertExpanded ? "chevron.up" : "chevron.right")
                                            .font(.caption.bold())
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .buttonStyle(.plain)
                                
                                if isAlertExpanded {
                                    Text(alertText)
                                        .font(.caption)
                                        .foregroundColor(.primary)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .padding(.top, 4)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    
                    // Elenco Treni con la grafica pulita (Badge categoria + Categoria & Numero treno)
                    Section {
                        if isLoading && trains.isEmpty {
                            HStack {
                                Spacer()
                                ProgressView()
                                    .padding(.vertical, 20)
                                Spacer()
                            }
                        } else if trains.isEmpty {
                            VStack(spacing: 8) {
                                Text("Nessun treno al momento")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 16)
                        } else {
                            ForEach(trains) { train in
                                ClipTrainRowView(train: train, currentStationName: station.name)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        Haptics.play(.light)
                                        selectedTrain = train
                                    }
                            }
                        }
                    } header: {
                        HStack {
                            Text(showingDepartures ? "PARTENZE" : "ARRIVI")
                                .font(.caption2.bold())
                                .foregroundColor(.secondary)
                            Spacer()
                            if isLoading {
                                ProgressView()
                                    .scaleEffect(0.7)
                            } else {
                                Text("Aggiornato \(formatTime(lastUpdated))")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    Section {
                        Text("Dati in tempo reale da tabelloni RFI e ViaggiaTreno")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
                .listStyle(.insetGrouped)
                .refreshable {
                    Haptics.play(.light)
                    await loadBoard(force: true)
                }
                
                // Dock inferiore per scaricare l'app completa
                bottomPromoDock
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSearchSheet = true
                        Haptics.play(.light)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "magnifyingglass")
                            Text("Cerca treno/stazione")
                        }
                        .font(.subheadline)
                    }
                }
            }
            .sheet(item: $selectedTrain) { train in
                ClipTrainDetailView(train: train, currentStation: station) { newStation in
                    self.station = newStation
                }
            }
            .sheet(isPresented: $showSearchSheet) {
                ClipSearchSheetView(selectedStation: $station) { selected in
                    self.selectedTrain = selected
                }
            }
            .task(id: "\(station.id)_\(showingDepartures)") {
                await loadBoard(force: false)
            }
            .onReceive(timer) { _ in
                Task { await loadBoard(force: true) }
            }
        }
    }
    
    // MARK: - Header Stazione
    
    private var stationHeader: some View {
        HStack(alignment: .center) {
            Text(station.formattedName)
                .font(.title)
                .bold()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            
            Spacer()
            
            // Selettore circolare P / A
            HStack(spacing: 8) {
                Button {
                    if !showingDepartures {
                        showingDepartures = true
                        Haptics.play(.medium)
                    }
                } label: {
                    Text("P")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .frame(width: 36, height: 36)
                        .background(showingDepartures ? Color.orange : Color(.systemGray5))
                        .foregroundColor(showingDepartures ? .white : .primary)
                        .clipShape(Circle())
                }
                
                Button {
                    if showingDepartures {
                        showingDepartures = false
                        Haptics.play(.medium)
                    }
                } label: {
                    Text("A")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .frame(width: 36, height: 36)
                        .background(!showingDepartures ? Color.orange : Color(.systemGray5))
                        .foregroundColor(!showingDepartures ? .white : .primary)
                        .clipShape(Circle())
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 12)
        .background(Color(.systemGroupedBackground))
        .zIndex(1)
    }
    
    // MARK: - Dock Promozionale Inferiore
    
    private var bottomPromoDock: some View {
        HStack(spacing: 12) {
            Image("AppIconImage")
                .resizable()
                .scaledToFit()
                .frame(width: 40, height: 40)
                .cornerRadius(9)
                .overlay(
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                )
                .shadow(color: Color.black.opacity(0.06), radius: 2, x: 0, y: 1)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Scarica In Orario")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)
                Text("Scarica la versione completa dell'app")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button {
                Haptics.play(.medium)
                openInOrarioAppStore()
            } label: {
                Text("Ottieni")
                    .font(.caption.bold())
                    .padding(.horizontal, 16)
                    .padding(.vertical, 7)
                    .background(Color.orange)
                    .foregroundColor(.white)
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemGroupedBackground))
        .overlay(Divider(), alignment: .top)
    }
    
    // MARK: - Fetch Logic
    
    private func loadBoard(force: Bool) async {
        if !force && trains.isEmpty {
            isLoading = true
        }
        
        let result = await ClipService.shared.fetchBoard(for: station, isDepartures: showingDepartures)
        
        await MainActor.run {
            self.trains = result.trains
            self.alerts = result.alerts
            self.isLoading = false
            self.lastUpdated = Date()
        }
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

// MARK: - TrainRowView (Pulita: Badge Categoria + Categoria & Numero)

public struct ClipTrainRowView: View {
    public let train: Train
    public var currentStationName: String? = nil
    
    @State private var pulseScale: CGFloat = 1.0
    @State private var pulseOpacity: Double = 1.0
    
    public init(train: Train, currentStationName: String? = nil) {
        self.train = train
        self.currentStationName = currentStationName
    }
    
    public var body: some View {
        let isDelayed = !train.delay.contains("In orario") && !train.delay.contains("0'") && !train.delay.isEmpty
        
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(train.category)
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 3)
                        .background(categoryColor(train.category))
                        .foregroundColor(.white)
                        .cornerRadius(4)
                    
                    Text("\(train.category) \(train.number)")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                }
                HStack(alignment: .center, spacing: 6) {
                    Text(SharedFormatters.formatDestination(train.destination))
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(train.time).font(.title3).bold()
                HStack {
                    HStack(spacing: 3) {
                        Text(train.delay)
                            .foregroundColor(train.delay.contains("In orario") ? .green : .red)
                            .scaleEffect(isDelayed ? pulseScale : 1.0)
                            .opacity(isDelayed ? pulseOpacity : 1.0)
                        
                        if train.isDelayUncertain {
                            Text("?")
                                .font(.system(size: 9, weight: .black))
                                .foregroundColor(.white)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(Color.orange)
                                .cornerRadius(3)
                        }
                    }
                    
                    Text(String(format: "Bin. %@", train.platform))
                        .padding(.horizontal, 4)
                        .background(Color.black.opacity(0.8))
                        .foregroundColor(.yellow)
                        .cornerRadius(4)
                }
                .font(.caption).bold()
            }
        }
        .padding(.vertical, 6)
        .onAppear {
            if isDelayed {
                withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                    pulseScale = 1.1
                    pulseOpacity = 0.7
                }
            }
        }
    }
}
