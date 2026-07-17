import SwiftUI

enum OnboardingPageType {
    case welcome, region, stations, passante, metro, features, ai
}

struct OnboardingPage: Identifiable {
    let id = UUID()
    let pageType: OnboardingPageType
    let title: String
    let description: String
    let iconName: String
    let iconColor: Color
}

struct OnboardingView: View {
    @Binding var showOnboarding: Bool
    @State private var currentPage = 0
    @EnvironmentObject var locationManager: LocationManager
    @EnvironmentObject var manager: TrainManager
    @EnvironmentObject var passanteManager: PassanteManager
    
    var pages: [OnboardingPage] {
        var p: [OnboardingPage] = []
        p.append(OnboardingPage(
            pageType: .welcome,
            title: "Benvenuto su In Orario",
            description: "Il tuo compagno ideale per viaggiare in treno. Vedi sul tuo iPhone esattamente ciò che mostrano i tabelloni fisici delle stazioni con dati ufficiali RFI aggiornati all'istante.",
            iconName: "train.side.front.car",
            iconColor: .blue
        ))
        p.append(OnboardingPage(
            pageType: .region,
            title: "La Tua Regione",
            description: "Seleziona la tua regione per ricevere scioperi, notizie rilevanti e abilitare i servizi locali.",
            iconName: "map.fill",
            iconColor: .red
        ))
        p.append(OnboardingPage(
            pageType: .stations,
            title: "Stazioni & Tratte Preferite",
            description: "Aggiungi le stazioni che frequenti più spesso e le tue tratte preferite per cercarle all'istante.",
            iconName: "star.fill",
            iconColor: .yellow
        ))
        
        if manager.strikeRegion == "Lombardia" {
            p.append(OnboardingPage(
                pageType: .passante,
                title: "Passante & Tunnel",
                description: "Monitora lo stato del Passante di Milano e del relativo Tunnel sotterraneo in un'unica schermata.",
                iconName: "tram.fill",
                iconColor: .green
            ))
        }
        
        let metroRegions = ["Lombardia", "Campania", "Piemonte", "Lazio"]
        if metroRegions.contains(manager.strikeRegion) {
            p.append(OnboardingPage(
                pageType: .metro,
                title: "Coincidenze Metropolitana",
                description: "Interscambi treno-metropolitana calcolati al secondo in base alla conformazione di ciascuna stazione.",
                iconName: "arrow.triangle.turn.up.right.diamond.fill",
                iconColor: .red
            ))
        }
        
        p.append(OnboardingPage(
            pageType: .features,
            title: "Funzioni Smart & Widget",
            description: "Tutto ciò di cui hai bisogno per viaggiare senza stress:",
            iconName: "sparkles",
            iconColor: .purple
        ))
        
        p.append(OnboardingPage(
            pageType: .ai,
            title: "Intelligenza Artificiale",
            description: "Personalizza come In Orario elabora le informazioni e gli scioperi per te:",
            iconName: "brain.head.profile",
            iconColor: .indigo
        ))
        
        return p
    }
    
    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()
            
            VStack {
                HStack {
                    Spacer()
                    Button("Salta") {
                        Haptics.play(.light)
                        withAnimation {
                            showOnboarding = false
                        }
                    }
                    .foregroundColor(.secondary)
                    .padding()
                    .opacity(currentPage == pages.count - 1 ? 0 : 1)
                }
                
                TabView(selection: $currentPage) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                        VStack {
                            switch page.pageType {
                            case .welcome:  OnboardingCardView(page: page, isLastPage: false)
                            case .region:   OnboardingRegionPickerView(page: page)
                            case .stations: OnboardingUnifiedPreferencesView(page: page)
                            case .passante: OnboardingPassanteLinePickerView(page: page)
                            case .metro:    OnboardingMetroInterchangesView(page: page)
                            case .features: OnboardingFeaturesView(page: page)
                            case .ai:       OnboardingAIChoiceView(page: page)
                            }
                        }
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .always))
                
                Spacer()
                
                Button(action: {
                    Haptics.play(.medium)
                    if currentPage < pages.count - 1 {
                        withAnimation {
                            currentPage += 1
                        }
                    } else {
                        withAnimation {
                            showOnboarding = false
                        }
                    }
                }) {
                    Text(currentPage == pages.count - 1 ? "Inizia ora" : "Avanti")
                        .bold()
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(14)
                        .padding(.horizontal, 30)
                }
                .padding(.bottom, 30)
            }
        }
        .onChange(of: pages.count) { old, new in
            if currentPage >= new {
                currentPage = new - 1
            }
        }
    }
}

