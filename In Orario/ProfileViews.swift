import SwiftUI
import StoreKit
import EventKit
import ActivityKit
import WidgetKit
import CoreLocation

enum NewsCategory: String, CaseIterable, Identifiable {
    case sciopero = "Scioperi"
    case lavoro = "Info Lavori"
    case realtime = "Info Mobilità"
    
    var id: String { self.rawValue }
    
    var localizedName: LocalizedStringKey {
        LocalizedStringKey(rawValue)
    }
    
    var filterKey: String {
        switch self {
        case .sciopero: return "sciopero"
        case .lavoro: return "lavoro"
        case .realtime: return "realtime"
        }
    }
}

struct NewsCenterView: View {
    @Binding var news: [NewsItem]
    @EnvironmentObject var manager: TrainManager
    @Environment(\.dismiss) var dismiss
    @State private var selectedCategory: NewsCategory

    init(news: Binding<[NewsItem]>, initialCategory: NewsCategory? = nil) {
        _news = news
        _selectedCategory = State(initialValue: initialCategory ?? .sciopero)
    }
    @State private var selectedRegion: String = ""
    @State private var regionOverrideNews: [NewsItem]? = nil
    @State private var isLoadingRegion = false
    @State private var isRefreshing = false
    @State private var showCalendarAlert = false
    @State private var calendarAlertMessage = ""
    @State private var addedCalendarItemIds: Set<UUID> = []
    @State private var selectedLavoroItem: NewsItem? = nil
    @State private var expandedRealtimeIds: Set<UUID> = []

    private static let allItalianRegions: [String] = [
        "Abruzzo", "Basilicata", "Calabria", "Campania", "Emilia-Romagna",
        "Friuli-Venezia Giulia", "Lazio", "Liguria", "Lombardia", "Marche",
        "Molise", "Piemonte", "Puglia", "Sardegna", "Sicilia",
        "Toscana", "Trentino-Alto Adige", "Umbria", "Valle d'Aosta", "Veneto"
    ]

    private var activeRegion: String {
        selectedRegion.isEmpty ? manager.strikeRegion : selectedRegion
    }

    private var activeNewsSource: [NewsItem] {
        regionOverrideNews ?? news
    }
    
    var filteredNews: [NewsItem] {
        let items = activeNewsSource.filter { ($0.category ?? "sciopero") == selectedCategory.filterKey }
        if selectedCategory == .lavoro {
            return items
                .filter { !$0.isExpiredNotice }
                .sorted { a, b in
                    if a.noticeSortRank != b.noticeSortRank {
                        return a.noticeSortRank < b.noticeSortRank
                    }
                    if a.noticeSortPrimaryDate != b.noticeSortPrimaryDate {
                        return a.noticeSortPrimaryDate < b.noticeSortPrimaryDate
                    }
                    if a.noticeSortSecondaryDate != b.noticeSortSecondaryDate {
                        return a.noticeSortSecondaryDate < b.noticeSortSecondaryDate
                    }
                    return a.title < b.title
                }
        }
        if selectedCategory == .realtime {
            return items
                .filter { $0.isRealtimeVisibleNow }
                .sorted { a, b in
                    if a.realtimeStatusRank != b.realtimeStatusRank {
                        return a.realtimeStatusRank < b.realtimeStatusRank
                    }
                    let dA = a.parsedLastUpdatedDate
                    let dB = b.parsedLastUpdatedDate
                    if dA != dB {
                        return dA > dB
                    }
                    return a.title < b.title
                }
        }
        return items.sorted { a, b in
            let dateA = a.sortableDate
            let dateB = b.sortableDate
            if dateA != dateB {
                return dateA < dateB
            }
            if a.isUrgent != b.isUrgent { return a.isUrgent }
            return a.title < b.title
        }
    }

    private func switchRegion(_ newRegion: String) {
        guard newRegion != activeRegion else { return }
        Haptics.play(.light)
        selectedRegion = newRegion
        expandedRealtimeIds.removeAll()
        if newRegion == manager.strikeRegion {
            regionOverrideNews = nil
            return
        }
        Task {
            isLoadingRegion = true
            let fetched = await manager.fetchNewsForRegion(newRegion)
            await MainActor.run {
                if activeRegion == newRegion {
                    regionOverrideNews = fetched
                }
                isLoadingRegion = false
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 12) {
                        Picker("Categoria", selection: $selectedCategory) {
                            ForEach(NewsCategory.allCases) { category in
                                Text(category.localizedName).tag(category)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)

                        // Selettore rapido Regione (Tutte / La tua regione / qualsiasi regione italiana)
                        Menu {
                            Button {
                                switchRegion("Tutte")
                            } label: {
                                Label("Tutte le regioni (Nazionale)", systemImage: activeRegion == "Tutte" ? "checkmark" : "globe.europe.africa")
                            }
                            if manager.strikeRegion != "Tutte" {
                                Button {
                                    switchRegion(manager.strikeRegion)
                                } label: {
                                    Label("\(manager.strikeRegion) (La tua regione)", systemImage: activeRegion == manager.strikeRegion ? "checkmark" : "location.fill")
                                }
                            }
                            Divider()
                            ForEach(Self.allItalianRegions, id: \.self) { reg in
                                Button {
                                    switchRegion(reg)
                                } label: {
                                    if activeRegion == reg {
                                        Label(reg, systemImage: "checkmark")
                                    } else {
                                        Text(reg)
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: activeRegion == "Tutte" ? "globe.europe.africa.fill" : "mappin.and.ellipse")
                                    .font(.subheadline)
                                    .foregroundColor(.blue)
                                Text(activeRegion == "Tutte" ? "Tutte le regioni" : activeRegion)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundColor(.primary)
                                Spacer()
                                if isLoadingRegion {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                } else {
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.caption.weight(.semibold))
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Color(.secondarySystemGroupedBackground))
                            .cornerRadius(12)
                        }
                        .padding(.horizontal, 16)
                        
                        if filteredNews.isEmpty {
                            if selectedCategory == .realtime {
                                VStack(spacing: 12) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 46))
                                        .foregroundColor(.green)
                                    Text("Circolazione regolare")
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                    Text(
                                        activeRegion == "Tutte"
                                        ? "Nessuna perturbazione segnalata oggi sulla rete RFI."
                                        : "Nessuna perturbazione segnalata oggi in \(activeRegion)."
                                    )
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)

                                    if activeRegion != "Tutte" {
                                        Button {
                                            switchRegion("Tutte")
                                        } label: {
                                            HStack(spacing: 6) {
                                                Image(systemName: "globe.europe.africa")
                                                Text("Mostra tutta Italia")
                                            }
                                            .font(.caption.weight(.semibold))
                                            .foregroundColor(.blue)
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 8)
                                            .background(Color.blue.opacity(0.1))
                                            .clipShape(Capsule())
                                        }
                                        .padding(.top, 4)
                                    }
                                }
                                .padding(24)
                                .frame(maxWidth: .infinity)
                                .background(Color(.secondarySystemGroupedBackground))
                                .cornerRadius(16)
                                .padding(.horizontal, 16)
                                .padding(.top, 8)
                            } else {
                                VStack(spacing: 15) {
                                    Image(systemName: "tray.full")
                                        .font(.system(size: 50))
                                        .foregroundColor(.secondary)
                                    let localizedCat = String(localized: String.LocalizationValue(selectedCategory.rawValue))
                                    Text(String(format: String(localized: "Nessuna notizia in %@"), localizedCat))
                                        .font(.headline)
                                        .foregroundColor(.secondary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.top, 40)
                            }
                        } else if selectedCategory == .lavoro {
                            let activeWorks = filteredNews.filter { $0.noticeSortRank == 0 }
                            let upcomingWorks = filteredNews.filter { $0.noticeSortRank == 1 }
                            let undatedWorks = filteredNews.filter { $0.noticeSortRank == 2 }

                            LazyVStack(alignment: .leading, spacing: 12) {
                                if !activeWorks.isEmpty {
                                    Text("IN CORSO")
                                        .font(.caption.weight(.semibold))
                                        .foregroundColor(.secondary)
                                        .padding(.horizontal, 20)
                                        .padding(.top, 2)

                                    ForEach(activeWorks) { item in
                                        RFILavoroCardView(
                                            item: item,
                                            showRegionBadge: activeRegion == "Tutte"
                                        ) {
                                            if item.hasNoticeDetail {
                                                Haptics.play(.light)
                                                selectedLavoroItem = item
                                            }
                                        }
                                        .padding(.horizontal, 16)
                                    }
                                }

                                if !upcomingWorks.isEmpty {
                                    Text("PROSSIMI LAVORI")
                                        .font(.caption.weight(.semibold))
                                        .foregroundColor(.secondary)
                                        .padding(.horizontal, 20)
                                        .padding(.top, activeWorks.isEmpty ? 2 : 8)

                                    ForEach(upcomingWorks) { item in
                                        RFILavoroCardView(
                                            item: item,
                                            showRegionBadge: activeRegion == "Tutte"
                                        ) {
                                            if item.hasNoticeDetail {
                                                Haptics.play(.light)
                                                selectedLavoroItem = item
                                            }
                                        }
                                        .padding(.horizontal, 16)
                                    }
                                }

                                if !undatedWorks.isEmpty {
                                    if !activeWorks.isEmpty || !upcomingWorks.isEmpty {
                                        Text("ALTRI AVVISI")
                                            .font(.caption.weight(.semibold))
                                            .foregroundColor(.secondary)
                                            .padding(.horizontal, 20)
                                            .padding(.top, 8)
                                    }

                                    ForEach(undatedWorks) { item in
                                        RFILavoroCardView(
                                            item: item,
                                            showRegionBadge: activeRegion == "Tutte"
                                        ) {
                                            if item.hasNoticeDetail {
                                                Haptics.play(.light)
                                                selectedLavoroItem = item
                                            }
                                        }
                                        .padding(.horizontal, 16)
                                    }
                                }
                            }
                        } else {
                            LazyVStack(spacing: 12) {
                                ForEach(filteredNews) { item in
                                    if selectedCategory == .realtime && item.isRFIStructured {
                                        RFIRealtimeCardView(
                                            item: item,
                                            isExpanded: expandedRealtimeIds.contains(item.id),
                                            showRegionBadge: activeRegion == "Tutte"
                                        ) {
                                            Haptics.play(.light)
                                            withAnimation(.easeInOut(duration: 0.24)) {
                                                if expandedRealtimeIds.contains(item.id) {
                                                    expandedRealtimeIds.remove(item.id)
                                                } else {
                                                    expandedRealtimeIds.insert(item.id)
                                                }
                                            }
                                        }
                                        .padding(.horizontal, 16)
                                    } else {
                                        VStack(alignment: .leading, spacing: 8) {
                                            HStack {
                                                Text(item.title).font(.headline)
                                                Spacer()
                                                if item.isUrgent {
                                                    Text("URGENTE")
                                                        .font(.system(size: 10, weight: .bold))
                                                        .padding(.horizontal, 6)
                                                        .padding(.vertical, 2)
                                                        .background(Color.red)
                                                        .foregroundColor(.white)
                                                        .cornerRadius(4)
                                                }
                                            }
                                            FormattedNewsContentView(content: item.content)
                                            
                                            if selectedCategory == .sciopero {
                                                HStack {
                                                    let isAdded = addedCalendarItemIds.contains(item.id)
                                                    Button(action: {
                                                        addStrikeToCalendar(item: item)
                                                    }) {
                                                        HStack(spacing: 5) {
                                                            Image(systemName: isAdded ? "calendar.badge.checkmark" : "calendar.badge.plus")
                                                            Text(isAdded ? "Aggiunto" : "Aggiungi al Calendario")
                                                        }
                                                        .font(.caption.bold())
                                                        .padding(.vertical, 5)
                                                        .padding(.horizontal, 10)
                                                        .background(isAdded ? Color.green.opacity(0.12) : Color.red.opacity(0.12))
                                                        .foregroundColor(isAdded ? .green : .red)
                                                        .cornerRadius(8)
                                                    }
                                                    
                                                    Spacer()
                                                    
                                                    Button(action: {
                                                        let locality = item.regions?.joined(separator: " ") ?? ""
                                                        let dateText = item.date ?? ""
                                                        let query = "sciopero treni \(locality) giorno \(dateText)"
                                                        if let urlString = "https://www.google.com/search?q=\(query)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                                                           let url = URL(string: urlString) {
                                                            UIApplication.shared.open(url)
                                                        }
                                                    }) {
                                                        HStack(spacing: 4) {
                                                            Image(systemName: "magnifyingglass")
                                                            Text("Cerca su Google")
                                                        }
                                                        .font(.caption.bold())
                                                        .foregroundColor(.blue)
                                                    }
                                                }
                                                .padding(.top, 4)
                                            }
                                        }
                                        .padding(16)
                                        .background(Color(.secondarySystemGroupedBackground))
                                        .cornerRadius(16)
                                        .padding(.horizontal, 16)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.bottom, 20)
                }
            }
            .navigationTitle("Centro News")
            .onAppear {
                if selectedRegion.isEmpty {
                    selectedRegion = manager.strikeRegion
                }
            }
            .sheet(item: $selectedLavoroItem) { item in
                RFILavoroDetailSheet(item: item)
            }
            .alert("Calendario", isPresented: $showCalendarAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(calendarAlertMessage)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Chiudi") { dismiss() }.fontWeight(.bold) }
                ToolbarItem(placement: .topBarTrailing) {
                    if isRefreshing {
                        ProgressView()
                    } else {
                        Button {
                            Task {
                                isRefreshing = true
                                let targetRegion = activeRegion
                                if targetRegion == manager.strikeRegion {
                                    let updatedNews = await manager.fetchStrikesAndNews(forceRefresh: true)
                                    await MainActor.run {
                                        self.news = updatedNews
                                        self.regionOverrideNews = nil
                                        isRefreshing = false
                                    }
                                } else {
                                    let updatedRegionNews = await manager.fetchNewsForRegion(targetRegion)
                                    await MainActor.run {
                                        self.regionOverrideNews = updatedRegionNews
                                        isRefreshing = false
                                    }
                                }
                            }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
            }
        }
    }
    
    private func addStrikeToCalendar(item: NewsItem) {
        let eventStore = EKEventStore()
        
        let performSave = {
            let event = EKEvent(eventStore: eventStore)
            event.title = item.title
            event.notes = item.content
            
            let strikeDate = item.sortableDate
            let startDate = (strikeDate != Date.distantFuture) ? strikeDate : Date()
            
            event.startDate = startDate
            event.endDate = startDate
            event.isAllDay = true
            event.calendar = eventStore.defaultCalendarForNewEvents
            
            do {
                try eventStore.save(event, span: .thisEvent)
                DispatchQueue.main.async {
                    addedCalendarItemIds.insert(item.id)
                    Haptics.play(.medium)
                    calendarAlertMessage = "Lo sciopero '\(item.title)' è stato aggiunto al calendario dell'iPhone."
                    showCalendarAlert = true
                }
            } catch {
                DispatchQueue.main.async {
                    Haptics.play(.light)
                    calendarAlertMessage = "Impossibile salvare lo sciopero nel calendario: \(error.localizedDescription)"
                    showCalendarAlert = true
                }
            }
        }
        
        let handlePermission: (Bool, Error?) -> Void = { granted, error in
            if granted && error == nil {
                performSave()
            } else {
                DispatchQueue.main.async {
                    Haptics.play(.light)
                    calendarAlertMessage = "Permesso per accedere al Calendario negato. Abilitalo nelle Impostazioni dell'iPhone per aggiungere gli scioperi."
                    showCalendarAlert = true
                }
            }
        }
        
        if #available(iOS 17.0, *) {
            eventStore.requestFullAccessToEvents { granted, error in
                handlePermission(granted, error)
            }
        } else {
            eventStore.requestAccess(to: .event) { granted, error in
                handlePermission(granted, error)
            }
        }
    }
}

struct SuburbanFavoriteRouteCardView: View {
    let route: SuburbanRoute
    @EnvironmentObject var manager: TrainManager
    @EnvironmentObject var passanteManager: PassanteManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "star.fill")
                        .foregroundColor(.yellow)
                        .font(.caption)
                    Text("\(route.originName) ➔ \(route.destinationName)")
                        .font(.system(size: 11, weight: .bold))
                }
                
                Spacer()
                
                Button {
                    Haptics.play(.medium)
                    manager.removeSmartRoute(id: route.id)
                } label: {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                        .font(.caption)
                }
            }
            
            let details = manager.loadedSmartRouteDetails[route.id]
            if manager.isLoadingSmartRoutes && details == nil {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .padding(.vertical, 10)
            } else if let details = details {
                let trainsToShow = details.originTrains
                
                if trainsToShow.isEmpty {
                    Text("Nessun treno suburbano in tempo reale.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .italic()
                        .padding(.vertical, 4)
                } else {
                    ForEach(trainsToShow.prefix(2)) { train in
                        let delayMin = Int(train.delay.replacingOccurrences(of: "+", with: "").replacingOccurrences(of: "'", with: "")) ?? 0
                        
                        HStack(spacing: 8) {
                            SuburbanLineBadge(id: train.category.isEmpty ? "S" : train.category)
                            
                            VStack(alignment: .leading, spacing: 1) {
                                Text(SharedFormatters.formatDestination(train.destination))
                                    .font(.system(size: 11, weight: .bold))
                                    .lineLimit(1)
                                
                                if delayMin > 0 {
                                    Text("Ritardo di \(delayMin)' (previsto \(train.time) da \(SharedFormatters.formatDestination(route.originName)))")
                                        .font(.system(size: 9))
                                        .foregroundColor(.red)
                                } else {
                                    Text("In orario da \(SharedFormatters.formatDestination(route.originName))")
                                        .font(.system(size: 9))
                                        .foregroundColor(.green)
                                }
                            }
                            
                            Spacer()
                            
                            Text(train.estimatedArrivalTime)
                                .font(.system(size: 15, weight: .black, design: .rounded))
                                .foregroundColor(delayMin > 0 ? .red : .primary)
                        }
                        .padding(.vertical, 4)
                        
                        if train.id != trainsToShow.prefix(2).last?.id {
                            Divider()
                        }
                    }
                }
            } else {
                Text("Trascina la home verso il basso per caricare i dati.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .italic()
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground).opacity(0.4))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.04), lineWidth: 1)
        )
    }
}

