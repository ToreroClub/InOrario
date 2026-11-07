import SwiftUI
import StoreKit
import EventKit
import ActivityKit
import WidgetKit

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
    @State private var selectedCategory: NewsCategory = .sciopero
    @State private var isRefreshing = false
    @State private var showCalendarAlert = false
    @State private var calendarAlertMessage = ""
    @State private var addedCalendarItemIds: Set<UUID> = []
    
    var filteredNews: [NewsItem] {
        let items = news.filter { ($0.category ?? "sciopero") == selectedCategory.filterKey }
        if selectedCategory == .lavoro {
            return items
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
                        
                        if manager.strikeRegion == "Lombardia" && selectedCategory != .realtime {
                            LavoraMiBannerView()
                                .padding(.horizontal, 16)
                        }
                        
                        if filteredNews.isEmpty {
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
                        } else {
                            LazyVStack(spacing: 12) {
                                ForEach(filteredNews) { item in
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
                    .padding(.bottom, 20)
                }
            }
            .navigationTitle("Centro News")
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
                                let updatedNews = await manager.fetchStrikesAndNews(forceRefresh: true)
                                await MainActor.run {
                                    self.news = updatedNews
                                    isRefreshing = false
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
    @EnvironmentObject var manager: TrainManager
    @EnvironmentObject var passanteManager: PassanteManager
    @EnvironmentObject var usageTracker: UsageTracker
    @Environment(\.dismiss) var dismiss
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = true

    @StateObject private var tipManager = TipManager()
    @ObservedObject private var updateManager = AppUpdateManager.shared
    @State private var showFeedbackSheet = false
    
    var body: some View {
        NavigationStack {
            List {
                if !manager.hasSupport() {
                    Section(header: Text("Sostieni In Orario")) {
                        if tipManager.isLoadingProducts {
                            HStack {
                                Spacer()
                                ProgressView("Caricamento offerte...")
                                    .padding()
                                Spacer()
                            }
                        } else if tipManager.products.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Le offerte non sono al momento disponibili.")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 4)
                        } else {
                            ForEach(tipManager.products, id: \.id) { product in
                                let isYearly = product.id == TipManager.yearlySubscriptionID
                                Button(action: {
                                    Task {
                                        await tipManager.purchase(product)
                                    }
                                }) {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(defaultName(for: product.id))
                                                .font(.headline)
                                                .foregroundColor(.primary)
                                            Text(defaultDescription(for: product.id))
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                                .multilineTextAlignment(.leading)
                                        }
                                        Spacer()
                                        if tipManager.purchaseState == .purchasing {
                                            ProgressView()
                                        } else {
                                            VStack(alignment: .trailing, spacing: 1) {
                                                Text(product.displayPrice)
                                                    .font(.subheadline.bold())
                                                    .foregroundColor(.white)
                                                Text(isYearly ? "all'anno" : "una tantum")
                                                    .font(.system(size: 9))
                                                    .foregroundColor(.white.opacity(0.9))
                                            }
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 6)
                                            .background(isYearly ? Color.green : Color.orange)
                                            .cornerRadius(8)
                                        }
                                    }
                                }
                                .disabled(tipManager.purchaseState == .purchasing)
                            }
                            
                            Button(action: {
                                Haptics.play(.medium)
                                Task {
                                    do {
                                        try await AppStore.sync()
                                        await tipManager.updatePurchases()
                                    } catch {
                                        print("Errore ripristino acquisti: \(error)")
                                    }
                                }
                            }) {
                                HStack {
                                    Spacer()
                                    Text("Ripristina Acquisti")
                                        .font(.subheadline)
                                        .foregroundColor(.blue)
                                    Spacer()
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                Section(header: Text("Generali e notifiche")) {
                    HStack {
                        Label("Regione", systemImage: "globe")
                            .foregroundColor(.blue)
                            .font(.headline)
                        Spacer()
                        Picker("", selection: $manager.strikeRegion) {
                            Text("Nazionale / Tutte").tag("Tutte")
                            ForEach(["Abruzzo", "Basilicata", "Calabria", "Campania", "Emilia-Romagna", "Friuli Venezia Giulia", "Lazio", "Liguria", "Lombardia", "Marche", "Molise", "Piemonte", "Puglia", "Sardegna", "Sicilia", "Toscana", "Trentino-Alto Adige", "Umbria", "Valle d'Aosta", "Veneto"], id: \.self) { region in
                                Text(region).tag(region)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    .onChange(of: manager.strikeRegion) { _, _ in
                        manager.saveFavorites()
                    }
                    
                    NavigationLink(destination: CustomizeDashboardView()) {
                        Label("Personalizza Dashboard", systemImage: "slider.horizontal.3")
                            .font(.headline)
                    }
                    
                    NavigationLink(destination: CustomizePassanteView()) {
                        Label("Personalizza Linee Suburbane", systemImage: "tram.fill")
                            .font(.headline)
                    }
                    
                    NavigationLink(destination: CustomizeWidgetView()) {
                        Label("Personalizza Widget", systemImage: "rectangle.3.group.fill")
                            .foregroundColor(.blue)
                            .font(.headline)
                    }
                    
                    NavigationLink(destination: NotificationsSettingsView()) {
                        Label("Avvisi Treno", systemImage: "bell.fill")
                            .foregroundColor(.orange)
                            .font(.headline)
                    }
                }

                Section(header: Text("Suggerimenti e IA")) {
                    NavigationLink(destination: AISettingsView()) {
                        Label("Assistente IA", systemImage: "brain.head.profile")
                            .foregroundColor(.indigo)
                            .font(.headline)
                    }
                    
                    NavigationLink(destination: SmartSuggestionsSettingsView()) {
                        Label("Suggerimenti personalizzati", systemImage: "sparkles")
                            .foregroundColor(.purple)
                            .font(.headline)
                    }
                    
                    if manager.hasSupport() {
                        NavigationLink(destination: CommuteSetupView()) {
                            Label("Abitudini di viaggio", systemImage: "clock.arrow.2.circlepath")
                                .foregroundColor(.pink)
                                .font(.headline)
                        }
                    }
                }
                
                Section(header: Text("FAQ e supporto")) {
                    NavigationLink(destination: FAQView()) {
                        Label("Domande Frequenti", systemImage: "questionmark.circle.fill")
                            .foregroundColor(.blue)
                            .font(.headline)
                    }
                    
                    NavigationLink(destination: AboutProjectView()) {
                        Label("Il Progetto In Orario", systemImage: "heart.fill")
                            .foregroundColor(.pink)
                            .font(.headline)
                    }
                    
                    Link(destination: URL(string: "https://inorario.toreroclub.com")!) {
                        Label("Informativa sulla Privacy", systemImage: "lock.shield.fill")
                            .foregroundColor(.green)
                            .font(.headline)
                    }
                }
                
                if manager.hasSupport() {
                    Section {
                        HStack(spacing: 12) {
                            Image(systemName: "crown.fill")
                                .font(.title2)
                                .foregroundColor(.yellow)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(supporterRoleTitle)
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                Text("Grazie ❤️")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 4)
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
            .alert("Grazie di cuore! ❤️", isPresented: Binding(
                get: { tipManager.purchaseState == .success },
                set: { if !$0 { tipManager.resetState() } }
            )) {
                Button("Prego!", role: .cancel) {}
            } message: {
                Text("Il tuo supporto è fondamentale per coprire i costi di gestione e sostenere il futuro di In Orario. Buon viaggio!")
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
            .sheet(isPresented: $showFeedbackSheet) {
                FeedbackFormView()
            }

        }
    }
    
    private var supporterRoleTitle: String {
        switch tipManager.activeProductType {
        case .yearly:
            return "Sostenitore annuale"
        case .lifetime, .legacy, .none:
            return "Sostenitore a vita"
        }
    }
    
    private func defaultName(for id: String) -> String {
        switch id {
        case TipManager.yearlySubscriptionID: return "Sostenitore Annuale"
        case TipManager.lifetimeProductID: return "Sostenitore per Sempre"
        case TipManager.legacyProductID: return "Sostenitore a vita"
        default: return "Supporto al progetto"
        }
    }
    
    private func defaultDescription(for id: String) -> String {
        switch id {
        case TipManager.yearlySubscriptionID: return "Accesso completo per 1 anno con rinnovo annuale."
        case TipManager.lifetimeProductID: return "Accesso completo per sempre con un unico pagamento."
        case TipManager.legacyProductID: return "Grazie per aver supportato In Orario!"
        default: return "Sostieni lo sviluppo dell'app."
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
                
                Text("Se In Orario ti aiuta a partire più sereno, a evitare attese inutili o semplicemente a viaggiare con maggiore tranquillità, puoi sostenere il progetto con un abbonamento annuale o un acquisto a vita.")
                    .font(.body)
                    .foregroundColor(.primary)
                    .lineSpacing(4)
                
                Text("Grazie davvero ❤️")
                    .font(.headline)
                    .foregroundColor(.primary)
                    .padding(.top, 8)
            }
            .padding(20)
        }
        .navigationTitle("Il Progetto In Orario")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct FeedbackFormView: View {
    @Environment(\.dismiss) var dismiss
    @State private var category = "Bug"
    @State private var message = ""
    @State private var contact = ""
    @State private var isSending = false
    @State private var showSuccessAlert = false
    @State private var showErrorAlert = false
    
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
                        .frame(height: 150)
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
                
                Section(header: Text("Contatto (Opzionale)"), footer: Text("Inserisci un'email se desideri essere ricontattato.")) {
                    TextField("Tua email", text: $contact)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
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
                Text("La tua segnalazione è stata inviata con successo direttamente agli sviluppatori.")
            }
            .alert("Errore di Invio", isPresented: $showErrorAlert) {
                Button("Riprova", role: .cancel) {}
            } message: {
                Text("Non è stato possibile inviare il feedback. Verifica la tua connessione internet o riprova più tardi.")
            }
        }
    }
    
    private func sendFeedback() {
        guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isSending = true
        Haptics.play(.medium)
        
        let payload: [String: String] = [
            "category": category,
            "message": message,
            "contact": contact
        ]
        
        guard let url = URL(string: "https://gestioneinorario.toreroclub.com/feedback") else {
            isSending = false
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10.0
        
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

struct CustomizeDashboardView: View {
    @EnvironmentObject var manager: TrainManager
    @EnvironmentObject var passanteManager: PassanteManager
    @State private var showNewSmartRouteSheet = false
    @State private var homeDestInput = ""
    
    @AppStorage("rememberNearbyState") private var rememberNearbyState = true
    @AppStorage("rememberMyStationsState") private var rememberMyStationsState = false
    @AppStorage("rememberFavoriteTrainsState") private var rememberFavoriteTrainsState = true
    @AppStorage("rememberPassanteState") private var rememberPassanteState = true
    @AppStorage("showSuburbanLines") private var showSuburbanLines = true
    
    var body: some View {
        List {
            Section(header: Text("Visualizzazione")) {
                Toggle(isOn: $showSuburbanLines) {
                    Label("Mostra Linee Suburbane", systemImage: "tram.fill")
                        .foregroundColor(.green)
                        .font(.headline)
                }
            }

            Section(header: Text("Ordine Sezioni Dashboard")) {
                ForEach(manager.sectionOrder, id: \.self) { section in
                    Text(section.rawValue).font(.headline)
                }
                .onMove { from, to in
                    Haptics.play(.medium)
                    manager.sectionOrder.move(fromOffsets: from, toOffset: to)
                    manager.saveSectionOrder()
                }
            }
            
            Section(header: Text("Comportamento Espansione"), footer: Text("Scegli se mantenere in memoria lo stato aperto o chiuso delle varie sezioni.")) {
                Toggle("Ricorda stato Stazioni Preferite", isOn: Binding(
                    get: { rememberMyStationsState },
                    set: { newValue in
                        rememberMyStationsState = newValue
                        Haptics.play(.medium)
                    }
                ))
                Toggle("Ricorda stato Treni Preferiti", isOn: Binding(
                    get: { rememberFavoriteTrainsState },
                    set: { newValue in
                        rememberFavoriteTrainsState = newValue
                        Haptics.play(.medium)
                    }
                ))
                if !passanteManager.selectedSuburbanLines.isEmpty {
                    Toggle("Ricorda stato Passante", isOn: Binding(
                        get: { rememberPassanteState },
                        set: { newValue in
                            rememberPassanteState = newValue
                            Haptics.play(.medium)
                        }
                    ))
                }
            }
            
            Section(header: Text("Le Mie Tratte Preferite")) {
                if manager.favoriteRoutes.isEmpty {
                    Text("Nessuna tratta preferita configurata.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .italic()
                } else {
                    ForEach(manager.favoriteRoutes) { route in
                        HStack {
                            HStack(spacing: 6) {
                                Image(systemName: "star.fill").foregroundColor(.yellow)
                                Text("\(route.originName) ➔ \(route.destinationName)")
                                    .font(.subheadline.bold())
                            }
                            Spacer()
                            Button(role: .destructive) {
                                Haptics.play(.medium)
                                manager.toggleFavoriteRoute(originName: route.originName, originID: route.originID, destName: route.destinationName, destID: route.destinationID)
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(BorderlessButtonStyle())
                        }
                    }
                }
                
                Button(action: {
                    Haptics.play(.light)
                    showNewSmartRouteSheet = true
                }) {
                    Label("Aggiungi Tratta Preferita", systemImage: "plus.circle")
                        .foregroundColor(.orange)
                        .font(.headline)
                }
                .buttonStyle(BorderlessButtonStyle())
            }
        }
        .navigationTitle("Dashboard")
        .environment(\.editMode, .constant(.active))
        .sheet(isPresented: $showNewSmartRouteSheet) {
            PassanteQuickSetupView()
                .environmentObject(manager)
        }
        .onAppear {
            homeDestInput = manager.homeDestinationStationName
        }
    }
}

struct CustomizePassanteView: View {
    @EnvironmentObject var manager: TrainManager
    @EnvironmentObject var passanteManager: PassanteManager
    @AppStorage("showSuburbanLines") private var showSuburbanLines = true
    
    var body: some View {
        List {
            Section(header: Text("Visualizzazione sulla Dashboard"), footer: Text("Abilita la visualizzazione del Passante e delle linee suburbane nella schermata principale per consultarne partenze e stato della rete.")) {
                Toggle(isOn: $showSuburbanLines) {
                    Label("Mostra Linee Suburbane", systemImage: "tram.fill")
                        .foregroundColor(.green)
                        .font(.headline)
                }
            }
            
            Section(header: Text("Vista Speciale Stazioni"), footer: Text("Quando attivo, il passante raggruppa le partenze in Ovest ed Est. Se disattivato, vedrai la lista classica Arrivi/Partenze.")) {
                Toggle(isOn: Binding(
                    get: { passanteManager.useSpecialPassanteView },
                    set: { newValue in
                        passanteManager.useSpecialPassanteView = newValue
                        manager.saveFavorites()
                        Haptics.play(.medium)
                    }
                )) {
                    Label("Mostra Vista Speciale Passante", systemImage: "eye.fill")
                        .foregroundColor(.orange)
                }
            }
            
            ForEach(SuburbanData.shared.allLines) { line in
                if line.stations.isEmpty {
                    Toggle(isOn: Binding(
                        get: { passanteManager.selectedSuburbanLines.contains(line.id) },
                        set: { _ in passanteManager.toggleSuburbanLine(line.id) }
                    )) {
                        Text(line.name).font(.headline).foregroundColor(line.color)
                    }
                } else {
                    Section {
                        if passanteManager.selectedSuburbanLines.contains(line.id) {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 15) {
                                    let hiddenForLine = passanteManager.hiddenSuburbanStations[line.id] ?? []
                                    ForEach(line.stations) { station in
                                        let isHidden = hiddenForLine.contains(station.name)
                                        
                                        VStack {
                                            PassanteNodeView(station: station, isFirst: false, isLast: false, isNearby: false, lineColor: isHidden ? .gray.opacity(0.3) : line.color)
                                                .opacity(isHidden ? 0.4 : 1.0)
                                        }
                                        .overlay(
                                            Button(action: {
                                                Haptics.play(.light)
                                                passanteManager.toggleHiddenStation(lineId: line.id, stationName: station.name)
                                            }) {
                                                Image(systemName: isHidden ? "plus.circle.fill" : "minus.circle.fill")
                                                    .foregroundColor(isHidden ? .green : .red)
                                                    .background(Circle().fill(Color.white))
                                                    .font(.title2)
                                            }
                                            .offset(x: 15, y: -25)
                                            , alignment: .topTrailing
                                        )
                                        .padding(.top, 20)
                                    }
                                }
                                .padding(.vertical, 10)
                                .padding(.horizontal, 5)
                             }
                             .listRowInsets(EdgeInsets())
                        }
                    } header: {
                        HStack {
                            Text(line.name).font(.headline).foregroundColor(line.color)
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { passanteManager.selectedSuburbanLines.contains(line.id) },
                                set: { _ in
                                    Haptics.play(.medium)
                                    passanteManager.toggleSuburbanLine(line.id)
                                }
                            ))
                            .labelsHidden()
                        }
                    } footer: {
                        if passanteManager.selectedSuburbanLines.contains(line.id) {
                            Text("Tocca il tasto - per nascondere le stazioni che non ti interessano, o + per ripristinarle.")
                        }
                    }
                }
            }
        }
        .navigationTitle("Personalizza Passante")
    }
}

struct CustomizeWidgetView: View {
    @EnvironmentObject var manager: TrainManager
    
    private var groupDefaults: UserDefaults? {
        UserDefaults(suiteName: "group.carlo.InOrario")
    }
    
    @State private var excludedNumbers: Set<String> = []
    
    var body: some View {
        List {
            Section(
                header: Text("Treni nei Widget"),
                footer: Text("Disattiva i treni che non vuoi vedere nei widget della schermata Home o di blocco. I widget mostrano fino a 3 treni nei formati Piccolo e Medio, ordinati e ruotati automaticamente in base all'orario attuale.")
            ) {
                if manager.favoriteTrains.isEmpty {
                    Text("Nessun treno salvato tra i preferiti.")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(manager.favoriteTrains) { train in
                        let isIncluded = !excludedNumbers.contains(train.number) && (train.showInWidget ?? true)
                        Toggle(isOn: Binding(
                            get: { isIncluded },
                            set: { newValue in
                                Haptics.play(.medium)
                                if newValue {
                                    excludedNumbers.remove(train.number)
                                } else {
                                    excludedNumbers.insert(train.number)
                                }
                                syncExclusions()
                                if let idx = manager.favoriteTrains.firstIndex(where: { $0.id == train.id }) {
                                    manager.favoriteTrains[idx].showInWidget = newValue
                                    manager.saveFavorites()
                                }
                                WidgetCenter.shared.reloadAllTimelines()
                            }
                        )) {
                            HStack(spacing: 12) {
                                Image(systemName: "train.side.front.car")
                                    .foregroundColor(.blue)
                                    .font(.title3)
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack {
                                        let dummy = manager.createDummyTrain(from: train)
                                        Text("\(dummy.category) \(train.number)")
                                            .font(.headline)
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
            
            Section(header: Text("Regole di Visualizzazione"), footer: Text("L'ordine dei treni nel widget si adatta durante la giornata: in alto trovi i treni in viaggio o in partenza a breve rispetto all'orario corrente.")) {
                HStack {
                    Label("Rotazione intelligente orario", systemImage: "clock.arrow.circlepath")
                        .foregroundColor(.orange)
                    Spacer()
                    Text("Attiva")
                        .font(.subheadline.bold())
                        .foregroundColor(.green)
                }
                HStack {
                    Label("Limite treni per widget", systemImage: "square.stack.3d.down.right.fill")
                        .foregroundColor(.blue)
                    Spacer()
                    Text("Max 3")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("Personalizza Widget")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadExclusions()
        }
    }
    
    private func loadExclusions() {
        if let rawData = groupDefaults?.data(forKey: "excludedWidgetTrainNumbers_v1"),
           let set = try? JSONDecoder().decode(Set<String>.self, from: rawData) {
            excludedNumbers = set
        } else if let arr = groupDefaults?.stringArray(forKey: "excludedWidgetTrainNumbers_v1") {
            excludedNumbers = Set(arr)
        } else {
            excludedNumbers = []
        }
        for train in manager.favoriteTrains where train.showInWidget == false {
            excludedNumbers.insert(train.number)
        }
    }
    
    private func syncExclusions() {
        if let encoded = try? JSONEncoder().encode(excludedNumbers) {
            groupDefaults?.set(encoded, forKey: "excludedWidgetTrainNumbers_v1")
        }
        groupDefaults?.set(Array(excludedNumbers), forKey: "excludedWidgetTrainNumbers_v1")
    }
}

struct NotificationsSettingsView: View {
    @EnvironmentObject var manager: TrainManager
    @EnvironmentObject var passanteManager: PassanteManager
    @State private var selectedTrainForConfig: SavedTrain? = nil
    
    var body: some View {
        List {
            Section(header: Text("Stato Treno")) {
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
                    Label("Abilita Notifiche", systemImage: "bell.fill")
                        .foregroundColor(.orange)
                        .font(.headline)
                }
            }
            
            if manager.remoteNotificationsEnabled {
                Section(header: Text("Notifiche Treni Preferiti"), footer: Text("Le notifiche automatiche ti avvisano se il treno è in ritardo o quando passa dalla stazione scelta.")) {
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
                                    Image(systemName: "train.side.front.car")
                                        .foregroundColor(.blue)
                                        .font(.subheadline)
                                    VStack(alignment: .leading, spacing: 4) {
                                        let dummy = manager.createDummyTrain(from: train)
                                        Text("\(dummy.category) \(train.number)")
                                            .font(.headline)
                                            .foregroundColor(.primary)
                                        
                                        let descParts = train.description.components(separatedBy: " - ")
                                        let origin = descParts.first ?? train.description
                                        let destination = descParts.count > 1 ? descParts[1] : ""
                                        Text("\(origin) → \(destination)")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                    
                                    Spacer()
                                    
                                    let hasNotifications = train.notifyDelay ?? false
                                    HStack(spacing: 4) {
                                        if hasNotifications {
                                            Text("Attive")
                                                .font(.caption2.bold())
                                                .foregroundColor(.green)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Color.green.opacity(0.12))
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
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Notifiche")
        .navigationBarTitleDisplayMode(.large)
        .sheet(item: $selectedTrainForConfig) { train in
            if let index = manager.favoriteTrains.firstIndex(where: { $0.id == train.id }) {
                TrainNotificationConfigSheet(train: Binding(
                    get: { manager.favoriteTrains[index] },
                    set: { manager.favoriteTrains[index] = $0 }
                ))
            }
        }
        .onAppear {
            // Enrich any existing favorites that are missing departure/arrival times
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

struct TrainNotificationConfigSheet: View {
    @Binding var train: SavedTrain
    @EnvironmentObject var manager: TrainManager
    @EnvironmentObject var passanteManager: PassanteManager
    @Environment(\.dismiss) var dismiss
    @State private var stops: [Stop] = []
    @State private var isLoadingStops = false
    @State private var showPaywallSheet = false
    @State private var notificationNoticeMessage: String? = nil
    
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

                Section(header: Text("Treno")) {
                    HStack(spacing: 12) {
                        Image(systemName: "train.side.front.car")
                            .foregroundColor(.blue)
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
                        }
                    }
                    .padding(.vertical, 4)
                }
                
                Section(header: Text("Widget Schermata Home"), footer: Text("Disattiva se non vuoi mostrare questo treno nei widget.")) {
                    Toggle("Mostra nei Widget", isOn: Binding(
                        get: { train.showInWidget ?? true },
                        set: { newValue in
                            train.showInWidget = newValue
                            saveAndSync()
                            if let groupDefaults = UserDefaults(suiteName: "group.carlo.InOrario") {
                                var excluded = Set(groupDefaults.stringArray(forKey: "excludedWidgetTrainNumbers_v1") ?? [])
                                if newValue {
                                    excluded.remove(train.number)
                                } else {
                                    excluded.insert(train.number)
                                }
                                groupDefaults.set(Array(excluded), forKey: "excludedWidgetTrainNumbers_v1")
                                if let encoded = try? JSONEncoder().encode(excluded) {
                                    groupDefaults.set(encoded, forKey: "excludedWidgetTrainNumbers_v1")
                                }
                            }
                            WidgetCenter.shared.reloadAllTimelines()
                        }
                    ))
                }
                
                Section(header: Text("Notifica di Base"), footer: Group {
                    if !manager.hasSupport() {
                        Text("Per via dei costi dei server, l'account gratuito consente di attivare le notifiche per 1 solo treno alla volta. Se attivi le notifiche per questo treno, verranno disattivate sugli altri.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }) {
                    Toggle(isOn: Binding(
                        get: { train.notifyDelay ?? false },
                        set: { newValue in
                            notificationNoticeMessage = nil
                            if newValue {
                                if !manager.hasSupport() {
                                    var disabledAnyOther = false
                                    for i in 0..<manager.favoriteTrains.count {
                                        if manager.favoriteTrains[i].id != train.id {
                                            let hadNotif = (manager.favoriteTrains[i].notifyDelay == true) ||
                                                           (manager.favoriteTrains[i].notifyDeparture == true) ||
                                                           (manager.favoriteTrains[i].notifyStationPass == true) ||
                                                           (manager.favoriteTrains[i].notifyPlatformChange == true)
                                            if hadNotif {
                                                manager.favoriteTrains[i].notifyDelay = false
                                                manager.favoriteTrains[i].notifyDeparture = false
                                                manager.favoriteTrains[i].notifyStationPass = false
                                                manager.favoriteTrains[i].notifyPlatformChange = false
                                                disabledAnyOther = true
                                            }
                                        }
                                    }
                                    
                                    if disabledAnyOther {
                                        notificationNoticeMessage = "Le notifiche del treno precedente sono state disattivate. L'account gratuito consente 1 notifica per treno."
                                    }
                                } else {
                                    // For premium users, enforce the limit of 10
                                    let limit = manager.getLimit()
                                    let activeCount = manager.favoriteTrains.filter { $0.notifyDelay == true && $0.id != train.id }.count
                                    if activeCount >= limit {
                                        Haptics.notify(.error)
                                        notificationNoticeMessage = "Puoi avere al massimo \(limit) notifiche attive alla volta. Disattivane un'altra per procedere."
                                        return
                                    }
                                }
                            }
                            
                            train.notifyDelay = newValue
                            if !newValue {
                                train.notifyDeparture = false
                                train.notifyStationPass = false
                                train.notifyPlatformChange = false
                            }
                            saveAndSync()
                        }
                    )) {
                        Text("Notifica variazione Ritardo")
                    }
                    
                    if train.notifyDelay ?? false {
                        DaySelectorView(
                            activeDays: $train.activeDays,
                            isDisabled: !manager.hasSupport(),
                            onTapDisabled: {
                                showPaywallSheet = true
                            }
                        ) {
                            saveAndSync()
                        }
                        .padding(.vertical, 4)
                    }
                }
                
                if train.notifyDelay ?? false {
                    Section(header: Text("Notifiche Avanzate")) {
                        Toggle(isOn: Binding(
                            get: { train.notifyDeparture ?? false },
                            set: { newValue in
                                train.notifyDeparture = newValue
                                saveAndSync()
                            }
                        )) {
                            Text("Notifica alla partenza da origine")
                        }
                        
                        Toggle(isOn: Binding(
                            get: { train.notifyStationPass ?? false },
                            set: { newValue in
                                train.notifyStationPass = newValue
                                saveAndSync()
                                if newValue {
                                    loadStops()
                                }
                            }
                        )) {
                            Text("Notifica al passaggio in stazione")
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
                            .padding(.leading, 8)
                            .onAppear {
                                loadStops()
                            }
                        }
                        
                        Toggle(isOn: Binding(
                            get: { train.notifyPlatformChange ?? false },
                            set: { newValue in
                                train.notifyPlatformChange = newValue
                                saveAndSync()
                                if newValue {
                                    loadStops()
                                }
                            }
                        )) {
                            Text("Notifica cambio binario in stazione")
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
                            .padding(.leading, 8)
                            .onAppear {
                                loadStops()
                            }
                        }
                    }
                }
            }
            .disabled(isItalo)
            .navigationTitle("Impostazioni Notifiche")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fatto") {
                        dismiss()
                    }
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
    }
    
    private func saveAndSync() {
        manager.saveFavorites()
        manager.syncRemoteNotifications()
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

struct DaySelectorView: View {
    @Binding var activeDays: [Int]?
    var isDisabled: Bool = false
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
            HStack {
                Text("Giorni attivi:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                if isDisabled {
                    Text("(Solo Sostenitori)")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
            }
            
            HStack(spacing: 6) {
                ForEach(days, id: \.0) { dayNum, label in
                    let isSelected = (activeDays == nil || activeDays!.contains(dayNum)) && !isDisabled
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
                            .background(isDisabled ? Color(.systemGray5) : (isSelected ? Color.blue : Color(.systemGray6)))
                            .foregroundColor(isDisabled ? Color(.secondaryLabel) : (isSelected ? .white : .primary))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
            
            if isDisabled {
                Text("La scelta dei giorni della settimana è riservata a chi sostiene il progetto In Orario.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.top, 2)
            }
        }
    }
    
    private func toggleDay(_ dayNum: Int) {
        var current = activeDays ?? [1, 2, 3, 4, 5, 6, 7]
        if current.contains(dayNum) {
            current.removeAll(where: { $0 == dayNum })
        } else {
            current.append(dayNum)
            current.sort()
        }
        
        if current.count == 7 {
            activeDays = nil
        } else {
            activeDays = current
        }
        onToggle()
    }
}

struct SmartSuggestionsSettingsView: View {
    @EnvironmentObject var usageTracker: UsageTracker
    @EnvironmentObject var guessingEngine: TrainGuessingEngine
    @State private var showDeleteConfirmation = false
    @State private var showResetIgnoredConfirmation = false

    var body: some View {
        List {
            Section(header: Text("Stato")) {
                Toggle(isOn: $usageTracker.smartSuggestionsEnabled) {
                    Label("Suggerimenti personalizzati", systemImage: "sparkles")
                        .font(.headline)
                }
            }

            
            let totalIgnored = usageTracker.ignoredStationNames.count + usageTracker.ignoredTrainNumbers.count + usageTracker.ignoredRouteKeys.count
            if totalIgnored > 0 {
                Section(
                    header: Text("Elementi ignorati"),
                    footer: Text("Puoi ignorare singoli elementi con un tocco prolungato su di essi nella sezione 'Per te'.")
                ) {
                    HStack {
                        Label("Suggerimenti nascosti", systemImage: "eye.slash")
                        Spacer()
                        Text("\(totalIgnored)")
                            .foregroundColor(.secondary)
                    }
                    
                    Button(role: .destructive) {
                        showResetIgnoredConfirmation = true
                    } label: {
                        Label("Ripristina suggerimenti ignorati", systemImage: "arrow.counterclockwise")
                    }
                }
            }
            
            Section(header: Text("Dati raccolti")) {
                Text("L'app apprende le tue abitudini (stazioni cercate, treni consultati, tratte preferite) per mostrarti informazioni personalizzate nella home al momento opportuno. I dati sono salvati esclusivamente in locale sul tuo dispositivo.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Label("Cancella preferenze apprese", systemImage: "trash")
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