struct OnboardingCardView: View {
    let page: OnboardingPage
    let isLastPage: Bool
    
    @State private var animateIcon = false
    
    var body: some View {
        VStack(spacing: 25) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(page.iconColor.opacity(0.12))
                    .frame(width: 160, height: 160)
                    .scaleEffect(animateIcon ? 1.05 : 0.95)
                
                Image(systemName: page.iconName)
                    .font(.system(size: 80))
                    .foregroundColor(page.iconColor)
                    .scaleEffect(animateIcon ? 1.1 : 0.9)
                    .shadow(color: page.iconColor.opacity(0.3), radius: animateIcon ? 12 : 6)
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                    animateIcon = true
                }
            }
            
            VStack(spacing: 12) {
                Text(LocalizedStringKey(page.title))
                    .font(.system(.title, design: .rounded))
                    .bold()
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                
                Text(LocalizedStringKey(page.description))
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(page.description.contains("•") ? .leading : .center)
                    .padding(.horizontal, 35)
                    .lineSpacing(4)
            }
            
            Spacer()
           }
    }
}

struct OnboardingRegionPickerView: View {
    let page: OnboardingPage
    @EnvironmentObject var manager: TrainManager

    private let regions = ["Tutte", "Abruzzo", "Basilicata", "Calabria", "Campania",
                           "Emilia-Romagna", "Friuli Venezia Giulia", "Lazio", "Liguria",
                           "Lombardia", "Marche", "Molise", "Piemonte", "Puglia",
                           "Sardegna", "Sicilia", "Toscana", "Trentino-Alto Adige",
                           "Umbria", "Valle d'Aosta", "Veneto"]

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            VStack(spacing: 12) {
                Image(systemName: page.iconName)
                    .font(.system(size: 56, weight: .semibold))
                    .foregroundStyle(page.iconColor)
                    .padding(.top, 20)

                Text(LocalizedStringKey(page.title))
                    .font(.title.bold())
                    .multilineTextAlignment(.center)

                Text(LocalizedStringKey(page.description))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
            }
            
            VStack(spacing: 8) {
                Text("Seleziona Regione")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Picker("Regione", selection: $manager.strikeRegion) {
                    ForEach(regions, id: \.self) { region in
                        Text(region == "Tutte" ? "🇮🇹 Nazionale / Tutte" : region).tag(region)
                    }
                }
                .pickerStyle(.menu)
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(14)
                .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
            }
            .padding(.top, 20)

            Spacer()
            Spacer()
        }
    }
}

struct OnboardingUnifiedPreferencesView: View {
    let page: OnboardingPage
    @EnvironmentObject var manager: TrainManager
    
    // Per le stazioni preferite
    @State private var favStationName = ""
    @State private var favStationID = ""
    @State private var showFavSearch = false
    
    // Per le tratte preferite
    @State private var originName = ""
    @State private var originID = ""
    @State private var destName = ""
    @State private var destID = ""
    @State private var showOriginSearch = false
    @State private var showDestSearch = false
    