struct ProfileView: View {
    var highlightRegionSelector: Bool = false

    @EnvironmentObject var manager: TrainManager
    @EnvironmentObject var passanteManager: PassanteManager
    @EnvironmentObject var usageTracker: UsageTracker
    @EnvironmentObject var locationManager: LocationManager
    @Environment(\.dismiss) var dismiss
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = true
    @AppStorage("metroMilanoBetaEnabled") private var metroMilanoBetaEnabled = false

    @ObservedObject private var tipManager = TipManager.shared
    @ObservedObject private var updateManager = AppUpdateManager.shared
    @ObservedObject private var commuteManager = SupporterCommuteManager.shared
    @State private var showPaywallSheet = false
    @State private var showFeedbackSheet = false
    @State private var showManageSubscriptions = false
    @State private var detectedGPSRegion: String? = nil
    @State private var didSelectRegionFromHighlight: Bool = false

    private let italianRegions: [String] = [
        "Abruzzo", "Basilicata", "Calabria", "Campania", "Emilia-Romagna",
        "Friuli Venezia Giulia", "Lazio", "Liguria", "Lombardia", "Marche",
        "Molise", "Piemonte", "Puglia", "Sardegna", "Sicilia", "Toscana",
        "Trentino-Alto Adige", "Umbria", "Valle d'Aosta", "Veneto"
    ]
    
