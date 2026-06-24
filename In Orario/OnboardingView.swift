import SwiftUI

struct OnboardingPage: Identifiable {
    let id = UUID()
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
    
    let pages = [
        OnboardingPage(
            title: "Benvenuto su In Orario",
            description: "Il tuo compagno ideale per viaggiare in treno. Vedi sul tuo iPhone esattamente ciò che mostrano i tabelloni fisici delle stazioni con dati ufficiali RFI aggiornati all'istante.",
            iconName: "train.side.front.car",
            iconColor: .blue
        ),
        OnboardingPage(
            title: "Stazione di Casa / Lavoro",
            description: "Cerca e salva la tua stazione preferita. Quando attivi il filtro Casa 🏠, l'app mostrerà solo i treni diretti qui.",
            iconName: "house.fill",
            iconColor: .orange
        ),
        OnboardingPage(
            title: "Le Tue Tratte Preferite",
            description: "Salva le tratte generiche (es. Magenta ➔ Milano Porta Garibaldi) slegate dagli orari per cercarle all'istante in tempo reale.",
            iconName: "star.fill",
            iconColor: .yellow
        ),
        OnboardingPage(
            title: "Passante & Tunnel",
            description: "Monitora lo stato del Passante di Milano e del relativo Tunnel sotterraneo in un'unica schermata. Seleziona qui sotto le tue linee suburbane preferite da tenere sott'occhio:",
            iconName: "tram.fill",
            iconColor: .green
        ),
        OnboardingPage(
            title: "Coincidenze Metropolitana",
            description: "Interscambi treno-metropolitana calcolati al secondo in base alla conformazione di ciascuna stazione.",
            iconName: "arrow.triangle.turn.up.right.diamond.fill",
            iconColor: .red
        ),
        OnboardingPage(
            title: "Funzioni Smart & Widget",
            description: "Tutto ciò di cui hai bisogno per viaggiare senza stress:",
            iconName: "sparkles",
            iconColor: .purple
        ),
        OnboardingPage(
            title: "Info Utili & Posizione",
            description: "Resta aggiornato sul servizio ed ottimizza la navigazione:",
            iconName: "location.circle.fill",
            iconColor: .blue
        )
    ]
    
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
                    ForEach(0..<pages.count, id: \.self) { index in
                        VStack {
                            if index == 0 {
                                OnboardingCardView(page: pages[index], isLastPage: false) {}
                            } else if index == 1 {
                                OnboardingHomeStationPickerView()
                            } else if index == 2 {
                                OnboardingFavoriteRoutesView()
                            } else if index == 3 {
                                OnboardingPassanteLinePickerView(page: pages[index])
                            } else if index == 4 {
                                OnboardingMetroInterchangesView(page: pages[index])
                            } else if index == 5 {
                                OnboardingFeaturesView(page: pages[index])
                            } else if index == 6 {
                                OnboardingNewsAndGPSView(page: pages[index]) {
                                    Haptics.play(.medium)
                                    locationManager.requestAuthorization()
                                }
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
    }
}

struct OnboardingCardView: View {
    let page: OnboardingPage
    let isLastPage: Bool
    var requestLocationAction: () -> Void
    
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
                Text(page.title)
                    .font(.system(.title, design: .rounded))
                    .bold()
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                
                Text(page.description)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(page.description.contains("•") ? .leading : .center)
                    .padding(.horizontal, 35)
                    .lineSpacing(4)
            }
            
            if page.iconName == "location.circle.fill" {
                Button(action: {
                    requestLocationAction()
                }) {
                    HStack {
                        Image(systemName: "location.fill")
                        Text("Consenti Posizione GPS")
                    }
                    .font(.subheadline.bold())
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.orange.opacity(0.15))
                    .foregroundColor(.orange)
                    .cornerRadius(20)
                }
                .padding(.top, 10)
            }
            
            Spacer()
           }
    }
}

struct OnboardingHomeStationPickerView: View {
    @EnvironmentObject var manager: TrainManager
    @EnvironmentObject var passanteManager: PassanteManager
    @State private var homeDestInput = ""
    @State private var hasSaved = false
    