    var body: some View {
        VStack(spacing: 12) {
            Text(LocalizedStringKey(page.title))
                .font(.system(.title, design: .rounded))
                .bold()
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
                .padding(.top, 10)
            
            Text(LocalizedStringKey(page.description))
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
            
            ScrollView {
                VStack(spacing: 20) {
                    
                    // SEZIONE STAZIONI PREFERITE GENERALI
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Stazioni Preferite")
                            .font(.subheadline.bold())
                            .foregroundColor(.blue)
                            .padding(.horizontal, 30)
                        
                        Button(action: { showFavSearch = true }) {
                            HStack {
                                Image(systemName: "magnifyingglass")
                                    .foregroundColor(.secondary)
                                Text(favStationName.isEmpty ? "Cerca e aggiungi stazione..." : favStationName)
                                    .foregroundColor(favStationName.isEmpty ? .secondary : .primary)
                                Spacer()
                                Image(systemName: "plus.circle.fill")
                                    .foregroundColor(.blue)
                            }
                            .padding()
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(12)
                        }
                        .padding(.horizontal, 30)
                        
                        VStack(spacing: 8) {
                            ForEach(manager.myStations, id: \.name) { station in
                                HStack {
                                    Image(systemName: "building.2.crop.circle.fill")
                                        .foregroundColor(.orange)
                                    Text(station.formattedName)
                                        .font(.subheadline.bold())
                                    Spacer()
                                    Button(role: .destructive) {
                                        Haptics.play(.medium)
                                        if let vtID = station.vtID {
                                            manager.removeMyStation(vtID: vtID)
                                        }
                                    } label: {
                                        Image(systemName: "trash").foregroundColor(.red)
                                    }
                                }
                                .padding(.horizontal, 15)
                                .padding(.vertical, 10)
                                .background(Color(.secondarySystemBackground).opacity(0.6))
                                .cornerRadius(10)
                            }
                        }
                        .padding(.horizontal, 30)
                    }
                    
                    Divider().padding(.horizontal, 30)
                    
                    // SEZIONE TRATTE
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Tratte Preferite")
                            .font(.subheadline.bold())
                            .foregroundColor(.purple)
                            .padding(.horizontal, 30)
                            
                        VStack(spacing: 8) {
                            Button(action: { showOriginSearch = true }) {
                                HStack {
                                    Image(systemName: "circle.fill").foregroundColor(.orange).font(.caption2)
                                    Text(originName.isEmpty ? "Stazione di Partenza" : originName)
                                        .fontWeight(originName.isEmpty ? .regular : .semibold)
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
                                }
                                .padding()
                                .background(Color(.secondarySystemBackground))
                                .cornerRadius(12)
                            }
                            .foregroundColor(.primary)
                            
                            Button(action: { showDestSearch = true }) {
                                HStack {
                                    Image(systemName: "mappin.circle.fill").foregroundColor(.red).font(.subheadline)
                                    Text(destName.isEmpty ? "Stazione di Arrivo" : destName)
                                        .fontWeight(destName.isEmpty ? .regular : .semibold)
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
                                }
                                .padding()
                                .background(Color(.secondarySystemBackground))
                                .cornerRadius(12)
                            }
                            .foregroundColor(.primary)
                            
                            Button(action: {
                                if !originID.isEmpty && !destID.isEmpty && originID != destID {
                                    Haptics.play(.medium)
                                    manager.toggleFavoriteRoute(originName: originName, originID: originID, destName: destName, destID: destID)
                                    originName = ""
                                    originID = ""
                                    destName = ""
                                    destID = ""
                                }
                            }) {
                                Text("Aggiungi Tratta")
                                    .bold()
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(originID.isEmpty || destID.isEmpty || originID == destID ? Color.gray : Color.purple)
                                    .foregroundColor(.white)
                                    .cornerRadius(12)
                            }
                            .disabled(originID.isEmpty || destID.isEmpty || originID == destID)
                        }
                        .padding(.horizontal, 30)
                        
                        VStack(spacing: 8) {
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
                                        Image(systemName: "trash").foregroundColor(.red)
                                    }
                                }
                                .padding()
                                .background(Color(.secondarySystemBackground).opacity(0.6))
                                .cornerRadius(12)
                            }
                        }
                        .padding(.horizontal, 30)
                        .padding(.top, 5)
                    }
                    
                }
                .padding(.bottom, 20)
            }
        }
        .sheet(isPresented: $showFavSearch) {
            StationSelectionSheet(selectedName: $favStationName, selectedID: $favStationID, title: "Aggiungi Preferita")
        }
        .sheet(isPresented: $showOriginSearch) {
            StationSelectionSheet(selectedName: $originName, selectedID: $originID, title: "Partenza")
        }
        .sheet(isPresented: $showDestSearch) {
            StationSelectionSheet(selectedName: $destName, selectedID: $destID, title: "Arrivo")
        }
        .onChange(of: favStationID) { oldValue, newValue in
            if !newValue.isEmpty {
                Haptics.play(.medium)
                let normalized = favStationName.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                var foundVtID: String? = nil
                
                for line in SuburbanData.shared.allLines {
                    if let stat = line.stations.first(where: { $0.name.lowercased() == normalized }) {
                        foundVtID = stat.vtID
                        break
                    }
                }
                
                if foundVtID == nil {
                    if let exactRFI = manager.allRFIStations.first(where: { $0.name.lowercased() == normalized }) {
                        foundVtID = exactRFI.rfiID
                    }
                }
                
                let finalVtID = foundVtID ?? favStationID
                if !manager.isMyStation(vtID: finalVtID) {
                    manager.addMyStation(name: favStationName, vtID: finalVtID)
                }
                
                favStationName = ""
                favStationID = ""
            }
        }
    }
}