    var body: some View {
        NavigationStack {
            ScrollViewReader { scrollProxy in
                List {
                    if highlightRegionSelector {
                        prominentRegionSelectorSection
                            .id("region_selector_top")
                    }

                    if !manager.hasSupport() {
                    Section(header: Text("In Orario Pro")) {
                        Button {
                            Haptics.play(.light)
                            showPaywallSheet = true
                        } label: {
                            HStack(spacing: 12) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(
                                            LinearGradient(
                                                colors: [.blue, .indigo],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .frame(width: 38, height: 38)
                                    Image(systemName: "sparkles")
                                        .font(.subheadline.bold())
                                        .foregroundColor(.white)
                                }

                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Passa a In Orario Pro")
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                    Text("IA su server, notifiche scioperi, 20 treni e Live Activities ogni minuto.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .multilineTextAlignment(.leading)
                                }

                                Spacer()

                                Text("Piani")
                                    .font(.caption.bold())
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color.blue.opacity(0.12))
                                    .foregroundColor(.blue)
                                    .clipShape(Capsule())
                            }
                            .padding(.vertical, 4)
                        }

                        Button {
                            Task {
                                await tipManager.restorePurchases()
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Spacer()
                                if tipManager.isRestoringPurchases {
                                    ProgressView()
                                        .controlSize(.small)
                                }
                                Text("Ripristina Acquisti")
                                    .font(.subheadline)
                                    .foregroundColor(.blue)
                                Spacer()
                            }
                        }
                        .disabled(tipManager.isRestoringPurchases)
                        .padding(.vertical, 2)
                    }
                }

                Section(header: Text("Generali")) {
                    if !highlightRegionSelector {
                        HStack {
                            Label("Regione", systemImage: "globe")
                                .foregroundColor(.blue)
                                .font(.headline)
                            Spacer()
                            Picker("", selection: $manager.strikeRegion) {
                                Text("Nazionale / Tutte").tag("Tutte")
                                ForEach(italianRegions, id: \.self) { region in
                                    Text(region).tag(region)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                        .onChange(of: manager.strikeRegion) { _, _ in
                            manager.saveFavorites()
                        }
                    }

                    NavigationLink(destination: CommuteSetupView()) {
                        HStack(spacing: 10) {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Abitudini di viaggio")
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                    if !commuteManager.origins.isEmpty || !commuteManager.destinations.isEmpty {
                                        let homeSummary = commuteManager.origins.isEmpty ? "Casa non impostata" : formatCityOrStationSummary(commuteManager.origins)
                                        let workSummary = commuteManager.destinations.isEmpty ? "Lavoro non impostato" : formatCityOrStationSummary(commuteManager.destinations)
                                        Text("\(homeSummary) ↔ \(workSummary)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    } else {
                                        Text("Imposta Casa, Lavoro e orari per viaggi e filtri")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                            } icon: {
                                Image(systemName: "clock.arrow.2.circlepath")
                                    .foregroundColor(.pink)
                            }
                        }
                    }

                    NavigationLink(destination: CustomizeHubView()) {
                        Label("Personalizza", systemImage: "slider.horizontal.3")
                            .foregroundColor(.blue)
                            .font(.headline)
                    }
                }

                Section(header: Text("Suggerimenti e IA")) {
                    NavigationLink(destination: AISettingsView()) {
                        HStack(spacing: 8) {
                            Label("Assistente IA", systemImage: "brain.head.profile")
                                .foregroundColor(.indigo)
                                .font(.headline)
                            BetaBadgeView()
                        }
                    }
                    
                    NavigationLink(destination: SmartSuggestionsSettingsView()) {
                        Label("Suggerimenti personalizzati", systemImage: "sparkles")
                            .foregroundColor(.purple)
                            .font(.headline)
                    }
                }
                
                Section(header: Text("FAQ e supporto")) {
                    NavigationLink(destination: FAQView()) {
                        Label("Domande Frequenti", systemImage: "questionmark.circle.fill")
                            .foregroundColor(.blue)
                            .font(.headline)
                    }
                    
                    Button {
                        Haptics.play(.medium)
                        showFeedbackSheet = true
                    } label: {
                        Label("Segnala Bug o Feedback", systemImage: "ladybug.fill")
                            .foregroundColor(.red)
                            .font(.headline)
                    }
                    
                    NavigationLink(destination: AboutProjectView()) {
                        Label("Il Progetto In Orario", systemImage: "heart.fill")
                            .foregroundColor(.pink)
                            .font(.headline)
                    }
                }
                
                if manager.hasSupport() {
                    Section(header: Text("In Orario Pro")) {
                        HStack(spacing: 12) {
                            Image(systemName: "crown.fill")
                                .font(.title2)
                                .foregroundColor(.yellow)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(supporterRoleTitle)
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                Text("Tutte le funzionalità avanzate sono sbloccate.")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 4)

                        Button {
                            showPaywallSheet = true
                        } label: {
                            Label("Dettagli Piano e Termini", systemImage: "doc.text.fill")
                                .foregroundColor(.blue)
                        }

                        if tipManager.activeProductType == .yearly {
                            Button {
                                showManageSubscriptions = true
                            } label: {
                                Label("Gestisci Abbonamento", systemImage: "gearshape.fill")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                }

                if updateManager.isUpdateAvailable {
                    Section {
                        Button {
                            updateManager.openAppStore()
                        } label: {
                            HStack {
                                Label("Aggiorna a v\(updateManager.storeVersion)", systemImage: "arrow.down.app.fill")
                                    .foregroundColor(.blue)
                                    .fontWeight(.semibold)
                                Spacer()
                                Text("Aggiorna")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(Color.blue)
                                    .foregroundColor(.white)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }
                

                
                Section(
                    header: Text("Metro Milano Beta"),
                    footer: Text("Funzionalità beta in fase prematura e sperimentale. È disattivata di default: attivala solo se vuoi provarla, tenendo presente che orari e informazioni mostrati potrebbero non essere affidabili.")
                ) {
                    Toggle(isOn: $metroMilanoBetaEnabled) {
                        Label {
                            Text("Abilita Metro Milano Beta")
                                .font(.headline)
                        } icon: {
                            Image(systemName: "tram.fill")
                                .foregroundColor(.red)
                        }
                    }
                    .onChange(of: metroMilanoBetaEnabled) { _, _ in
                        Haptics.play(.light)
                    }
                }

                Section(footer:
                    HStack {
                        Spacer()
                        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
                        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
                        Text("In Orario v\(version) (\(build))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.top, 8)
                ) {
                    EmptyView()
                }
                
            }
            .onAppear {
                if highlightRegionSelector {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            scrollProxy.scrollTo("region_selector_top", anchor: .top)
                        }
                    }
                    tryDetectGPSRegion()
                }
            }
            .onChange(of: highlightRegionSelector) { _, highlighted in
                if highlighted {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            scrollProxy.scrollTo("region_selector_top", anchor: .top)
                        }
                    }
                    tryDetectGPSRegion()
                }
            }
            }
            .navigationTitle("Impostazioni")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Chiudi") {
                        dismiss()
                    }.fontWeight(.bold)
                }
            }
            .task {
                await tipManager.fetchProducts()
            }
            .sheet(isPresented: $showPaywallSheet) {
                SupportPaywallSheet()
                    .environmentObject(manager)
            }
            .sheet(isPresented: $showFeedbackSheet) {
                FeedbackFormView()
                    .environmentObject(manager)
            }
            .manageSubscriptionsSheet(
                isPresented: $showManageSubscriptions,
                subscriptionGroupID: tipManager.activeSubscriptionGroupID
            )
            .alert("Piano Attivato", isPresented: Binding(
                get: { tipManager.purchaseState == .success },
                set: { if !$0 { tipManager.resetState() } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Il tuo piano In Orario Pro è attivo e tutte le funzionalità avanzate sono ora sbloccate.")
            }
            .alert("Ripristino Acquisti", isPresented: Binding(
                get: { tipManager.restoreOutcome != nil },
                set: { if !$0 { tipManager.restoreOutcome = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                if tipManager.restoreOutcome == .restored {
                    Text("I tuoi acquisti precedenti sono stati ripristinati con successo.")
                } else {
                    Text("Nessun acquisto precedente da ripristinare per questo account Apple.")
                }
            }
            .alert("Errore", isPresented: Binding(
                get: {
                    if case .error = tipManager.purchaseState { return true }
                    return false
                },
                set: { if !$0 { tipManager.resetState() } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                if case .error(let msg) = tipManager.purchaseState {
                    Text(msg)
                }
            }
        }
    }
    
    private var prominentRegionSelectorSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [.blue, .teal],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 44, height: 44)
                        Image(systemName: "globe.europe.africa.fill")
                            .font(.title3.bold())
                            .foregroundColor(.white)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Seleziona la tua regione")
                            .font(.title3.bold())
                            .foregroundColor(.primary)
                        Text("Scegli la regione in cui viaggi di più per ricevere solo scioperi, avvisi e notizie ferroviarie rilevanti per te.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Menu {
                    Button {
                        selectHighlightedRegion("Tutte")
                    } label: {
                        HStack {
                            Text("🇮🇹 Nazionale / Tutte")
                            if manager.strikeRegion == "Tutte" {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    Divider()
                    ForEach(italianRegions, id: \.self) { region in
                        Button {
                            selectHighlightedRegion(region)
                        } label: {
                            HStack {
                                Text(region)
                                if manager.strikeRegion == region {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.headline)
                        Text(manager.strikeRegion == "Tutte" ? "🇮🇹 Nazionale / Tutte" : manager.strikeRegion)
                            .font(.headline.bold())
                            .lineLimit(1)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.subheadline.bold())
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 52)
                    .background(
                        LinearGradient(
                            colors: [.blue, .indigo],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .shadow(color: Color.blue.opacity(0.25), radius: 6, x: 0, y: 3)
                }

                if let detected = detectedGPSRegion, detected != manager.strikeRegion {
                    Button {
                        selectHighlightedRegion(detected)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "location.fill")
                                .font(.caption.bold())
                            Text("Usa regione rilevata: \(detected)")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Image(systemName: "arrow.right.circle.fill")
                                .font(.subheadline)
                        }
                        .foregroundColor(.green)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color.green.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }

                if manager.strikeRegion != "Tutte" || didSelectRegionFromHighlight {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text(manager.strikeRegion == "Tutte"
                             ? "Preferenza salvata: Nazionale / Tutte."
                             : "Regione impostata: \(manager.strikeRegion). Ora riceverai avvisi mirati!")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.green.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
            .padding(.vertical, 6)
        }
    }

    private func selectHighlightedRegion(_ region: String) {
        manager.strikeRegion = region
        manager.saveFavorites()
        didSelectRegionFromHighlight = (region != "Tutte")
        Haptics.notify(.success)
    }

    private func tryDetectGPSRegion() {
        let auth = locationManager.authorizationStatus
        guard auth == .authorizedWhenInUse || auth == .authorizedAlways else { return }

        let regionsList = italianRegions
        Task {
            let loc: CLLocation?
            if let existing = locationManager.userLocation {
                loc = existing
            } else {
                loc = await locationManager.getCurrentLocation(maxAge: 300, timeout: 3)
            }
            guard let loc else { return }
            CLGeocoder().reverseGeocodeLocation(loc) { placemarks, _ in
                guard let admin = placemarks?.first?.administrativeArea else { return }
                let matched = regionsList.first {
                    $0.localizedCaseInsensitiveCompare(admin) == .orderedSame ||
                    admin.localizedCaseInsensitiveContains($0) ||
                    $0.localizedCaseInsensitiveContains(admin)
                }
                if let matched {
                    DispatchQueue.main.async {
                        self.detectedGPSRegion = matched
                    }
                }
            }
        }
    }

    private var supporterRoleTitle: LocalizedStringKey {
        switch tipManager.activeProductType {
        case .yearly:
            return "In Orario Pro · Piano Annuale"
        case .lifetime, .legacy, .none:
            return "In Orario Pro · Piano a Vita"
        }
    }
}

// MARK: - AboutProjectView

struct AboutProjectView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Ho creato In Orario per rendere un po’ più semplice la vita di chi prende il treno ogni giorno. L’app mostra le stesse informazioni presenti sui tabelloni in stazione, aggiornate in tempo reale.")
                    .font(.body)
                    .foregroundColor(.primary)
                    .lineSpacing(4)
                
                Text("La sviluppo e la mantengo da solo, nel mio tempo libero. Ho scelto di offrirla gratuitamente e senza pubblicità, ma mantenerla attiva comporta alcuni costi.")
                    .font(.body)
                    .foregroundColor(.primary)
                    .lineSpacing(4)
                
                Text("Se In Orario ti aiuta a partire più sereno, a evitare attese inutili o semplicemente a viaggiare con maggiore tranquillità, puoi attivare In Orario Pro con un abbonamento annuale o un acquisto a vita per sbloccare tutte le funzionalità avanzate.")
                    .font(.body)
                    .foregroundColor(.primary)
                    .lineSpacing(4)
                
                Text("Grazie davvero ❤️")
                    .font(.headline)
                    .foregroundColor(.primary)
                    .padding(.top, 4)
                
                Divider()
                    .padding(.vertical, 8)
                
                VStack(spacing: 12) {
                    Link(destination: URL(string: "https://apps.apple.com/app/id6773419855?action=write-review")!) {
                        HStack(spacing: 12) {
                            Image(systemName: "star.bubble.fill")
                                .foregroundColor(.yellow)
                                .font(.title3)
                            Text("Valuta In Orario su App Store")
                                .font(.body.weight(.medium))
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(12)
                    }
                    
                    ShareLink(
                        item: URL(string: "https://apps.apple.com/app/id6773419855")!,
                        subject: Text("In Orario"),
                        message: Text("Prova In Orario: l'app per seguire i treni e i ritardi in tutta Italia!")
                    ) {
                        HStack(spacing: 12) {
                            Image(systemName: "square.and.arrow.up.fill")
                                .foregroundColor(.blue)
                                .font(.title3)
                            Text("Consiglia In Orario a un amico")
                                .font(.body.weight(.medium))
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(12)
                    }
                }
            }
            .padding(20)
        }
        .navigationTitle("Il Progetto In Orario")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct FeedbackFormView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var manager: TrainManager
    @State private var category: String
    @State private var message: String
    @State private var contact = ""
    @State private var includeDiagnostics: Bool
    @State private var showLogsSheet = false
    @State private var isSending = false
    @State private var showSuccessAlert = false
    @State private var showErrorAlert = false

    init(
        initialCategory: String = "Bug",
        initialMessage: String = "",
        defaultIncludeDiagnostics: Bool = true
    ) {
        _category = State(initialValue: initialCategory)
        _message = State(initialValue: initialMessage)
        _includeDiagnostics = State(initialValue: defaultIncludeDiagnostics)
    }
    
    private var effectiveAPNsToken: String {
        [manager.apnsToken, UserDefaults.standard.string(forKey: "apnsTokenKey_v1")]
            .compactMap { $0 }
            .first(where: { !$0.isEmpty }) ?? ""
    }

    private var isPushActive: Bool {
        return !effectiveAPNsToken.isEmpty && manager.remoteNotificationsEnabled
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Tipo di Segnalazione")) {
                    Picker("Categoria", selection: $category) {
                        Text("Bug 🐛").tag("Bug")
                        Text("Suggerimento 💡").tag("Suggestion")
                        Text("Altro 💬").tag("Other")
                    }
                    .pickerStyle(.segmented)
                }
                
                Section(header: Text("Dettagli")) {
                    TextEditor(text: $message)
                        .frame(height: 140)
                        .overlay(
                            Group {
                                if message.isEmpty {
                                    Text("Descrivi qui cosa è successo o il tuo suggerimento...")
                                        .foregroundColor(.gray.opacity(0.5))
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 8)
                                        .allowsHitTesting(false)
                                }
                            },
                            alignment: .topLeading
                        )
                }
                
                Section(header: Text("Contatto & Notifiche"), footer: Text("Inserisci un'email opzionale se desideri essere ricontattato via posta, oppure attiva le notifiche push per ricevere la risposta direttamente qui sull'app.")) {
                    TextField("Tua email (opzionale)", text: $contact)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    
                    if isPushActive {
                        HStack(spacing: 10) {
                            Image(systemName: "bell.badge.fill")
                                .foregroundColor(.green)
                            Text("Notifiche push attive: lo sviluppatore potrà inviarti una risposta direttamente sul tuo dispositivo.")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 2)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Image(systemName: "bell.badge")
                                    .foregroundColor(.orange)
                                Text("Vuoi ricevere una risposta direttamente qui?")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                            }
                            
                            Text("Abilitando le notifiche push, lo sviluppatore potrà notificarti quando il problema sarà risolto.")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                            
                            Button(action: requestPushPermission) {
                                Label("Abilita Notifiche Push", systemImage: "bell.fill")
                                    .font(.subheadline.bold())
                                    .foregroundColor(.blue)
                            }
                            .buttonStyle(.borderless)
                            .padding(.top, 2)
                        }
                        .padding(.vertical, 4)
                    }
                }
                
                Section(header: Text("Diagnostica e Risoluzione Problemi"), footer: Text("I dati diagnostici includono modello dispositivo, versione iOS e gli ultimi errori o timeout rilevati dall'app. Non contengono dati personali né credenziali.")) {
                    Toggle("Allega diagnostica e log recenti", isOn: $includeDiagnostics)
                    
                    if includeDiagnostics {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Dispositivo: \(manager.getDeviceModelName()) • iOS \(UIDevice.current.systemVersion)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Button(action: { showLogsSheet = true }) {
                                HStack {
                                    Image(systemName: "doc.text.magnifyingglass")
                                    Text("Visualizza dettagli e log che verranno inviati")
                                }
                                .font(.caption.bold())
                                .foregroundColor(.blue)
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(.vertical, 2)
                    }
                }
                
                Section {
                    Button(action: sendFeedback) {
                        if isSending {
                            HStack {
                                Spacer()
                                ProgressView()
                                Spacer()
                            }
                        } else {
                            Text("Invia Segnalazione")
                                .bold()
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
                }
            }
            .navigationTitle("Segnala Bug o Feedback")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Annulla") {
                        dismiss()
                    }
                }
            }
            .alert("Grazie mille! ❤️", isPresented: $showSuccessAlert) {
                Button("OK") {
                    dismiss()
                }
            } message: {
                Text(isPushActive ? "La tua segnalazione è stata inviata con successo. Riceverai un riscontro non appena lo sviluppatore risponderà!" : "La tua segnalazione è stata inviata con successo direttamente agli sviluppatori.")
            }
            .alert("Errore di Invio", isPresented: $showErrorAlert) {
                Button("Riprova", role: .cancel) {}
            } message: {
                Text("Non è stato possibile inviare il feedback. Verifica la tua connessione internet o riprova più tardi.")
            }
            .sheet(isPresented: $showLogsSheet) {
                DiagnosticLogsPreviewSheet(
                    deviceInfo: "\(manager.getDeviceModelName()) • iOS \(UIDevice.current.systemVersion) • App v\(AppUpdateManager.shared.currentVersion) (\(AppUpdateManager.shared.currentBuild))",
                    logs: AppLogger.getRecentLogs()
                )
            }
        }
    }
    
    private func requestPushPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            DispatchQueue.main.async {
                if granted {
                    self.manager.remoteNotificationsEnabled = true
                    UIApplication.shared.registerForRemoteNotifications()
                    self.manager.syncRemoteNotifications()
                    Haptics.notify(.success)
                } else {
                    Haptics.notify(.warning)
                }
            }
        }
    }
    
    private func sendFeedback() {
        guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isSending = true
        Haptics.play(.medium)
        
        let token = effectiveAPNsToken
        let deviceID = DeviceIdentityManager.shared.deviceID
        let payload: [String: Any] = [
            "category": category,
            "message": message,
            "contact": contact,
            "email": contact,
            "device_id": deviceID,
            "device_token": token,
            "device_model": manager.getDeviceModelName(),
            "os_version": UIDevice.current.systemVersion,
            "app_version": AppUpdateManager.shared.currentVersion,
            "app_build": AppUpdateManager.shared.currentBuild,
            "notifications_enabled": manager.remoteNotificationsEnabled,
            "logs": includeDiagnostics ? AppLogger.getRecentLogs() : ""
        ]
        
        guard let url = URL(string: "https://gestioneinorario.toreroclub.com/feedback") else {
            isSending = false
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(deviceID, forHTTPHeaderField: "X-Device-ID")
        if !token.isEmpty {
            request.setValue(token, forHTTPHeaderField: "X-Device-Token")
        }
        request.timeoutInterval = 15.0
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        } catch {
            isSending = false
            showErrorAlert = true
            return
        }
        
        Task {
            do {
                let (_, response) = try await NetworkService.shared.post(request: request)
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    isSending = false
                    showSuccessAlert = true
                    Haptics.notify(.success)
                } else {
                    isSending = false
                    showErrorAlert = true
                    Haptics.notify(.error)
                }
            } catch {
                isSending = false
                showErrorAlert = true
                Haptics.notify(.error)
            }
        }
    }
}

struct DiagnosticLogsPreviewSheet: View {
    @Environment(\.dismiss) var dismiss
    let deviceInfo: String
    let logs: String
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Dispositivo")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .textCase(.uppercase)
                        Text(deviceInfo)
                            .font(.subheadline)
                            .bold()
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(UIColor.secondarySystemGroupedBackground))
                    .cornerRadius(12)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Log ed Errori Recenti")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .textCase(.uppercase)
                        
                        Text(logs)
                            .font(.system(size: 11.5, design: .monospaced))
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(Color(UIColor.secondarySystemGroupedBackground))
                            .cornerRadius(12)
                    }
                    
                    Text("Nota: questi dati sono anonimi e non contengono token APNs, header di autenticazione o informazioni di navigazione personale.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 4)
                }
                .padding()
            }
            .background(Color(UIColor.systemGroupedBackground))
            .navigationTitle("Dati Diagnostici Allegati")
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

struct LaunchTabPickerRow: View {
    @AppStorage(MainTab.launchStorageKey) private var preferredLaunchTab: String = MainTab.home.rawValue

    var body: some View {
        HStack {
            Label("Schermata iniziale", systemImage: "rectangle.portrait.on.rectangle.portrait")
                .foregroundColor(.indigo)
                .font(.headline)
            Spacer()
            Picker("", selection: $preferredLaunchTab) {
                ForEach(MainTab.barOrder) { tab in
                    Text(tab.title).tag(tab.rawValue)
                }
            }
            .pickerStyle(.menu)
        }
    }
}

struct CustomizeHubView: View {
    var body: some View {
        List {
            Section(header: Text("Opzioni di personalizzazione"), footer: Text("Scegli le sezioni e il numero di elementi nella Home, nascondi le fermate che non ti servono sulle tue linee e configura i widget Stazioni e Treni.")) {
                NavigationLink(destination: CustomizeDashboardView()) {
                    Label("Personalizza Home", systemImage: "house.fill")
                        .foregroundColor(.blue)
                        .font(.headline)
                }
                
                NavigationLink(destination: CustomizeLinesView()) {
                    Label("Personalizza Linee", systemImage: "point.topleft.down.curvedto.point.bottomright.up.fill")
                        .foregroundColor(.orange)
                        .font(.headline)
                }
                
                NavigationLink(destination: CustomizeWidgetView()) {
                    Label("Personalizza Widget", systemImage: "rectangle.3.group.fill")
                        .foregroundColor(.purple)
                        .font(.headline)
                }
            }

            Section(header: Text("Avvio Applicazione"), footer: Text("Seleziona la sezione che vuoi vedere subito all'apertura di In Orario. L'ordine nella barra inferiore resta invariato.")) {
                LaunchTabPickerRow()
            }
        }
        .navigationTitle("Personalizza")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct CustomizeDashboardView: View {
    @EnvironmentObject var manager: TrainManager

    private func sectionIcon(for section: AppSection) -> (symbol: String, color: Color) {
        switch section {
        case .nearby:
            return ("location.fill", .blue)
        case .myStations:
            return ("building.2.crop.circle.fill", .blue)
        case .favoriteTrains:
            return ("tram.fill", .blue)
        case .favoriteRoutes:
            return ("map.fill", .green)
        case .passante:
            return ("point.topleft.down.curvedto.point.bottomright.up.fill", .orange)
        }
    }

    private func supportsMaxItems(_ section: AppSection) -> Bool {
        section != .nearby
    }

    var body: some View {
        List {
            Section(
                header: Text("Sezioni Dashboard"),
                footer: Text("Trascina le sezioni per riordinarle e usa gli interruttori per mostrarle o nasconderle nella Home. Per ogni sezione puoi scegliere quanti elementi mostrare (da 1 a 10): gli altri restano sempre disponibili nelle rispettive schede, mentre in Home i contenuti vengono ordinati in modo intelligente.")
            ) {
                ForEach(manager.sectionOrder, id: \.self) { section in
                    let icon = sectionIcon(for: section)
                    let isVisible = manager.isSectionVisible(section)

                    VStack(alignment: .leading, spacing: 10) {
                        Toggle(isOn: Binding(
                            get: { isVisible },
                            set: { newValue in
                                Haptics.play(.medium)
                                withAnimation(.snappy(duration: 0.22)) {
                                    manager.setSectionVisible(section, newValue)
                                }
                            }
                        )) {
                            HStack(spacing: 10) {
                                Image(systemName: icon.symbol)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(isVisible ? icon.color : .secondary)
                                    .frame(width: 22)
                                Text(section.displayTitle)
                                    .font(.headline)
                                    .foregroundColor(isVisible ? .primary : .secondary)
                            }
                        }

                        if isVisible && supportsMaxItems(section) {
                            HStack {
                                Text("Elementi da mostrare")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Menu {
                                    ForEach(TrainManager.homeSectionMaxItemsRange, id: \.self) { count in
                                        Button {
                                            Haptics.play(.light)
                                            manager.setHomeMaxItems(count, for: section)
                                        } label: {
                                            let labelText = count == 1 ? "1 elemento" : "\(count) elementi"
                                            if manager.homeMaxItems(for: section) == count {
                                                Label(labelText, systemImage: "checkmark")
                                            } else {
                                                Text(labelText)
                                            }
                                        }
                                    }
                                } label: {
                                    let current = manager.homeMaxItems(for: section)
                                    HStack(spacing: 4) {
                                        Text("\(current)")
                                            .font(.subheadline.weight(.semibold).monospacedDigit())
                                        Image(systemName: "chevron.up.chevron.down")
                                            .font(.caption2.weight(.semibold))
                                    }
                                    .foregroundColor(.blue)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(Color.blue.opacity(0.12))
                                    .clipShape(Capsule())
                                }
                                .buttonStyle(.borderless)
                            }
                            .padding(.leading, 32)
                        }
                    }
                    .padding(.vertical, 6)
                }
                .onMove { from, to in
                    Haptics.play(.medium)
                    manager.sectionOrder.move(fromOffsets: from, toOffset: to)
                    manager.saveSectionOrder()
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Personalizza Home")
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.editMode, .constant(.active))
    }
}

struct CustomizeLinesView: View {
    @EnvironmentObject var manager: TrainManager
    @EnvironmentObject var passanteManager: PassanteManager
    @EnvironmentObject var locationManager: LocationManager
    @EnvironmentObject var personalLinesManager: PersonalLinesManager

    @State private var selectedLineForStops: PersonalRailwayLine? = nil
    @State private var showManageLinesSheet = false

    var body: some View {
        List {
            if personalLinesManager.savedLines.isEmpty {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "point.topleft.down.curvedto.point.bottomright.up.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.orange)
                        Text("Nessuna linea salvata")
                            .font(.headline)
                        Text("Aggiungi le tue linee preferite per personalizzare le fermate visibili e monitorare le partenze.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        Button {
                            showManageLinesSheet = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "plus")
                                Text("Aggiungi linee")
                            }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
            } else {
                Section(
                    header: Text("Le tue linee"),
                    footer: Text("Tocca una linea per scegliere quali fermate mostrare o nascondere nello schema della linea e nei suggerimenti.")
                ) {
                    ForEach(personalLinesManager.savedLines) { line in
                        let hiddenCount = line.stations.filter { st in
                            personalLinesManager.isStationHidden(lineID: line.id, stationName: st)
                                || (passanteManager.hiddenSuburbanStations[line.id]?.contains(st) ?? false)
                        }.count
                        let visibleCount = max(0, line.stations.count - hiddenCount)

                        Button {
                            Haptics.play(.light)
                            selectedLineForStops = line
                        } label: {
                            HStack(spacing: 12) {
                                LineCodeBadge(line: line)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(line.name)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundColor(.primary)
                                        .lineLimit(1)
                                    Text(hiddenCount == 0
                                         ? "Tutte le \(line.stations.count) fermate visibili"
                                         : "\(visibleCount) di \(line.stations.count) fermate visibili · \(hiddenCount) nascoste")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(Color(.tertiaryLabel))
                            }
                            .padding(.vertical, 3)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }

                Section {
                    Button {
                        Haptics.play(.light)
                        showManageLinesSheet = true
                    } label: {
                        Label("Aggiungi o rimuovi linee", systemImage: "plus.circle.fill")
                            .foregroundColor(.orange)
                            .font(.subheadline.weight(.semibold))
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Personalizza Linee")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedLineForStops) { line in
            LineStationVisibilitySheet(line: line)
                .environmentObject(personalLinesManager)
                .environmentObject(passanteManager)
        }
        .sheet(isPresented: $showManageLinesSheet) {
            LineManagementSheet(news: [])
                .environmentObject(manager)
                .environmentObject(passanteManager)
                .environmentObject(locationManager)
                .environmentObject(personalLinesManager)
        }
    }
}

struct CustomizeWidgetView: View {
    @EnvironmentObject var manager: TrainManager
    
    private var groupDefaults: UserDefaults? {
        UserDefaults(suiteName: "group.carlo.InOrario")
    }
    
    @State private var excludedStationKeys: Set<String> = []
    @State private var excludedTrainNumbers: Set<String> = []
    
    var body: some View {
        List {
            Section(
                header: Label("Widget Stazioni", systemImage: "building.2.fill"),
                footer: Text("Scegli quali stazioni preferite mostrare nel widget Tabellone Stazioni. Le stazioni disattivate vengono saltate automaticamente.")
            ) {
                if manager.myStations.isEmpty {
                    Text("Nessuna stazione salvata tra i preferiti.")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(manager.myStations) { station in
                        let key = TrainManager.widgetStationExclusionKey(for: station)
                        let isIncluded = !excludedStationKeys.contains(key)
                        Toggle(isOn: Binding(
                            get: { isIncluded },
                            set: { newValue in
                                Haptics.play(.medium)
                                if newValue {
                                    excludedStationKeys.remove(key)
                                } else {
                                    excludedStationKeys.insert(key)
                                }
                                syncStationExclusions()
                                WidgetCenter.shared.reloadAllTimelines()
                            }
                        )) {
                            HStack(spacing: 12) {
                                Image(systemName: "building.2.crop.circle.fill")
                                    .foregroundColor(isIncluded ? .blue : .secondary)
                                    .font(.title3)
                                Text(station.formattedName)
                                    .font(.headline)
                                    .foregroundColor(isIncluded ? .primary : .secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }

            Section(
                header: Label("Widget Treni", systemImage: "tram.fill"),
                footer: Text("Il widget Treni mostra fino a 3 treni alla volta seguendo automaticamente l'ordine intelligente della schermata Treni (prima i treni in viaggio e le prossime partenze). Se disattivi un treno, il widget mostra automaticamente quello successivo.")
            ) {
                if manager.favoriteTrains.isEmpty {
                    Text("Nessun treno salvato tra i preferiti.")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(TrainManager.sortedTrainsByDeparture(manager.favoriteTrains, snapshots: manager.liveTrainSnapshots)) { train in
                        let isIncluded = !excludedTrainNumbers.contains(train.number) && (train.showInWidget ?? true)
                        Toggle(isOn: Binding(
                            get: { isIncluded },
                            set: { newValue in
                                Haptics.play(.medium)
                                if newValue {
                                    excludedTrainNumbers.remove(train.number)
                                } else {
                                    excludedTrainNumbers.insert(train.number)
                                }
                                syncTrainExclusions()
                                if let idx = manager.favoriteTrains.firstIndex(where: { $0.id == train.id }) {
                                    manager.favoriteTrains[idx].showInWidget = newValue
                                    manager.saveFavorites()
                                }
                                WidgetCenter.shared.reloadAllTimelines()
                            }
                        )) {
                            HStack(spacing: 12) {
                                Image(systemName: "tram.fill")
                                    .foregroundColor(isIncluded ? .blue : .secondary)
                                    .font(.title3)
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack {
                                        let dummy = manager.createDummyTrain(from: train)
                                        Text("\(dummy.category) \(train.number)")
                                            .font(.headline)
                                            .foregroundColor(isIncluded ? .primary : .secondary)
                                        if let dep = train.departureTime, !dep.isEmpty, dep != "--:--" {
                                            Text("• \(dep)")
                                                .font(.caption.bold())
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    Text(train.description)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Personalizza Widget")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadExclusions()
        }
    }
    
    private func loadExclusions() {
        if let rawData = groupDefaults?.data(forKey: "excludedWidgetStationKeys_v1"),
           let set = try? JSONDecoder().decode(Set<String>.self, from: rawData) {
            excludedStationKeys = set
        } else if let arr = groupDefaults?.stringArray(forKey: "excludedWidgetStationKeys_v1") {
            excludedStationKeys = Set(arr)
        } else {
            excludedStationKeys = []
        }

        if let rawData = groupDefaults?.data(forKey: "excludedWidgetTrainNumbers_v1"),
           let set = try? JSONDecoder().decode(Set<String>.self, from: rawData) {
            excludedTrainNumbers = set
        } else if let arr = groupDefaults?.stringArray(forKey: "excludedWidgetTrainNumbers_v1") {
            excludedTrainNumbers = Set(arr)
        } else {
            excludedTrainNumbers = []
        }
        for train in manager.favoriteTrains where train.showInWidget == false {
            excludedTrainNumbers.insert(train.number)
        }
    }

    private func syncStationExclusions() {
        groupDefaults?.set(Array(excludedStationKeys), forKey: "excludedWidgetStationKeys_v1")
    }
    
    private func syncTrainExclusions() {
        groupDefaults?.set(Array(excludedTrainNumbers), forKey: "excludedWidgetTrainNumbers_v1")
    }
}

struct NotificationsSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var manager: TrainManager
    @EnvironmentObject var passanteManager: PassanteManager
    @ObservedObject private var commuteManager = SupporterCommuteManager.shared
    var showCloseButton: Bool = false
    @State private var selectedTrainForConfig: SavedTrain? = nil
    @State private var showPaywallSheet = false
    @State private var showScheduledSummaryConfig = false

    var body: some View {
        List {
            // 1. Interruttore master globale: spegnendolo si spengono TUTTE le notifiche dell'app sul server
            Section(footer: Text("Disattivando questo interruttore sospendi tutte le notifiche dell'app senza perdere le preferenze configurate.")) {
                Toggle(isOn: Binding(
                    get: { manager.remoteNotificationsEnabled },
                    set: { newValue in
                        Haptics.play(.medium)
                        if newValue {
                            manager.requestNotificationPermission()
                        } else {
                            manager.disableNotifications()
                        }
                    }
                )) {
                    Label {
                        Text("Abilita Notifiche")
                            .foregroundColor(.primary)
                            .font(.headline)
                    } icon: {
                        Image(systemName: "bell.fill")
                            .foregroundColor(.orange)
                    }
                }
            }

            // 2. Categorie di notifica (Treni, Scioperi e News, Riepilogo programmato)
            Section {
                Toggle(isOn: Binding(
                    get: { manager.remoteNotificationsEnabled && manager.trainNotificationsEnabled },
                    set: { newValue in
                        Haptics.play(.light)
                        manager.trainNotificationsEnabled = newValue
                    }
                )) {
                    Label {
                        Text("Treni")
                            .foregroundColor(manager.remoteNotificationsEnabled ? .primary : .secondary)
                            .font(.subheadline.weight(.medium))
                    } icon: {
                        Image(systemName: "tram.fill")
                            .foregroundColor(manager.remoteNotificationsEnabled ? .orange : .secondary)
                    }
                }
                .disabled(!manager.remoteNotificationsEnabled)

                Toggle(isOn: Binding(
                    get: { manager.remoteNotificationsEnabled && manager.strikeNotificationsEnabled },
                    set: { newValue in
                        Haptics.play(.light)
                        manager.strikeNotificationsEnabled = newValue
                    }
                )) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Scioperi e News")
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(manager.remoteNotificationsEnabled ? .primary : .secondary)
                            Text("Scioperi, infomobilità e lavori")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(manager.remoteNotificationsEnabled ? .orange : .secondary)
                    }
                }
                .disabled(!manager.remoteNotificationsEnabled)

                let canUseSummary = manager.remoteNotificationsEnabled && manager.hasSupport()
                HStack(spacing: 10) {
                    if manager.hasSupport() {
                        Button {
                            Haptics.play(.light)
                            showScheduledSummaryConfig = true
                        } label: {
                            HStack(spacing: 10) {
                                Label {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Riepilogo programmato")
                                            .font(.subheadline.weight(.medium))
                                            .foregroundColor(canUseSummary ? .primary : .secondary)
                                            .lineLimit(1)
                                        Text("Tocca per personalizzare")
                                            .font(.caption.weight(.medium))
                                            .foregroundColor(canUseSummary ? .blue : .secondary)
                                    }
                                } icon: {
                                    Image(systemName: "calendar.badge.clock")
                                        .foregroundColor(canUseSummary ? .orange : .secondary)
                                }
                                Spacer(minLength: 4)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.borderless)
                        .disabled(!canUseSummary)
                    } else {
                        HStack(spacing: 10) {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text("Riepilogo programmato")
                                            .font(.subheadline.weight(.medium))
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                        HStack(spacing: 3) {
                                            Text("Pro")
                                                .font(.caption2.bold())
                                            Image(systemName: "lock.fill")
                                                .font(.caption2)
                                        }
                                        .foregroundColor(.secondary)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1)
                                        .background(Color(.tertiarySystemFill))
                                        .clipShape(Capsule())
                                    }
                                    Text("Disponibile con In Orario Pro")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            } icon: {
                                Image(systemName: "calendar.badge.clock")
                                    .foregroundColor(.secondary)
                            }
                            Spacer(minLength: 4)
                        }
                    }

                    Toggle("", isOn: Binding(
                        get: { canUseSummary && commuteManager.scheduledSummaryEnabled },
                        set: { newValue in
                            guard canUseSummary else { return }
                            Haptics.play(.light)
                            commuteManager.scheduledSummaryEnabled = newValue
                            Task {
                                await commuteManager.syncRoutineWithServer()
                            }
                        }
                    ))
                    .labelsHidden()
                    .disabled(!canUseSummary)
                }
                .saturation(manager.hasSupport() ? 1.0 : 0.0)
                .opacity(manager.hasSupport() ? 1.0 : 0.5)
                .disabled(!manager.hasSupport())
            }
            .opacity(manager.remoteNotificationsEnabled ? 1.0 : 0.55)

            // 3. Notifiche Treni Preferiti
            if manager.remoteNotificationsEnabled {
                Section(
                    header: Text("Notifiche Treni Preferiti"),
                    footer: Text(
                        manager.trainNotificationsEnabled
                        ? "Puoi attivare gratis le notifiche a un orario specifico fino a 10 treni. Con In Orario Pro hai il monitoraggio continuo fino a 20 treni."
                        : "Le notifiche dei treni sono attualmente disattivate. Riattiva \"Treni\" in alto per riprendere il monitoraggio."
                    )
                ) {
                    if manager.favoriteTrains.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "star.slash.fill")
                                .font(.system(size: 32))
                                .foregroundColor(.secondary)
                                .padding(.top, 8)
                            Text("Nessun Treno Preferito")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            Text("Aggiungi i tuoi treni abituali ai preferiti per abilitare e configurare le notifiche personalizzate.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                                .padding(.bottom, 8)
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        ForEach(manager.favoriteTrains) { train in
                            Button {
                                Haptics.play(.medium)
                                selectedTrainForConfig = train
                            } label: {
                                HStack {
                                    Image(systemName: "tram.fill")
                                        .foregroundColor(train.isNotificationsPaused ? .secondary : .orange)
                                        .font(.subheadline)
                                    VStack(alignment: .leading, spacing: 4) {
                                        let dummy = manager.createDummyTrain(from: train)
                                        Text("\(dummy.category) \(train.number)")
                                            .font(.headline)
                                            .foregroundColor(.primary)

                                        let descParts = train.description.components(separatedBy: " - ")
                                        let origin = descParts.first ?? train.description
                                        let destination = descParts.count > 1 ? descParts[1] : ""
                                        Text(destination.isEmpty ? origin : "\(origin) → \(destination)")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }

                                    Spacer()

                                    let hasContinuous = manager.hasSupport() && (
                                        train.notifyDelay == true ||
                                        train.notifyDeparture == true ||
                                        train.notifyStationPass == true ||
                                        train.notifyPlatformChange == true
                                    )
                                    let hasScheduled = train.notifyScheduledTime == true
                                    HStack(spacing: 4) {
                                        if train.isNotificationsPaused && (hasContinuous || hasScheduled) {
                                            Label("In pausa", systemImage: "bell.slash.fill")
                                                .font(.caption2.bold())
                                                .foregroundColor(.secondary)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Color(.secondarySystemBackground))
                                                .cornerRadius(6)
                                        } else if hasContinuous {
                                            Text("Attive")
                                                .font(.caption2.bold())
                                                .foregroundColor(.green)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Color.green.opacity(0.12))
                                                .cornerRadius(6)
                                        } else if hasScheduled {
                                            let normalized = SharedFormatters.format24HourTimeString(train.scheduledNotificationTime ?? "")
                                            let timeLabel = normalized.isEmpty ? "Orario" : "🕒 \(normalized)"
                                            Text(timeLabel)
                                                .font(.caption2.bold())
                                                .foregroundColor(.orange)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Color.orange.opacity(0.14))
                                                .cornerRadius(6)
                                        } else {
                                            Text("Disattive")
                                                .font(.caption2.bold())
                                                .foregroundColor(.secondary)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Color(.secondarySystemBackground))
                                                .cornerRadius(6)
                                        }
                                        Image(systemName: "chevron.right")
                                            .font(.footnote)
                                            .foregroundColor(Color(.tertiaryLabel))
                                    }
                                }
                                .padding(.vertical, 4)
                                .opacity(manager.trainNotificationsEnabled ? 1.0 : 0.55)
                            }
                        }
                    }
                }
            }
        }
        .tint(.orange)
        .navigationTitle("Notifiche")
        .navigationBarTitleDisplayMode(.large)
        .navigationDestination(isPresented: $showScheduledSummaryConfig) {
            ScheduledSummaryConfigView()
                .environmentObject(manager)
        }
        .toolbar {
            if showCloseButton {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Chiudi") {
                        dismiss()
                    }
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                }
            }
        }
        .sheet(item: $selectedTrainForConfig) { train in
            if let index = manager.favoriteTrains.firstIndex(where: { $0.id == train.id }) {
                TrainNotificationConfigSheet(train: Binding(
                    get: { manager.favoriteTrains[index] },
                    set: { manager.favoriteTrains[index] = $0 }
                ))
            }
        }
        .sheet(isPresented: $showPaywallSheet) {
            SupportPaywallSheet()
                .environmentObject(manager)
        }
        .onAppear {
            Task {
                for train in manager.favoriteTrains {
                    if train.departureTime == nil || train.arrivalTime == nil {
                        await manager.enrichFavoriteTrainData(trainNumber: train.number)
                    }
                }
            }
        }
    }
}

struct ScheduledSummaryConfigView: View {
    @EnvironmentObject var manager: TrainManager
    @ObservedObject private var commuteManager = SupporterCommuteManager.shared
    @State private var showPaywallSheet = false
    @State private var isSummaryDaysExpanded = true

    private let summaryWeekdays: [(Int, String)] = [
        (1, "Lunedì"),
        (2, "Martedì"),
        (3, "Mercoledì"),
        (4, "Giovedì"),
        (5, "Venerdì"),
        (6, "Sabato"),
        (7, "Domenica")
    ]

    var body: some View {
        List {
            if !manager.hasSupport() {
                Section(footer: Text("Ricevi un punto situazione automatico sulla tua tratta abituale prima della tua fascia oraria di viaggio nei giorni scelti.")) {
                    Button {
                        Haptics.notify(.warning)
                        showPaywallSheet = true
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                Label("Riepilogo programmato", systemImage: "calendar.badge.clock")
                                    .foregroundColor(.orange)
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Text("Solo Pro")
                                    .font(.caption2.bold())
                                    .foregroundColor(.orange)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.orange.opacity(0.14))
                                    .cornerRadius(6)
                                Image(systemName: "lock.fill")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Text("Disponibile per gli utenti Pro. Tocca per attivare In Orario Pro.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                Section(footer: Text("Ricevi un punto situazione automatico sulla tua tratta abituale prima della tua fascia oraria di viaggio nei giorni scelti, basato sullo stato reale della linea e dei treni.")) {
                    Toggle(isOn: Binding(
                        get: { commuteManager.scheduledSummaryEnabled },
                        set: { newValue in
                            Haptics.play(.light)
                            commuteManager.scheduledSummaryEnabled = newValue
                            Task {
                                await commuteManager.syncRoutineWithServer()
                            }
                        }
                    )) {
                        Label("Abilita riepilogo programmato", systemImage: "calendar.badge.clock")
                            .foregroundColor(.orange)
                            .font(.subheadline.weight(.semibold))
                    }
                    .disabled(!manager.remoteNotificationsEnabled)
                }

                if !commuteManager.origins.isEmpty && !commuteManager.destinations.isEmpty {
                    Section("Configurazione") {
                        Button {
                            Haptics.play(.light)
                            withAnimation(.easeInOut(duration: 0.22)) {
                                isSummaryDaysExpanded.toggle()
                            }
                        } label: {
                            HStack {
                                Text("Avvisami")
                                    .foregroundColor(.primary)
                                Spacer()
                                Text(commuteManager.scheduledSummaryDaysSummaryText)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                Image(systemName: isSummaryDaysExpanded ? "chevron.up" : "chevron.down")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(!manager.remoteNotificationsEnabled || !commuteManager.scheduledSummaryEnabled)

                        if isSummaryDaysExpanded {
                            ForEach(summaryWeekdays, id: \.0) { dayIndex, dayName in
                                summaryDayRow(dayIndex: dayIndex, dayName: dayName)
                            }
                        }

                        Picker("Anticipo", selection: $commuteManager.scheduledSummaryLeadMinutes) {
                            Text("10 min prima").tag(10)
                            Text("15 min prima").tag(15)
                            Text("30 min prima").tag(30)
                            Text("45 min prima").tag(45)
                            Text("60 min prima").tag(60)
                        }
                        .disabled(!manager.remoteNotificationsEnabled || !commuteManager.scheduledSummaryEnabled)
                        .onChange(of: commuteManager.scheduledSummaryLeadMinutes) { _, _ in
                            Task { await commuteManager.syncRoutineWithServer() }
                        }

                        Picker("Fasce", selection: $commuteManager.scheduledSummaryScope) {
                            Text("Andata e Ritorno").tag("both")
                            Text("Solo Andata").tag("outbound")
                            Text("Solo Ritorno").tag("return")
                        }
                        .disabled(!manager.remoteNotificationsEnabled || !commuteManager.scheduledSummaryEnabled)
                        .onChange(of: commuteManager.scheduledSummaryScope) { _, _ in
                            Task { await commuteManager.syncRoutineWithServer() }
                        }
                    }
                    .opacity(commuteManager.scheduledSummaryEnabled ? 1.0 : 0.5)
                }

                Section("Abitudini di viaggio") {
                    NavigationLink(destination: CommuteSetupView()) {
                        HStack(spacing: 10) {
                            Image(systemName: "clock.arrow.2.circlepath")
                                .foregroundColor(.orange)
                            VStack(alignment: .leading, spacing: 2) {
                                if commuteManager.origins.isEmpty || commuteManager.destinations.isEmpty {
                                    Text("Configura Abitudini di Viaggio")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundColor(.primary)
                                    Text("Imposta stazioni, giorni e treni abituali.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                } else {
                                    Text("\(formatCityOrStationSummary(commuteManager.origins)) ↔ \(formatCityOrStationSummary(commuteManager.destinations))")
                                        .font(.subheadline.weight(.medium))
                                        .foregroundColor(.primary)
                                        .lineLimit(1)
                                    Text("Personalizza stazioni, giorni e treni")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .tint(.orange)
        .navigationTitle("Riepilogo programmato")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPaywallSheet) {
            SupportPaywallSheet()
                .environmentObject(manager)
        }
    }

    @ViewBuilder
    private func summaryDayRow(dayIndex: Int, dayName: String) -> some View {
        let isCommuteActive = commuteManager.isCommuteDayActive(dayIndex)
        let isSelected = commuteManager.isScheduledSummaryActive(on: dayIndex)
        let bands = commuteManager.commuteBandsForDay(dayIndex)
        let outCompact = bands.outbound.replacingOccurrences(of: " - ", with: "-")
        let retCompact = bands.returnBand.replacingOccurrences(of: " - ", with: "-")
        let timeLabel: String = {
            switch commuteManager.scheduledSummaryScope {
            case "outbound":
                return outCompact
            case "return":
                return retCompact
            default:
                return "\(outCompact)  •  \(retCompact)"
            }
        }()

        Button {
            guard isCommuteActive else { return }
            if isSelected {
                if commuteManager.effectiveScheduledSummaryWeekdays.count <= 1 {
                    Haptics.notify(.warning)
                    return
                }
                commuteManager.scheduledSummaryExcludedWeekdays.insert(dayIndex)
            } else {
                commuteManager.scheduledSummaryExcludedWeekdays.remove(dayIndex)
            }
            Haptics.play(.light)
            Task {
                await commuteManager.syncRoutineWithServer()
            }
        } label: {
            HStack(spacing: 8) {
                Text(dayName)
                    .font(.subheadline)
                    .foregroundColor(isCommuteActive ? .primary : .secondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)

                Spacer(minLength: 8)

                if isCommuteActive {
                    Text(timeLabel)
                        .font(.caption.weight(.medium))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundColor(isSelected ? .primary : .secondary)
                } else {
                    Text("Non attivo")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundColor(isSelected ? .orange : .secondary)
            }
            .padding(.leading, 6)
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
        .disabled(!isCommuteActive || !manager.remoteNotificationsEnabled || !commuteManager.scheduledSummaryEnabled)
        .opacity(isCommuteActive ? 1.0 : 0.45)
    }
}

struct TrainNotificationConfigSheet: View {
    @Binding var train: SavedTrain
    @EnvironmentObject var manager: TrainManager
    @EnvironmentObject var passanteManager: PassanteManager
    @Environment(\.dismiss) var dismiss
    @State private var stops: [Stop] = []
    @State private var isLoadingStops = false
    @State private var showPaywallSheet = false
    @State private var notificationNoticeMessage: String? = nil
    @State private var lastSelectedDays: [Int] = [1, 2, 3, 4, 5, 6, 7]
    
    private var dummy: Train {
        manager.createDummyTrain(from: train)
    }
    
    private var isItalo: Bool {
        dummy.isItalo || train.description.localizedCaseInsensitiveContains("Italo") || isItaloTrain(category: dummy.category, number: train.number)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                if let notice = notificationNoticeMessage {
                    Section {
                        HStack(spacing: 8) {
                            Image(systemName: "info.circle.fill")
                                .foregroundColor(.orange)
                                .font(.headline)
                            Text(notice)
                                .font(.caption)
                                .foregroundColor(.primary)
                        }
                        .padding(.vertical, 2)
                    }
                }

                if isItalo {
                    Section {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text("Le notifiche e le Live Activity non sono disponibili per i treni Italo: In Orario supporta il monitoraggio in background solo per Trenitalia e Trenord.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }

                let isPaused = train.isNotificationsPaused

                Section(header: Text("Treno")) {
                    HStack(spacing: 12) {
                        Image(systemName: "tram.fill")
                            .foregroundColor(isPaused ? .secondary : .orange)
                            .font(.title2)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(dummy.category) \(train.number)")
                                .font(.headline)
                            
                            let descParts = train.description.components(separatedBy: " - ")
                            let origin = descParts.first ?? train.description
                            let destination = descParts.count > 1 ? descParts[1] : ""
                            
                            if !destination.isEmpty {
                                Text("\(origin) → \(destination)")
                                    .font(.subheadline)
                                    .foregroundColor(.primary)
                            } else {
                                Text(train.description)
                                    .font(.subheadline)
                                    .foregroundColor(.primary)
                            }
                            
                            HStack(spacing: 4) {
                                Image(systemName: "clock")
                                    .foregroundColor(.secondary)
                                Text("\(train.departureTime ?? "--:--") → \(train.arrivalTime ?? "--:--")")
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)

                            Text(isPaused
                                 ? "Notifiche spente. Tocca la campanella per attivarle"
                                 : "Notifiche attive. Tocca la campanella per disattivarle")
                                .font(.caption2.weight(.medium))
                                .foregroundColor(isPaused ? .secondary : .orange)
                        }

                        Spacer(minLength: 8)

                        Button {
                            Haptics.play(.medium)
                            train.notificationsPaused = !isPaused
                            saveAndSync()
                        } label: {
                            Image(systemName: isPaused ? "bell.slash.fill" : "bell.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(isPaused ? .secondary : .orange)
                                .frame(width: 38, height: 38)
                                .background((isPaused ? Color.secondary : Color.orange).opacity(0.15))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(isPaused ? "Riattiva notifiche treno" : "Metti in stand-by notifiche treno")
                    }
                    .padding(.vertical, 4)
                }
                
                let allDaysSelected = Set(train.activeDays ?? []) == Set([1, 2, 3, 4, 5, 6, 7])
                Section(
                    header: HStack {
                        Text("Giorni")
                        Spacer()
                        Button(allDaysSelected ? "Deseleziona tutto" : "Seleziona tutto") {
                            Haptics.play(.light)
                            if allDaysSelected {
                                train.activeDays = []
                            } else {
                                train.activeDays = [1, 2, 3, 4, 5, 6, 7]
                            }
                            saveAndSync()
                        }
                        .font(.caption.weight(.semibold))
                        .textCase(nil)
                    },
                    footer: Text((train.activeDays ?? []).isEmpty
                                 ? "Le notifiche sono attive solo per oggi e si disattiveranno automaticamente a fine giornata."
                                 : "Le notifiche su questo treno sono attive nei giorni selezionati.")
                ) {
                    NotificationCheckRow(
                        title: "Solo per oggi",
                        isSelected: (train.activeDays ?? []).isEmpty
                    ) {
                        if !(train.activeDays ?? []).isEmpty {
                            if let existing = train.activeDays, !existing.isEmpty {
                                lastSelectedDays = existing
                            }
                            train.activeDays = []
                            saveAndSync()
                        }
                    }

                    DaySelectorView(
                        activeDays: $train.activeDays,
                        isDisabled: isPaused,
                        showHeader: false
                    ) {
                        saveAndSync()
                    }
                    .padding(.vertical, 4)
                }
                .disabled(isPaused)
                .saturation(isPaused ? 0.0 : 1.0)
                .opacity(isPaused ? 0.5 : 1.0)

                Section(
                    header: Text("Notifica a un orario specifico"),
                    footer: Text(manager.hasSupport()
                                 ? "Ricevi lo stato del treno (in orario, ritardo o soppressione) all'orario scelto, senza monitoraggio continuo."
                                 : "Ricevi lo stato del treno (in orario, ritardo o soppressione) all'orario scelto, senza monitoraggio continuo. Disponibile gratis fino a 10 treni.")
                ) {
                    NotificationCheckRow(
                        title: "Notifica a un orario specifico",
                        isSelected: train.notifyScheduledTime ?? false
                    ) {
                        notificationNoticeMessage = nil
                        let newValue = !(train.notifyScheduledTime ?? false)
                        if newValue && !canEnableNotificationOnThisTrain(isScheduled: true) {
                            return
                        }
                        train.notifyScheduledTime = newValue
                        if newValue && (train.scheduledNotificationTime ?? "").isEmpty {
                            train.scheduledNotificationTime = defaultScheduledTime()
                        }
                        saveAndSync()
                    }

                    if train.notifyScheduledTime ?? false {
                        HStack {
                            Text("Orario notifica:")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Spacer()
                            Italian24HourTimePicker(selection: scheduledTimeBinding, tintColor: .orange)
                        }
                        .padding(.leading, 8)
                    }
                }
                .disabled(isPaused)
                .saturation(isPaused ? 0.0 : 1.0)
                .opacity(isPaused ? 0.5 : 1.0)

                let allContinuousSelected = (train.notifyDelay == true)
                    && (train.notifyDeparture == true)
                    && (train.notifyStationPass == true)
                    && (train.notifyPlatformChange == true)
                Section(
                    header: HStack(spacing: 6) {
                        Text("Monitoraggio Continuo")
                        if !manager.hasSupport() {
                            Text("(Solo Pro)")
                                .font(.caption2.bold())
                                .foregroundColor(.orange)
                        }
                        Spacer()
                        if manager.hasSupport() {
                            Button(allContinuousSelected ? "Deseleziona tutto" : "Seleziona tutto") {
                                Haptics.play(.light)
                                notificationNoticeMessage = nil
                                if allContinuousSelected {
                                    train.notifyDelay = false
                                    train.notifyDeparture = false
                                    train.notifyStationPass = false
                                    train.notifyPlatformChange = false
                                    saveAndSync()
                                } else {
                                    if !canEnableNotificationOnThisTrain(isScheduled: false) {
                                        return
                                    }
                                    train.notifyDelay = true
                                    train.notifyDeparture = true
                                    train.notifyStationPass = true
                                    train.notifyPlatformChange = true
                                    saveAndSync()
                                    loadStops()
                                }
                            }
                            .font(.caption.weight(.semibold))
                            .textCase(nil)
                        }
                    },
                    footer: Text(manager.hasSupport()
                                 ? "Ogni opzione è indipendente: attiva solo gli avvisi che desideri ricevere in tempo reale durante il viaggio (fino a 20 treni)."
                                 : "Monitora costantemente ritardi, soppressioni, partenze, passaggi in stazione e cambi binario fino a 20 treni con In Orario Pro.")
                ) {
                    if !manager.hasSupport() {
                        Button {
                            Haptics.notify(.warning)
                            showPaywallSheet = true
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 8) {
                                    Label("Monitoraggio continuo del treno", systemImage: "bell.badge.waveform.fill")
                                        .foregroundColor(.secondary)
                                        .font(.subheadline.weight(.semibold))

                                    Spacer()

                                    Text("Solo Pro")
                                        .font(.caption2.bold())
                                        .foregroundColor(.orange)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.orange.opacity(0.14))
                                        .cornerRadius(6)

                                    Image(systemName: "lock.fill")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Text("Include variazioni di ritardo e soppressioni, partenza da origine, passaggio in stazione e cambio binario. Tocca per attivare In Orario Pro.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 4)
                            .opacity(0.7)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    } else {
                        NotificationCheckRow(
                            title: "Variazioni ritardo e soppressioni",
                            isSelected: train.notifyDelay ?? false
                        ) {
                            notificationNoticeMessage = nil
                            let newValue = !(train.notifyDelay ?? false)
                            if newValue && !canEnableNotificationOnThisTrain(isScheduled: false) {
                                return
                            }
                            train.notifyDelay = newValue
                            saveAndSync()
                        }

                        NotificationCheckRow(
                            title: "Notifica alla partenza da origine",
                            isSelected: train.notifyDeparture ?? false
                        ) {
                            notificationNoticeMessage = nil
                            let newValue = !(train.notifyDeparture ?? false)
                            if newValue && !canEnableNotificationOnThisTrain(isScheduled: false) {
                                return
                            }
                            train.notifyDeparture = newValue
                            saveAndSync()
                        }

                        NotificationCheckRow(
                            title: "Notifica al passaggio in stazione",
                            isSelected: train.notifyStationPass ?? false
                        ) {
                            notificationNoticeMessage = nil
                            let newValue = !(train.notifyStationPass ?? false)
                            if newValue && !canEnableNotificationOnThisTrain(isScheduled: false) {
                                return
                            }
                            train.notifyStationPass = newValue
                            saveAndSync()
                            if newValue {
                                loadStops()
                            }
                        }

                        if train.notifyStationPass ?? false {
                            HStack {
                                Text("Stazione di transito:")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Spacer()

                                if isLoadingStops {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                } else if !stops.isEmpty {
                                    Picker("", selection: Binding(
                                        get: { train.stationPassName ?? stops.first?.stationName ?? "" },
                                        set: { newValue in
                                            train.stationPassName = newValue
                                            saveAndSync()
                                        }
                                    )) {
                                        ForEach(stops) { stop in
                                            Text(stop.stationName).tag(stop.stationName)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                } else {
                                    Button("Riprova caricamento") {
                                        loadStops()
                                    }
                                    .font(.caption)
                                    .foregroundColor(.orange)
                                }
                            }
                            .padding(.leading, 28)
                            .onAppear {
                                loadStops()
                            }
                        }

                        NotificationCheckRow(
                            title: "Notifica cambio binario in stazione",
                            isSelected: train.notifyPlatformChange ?? false
                        ) {
                            notificationNoticeMessage = nil
                            let newValue = !(train.notifyPlatformChange ?? false)
                            if newValue && !canEnableNotificationOnThisTrain(isScheduled: false) {
                                return
                            }
                            train.notifyPlatformChange = newValue
                            saveAndSync()
                            if newValue {
                                loadStops()
                            }
                        }

                        if train.notifyPlatformChange ?? false {
                            HStack {
                                Text("Stazione di rilevamento:")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Spacer()

                                if isLoadingStops {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                } else if !stops.isEmpty {
                                    Picker("", selection: Binding(
                                        get: { train.platformChangeStationName ?? stops.first?.stationName ?? "" },
                                        set: { newValue in
                                            train.platformChangeStationName = newValue
                                            saveAndSync()
                                        }
                                    )) {
                                        ForEach(stops) { stop in
                                            Text(stop.stationName).tag(stop.stationName)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                } else {
                                    Button("Riprova caricamento") {
                                        loadStops()
                                    }
                                    .font(.caption)
                                    .foregroundColor(.orange)
                                }
                            }
                            .padding(.leading, 12)
                            .onAppear {
                                loadStops()
                            }
                        }
                    }
                }
                .disabled(isPaused)
                .saturation(isPaused ? 0.0 : 1.0)
                .opacity(isPaused ? 0.5 : 1.0)
            }
            .disabled(isItalo)
            .navigationTitle("Impostazioni Notifiche")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Chiudi") {
                        dismiss()
                    }
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                }
            }
            .sheet(isPresented: $showPaywallSheet) {
                SupportPaywallSheet()
                    .environmentObject(manager)
            }
            .onDisappear {
                saveAndSync()
            }
        }
        .tint(.orange)
    }

    private func canEnableNotificationOnThisTrain(isScheduled: Bool) -> Bool {
        if manager.hasSupport() {
            let alreadyActiveOnThisTrain = (train.notifyScheduledTime == true) ||
                                           (train.notifyDelay == true) ||
                                           (train.notifyDeparture == true) ||
                                           (train.notifyStationPass == true) ||
                                           (train.notifyPlatformChange == true)
            if alreadyActiveOnThisTrain {
                return true
            }
            let limit = manager.getLimit()
            let otherCount = manager.favoriteTrains.filter { other in
                other.id != train.id && (
                    other.notifyScheduledTime == true ||
                    other.notifyDelay == true ||
                    other.notifyDeparture == true ||
                    other.notifyStationPass == true ||
                    other.notifyPlatformChange == true
                )
            }.count
            if otherCount >= limit {
                Haptics.notify(.error)
                notificationNoticeMessage = "Puoi avere al massimo \(limit) treni con notifiche attive alla volta. Disattivane un altro per procedere."
                return false
            }
            return true
        } else {
            guard isScheduled else { return false }
            let limit = TrainManager.freeScheduledNotificationLimit
            let otherScheduledCount = manager.favoriteTrains.filter {
                $0.id != train.id && $0.notifyScheduledTime == true
            }.count
            if otherScheduledCount >= limit {
                Haptics.notify(.error)
                notificationNoticeMessage = "Con il piano gratuito puoi attivare la notifica a un orario specifico per massimo \(limit) treni. Passa a In Orario Pro per arrivare fino a \(TrainManager.proNotificationLimit) treni e sbloccare il monitoraggio continuo."
                return false
            }
            return true
        }
    }

    private func saveAndSync() {
        manager.saveFavorites()
        manager.syncRemoteNotifications()
    }
    
    private var scheduledTimeBinding: Binding<Date> {
        Binding<Date>(
            get: {
                let raw = train.scheduledNotificationTime ?? defaultScheduledTime()
                if let d = SharedFormatters.time.date(from: raw) {
                    return d
                }
                let cleaned = raw.replacingOccurrences(of: "\u{202F}", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                let f12 = DateFormatter()
                f12.locale = Locale(identifier: "en_US_POSIX")
                f12.timeZone = TimeZone(identifier: "Europe/Rome")
                f12.dateFormat = "h:mm a"
                return f12.date(from: cleaned)
                    ?? SharedFormatters.time.date(from: "07:30")
                    ?? Date()
            },
            set: { newDate in
                train.scheduledNotificationTime = SharedFormatters.time.string(from: newDate)
                saveAndSync()
            }
        )
    }
    
    private func defaultScheduledTime() -> String {
        if let depStr = train.departureTime?.trimmingCharacters(in: .whitespacesAndNewlines),
           !depStr.isEmpty {
            var parsedDate = SharedFormatters.time.date(from: depStr)
            if parsedDate == nil {
                let f12 = DateFormatter()
                f12.locale = Locale(identifier: "en_US_POSIX")
                f12.timeZone = TimeZone(identifier: "Europe/Rome")
                f12.dateFormat = "h:mm a"
                parsedDate = f12.date(from: depStr)
            }
            if let depDate = parsedDate {
                var cal = Calendar(identifier: .gregorian)
                cal.timeZone = TimeZone(identifier: "Europe/Rome") ?? .current
                if let minus15 = cal.date(byAdding: .minute, value: -15, to: depDate) {
                    return SharedFormatters.time.string(from: minus15)
                }
            }
        }
        return "07:30"
    }
    
    private func loadStops() {
        if let cached = manager.favoriteTrainsStops[train.number], !cached.isEmpty {
            self.stops = cached
            return
        }
        
        isLoadingStops = true
        Task {
            let result = await manager.fetchLiveStops(for: train.number)
            await MainActor.run {
                if !result.stops.isEmpty {
                    manager.favoriteTrainsStops[train.number] = result.stops
                    self.stops = result.stops
                }
                isLoadingStops = false
            }
        }
    }
}

private struct NotificationCheckRow: View {
    let title: LocalizedStringKey
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.play(.light)
            action()
        } label: {
            HStack(spacing: 12) {
                Text(title)
                    .foregroundColor(.primary)
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundColor(isSelected ? .orange : .secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct Italian24HourTimePicker: View {
    @Binding var selection: Date
    var tintColor: Color = .accentColor

    @State private var showPopover: Bool = false

    private static let romeTimeZone = TimeZone(identifier: "Europe/Rome") ?? .current

    private var romeCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = Self.romeTimeZone
        return cal
    }

    private var currentHour: Int {
        romeCalendar.component(.hour, from: selection)
    }

    private var currentMinute: Int {
        romeCalendar.component(.minute, from: selection)
    }

    private var formatted24h: String {
        String(format: "%02d:%02d", currentHour, currentMinute)
    }

    var body: some View {
        Button {
            Haptics.play(.light)
            showPopover = true
        } label: {
            Text(formatted24h)
                .font(.subheadline.weight(.medium).monospacedDigit())
                .foregroundColor(.primary)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(Color(.tertiarySystemFill))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.borderless)
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            VStack(spacing: 6) {
                HStack {
                    Text("Orario (24h)")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Fatto") {
                        showPopover = false
                    }
                    .font(.caption.weight(.bold))
                    .foregroundColor(tintColor)
                }
                .padding(.horizontal, 14)
                .padding(.top, 10)

                HStack(spacing: 0) {
                    Picker("Ora", selection: Binding(
                        get: { currentHour },
                        set: { updateTime(hour: $0, minute: currentMinute) }
                    )) {
                        ForEach(0..<24, id: \.self) { h in
                            Text(String(format: "%02d", h))
                                .monospacedDigit()
                                .tag(h)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(width: 72, height: 140)
                    .clipped()

                    Text(":")
                        .font(.title3.weight(.bold))
                        .foregroundColor(.secondary)

                    Picker("Minuti", selection: Binding(
                        get: { currentMinute },
                        set: { updateTime(hour: currentHour, minute: $0) }
                    )) {
                        ForEach(0..<60, id: \.self) { m in
                            Text(String(format: "%02d", m))
                                .monospacedDigit()
                                .tag(m)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(width: 72, height: 140)
                    .clipped()
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
            }
            .frame(width: 192)
            .presentationCompactAdaptation(.popover)
        }
    }

    private func updateTime(hour: Int, minute: Int) {
        var comps = romeCalendar.dateComponents([.year, .month, .day], from: selection)
        comps.hour = hour
        comps.minute = minute
        comps.second = 0
        if let updated = romeCalendar.date(from: comps) {
            selection = updated
        }
    }
}

struct DaySelectorView: View {
    @Binding var activeDays: [Int]?
    var isDisabled: Bool = false
    var showHeader: Bool = true
    var onTapDisabled: (() -> Void)? = nil
    let onToggle: () -> Void
    
    let days = [
        (1, "L"),
        (2, "M"),
        (3, "M"),
        (4, "G"),
        (5, "V"),
        (6, "S"),
        (7, "D")
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if showHeader {
                HStack {
                    Text("Giorni attivi:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if isDisabled {
                        Text("(Solo Pro)")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                }
            }
            
            HStack(spacing: 6) {
                ForEach(days, id: \.0) { dayNum, label in
                    let isSelected = activeDays?.contains(dayNum) ?? false
                    Button(action: {
                        if isDisabled {
                            Haptics.play(.light)
                            onTapDisabled?()
                        } else {
                            toggleDay(dayNum)
                        }
                    }) {
                        Text(label)
                            .font(.caption)
                            .fontWeight(.bold)
                            .frame(width: 28, height: 28)
                            .background(isSelected ? (isDisabled ? Color(.systemGray3) : Color.orange) : Color(.systemGray6))
                            .foregroundColor(isSelected ? .white : (isDisabled ? Color(.secondaryLabel) : .primary))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
            
            if isDisabled && showHeader {
                Text("La scelta dei giorni della settimana è inclusa nel piano In Orario Pro.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.top, 2)
            }
        }
    }
    
    private func toggleDay(_ dayNum: Int) {
        var current = activeDays ?? []
        if current.contains(dayNum) {
            current.removeAll(where: { $0 == dayNum })
        } else {
            current.append(dayNum)
            current.sort()
        }
        
        activeDays = current
        onToggle()
    }
}

struct SmartSuggestionsSettingsView: View {
    @EnvironmentObject var usageTracker: UsageTracker
    @EnvironmentObject var manager: TrainManager
    @EnvironmentObject var guessingEngine: TrainGuessingEngine
    @State private var showDeleteConfirmation = false
    @State private var showResetIgnoredConfirmation = false
    @State private var isIgnoredExpanded = false
    @State private var selectedSlotIndex: Int = {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour >= 5 && hour < 12 { return 0 }
        else if hour >= 12 && hour < 19 { return 1 }
        else { return 2 }
    }()

    var body: some View {
        let habits = usageTracker.learnedHabitsByTimeSlot(
            favoriteTrains: manager.favoriteTrains,
            favoriteStations: manager.myStations
        )
        let hasAnyData = habits.contains { !$0.isEmpty }

        List {
            Section(header: Text("Stato")) {
                Toggle(isOn: $usageTracker.smartSuggestionsEnabled) {
                    Label("Suggerimenti personalizzati", systemImage: "sparkles")
                        .font(.headline)
                }
                .onChange(of: usageTracker.smartSuggestionsEnabled) { _, isEnabled in
                    if !isEnabled {
                        UserInterestTelemetryManager.shared.clearLocalStore()
                    }
                }
            }

            Section(
                header: Text("Abitudini apprese"),
                footer: Text("Le abitudini si basano su ciò che consulti davvero (tabelloni, treni, linee e tratte nelle diverse fasce orarie). I dati anonimi vengono sincronizzati con i server di In Orario solo se i suggerimenti personalizzati sono attivi.")
            ) {
                if !hasAnyData {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "brain.head.profile")
                                .font(.title3)
                                .foregroundColor(.accentColor)
                            Text("Nessuna abitudine registrata")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                        }
                        Text("L'app apprende man mano che consulti orari, tabelloni e stazioni nelle diverse ore della giornata, integrando i tuoi preferiti storici. Continuando a usare l'app, vedrai apparire qui i tuoi tragitti abituali.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                } else {
                    Picker("Fascia oraria", selection: $selectedSlotIndex) {
                        Text("Mattina").tag(0)
                        Text("Pomeriggio").tag(1)
                        Text("Sera").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .padding(.vertical, 4)

                    if selectedSlotIndex < habits.count {
                        let slot = habits[selectedSlotIndex]

                        HStack(spacing: 6) {
                            Image(systemName: slot.icon)
                                .foregroundColor(slot.color)
                            Text("\(slot.title) • \(slot.timeRange)")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.primary)
                        }
                        .padding(.vertical, 2)

                        if slot.isEmpty {
                            Text("Nessuna attività o treno abituale registrato in questa fascia oraria (\(slot.timeRange)).")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.vertical, 4)
                        } else {
                            if !slot.stations.isEmpty {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text("STAZIONI PIÙ CONSULTATE")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundColor(.secondary)
                                        Spacer()
                                        Text("Aperture tabellone")
                                            .font(.system(size: 9))
                                            .foregroundColor(.secondary)
                                    }

                                    ForEach(slot.stations) { st in
                                        HStack(alignment: .center, spacing: 8) {
                                            Image(systemName: "building.2.fill")
                                                .font(.system(size: 13))
                                                .foregroundColor(.blue)
                                                .frame(width: 22)
                                            
                                            VStack(alignment: .leading, spacing: 2) {
                                                HStack(spacing: 4) {
                                                    Text(st.name)
                                                        .font(.subheadline)
                                                        .fontWeight(.semibold)
                                                    
                                                    if st.isFavorite {
                                                        Image(systemName: "star.fill")
                                                            .font(.system(size: 9))
                                                            .foregroundColor(.yellow)
                                                    }
                                                }
                                                
                                                Text(st.countDescription)
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                                    .lineLimit(1)
                                            }
                                            
                                            Spacer()
                                            
                                            Text(st.habitStrength)
                                                .font(.system(size: 10, weight: .bold))
                                                .padding(.horizontal, 7)
                                                .padding(.vertical, 3)
                                                .background(habitTierColor(st.habitStrength).opacity(0.14))
                                                .foregroundColor(habitTierColor(st.habitStrength))
                                                .clipShape(Capsule())
                                        }
                                        .padding(.vertical, 3)
                                    }
                                }
                                .padding(.vertical, 4)
                            }

                            if !slot.trains.isEmpty {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text("TRENI ABITUALI E CONSULTATI")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundColor(.secondary)
                                        Spacer()
                                        Text("Frequenza & orari")
                                            .font(.system(size: 9))
                                            .foregroundColor(.secondary)
                                    }

                                    ForEach(slot.trains) { tr in
                                        HStack(alignment: .center, spacing: 8) {
                                            // Badge categoria
                                            Text(tr.category)
                                                .font(.system(size: 9, weight: .black))
                                                .foregroundColor(.white)
                                                .padding(.horizontal, 4)
                                                .padding(.vertical, 2)
                                                .background(habitCategoryColor(for: tr.category))
                                                .cornerRadius(4)

                                            VStack(alignment: .leading, spacing: 2) {
                                                HStack(spacing: 4) {
                                                    Text(tr.number)
                                                        .font(.subheadline)
                                                        .fontWeight(.bold)
                                                    if let dep = tr.departureTime, !dep.isEmpty, dep != "--:--" {
                                                        Text("• ore \(dep)")
                                                            .font(.caption)
                                                            .foregroundColor(.secondary)
                                                    }
                                                    if tr.isFavorite {
                                                        Image(systemName: "star.fill")
                                                            .font(.system(size: 9))
                                                            .foregroundColor(.yellow)
                                                    }
                                                }
                                                HStack(spacing: 3) {
                                                    if !tr.destination.isEmpty {
                                                        Text("Per \(tr.destination) •")
                                                            .lineLimit(1)
                                                    }
                                                    Text(tr.countDescription)
                                                        .lineLimit(1)
                                                }
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                            }
                                            
                                            Spacer()
                                            
                                            Text(tr.habitStrength)
                                                .font(.system(size: 10, weight: .bold))
                                                .padding(.horizontal, 7)
                                                .padding(.vertical, 3)
                                                .background(habitTierColor(tr.habitStrength).opacity(0.14))
                                                .foregroundColor(habitTierColor(tr.habitStrength))
                                                .clipShape(Capsule())
                                        }
                                        .padding(.vertical, 3)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }
            }

            let sortedIgnoredStations = usageTracker.ignoredStationNames.sorted()
            let sortedIgnoredTrains = usageTracker.ignoredTrainNumbers.sorted()
            let sortedIgnoredRoutes = usageTracker.ignoredRouteKeys.sorted()
            let totalIgnored = sortedIgnoredStations.count + sortedIgnoredTrains.count + sortedIgnoredRoutes.count
            if totalIgnored > 0 {
                Section(
                    header: Text("Elementi ignorati"),
                    footer: Text("Espandi l'elenco per ripristinare singoli elementi oppure usa il pulsante qui sotto per ripristinarli tutti.")
                ) {
                    DisclosureGroup(isExpanded: $isIgnoredExpanded) {
                        ForEach(sortedIgnoredStations, id: \.self) { name in
                            HStack(spacing: 10) {
                                Image(systemName: "building.2.fill")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                                    .frame(width: 18)
                                Text(name.formattedStationName)
                                    .font(.subheadline)
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                                Spacer()
                                Button("Ripristina") {
                                    Haptics.play(.light)
                                    withAnimation(.snappy(duration: 0.22)) {
                                        usageTracker.unignoreStation(name)
                                    }
                                }
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.blue)
                                .buttonStyle(.borderless)
                            }
                        }

                        ForEach(sortedIgnoredTrains, id: \.self) { number in
                            HStack(spacing: 10) {
                                Image(systemName: "tram.fill")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                                    .frame(width: 18)
                                Text("Treno \(number)")
                                    .font(.subheadline)
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                                Spacer()
                                Button("Ripristina") {
                                    Haptics.play(.light)
                                    withAnimation(.snappy(duration: 0.22)) {
                                        usageTracker.unignoreTrain(number)
                                    }
                                }
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.blue)
                                .buttonStyle(.borderless)
                            }
                        }

                        ForEach(sortedIgnoredRoutes, id: \.self) { key in
                            let displayRoute = key.replacingOccurrences(of: "-", with: " → ")
                            HStack(spacing: 10) {
                                Image(systemName: "arrow.left.arrow.right")
                                    .font(.caption)
                                    .foregroundColor(.green)
                                    .frame(width: 18)
                                Text(displayRoute)
                                    .font(.subheadline)
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                                Spacer()
                                Button("Ripristina") {
                                    Haptics.play(.light)
                                    withAnimation(.snappy(duration: 0.22)) {
                                        usageTracker.unignoreRoute(key)
                                    }
                                }
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.blue)
                                .buttonStyle(.borderless)
                            }
                        }
                    } label: {
                        HStack {
                            Label("Suggerimenti nascosti", systemImage: "eye.slash")
                            Spacer()
                            Text("\(totalIgnored)")
                                .foregroundColor(.secondary)
                        }
                    }

                    Button(role: .destructive) {
                        showResetIgnoredConfirmation = true
                    } label: {
                        Label("Ripristina tutti i suggerimenti", systemImage: "arrow.counterclockwise")
                    }
                }
            }

            Section(header: Text("Dati raccolti")) {
                Text("L'app apprende le tue abitudini per mostrarti informazioni personalizzate al momento opportuno. I dati sono salvati sui server di In Orario per consentirne la rielaborazione. Sono totalmente anonimi e slegati da ogni identità. Se disattivi i suggerimenti personalizzati, l'app smette anche di raccogliere e inviare questi dati.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Label("Cancella abitudini apprese", systemImage: "trash")
                        .foregroundColor(.red)
                }
            }
        }
        .navigationTitle("Suggerimenti personalizzati")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Conferma eliminazione", isPresented: $showDeleteConfirmation) {
            Button("Annulla", role: .cancel) {}
            Button("Elimina", role: .destructive) {
                usageTracker.clearHistory()
                UserInterestTelemetryManager.shared.clearLocalStore()
            }
        } message: {
            Text("Sei sicuro di voler eliminare tutte le preferenze e le abitudini apprese finora? Questa operazione non può essere annullata.")
        }
        .alert("Ripristina suggerimenti", isPresented: $showResetIgnoredConfirmation) {
            Button("Annulla", role: .cancel) {}
            Button("Ripristina", role: .destructive) {
                usageTracker.unignoreAll()
            }
        } message: {
            Text("Tutti i treni e le stazioni che avevi scelto di non visualizzare potranno essere nuovamente suggeriti in base alle tue abitudini.")
        }
    }
}