    // Per le stazioni preferite generiche
    @State private var favStationName = ""
    @State private var favStationID = ""
    @State private var showFavSearch = false
    
    var body: some View {
        VStack(spacing: 12) {
            Text("Stazione di Casa & Preferite")
                .font(.system(.title, design: .rounded))
                .bold()
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
                .padding(.top, 10)
            
            Text("Configura la stazione di casa per il filtro rapido 🏠 e aggiungi le stazioni che frequenti più spesso per averle sempre in primo piano.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
            
            ScrollView {
                VStack(spacing: 20) {
                    // SEZIONE CASA / LAVORO
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Stazione di Casa / Lavoro (Filtro 🏠)")
                            .font(.subheadline.bold())
                            .foregroundColor(.orange)
                            .padding(.horizontal, 30)
                        
                        let allStations = SuburbanData.shared.allLines.flatMap { $0.stations.map { $0.name.capitalized } } + manager.allRFIStations.map { $0.name.capitalized }
                        AutocompleteField(
                            label: "Seleziona Stazione di Casa",
                            placeholder: "Es. Magenta, Rho, Milano Centrale...",
                            text: $homeDestInput,
                            suggestions: Array(Set(allStations)).sorted()
                        )
                        .padding(.horizontal, 30)
                        
                        if !manager.homeDestinationStationName.isEmpty {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("Stazione salvata: **\(manager.homeDestinationStationName)**")
                                    .font(.caption)
                            }
                            .padding(.horizontal, 30)
                            .padding(.top, 2)
                        }
                        
                        HStack(spacing: 15) {
                            Button(action: {
                                Haptics.play(.medium)
                                manager.homeDestinationStationName = homeDestInput
                                manager.saveFavorites()
                                hasSaved = true
                                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                            }) {
                                Text(manager.homeDestinationStationName.isEmpty ? "Salva Stazione" : "Aggiorna")
                                    .font(.subheadline.bold())
                                    .padding(.vertical, 8)
                                    .frame(maxWidth: .infinity)
                                    .background(homeDestInput.isEmpty ? Color.gray : Color.orange)
                                    .foregroundColor(.white)
                                    .cornerRadius(10)
                            }
                            .disabled(homeDestInput.isEmpty)
                            
                            if !manager.homeDestinationStationName.isEmpty {
                                Button(action: {
                                    Haptics.play(.medium)
                                    homeDestInput = ""
                                    manager.homeDestinationStationName = ""
                                    manager.saveFavorites()
                                    hasSaved = false
                                }) {
                                    Text("Rimuovi")
                                        .font(.subheadline.bold())
                                        .padding(.vertical, 8)
                                        .frame(maxWidth: .infinity)
                                        .background(Color.red.opacity(0.1))
                                        .foregroundColor(.red)
                                        .cornerRadius(10)
                                }
                            }
                        }
                        .padding(.horizontal, 30)
                    }
                    
                    Divider()
                        .padding(.horizontal, 30)
                    
                    // SEZIONE STAZIONI PREFERITE GENERALI
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Le Mie Stazioni Preferite")
                            .font(.subheadline.bold())
                            .foregroundColor(.blue)
                            .padding(.horizontal, 30)
                        
                        Button(action: { showFavSearch = true }) {
                            HStack {
                                Image(systemName: "magnifyingglass")
                                    .foregroundColor(.secondary)
                                Text(favStationName.isEmpty ? "Cerca e aggiungi stazione preferita..." : favStationName)
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
                        
                        // Lista stazioni preferite già aggiunte
                        VStack(spacing: 8) {
                            if manager.myStations.isEmpty {
                                Text("Nessuna stazione preferita aggiunta.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .italic()
                                    .padding(.top, 5)
                            } else {
                                ForEach(manager.myStations, id: \.name) { station in
                                    HStack {
                                        Image(systemName: "building.2.crop.circle.fill")
                                            .foregroundColor(.orange)
                                        Text(station.name)
                                            .font(.subheadline.bold())
                                        Spacer()
                                        Button(role: .destructive) {
                                            Haptics.play(.medium)
                                            if let vtID = station.vtID {
                                                manager.removeMyStation(vtID: vtID)
                                            }
                                        } label: {
                                            Image(systemName: "trash")
                                                .foregroundColor(.red)
                                        }
                                    }
                                    .padding(.horizontal, 15)
                                    .padding(.vertical, 10)
                                    .background(Color(.secondarySystemBackground).opacity(0.6))
                                    .cornerRadius(10)
                                }
                            }
                        }
                        .padding(.horizontal, 30)
                    }
                }
                .padding(.bottom, 20)
            }
        }
        .onAppear {
            homeDestInput = manager.homeDestinationStationName
        }
        .sheet(isPresented: $showFavSearch) {
            StationSelectionSheet(selectedName: $favStationName, selectedID: $favStationID, title: "Aggiungi Preferita")
        }
        .onChange(of: favStationID) { oldValue, newValue in
            if !newValue.isEmpty {
                Haptics.play(.medium)
                // Cerca se c'è un vtID corrispondente o se è sui dati suburban/rfi
                let normalized = favStationName.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                
                // Proviamo a recuperare un vtID
                var foundVtID: String? = nil
                
                // Ricerca nei dati suburbani
                for line in SuburbanData.shared.allLines {
                    if let stat = line.stations.first(where: { $0.name.lowercased() == normalized }) {
                        foundVtID = stat.vtID
                        break
                    }
                }
                
                // Ricerca nelle stazioni RFI caricate
                if foundVtID == nil {
                    if let exactRFI = manager.allRFIStations.first(where: { $0.name.lowercased() == normalized }) {
                        // Per RFI non abbiamo sempre vtID nativo ma myStations accetta vtID.
                        // Usiamo una codifica fittizia o cerchiamo se c'è matching in rfiID
                        foundVtID = exactRFI.rfiID
                    }
                }
                
                // Fallback con ID passato dalla ricerca trenitalia
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

struct OnboardingFavoriteRoutesView: View {
    @EnvironmentObject var manager: TrainManager
    @EnvironmentObject var passanteManager: PassanteManager
    
    @State private var originName = ""
    @State private var originID = ""
    @State private var destName = ""
    @State private var destID = ""
    
    @State private var showOriginSearch = false
    @State private var showDestSearch = false
    
    var body: some View {
        VStack(spacing: 12) {
            Text("Le Tue Tratte Preferite")
                .font(.system(.title, design: .rounded))
                .bold()
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
                .padding(.top, 10)
            
            Text("Salva le tratte generiche (es. Magenta ➔ Milano Porta Garibaldi). Non contengono orari fissi e mostreranno tutti i treni regionali e suburbani in tempo reale.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
            
            VStack(spacing: 12) {
                Button(action: { showOriginSearch = true }) {
                    HStack {
                        Image(systemName: "circle.fill")
                            .foregroundColor(.orange)
                            .font(.caption2)
                        Text(originName.isEmpty ? "Seleziona Stazione di Partenza" : originName)
                            .fontWeight(originName.isEmpty ? .regular : .semibold)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(12)
                }
                .foregroundColor(.primary)
                .padding(.horizontal, 30)
                
                Button(action: { showDestSearch = true }) {
                    HStack {
                        Image(systemName: "mappin.circle.fill")
                            .foregroundColor(.red)
                            .font(.subheadline)
                        Text(destName.isEmpty ? "Seleziona Stazione di Arrivo" : destName)
                            .fontWeight(destName.isEmpty ? .regular : .semibold)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(12)
                }
                .foregroundColor(.primary)
                .padding(.horizontal, 30)
                
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
                    Text("Aggiungi ai Preferiti")
                        .bold()
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(originID.isEmpty || destID.isEmpty || originID == destID ? Color.gray : Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .disabled(originID.isEmpty || destID.isEmpty || originID == destID)
                .padding(.horizontal, 30)
            }
            
            Divider()
                .padding(.horizontal, 30)
                .padding(.vertical, 5)
            
            ScrollView {
                VStack(spacing: 8) {
                    if manager.favoriteRoutes.isEmpty {
                        Text("Nessuna tratta preferita ancora aggiunta.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .italic()
                            .padding(.top, 10)
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
                            }
                            .padding()
                            .background(Color(.secondarySystemBackground).opacity(0.6))
                            .cornerRadius(12)
                        }
                    }
                }
                .padding(.horizontal, 30)
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

struct OnboardingPassanteLinePickerView: View {
    let page: OnboardingPage
    @EnvironmentObject var manager: TrainManager
    @EnvironmentObject var passanteManager: PassanteManager
    
    var body: some View {
        VStack(spacing: 12) {
            Text(page.title)
                .font(.system(.title, design: .rounded))
                .bold()
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
                .padding(.top, 10)
            
            Text(page.description)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
            
            // Griglia compatta delle linee S (S1-S13)
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
                
                Text("Nelle impostazioni dell'app potrai configurare le singole stazioni da mostrare per ciascuna linea e se includere le stazioni esterne alla tratta urbana.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 35)
                    .lineSpacing(2)
            }
            .padding(.top, 5)
            .padding(.bottom, 15)
            
            Spacer()
        }
    }
}

struct OnboardingFeaturesView: View {
    let page: OnboardingPage
    
    var body: some View {
        VStack(spacing: 12) {
            Text(page.title)
                .font(.system(.title, design: .rounded))
                .bold()
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
                .padding(.top, 10)
            
            Text(page.description)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
            
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    FeatureRow(icon: "iphone.circle.fill", color: .purple, title: "Live Activities & Dynamic Island", desc: "Segui l'andamento del treno direttamente sulla Schermata di Blocco e nell'Isola Dinamica.")
                    
                    FeatureRow(icon: "bolt.fill", color: .yellow, title: "Smart Routes", desc: "Algoritmo intelligente per trovare le migliori coincidenze tra treni regionali e metropolitane.")
                    
                    FeatureRow(icon: "bookmark.fill", color: .blue, title: "Treni Salvati", desc: "Tieni d'occhio i tuoi treni frequenti direttamente dalla dashboard principale.")
                    
                    FeatureRow(icon: "exclamationmark.bubble.fill", color: .orange, title: "Segnalazioni in Tempo Reale", desc: "Segnala affollamento, temperatura o blocchi del treno in un lampo per aiutare i viaggiatori.")
                    
                    FeatureRow(icon: "tram", color: .teal, title: "Orari della Metropolitana", desc: "Esplora gli orari integrati della metropolitana di Milano direttamente dentro l'app.")
                    
                    FeatureRow(icon: "square.grid.2x2.fill", color: .green, title: "Widget per la Schermata Home", desc: "Visualizza lo stato dei tuoi treni o del passante a colpo d'occhio senza aprire l'app.")
                }
                .padding(.horizontal, 30)
                .padding(.top, 10)
            }
            
            Spacer()
        }
    }
}

struct OnboardingNewsAndGPSView: View {
    let page: OnboardingPage
    var requestLocationAction: () -> Void
    @EnvironmentObject var locationManager: LocationManager
    
    @State private var animateIcon = false
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Info Utili & Posizione")
                .font(.system(.title, design: .rounded))
                .bold()
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
                .padding(.top, 10)
            
            Text("Resta aggiornato sul servizio ed ottimizza la navigazione:")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
            
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    // SEZIONE NEWS / SCIOPERI
                    HStack(alignment: .top, spacing: 15) {
                        ZStack {
                            Circle()
                                .fill(Color.red.opacity(0.12))
                                .frame(width: 46, height: 46)
                            
                            Image(systemName: "megaphone.fill")
                                .font(.title3)
                                .foregroundColor(.red)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Scioperi & News in Tempo Reale")
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            Text("Ricevi notifiche ed avvisi elaborati su scioperi, ritardi improvvisi o lavori sulla rete ferroviaria e metropolitana direttamente nella scheda News dell'app.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .lineSpacing(2)
                        }
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground).opacity(0.5))
                    .cornerRadius(16)
                    
                    // SEZIONE GPS / POSIZIONE
                    HStack(alignment: .top, spacing: 15) {
                        ZStack {
                            Circle()
                                .fill(Color.blue.opacity(0.12))
                                .frame(width: 46, height: 46)
                                .scaleEffect(animateIcon ? 1.05 : 0.95)
                            
                            Image(systemName: "location.fill")
                                .font(.title3)
                                .foregroundColor(.blue)
                                .scaleEffect(animateIcon ? 1.08 : 0.92)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Stazioni Vicine con il GPS")
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            Text("Consenti l'uso della tua posizione per trovare all'istante le stazioni e le fermate del Passante a te più vicine, facilitando la consultazione rapida degli orari.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .lineSpacing(2)
                        }
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground).opacity(0.5))
                    .cornerRadius(16)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                            animateIcon = true
                        }
                    }
                    
                    // BUTTON CONSENTI GPS
                    Button(action: {
                        Haptics.play(.medium)
                        requestLocationAction()
                    }) {
                        HStack {
                            Image(systemName: "location.circle.fill")
                            Text("Consenti Posizione GPS")
                        }
                        .font(.subheadline.bold())
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(22)
                        .shadow(color: Color.blue.opacity(0.3), radius: 8, x: 0, y: 4)
                    }
                    .padding(.top, 10)
                }
                .padding(.horizontal, 30)
                .padding(.bottom, 20)
            }
            
            Spacer()
        }
    }
}


struct FeatureRow: View {
    let icon: String
    let color: Color
    let title: String
    let desc: String
    
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

struct OnboardingMetroInterchangesView: View {
    let page: OnboardingPage
    
    var body: some View {
        VStack(spacing: 12) {
            Text(page.title)
                .font(.system(.title, design: .rounded))
                .bold()
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
                .padding(.top, 10)
            
            Text(page.description)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
            
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    // Come funziona
                    HStack(alignment: .top, spacing: 15) {
                        Image(systemName: "hand.tap.fill")
                            .font(.title3)
                            .foregroundColor(.blue)
                            .frame(width: 40, height: 40)
                            .background(Color.blue.opacity(0.12))
                            .cornerRadius(10)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Anteprima con Pressione Prolungata")
                                .font(.subheadline.bold())
                            Text("Dalla vista di un treno basta tenere premuto sulla fermata di interscambio (es. Centrale, Garibaldi, Dateo) per vedere al volo le partenze metro in tempo reale.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineSpacing(2)
                        }
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground).opacity(0.5))
                    .cornerRadius(16)
                    
                    Divider().padding(.vertical, 4)
                    
                    Text("Stima di Fattibilità dell'Interscambio")
                        .font(.subheadline.bold())
                        .foregroundColor(.primary)
                    
                    Text("L'app confronta l'orario di arrivo stimato del treno con le partenze reali della metro, calcolando i tempi fisici di camminata specifici per ogni stazione:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineSpacing(2)
                    
                    VStack(spacing: 12) {
                        FeasibilityTutorialRow(
                            icon: "checkmark.circle.fill",
                            color: .green,
                            bg: Color.green.opacity(0.1),
                            title: "Ce la fai comodo",
                            desc: "Il tempo a disposizione è ampiamente sufficiente per raggiungere la banchina della metro camminando normalmente."
                        )
                        
                        FeasibilityTutorialRow(
                            icon: "figure.walk",
                            color: .orange,
                            bg: Color.orange.opacity(0.08),
                            title: "Sbrigati",
                            desc: "Il margine è ridotto. Devi camminare a passo molto svelto per non perdere la corsa."
                        )
                        
                        FeasibilityTutorialRow(
                            icon: "bolt.fill",
                            color: .orange,
                            bg: Color.orange.opacity(0.12),
                            title: "Corri!",
                            desc: "La coincidenza è al limite. Se vuoi prendere questa metro, devi correre."
                        )
                        
                        FeasibilityTutorialRow(
                            icon: "xmark.circle.fill",
                            color: .red,
                            bg: Color.red.opacity(0.1),
                            title: "Non ce la fai",
                            desc: "La metropolitana parte troppo presto rispetto all'arrivo del treno. Non è fisicamente possibile prenderla."
                        )
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
    let title: String
    let desc: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(bg)
                    .frame(width: 26, height: 26)
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(color)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.bold())
                    .foregroundColor(color)
                Text(desc)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(3)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}