struct OnboardingPassanteLinePickerView: View {
    let page: OnboardingPage
    @EnvironmentObject var manager: TrainManager
    @EnvironmentObject var passanteManager: PassanteManager
    
    var body: some View {
        VStack(spacing: 12) {
            Text(LocalizedStringKey(page.title))
                .font(.system(.title, design: .rounded))
                .bold()
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
                .padding(.top, 10)
            
            Text(LocalizedStringKey(page.description))
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
            
            let columns = [
                GridItem(.adaptive(minimum: 70, maximum: 90), spacing: 10)
            ]
            
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(SuburbanData.shared.allLines) { line in
                        let isSelected = passanteManager.selectedSuburbanLines.contains(line.id)
                        Button(action: {
                            Haptics.play(.light)
                            passanteManager.toggleSuburbanLine(line.id)
                        }) {
                            Text(line.id)
                                .font(.system(.headline, design: .rounded))
                                .bold()
                                .frame(width: 70, height: 44)
                                .background(isSelected ? line.color : Color(.secondarySystemBackground))
                                .foregroundColor(isSelected ? .white : .primary)
                                .cornerRadius(10)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(line.color, lineWidth: isSelected ? 0 : 1.5)
                                )
                        }
                    }
                }
                .padding(.horizontal, 30)
                .padding(.vertical, 10)
            }
            .frame(maxHeight: 220)
            
            VStack(spacing: 8) {
                Text("ℹ️ Nota sulle stazioni")
                    .font(.footnote.bold())
                    .foregroundColor(.secondary)
                
                Text("Nelle impostazioni dell'app potrai configurare le singole stazioni da mostrare per ciascuna linea.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 35)
            }
            .padding(.top, 5)
            .padding(.bottom, 15)
            
            Spacer()
        }
    }
}

struct OnboardingMetroInterchangesView: View {
    let page: OnboardingPage
    
    var body: some View {
        VStack(spacing: 12) {
            Text(LocalizedStringKey(page.title))
                .font(.system(.title, design: .rounded))
                .bold()
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
                .padding(.top, 10)
            
            Text(LocalizedStringKey(page.description))
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
            
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 15) {
                        Image(systemName: "hand.tap.fill")
                            .font(.title3)
                            .foregroundColor(.blue)
                            .frame(width: 40, height: 40)
                            .background(Color.blue.opacity(0.12))
                            .cornerRadius(10)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Pressione Prolungata")
                                .font(.subheadline.bold())
                            Text("Tieni premuto su una fermata di interscambio per vedere le partenze metro in tempo reale.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground).opacity(0.5))
                    .cornerRadius(16)
                    
                    Divider().padding(.vertical, 4)
                    
                    Text("Stima Interscambio")
                        .font(.subheadline.bold())
                        .foregroundColor(.primary)
                    
                    VStack(spacing: 8) {
                        FeasibilityTutorialRow(icon: "checkmark.circle.fill", color: .green, bg: Color.green.opacity(0.1), title: "Ce la fai comodo", desc: "Tempo ampiamente sufficiente.")
                        FeasibilityTutorialRow(icon: "figure.walk", color: .orange, bg: Color.orange.opacity(0.08), title: "Sbrigati", desc: "Margine ridotto, cammina veloce.")
                        FeasibilityTutorialRow(icon: "bolt.fill", color: .orange, bg: Color.orange.opacity(0.12), title: "Corri!", desc: "Coincidenza al limite.")
                        FeasibilityTutorialRow(icon: "xmark.circle.fill", color: .red, bg: Color.red.opacity(0.1), title: "Non ce la fai", desc: "Fisicamente impossibile.")
                    }
                    .padding(.top, 4)
                }
                .padding(.horizontal, 30)
                .padding(.bottom, 20)
            }
            
            Spacer()
        }
    }
}

struct FeasibilityTutorialRow: View {
    let icon: String
    let color: Color
    let bg: Color
    let title: LocalizedStringKey
    let desc: LocalizedStringKey
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(bg).frame(width: 26, height: 26)
                Image(systemName: icon).font(.system(size: 11, weight: .bold)).foregroundColor(color)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption.bold()).foregroundColor(color)
                Text(desc).font(.system(size: 11)).foregroundColor(.secondary).lineLimit(2)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

struct OnboardingFeaturesView: View {
    let page: OnboardingPage
    
    var body: some View {
        VStack(spacing: 12) {
            Text(LocalizedStringKey(page.title))
                .font(.system(.title, design: .rounded))
                .bold()
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
                .padding(.top, 10)
            
            Text(LocalizedStringKey(page.description))
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
            
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    FeatureRow(icon: "iphone.circle.fill", color: .purple, title: "Live Activities & Dynamic Island", desc: "Segui l'andamento del treno direttamente sulla Schermata di Blocco.")
                    FeatureRow(icon: "megaphone.fill", color: .red, title: "Scioperi & News", desc: "Ricevi notifiche ed avvisi elaborati su scioperi e ritardi improvvisi.")
                    FeatureRow(icon: "bolt.fill", color: .yellow, title: "Smart Routes", desc: "Trova le migliori coincidenze tra treni e metropolitane.")
                    FeatureRow(icon: "exclamationmark.bubble.fill", color: .orange, title: "Segnalazioni in Tempo Reale", desc: "Segnala affollamento o problemi per aiutare i viaggiatori.")
                    FeatureRow(icon: "tram", color: .teal, title: "Orari Metropolitana", desc: "Esplora gli orari integrati delle principali metropolitane italiane.")
                    FeatureRow(icon: "square.grid.2x2.fill", color: .green, title: "Widget", desc: "Visualizza lo stato dei tuoi treni senza aprire l'app.")
                }
                .padding(.horizontal, 30)
                .padding(.top, 10)
            }
            
            Spacer()
        }
    }
}

struct FeatureRow: View {
    let icon: String
    let color: Color
    let title: LocalizedStringKey
    let desc: LocalizedStringKey
    
    var body: some View {
        HStack(alignment: .top, spacing: 15) {
            Image(systemName: icon)
                .font(.title)
                .foregroundColor(color)
                .frame(width: 40, height: 40)
                .background(color.opacity(0.12))
                .cornerRadius(10)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.bold())
                Text(desc)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        }
    }
}

struct OnboardingAIChoiceView: View {
    let page: OnboardingPage
    @ObservedObject var aiManager = AIFeatureManager.shared
    @EnvironmentObject var manager: TrainManager
    
    var body: some View {
        VStack(spacing: 8) {
            Text(LocalizedStringKey(page.title))
                .font(.system(.title, design: .rounded))
                .bold()
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
                .padding(.top, 10)
            
            Text(LocalizedStringKey(page.description))
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
                .padding(.bottom, 4)
            
            ScrollView(showsIndicators: false) {
                AIModelSelectorView(isOnboarding: false)
                    .padding(.bottom, 20)
            }
        }
    }
}
