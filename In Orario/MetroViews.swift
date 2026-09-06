import SwiftUI
import MapKit
import CoreLocation
import Combine

// MARK: - Metro Home View

struct MetroHomeView: View {
    @EnvironmentObject var metroManager: MetroManager
    @EnvironmentObject var metroCache: MetroCache
    @EnvironmentObject var locationManager: LocationManager

    @State private var selectedStation: MetroStation? = nil
    @State private var isMapExpanded = false

    var nearbyStation: MetroStation? {
        metroManager.nearbyStation(from: locationManager.userLocation?.coordinate)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // MARK: Subtitle
                HStack(spacing: 8) {
                    Text("Metro")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.secondary)
                    
                    Text("BETA")
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.purple.opacity(0.15))
                        .foregroundColor(.purple)
                        .cornerRadius(6)
                }
                .padding(.leading, 20)
                .padding(.top, -4)
                .padding(.bottom, -10)

                // MARK: Status Dashboard
                MetroStatusDashboardView()

                // MARK: Recent Chips
                if !metroManager.recentStations.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            Text("Recenti:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            ForEach(metroManager.recentStations) { station in
                                Button {
                                    metroManager.addToRecent(station)
                                    selectedStation = station
                                } label: {
                                    HStack(spacing: 4) {
                                        let uLines = station.uniqueLines
                                        if uLines.count >= 2 {
                                            Circle()
                                                .fill(LinearGradient(stops: [.init(color: uLines[0].color, location: 0.5), .init(color: uLines[1].color, location: 0.5)], startPoint: .leading, endPoint: .trailing))
                                                .frame(width: 8, height: 8)
                                        } else {
                                            Circle().fill(station.color).frame(width: 8, height: 8)
                                        }
                                        Text(station.displayName)
                                            .font(.caption.weight(.medium))
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color(.secondarySystemGroupedBackground))
                                    .cornerRadius(20)
                                }
                                .foregroundColor(.primary)
                            }
                        }
                        .padding(.horizontal)
                    }
                }

                // MARK: Favorites
                if !metroManager.favoriteStations.isEmpty {
                    MetroSectionHeader(title: "Le Mie Stazioni Metro", icon: "star.fill", color: .orange)
                        .padding(.horizontal)
                    VStack(spacing: 10) {
                        ForEach(metroManager.favoriteStations) { station in
                            MetroStationCard(station: station) {
                                metroManager.addToRecent(station)
                                selectedStation = station
                            }
                            .padding(.horizontal)
                        }
                    }
                }

                // MARK: Nearby
                if let nearby = nearbyStation {
                    MetroSectionHeader(title: "Vicino a te", icon: "location.fill", color: .blue)
                        .padding(.horizontal)
                    MetroStationCard(station: nearby) {
                        metroManager.addToRecent(nearby)
                        selectedStation = nearby
                    }
                    .padding(.horizontal)
                }

                if metroManager.favoriteStations.isEmpty && nearbyStation == nil {
                    VStack(spacing: 12) {
                        Image(systemName: "tram.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.purple.opacity(0.3))
                        Text("Usa la ricerca in alto per trovare e salvare stazioni metro preferite")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                }

                // MARK: Interactive Map (Collapsible)
                DisclosureGroup(isExpanded: $isMapExpanded) {
                    MetroInteractiveMapView(onStationTap: { station in
                        metroManager.addToRecent(station)
                        selectedStation = station
                    })
                        .padding(.top, 10)
                } label: {
                    MetroSectionHeader(title: "Mappa Linee", icon: "map.fill", color: .purple)
                }
                .padding(14)
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(16)
                .padding(.horizontal)
                .padding(.bottom, 20)
                
                HStack {
                    Spacer()
                    Button(action: {
                        NotificationCenter.default.post(name: Notification.Name("OpenProfile"), object: nil)
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "gearshape")
                            Text("Impostazioni")
                        }
                        .font(.headline)
                        .foregroundColor(.blue)
                        .padding(.vertical, 16)
                    }
                    Spacer()
                }
                .padding(.bottom, 30)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationDestination(item: $selectedStation) { station in
            MetroStationDetailView(station: station)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenMetroStation"))) { notification in
            if let station = notification.object as? MetroStation {
                metroManager.addToRecent(station)
                selectedStation = station
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenMetroHistory"))) { _ in
            NotificationCenter.default.post(name: NSNotification.Name("TriggerOpenMetroHistorySheet"), object: nil)
        }
        .task {
            await metroManager.fetchMetroStatus()
        }
        .refreshable {
            await metroManager.fetchMetroStatus()
        }
    }
}

// MARK: - Section Header

struct MetroSectionHeader: View {
    let title: String
    let icon: String
    let color: Color
    var body: some View {
        Label(title, systemImage: icon)
            .font(.headline)
            .foregroundColor(color)
    }
}

// MARK: - Search Bar

struct MetroSearchBar: View {
    @Binding var query: String
    @Binding var isActive: Bool
    var focused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .font(.system(size: 17, weight: .medium))
            TextField("Cerca stazione metro...", text: $query)
                .font(.system(size: 17))
                .focused(focused)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(14)
        .shadow(color: Color.black.opacity(0.06), radius: 4, x: 0, y: 2)
        .animation(.easeInOut(duration: 0.2), value: query)
    }
}

// MARK: - Search Result Row

struct MetroSearchResultRow: View {
    let station: MetroStation
    let onTap: () -> Void
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                ZStack {
                    let uLines = station.uniqueLines
                    if uLines.count >= 2 {
                        let c1 = uLines[0].color
                        let c2 = uLines[1].color
                        Circle()
                            .fill(LinearGradient(stops: [.init(color: c1.opacity(0.15), location: 0.5), .init(color: c2.opacity(0.15), location: 0.5)], startPoint: .leading, endPoint: .trailing))
                            .frame(width: 36, height: 36)
                        
                        Image(systemName: "tram.fill")
                            .foregroundStyle(LinearGradient(stops: [.init(color: c1, location: 0.5), .init(color: c2, location: 0.5)], startPoint: .leading, endPoint: .trailing))
                            .font(.system(size: 16))
                    } else {
                        Circle().fill(station.color.opacity(0.15)).frame(width: 36, height: 36)
                        Image(systemName: "tram.fill").foregroundColor(station.color).font(.system(size: 16))
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(station.displayName).font(.subheadline.weight(.semibold)).foregroundColor(.primary)
                    let desc = station.uniqueLines.map { station.lineLabelWithBranch(String($0.name.prefix(2))) }.joined(separator: " · ")
                    Text(desc)
                        .font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundColor(Color(.tertiaryLabel))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }
}

// MARK: - Station Card

struct MetroStationCard: View {
    @EnvironmentObject var metroManager: MetroManager
    @EnvironmentObject var metroCache: MetroCache
    let station: MetroStation
    let onTap: () -> Void

    var hasInterchange: Bool {
        uniqueLineLabels(station.lines).count > 1
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 10) {
                    Text(station.displayName)
                        .font(.system(size: 19, weight: .bold))
                        .foregroundColor(.primary)
                    
                    ForEach(uniqueLineLabels(station.lines), id: \.self) { label in
                        MetroLineBadge(label: station.lineLabelWithBranch(label), color: colorForLabel(label, in: station.lines))
                    }
                    
                    Spacer()
                    
                    Button {
                        Haptics.play(.light)
                        metroManager.toggleFavorite(station)
                    } label: {
                        Image(systemName: metroManager.isFavorite(station) ? "star.fill" : "star")
                            .foregroundColor(metroManager.isFavorite(station) ? .orange : .secondary)
                            .font(.system(size: 20))
                    }
                    .buttonStyle(.plain)
                }
                
                if hasInterchange {
                    let grouped = Dictionary(grouping: station.lines) { line in
                        String(line.name.prefix(2))
                    }
                    let sortedKeys = grouped.keys.sorted()
                    
                    HStack(alignment: .top, spacing: 16) {
                        ForEach(sortedKeys, id: \.self) { key in
                            if let lines = grouped[key] {
                                VStack(alignment: .leading, spacing: 10) {
                                    ForEach(lines) { line in
                                        MetroLineNextDepartures(line: line, station: station, limit: 2, fontSize: 13)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                } else {
                    VStack(spacing: 10) {
                        ForEach(station.lines) { line in
                            MetroLineNextDepartures(line: line, station: station, limit: 3, fontSize: 14)
                        }
                    }
                }
            }
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.05), radius: 6, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .task(id: station.id) {
            for line in station.lines {
                let prefix = String(line.name.prefix(2))
                await metroCache.sync(
                    city: line.city,
                    line: prefix,
                    pdfID: line.pdfID ?? "",
                    direction: line.direction
                )
            }
        }
    }

    private func uniqueLineLabels(_ lines: [MetroLine]) -> [String] {
        var seen = Set<String>()
        return lines.compactMap { line -> String? in
            let prefix = String(line.name.prefix(2))
            guard !seen.contains(prefix) else { return nil }
            seen.insert(prefix)
            return prefix
        }
    }
    private func colorForLabel(_ label: String, in lines: [MetroLine]) -> Color {
        lines.first { $0.name.hasPrefix(label) }?.color ?? .gray
    }
}

struct MetroLineBadge: View {
    let label: String
    let color: Color
    var body: some View {
        Text(label)
            .font(.system(size: 12.5, weight: .bold))
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color)
            .cornerRadius(6)
    }
}

struct MetroLineNextDepartures: View {
    @EnvironmentObject var metroCache: MetroCache
    let line: MetroLine
    let station: MetroStation
    let limit: Int
    let fontSize: CGFloat

    var departures: [FormattedDeparture] {
        let mode = metroCache.getNextDepartures(metro: line, time: nil, now: Date())
        if case .exact(let deps) = mode { return Array(deps.prefix(limit)) }
        return []
    }

    var body: some View {
        HStack(spacing: 6) {
            let displayName = cleanLineName(line.name)
            
            Text(displayName)
                .font(.system(size: fontSize, weight: .medium))
                .foregroundColor(.secondary)
                .lineLimit(1)
            
            if departures.isEmpty {
                Text("—").font(.system(size: fontSize)).foregroundColor(Color(.tertiaryLabel))
            } else {
                HStack(spacing: 4) {
                    ForEach(departures, id: \.timeString) { dep in
                        Text(dep.timeString)
                            .font(.system(size: fontSize, weight: .semibold, design: .rounded))
                            .foregroundColor(.primary)
                            .padding(.horizontal, fontSize * 0.5)
                            .padding(.vertical, fontSize * 0.2)
                            .background(line.color.opacity(0.12))
                            .cornerRadius(6)
                            .fixedSize(horizontal: true, vertical: true)
                    }
                }
            }
            Spacer()
        }
    }

    private func cleanLineName(_ name: String) -> String {
        var clean = name
        let pattern = "^M[1-5]\\s+"
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let range = NSRange(clean.startIndex..<clean.endIndex, in: clean)
            clean = regex.stringByReplacingMatches(in: clean, options: [], range: range, withTemplate: "")
        }
        clean = clean.replacingOccurrences(of: "Rho/Bisc.", with: "Rho/Bis")
        clean = clean.replacingOccurrences(of: "S. Cristoforo", with: "S. Crist.")
        return clean
    }
}

// MARK: - Station Detail View

struct MetroStationDetailView: View {
    @EnvironmentObject var metroManager: MetroManager
    @EnvironmentObject var metroCache: MetroCache
    let station: MetroStation

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    ZStack {
                        let uLines = station.uniqueLines
                        if uLines.count >= 2 {
                            let c1 = uLines[0].color
                            let c2 = uLines[1].color
                            Circle()
                                .fill(LinearGradient(stops: [.init(color: c1.opacity(0.15), location: 0.5), .init(color: c2.opacity(0.15), location: 0.5)], startPoint: .leading, endPoint: .trailing))
                                .frame(width: 52, height: 52)
                            
                            Image(systemName: "tram.fill")
                                .font(.title2)
                                .foregroundStyle(LinearGradient(stops: [.init(color: c1, location: 0.5), .init(color: c2, location: 0.5)], startPoint: .leading, endPoint: .trailing))
                        } else {
                            Circle().fill(station.color.opacity(0.15)).frame(width: 52, height: 52)
                            Image(systemName: "tram.fill").font(.title2).foregroundColor(station.color)
                        }
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(station.displayName).font(.title2.bold())
                    }
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, 8)

                Divider()

                ForEach(station.lines) { line in
                    MetroLineDetailSection(line: line, station: station)
                        .padding(.horizontal)
                }
                Spacer(minLength: 20)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(station.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Haptics.play(.light)
                    metroManager.toggleFavorite(station)
                } label: {
                    Image(systemName: metroManager.isFavorite(station) ? "star.fill" : "star")
                        .foregroundColor(metroManager.isFavorite(station) ? .orange : .primary)
                }
            }
        }
        .task(id: station.id) { await refreshAll() }
        .refreshable { await refreshAll() }
    }

    private func refreshAll() async {
        await withTaskGroup(of: Void.self) { group in
            for line in station.lines {
                group.addTask {
                    let prefix = String(line.name.prefix(2))
                    await metroCache.sync(
                        city: line.city,
                        line: prefix,
                        pdfID: line.pdfID ?? "",
                        direction: line.direction,
                        force: true
                    )
                }
            }
        }
    }
}

struct MetroLineDetailSection: View {
    @EnvironmentObject var metroCache: MetroCache
    let line: MetroLine
    let station: MetroStation

    var mode: MetroDisplayMode {
        metroCache.getNextDepartures(metro: line, time: nil, now: Date())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle().fill(line.color).frame(width: 12, height: 12)
                Text(line.name).font(.headline)
                Spacer()
            }
            switch mode {
            case .exact(let deps):
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 8)], spacing: 8) {
                    ForEach(deps.prefix(12), id: \.timeString) { dep in
                        VStack(spacing: 2) {
                            Text(dep.timeString)
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                            if let dest = dep.destinationName {
                                Text(dest).font(.system(size: 9)).foregroundColor(.secondary).lineLimit(1)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(line.color.opacity(0.1))
                        .cornerRadius(10)
                    }
                }
            case .frequency(let f):
                Text(f).font(.subheadline).foregroundColor(.secondary)
            case .closed:
                Text("Servizio non attivo o dati non disponibili").font(.subheadline).foregroundColor(.secondary)
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
    }
}

// MARK: - Interactive Map View (PDF implementation)

import PDFKit

struct PDFPreviewView: UIViewRepresentable {
    let pdfURL: URL

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePage
        pdfView.isUserInteractionEnabled = false
        if let document = PDFDocument(url: pdfURL) {
            pdfView.document = document
        }
        return pdfView
    }

    func updateUIView(_ uiView: PDFView, context: Context) {}
}

struct ZoomablePDFView: UIViewRepresentable {
    let pdfURL: URL
    let onStationTap: (MetroStation) -> Void

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePage
        pdfView.displayDirection = .vertical
        pdfView.maxScaleFactor = 8.0
        pdfView.minScaleFactor = pdfView.scaleFactorForSizeToFit
        pdfView.delegate = context.coordinator
        
        if let document = PDFDocument(url: pdfURL) {
            pdfView.document = document
        }
        
        pdfView.isUserInteractionEnabled = true
        return pdfView
    }

    func updateUIView(_ uiView: PDFView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    class Coordinator: NSObject, PDFViewDelegate {
        let parent: ZoomablePDFView

        init(parent: ZoomablePDFView) {
            self.parent = parent
        }

        private func normalize(_ text: String) -> String {
            var s = text.lowercased()
            s = s.folding(options: .diacriticInsensitive, locale: .current)
            s = s.replacingOccurrences(of: "sant'", with: "s")
            s = s.replacingOccurrences(of: "sant’", with: "s")
            s = s.replacingOccurrences(of: "santa ", with: "s ")
            s = s.replacingOccurrences(of: "san ", with: "s ")
            return String(s.filter { $0.isLetter || $0.isNumber })
        }

        private func normalizeWithOverrides(_ query: String) -> String {
            let q = normalize(query)
            if q == "sestofs" {
                return "sesto1maggiofs"
            }
            if q == "villasangiovanni" {
                return "villasg"
            }
            if q == "pabbiategrasso" {
                return "abbiategrasso"
            }
            return q
        }

        func pdfViewWillClick(onLink sender: PDFView, with url: URL) {
            guard url.scheme == "metro",
                  let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let queryItems = components.queryItems,
                  let name = queryItems.first(where: { $0.name == "name" })?.value else {
                return
            }

            let qNorm = normalizeWithOverrides(name)
            if let station = MilanoMetroCatalog.stations.first(where: {
                let dbNorm = normalize($0.displayName)
                return qNorm == dbNorm ||
                       (qNorm.count >= 4 && dbNorm.contains(qNorm)) ||
                       (dbNorm.count >= 4 && qNorm.contains(dbNorm))
            }) {
                Haptics.play(.medium)
                DispatchQueue.main.async {
                    self.parent.onStationTap(station)
                }
            }
        }
    }
}

struct MetroMapFullScreenView: View {
    @Environment(\.dismiss) var dismiss
    let pdfURL: URL
    let onStationTap: (MetroStation) -> Void

    var body: some View {
        NavigationStack {
            ZoomablePDFView(pdfURL: pdfURL, onStationTap: onStationTap)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("Mappa Metropolitana")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Chiudi") {
                            dismiss()
                        }
                        .fontWeight(.bold)
                    }
                }
        }
    }
}

@MainActor
class MetroMapManager: ObservableObject {
    static let shared = MetroMapManager()
    
    @Published var isDownloading = false
    @Published var errorMessage: String? = nil
    @Published var isDownloaded = false
    
    private let remoteURL = URL(string: "https://gestioneinorario.toreroclub.com/metro_map.pdf")!
    
    var localPDFURL: URL? {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let localFile = docs.appendingPathComponent("metro_map.pdf")
        if FileManager.default.fileExists(atPath: localFile.path) {
            return localFile
        }
        if let bundleURL = Bundle.main.url(forResource: "metro_map", withExtension: "pdf") {
            return bundleURL
        }
        return nil
    }
    
    init() {
        checkStatus()
    }
    
    func checkStatus() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let localFile = docs.appendingPathComponent("metro_map.pdf")
        isDownloaded = FileManager.default.fileExists(atPath: localFile.path) || Bundle.main.url(forResource: "metro_map", withExtension: "pdf") != nil
    }
    
    func downloadMap() async {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let destinationURL = docs.appendingPathComponent("metro_map.pdf")
        
        isDownloading = true
        errorMessage = nil
        
        do {
            let (tempURL, response) = try await URLSession.shared.download(from: remoteURL)
            guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 else {
                throw NSError(domain: "DownloadError", code: 404, userInfo: [NSLocalizedDescriptionKey: "Impossibile scaricare la mappa dal server."])
            }
            
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.moveItem(at: tempURL, to: destinationURL)
            
            isDownloading = false
            isDownloaded = true
            Haptics.play(.medium)
        } catch {
            isDownloading = false
            errorMessage = "Errore durante il download: \(error.localizedDescription)"
            Haptics.play(.light)
        }
    }
}

struct MetroInteractiveMapView: View {
    let onStationTap: (MetroStation) -> Void
    @StateObject private var mapManager = MetroMapManager.shared
    @State private var showFullScreen = false
    
    var body: some View {
        if let pdfURL = mapManager.localPDFURL {
            Button {
                Haptics.play(.medium)
                showFullScreen = true
            } label: {
                ZStack(alignment: .bottomTrailing) {
                    PDFPreviewView(pdfURL: pdfURL)
                        .frame(height: 240)
                        .cornerRadius(14)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                        )
                    
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                        Text("Espandi")
                    }
                    .font(.caption.bold())
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.75))
                    .cornerRadius(8)
                    .padding(10)
                }
            }
            .buttonStyle(.plain)
            .fullScreenCover(isPresented: $showFullScreen) {
                MetroMapFullScreenView(pdfURL: pdfURL, onStationTap: { station in
                    showFullScreen = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        onStationTap(station)
                    }
                })
            }
        } else {
            VStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(.secondarySystemGroupedBackground))
                        .frame(height: 190)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color.purple.opacity(0.2), lineWidth: 1)
                        )
                    
                    VStack(spacing: 8) {
                        Image(systemName: "map.fill")
                            .font(.system(size: 36))
                            .foregroundColor(.purple)
                        
                        Text("Mappa Metropolitana Interattiva")
                            .font(.headline)
                        
                        Text("Scarica la mappa HD per consultarla ed esplorare le stazioni.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)
                        
                        if mapManager.isDownloading {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("Download in corso...")
                                    .font(.caption.bold())
                                    .foregroundColor(.purple)
                            }
                            .padding(.top, 4)
                        } else {
                            Button {
                                Task {
                                    await mapManager.downloadMap()
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "arrow.down.circle.fill")
                                    Text("Scarica Mappa Metro (~1.4 MB)")
                                }
                                .font(.caption.bold())
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Color.purple)
                                .foregroundColor(.white)
                                .cornerRadius(20)
                            }
                            .padding(.top, 4)
                        }
                        
                        if let error = mapManager.errorMessage {
                            Text(error)
                                .font(.caption2)
                                .foregroundColor(.red)
                        }
                    }
                    .padding(14)
                }
            }
        }
    }
}

// MARK: - Metro Status Dashboard View

struct MetroStatusDashboardView: View {
    @EnvironmentObject var metroManager: MetroManager

    let lineColors: [String: Color] = [
        "M1": Color(red: 0.89, green: 0.0, blue: 0.10),
        "M2": Color(red: 0.11, green: 0.51, blue: 0.28),
        "M3": Color(red: 0.96, green: 0.65, blue: 0.14),
        "M4": Color(red: 0.0, green: 0.45, blue: 0.73),
        "M5": Color(red: 0.56, green: 0.27, blue: 0.68)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // General Alerts / Disruptions Panel
            if !metroManager.metroAlertMessage.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                            .font(.system(size: 16, weight: .bold))
                        Text("Avviso mobilità ATM")
                            .font(.subheadline.weight(.bold))
                            .foregroundColor(.primary)
                    }
                    Text(metroManager.metroAlertMessage)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .lineSpacing(3)
                        .multilineTextAlignment(.leading)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(16)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.orange.opacity(0.2), lineWidth: 1)
                )
                .padding(.horizontal)
            }

            // Real-time status list
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(["M1", "M2", "M3", "M4", "M5"], id: \.self) { line in
                        let status = metroManager.lineStatuses[line] ?? "Regolare"
                        
                        NavigationLink(destination: MetroLineVerticalView(line: line)) {
                            HStack(spacing: 8) {
                                Text(line)
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(lineColors[line] ?? .gray)
                                    .cornerRadius(6)
                                
                                Circle()
                                    .fill(statusColor(for: status))
                                    .frame(width: 8, height: 8)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(Color(.secondarySystemGroupedBackground))
                            .cornerRadius(12)
                            .shadow(color: Color.black.opacity(0.04), radius: 3, x: 0, y: 1)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
    
    private func statusColor(for status: String) -> Color {
        let s = status.lowercased()
        if s.contains("regolare") { return .green }
        if s.contains("rallentat") || s.contains("limitat") || s.contains("modific") { return .orange }
        if s.contains("sospes") || s.contains("interrott") || s.contains("chius") || s.contains("grave") { return .red }
        return .orange
    }
}

struct MetroLineVerticalView: View {
    let line: String
    @EnvironmentObject var metroManager: MetroManager

    private var lineColor: Color { colorForLine(line) }

    var body: some View {
        VStack(spacing: 0) {
            switch line {
            case "M1": M1MapView(lineColor: lineColor)
            case "M2": M2MapView(lineColor: lineColor)
            default:   LinearMetroMapView(line: line, lineColor: lineColor)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Linea \(line)")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func colorForLine(_ l: String) -> Color {
        if l.hasPrefix("M1") { return Color(red: 0.89, green: 0.0, blue: 0.10) }
        if l.hasPrefix("M2") { return Color(red: 0.11, green: 0.51, blue: 0.28) }
        if l.hasPrefix("M3") { return Color(red: 0.96, green: 0.65, blue: 0.14) }
        if l.hasPrefix("M4") { return Color(red: 0.0, green: 0.45, blue: 0.73) }
        if l.hasPrefix("M5") { return Color(red: 0.54, green: 0.35, blue: 0.64) }
        return .gray
    }
}

// MARK: - Metro Vector Models

enum MetroColumn {
    case left
    case center
    case right
    
    func xOffset(baseOffset: CGFloat) -> CGFloat {
        switch self {
        case .left: return -baseOffset
        case .center: return 0
        case .right: return baseOffset
        }
    }
}

struct MetroMapNode {
    let name: String
    let row: Int
    let column: MetroColumn
    let isTerminus: Bool
}

struct VectorMetroStationView: View {
    let node: MetroMapNode
    let station: MetroStation?
    let x: CGFloat
    let y: CGFloat
    let lineColor: Color
    let isCurrentLine: String
    @EnvironmentObject var metroManager: MetroManager

    var interchanges: [String] {
        guard let s = station else { return [] }
        let prefixes = s.uniqueLines.map { String($0.name.prefix(2)) }
        return Array(Set(prefixes)).filter { $0 != isCurrentLine }.sorted()
    }

    private func colorForLine(_ l: String) -> Color {
        if l == "M1" { return Color(red: 0.89, green: 0.0, blue: 0.10) }
        if l == "M2" { return Color(red: 0.11, green: 0.51, blue: 0.28) }
        if l == "M3" { return Color(red: 0.96, green: 0.65, blue: 0.14) }
        if l == "M4" { return Color(red: 0.0, green: 0.45, blue: 0.73) }
        if l == "M5" { return Color(red: 0.54, green: 0.35, blue: 0.64) }
        return .gray
    }

    var body: some View {
        ZStack {
            let textWidth: CGFloat = 150
            let textOffset: CGFloat = 22 + textWidth / 2
            let textX = node.column == .left ? x - textOffset : x + textOffset
            
            VStack(alignment: node.column == .left ? .trailing : .leading, spacing: 2) {
                Text(node.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                
                if !interchanges.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(interchanges, id: \.self) { prefix in
                            Text(prefix)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(colorForLine(prefix))
                                .cornerRadius(4)
                        }
                    }
                }
            }
            .frame(width: textWidth, alignment: node.column == .left ? .trailing : .leading)
            .position(x: textX, y: y)

            Circle()
                .fill(Color(.systemBackground))
                .frame(width: 20, height: 20)
                .overlay(
                    Circle().stroke(lineColor, lineWidth: 6)
                )
                .position(x: x, y: y)
                
            if node.isTerminus {
                Text("Capolinea")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                    .position(x: textX, y: y + 20)
            }
        }
    }
}

// MARK: - M1 Map
private struct M1MapView: View {
    let lineColor: Color
    @EnvironmentObject var metroManager: MetroManager

    let trunk = [
        "Sesto 1° Maggio FS", "Sesto Rondo", "Sesto Marelli", "Villa S.G.",
        "Precotto", "Gorla", "Turro", "Rovereto", "Pasteur", "Loreto",
        "Lima", "Porta Venezia", "Palestro", "San Babila", "Duomo",
        "Cordusio", "Cairoli", "Cadorna FN", "Conciliazione", "Pagano"
    ]
    let rhoBranch = [
        "Buonarroti", "Amendola", "Lotto", "Qt8", "Lampugnano",
        "Uruguay", "Bonola", "San Leonardo", "Molino Dorino", "Pero", "Rho Fieramilano"
    ]
    let bisceglieBranch = [
        "Wagner", "De Angeli", "Gambara", "Bande Nere", "Primaticcio", "Inganni", "Bisceglie"
    ]

    var nodes: [MetroMapNode] {
        var res = [MetroMapNode]()
        for (i, name) in trunk.enumerated() {
            res.append(MetroMapNode(name: name, row: i, column: .center, isTerminus: i == 0))
        }
        let forkRow = trunk.count - 1
        for (i, name) in rhoBranch.enumerated() {
            res.append(MetroMapNode(name: name, row: forkRow + 1 + i, column: .left, isTerminus: i == rhoBranch.count - 1))
        }
        for (i, name) in bisceglieBranch.enumerated() {
            res.append(MetroMapNode(name: name, row: forkRow + 1 + i, column: .right, isTerminus: i == bisceglieBranch.count - 1))
        }
        return res
    }

        @State private var zoomScale: CGFloat = 1.0
    @State private var initialZoomSet = false
    @State private var lastZoomScale: CGFloat = 1.0

    var body: some View {
        let maxRow = nodes.map { $0.row }.max() ?? 0
        let stationSpacing: CGFloat = 50
        let totalHeight = CGFloat(maxRow + 1) * stationSpacing + 80
        
        GeometryReader { geo in
            let w = geo.size.width > 0 ? geo.size.width : UIScreen.main.bounds.width
            let h = geo.size.height > 0 ? geo.size.height : UIScreen.main.bounds.height
            let cx = w / 2
            let branchOff: CGFloat = 18
            
            let pt = { (row: CGFloat, col: MetroColumn) -> CGPoint in
                CGPoint(x: cx + col.xOffset(baseOffset: branchOff), y: 40 + row * stationSpacing)
            }
            
            ScrollView(.vertical, showsIndicators: false) {
                ZStack {
                    Path { path in
                    path.move(to: pt(0, .center))
                    path.addLine(to: pt(19, .center))
                    
                    let fork = pt(19, .center)
                    path.move(to: fork)
                    path.addCurve(to: pt(20, .left), control1: CGPoint(x: fork.x, y: fork.y + stationSpacing*0.6), control2: CGPoint(x: pt(20, .left).x, y: fork.y + stationSpacing*0.6))
                    path.addLine(to: pt(CGFloat(19 + rhoBranch.count), .left))
                    
                    path.move(to: fork)
                    path.addCurve(to: pt(20, .right), control1: CGPoint(x: fork.x, y: fork.y + stationSpacing*0.6), control2: CGPoint(x: pt(20, .right).x, y: fork.y + stationSpacing*0.6))
                    path.addLine(to: pt(CGFloat(19 + bisceglieBranch.count), .right))
                }
                .stroke(lineColor, style: StrokeStyle(lineWidth: 14, lineCap: .round, lineJoin: .round))
                
                ForEach(nodes, id: \.name) { node in
                    let s = metroManager.allStations.first { $0.displayName.lowercased().trimmingCharacters(in: .whitespaces) == node.name.lowercased().trimmingCharacters(in: .whitespaces) }
                    if let station = s {
                        NavigationLink(destination: MetroStationDetailView(station: station)) {
                            VectorMetroStationView(node: node, station: station, x: pt(CGFloat(node.row), node.column).x, y: pt(CGFloat(node.row), node.column).y, lineColor: lineColor, isCurrentLine: "M1")
                        }
                        .buttonStyle(.plain)
                    } else {
                        VectorMetroStationView(node: node, station: nil, x: pt(CGFloat(node.row), node.column).x, y: pt(CGFloat(node.row), node.column).y, lineColor: lineColor, isCurrentLine: "M1")
                    }
                }
            }
            .scaleEffect(zoomScale, anchor: .top)
            .frame(width: w, height: totalHeight * zoomScale, alignment: .top)
            }
            .frame(width: w, height: h, alignment: .top)
            .gesture(
                MagnificationGesture()
                    .onChanged { val in
                        let delta = val / lastZoomScale
                        lastZoomScale = val
                        zoomScale = min(max(zoomScale * delta, 0.2), 3.0)
                    }
                    .onEnded { _ in
                        lastZoomScale = 1.0
                    }
            )
            .onAppear {
                if !initialZoomSet {
                    let fitScale = w / 390
                    zoomScale = min(max(fitScale, 0.7), 1.3)
                    initialZoomSet = true
                }
            }
        }
    }
}

// MARK: - M2 Map
private struct M2MapView: View {
    let lineColor: Color
    @EnvironmentObject var metroManager: MetroManager

    let colognoTop = ["Cologno Nord", "Cologno Centro", "Cologno Sud"]
    let gessateTop = [
        "Gessate", "Cascina Antonietta", "Villa Pompea", "Gorgonzola",
        "Bussero", "Cassina De Pecchi", "Villa Fiorita", "Cernusco Sul Naviglio",
        "Cascina Burrona", "Vimodrone"
    ]
    let trunk = [
        "Cascina Gobba", "Crescenzago", "Cimiano", "Udine", "Lambrate FS",
        "Piola", "Loreto", "Caiazzo", "Centrale FS", "Gioia", "Garibaldi FS",
        "Moscova", "Lanza", "Cadorna FN", "Sant'Ambrogio", "Sant'Agostino",
        "Porta Genova FS", "Romolo", "Famagosta"
    ]
    let abbiategrassoBottom = ["Abbiategrasso"]
    let assagoBottom = ["Assago Milanofiori Nord", "Assago Milanofiori Forum"]

    var nodes: [MetroMapNode] {
        var res = [MetroMapNode]()
        for (i, name) in gessateTop.enumerated() {
            res.append(MetroMapNode(name: name, row: i, column: .right, isTerminus: i == 0))
        }
        for (i, name) in colognoTop.enumerated() {
            res.append(MetroMapNode(name: name, row: 7 + i, column: .left, isTerminus: i == 0))
        }
        for (i, name) in trunk.enumerated() {
            res.append(MetroMapNode(name: name, row: 10 + i, column: .center, isTerminus: false))
        }
        res.append(MetroMapNode(name: abbiategrassoBottom[0], row: 29, column: .left, isTerminus: true))
        for (i, name) in assagoBottom.enumerated() {
            res.append(MetroMapNode(name: name, row: 29 + i, column: .right, isTerminus: i == assagoBottom.count - 1))
        }
        return res
    }

        @State private var zoomScale: CGFloat = 1.0
    @State private var initialZoomSet = false
    @State private var lastZoomScale: CGFloat = 1.0

    var body: some View {
        let maxRow = nodes.map { $0.row }.max() ?? 0
        let stationSpacing: CGFloat = 50
        let totalHeight = CGFloat(maxRow + 1) * stationSpacing + 80
        
        GeometryReader { geo in
            let w = geo.size.width > 0 ? geo.size.width : UIScreen.main.bounds.width
            let h = geo.size.height > 0 ? geo.size.height : UIScreen.main.bounds.height
            let cx = w / 2
            let branchOff: CGFloat = 18
            
            let pt = { (row: CGFloat, col: MetroColumn) -> CGPoint in
                CGPoint(x: cx + col.xOffset(baseOffset: branchOff), y: 40 + row * stationSpacing)
            }
            
            ScrollView(.vertical, showsIndicators: false) {
                ZStack {
                    Path { path in
                    path.move(to: pt(0, .right))
                    path.addLine(to: pt(9, .right))
                    path.addCurve(to: pt(10, .center), control1: CGPoint(x: pt(9, .right).x, y: pt(9.5, .center).y), control2: CGPoint(x: pt(10, .center).x, y: pt(9.5, .center).y))
                    
                    path.move(to: pt(7, .left))
                    path.addLine(to: pt(9, .left))
                    path.addCurve(to: pt(10, .center), control1: CGPoint(x: pt(9, .left).x, y: pt(9.5, .center).y), control2: CGPoint(x: pt(10, .center).x, y: pt(9.5, .center).y))
                    
                    path.move(to: pt(10, .center))
                    path.addLine(to: pt(28, .center))
                    
                    let forkB = pt(28, .center)
                    path.move(to: forkB)
                    path.addCurve(to: pt(29, .left), control1: CGPoint(x: forkB.x, y: pt(28.5, .center).y), control2: CGPoint(x: pt(29, .left).x, y: pt(28.5, .center).y))
                    
                    path.move(to: forkB)
                    path.addCurve(to: pt(29, .right), control1: CGPoint(x: forkB.x, y: pt(28.5, .center).y), control2: CGPoint(x: pt(29, .right).x, y: pt(28.5, .center).y))
                    path.addLine(to: pt(30, .right))
                }
                .stroke(lineColor, style: StrokeStyle(lineWidth: 14, lineCap: .round, lineJoin: .round))
                
                ForEach(nodes, id: \.name) { node in
                    let s = metroManager.allStations.first { $0.displayName.lowercased().trimmingCharacters(in: .whitespaces) == node.name.lowercased().trimmingCharacters(in: .whitespaces) }
                    if let station = s {
                        NavigationLink(destination: MetroStationDetailView(station: station)) {
                            VectorMetroStationView(node: node, station: station, x: pt(CGFloat(node.row), node.column).x, y: pt(CGFloat(node.row), node.column).y, lineColor: lineColor, isCurrentLine: "M2")
                        }
                        .buttonStyle(.plain)
                    } else {
                        VectorMetroStationView(node: node, station: nil, x: pt(CGFloat(node.row), node.column).x, y: pt(CGFloat(node.row), node.column).y, lineColor: lineColor, isCurrentLine: "M2")
                    }
                }
            }
            .scaleEffect(zoomScale, anchor: .top)
            .frame(width: w, height: totalHeight * zoomScale, alignment: .top)
            }
            .frame(width: w, height: h, alignment: .top)
            .gesture(
                MagnificationGesture()
                    .onChanged { val in
                        let delta = val / lastZoomScale
                        lastZoomScale = val
                        zoomScale = min(max(zoomScale * delta, 0.2), 3.0)
                    }
                    .onEnded { _ in
                        lastZoomScale = 1.0
                    }
            )
            .onAppear {
                if !initialZoomSet {
                    let fitScale = w / 390
                    zoomScale = min(max(fitScale, 0.7), 1.3)
                    initialZoomSet = true
                }
            }
        }
    }
}

// MARK: - Linear Map (M3, M4, M5)
private struct LinearMetroMapView: View {
    let line: String
    let lineColor: Color
    @EnvironmentObject var metroManager: MetroManager

    var stationsInLine: [MetroStation] {
        metroManager.allStations.filter { s in s.lines.contains { $0.name.hasPrefix(line) } }
            .sorted { $0.displayName < $1.displayName }
    }
    
    let m3Order = [
        "Comasina", "Affori FN", "Affori Centro", "Dergano", "Maciachini", "Zara",
        "Sondrio", "Centrale FS", "Repubblica", "Turati", "Montenapoleone", "Duomo",
        "Missori", "Crocetta", "Porta Romana", "Lodi T.i.b.b.", "Brenta", "Corvetto",
        "Porto Di Mare", "Rogoredo FS", "San Donato"
    ]
    let m4Order = [
        "Linate Aeroporto", "Repetti", "Stazione Forlanini", "Argonne", "Susa",
        "Dateo", "Tricolore", "San Babila", "Sforza Policlinico", "Santa Sofia",
        "Vetra", "De Amicis", "Sant'Ambrogio", "Coni Zugna", "California",
        "Bolivar", "Tolstoj", "Frattini", "Gelsomini", "Segneri", "San Cristoforo"
    ]
    let m5Order = [
        "Bignami", "Ponale", "Bicocca", "Ca' Granda", "Istria", "Marche",
        "Zara", "Isola", "Garibaldi FS", "Monumentale", "Cenisio", "Gerusalemme",
        "Domodossola FN", "Tre Torri", "Portello", "Lotto", "Segesta", "San Siro Ippodromo",
        "San Siro Stadio"
    ]

    var orderedNames: [String] {
        if line == "M3" { return m3Order }
        if line == "M4" { return m4Order }
        if line == "M5" { return m5Order }
        return stationsInLine.map { $0.displayName }
    }

    var nodes: [MetroMapNode] {
        orderedNames.enumerated().map { i, name in
            MetroMapNode(name: name, row: i, column: .center, isTerminus: i == 0 || i == orderedNames.count - 1)
        }
    }

        @State private var zoomScale: CGFloat = 1.0
    @State private var initialZoomSet = false
    @State private var lastZoomScale: CGFloat = 1.0

    var body: some View {
        let maxRow = nodes.map { $0.row }.max() ?? 0
        let stationSpacing: CGFloat = 50
        let totalHeight = CGFloat(maxRow + 1) * stationSpacing + 80
        
        GeometryReader { geo in
            let w = geo.size.width > 0 ? geo.size.width : UIScreen.main.bounds.width
            let h = geo.size.height > 0 ? geo.size.height : UIScreen.main.bounds.height
            let cx = w / 2
            
            let pt = { (row: CGFloat) -> CGPoint in
                CGPoint(x: cx, y: 40 + row * stationSpacing)
            }
            
            ScrollView(.vertical, showsIndicators: false) {
                ZStack {
                    Path { path in
                    path.move(to: pt(0))
                    path.addLine(to: pt(CGFloat(maxRow)))
                }
                .stroke(lineColor, style: StrokeStyle(lineWidth: 14, lineCap: .round, lineJoin: .round))
                
                ForEach(nodes, id: \.name) { node in
                    let s = metroManager.allStations.first { $0.displayName.lowercased().trimmingCharacters(in: .whitespaces) == node.name.lowercased().trimmingCharacters(in: .whitespaces) }
                    
                    if let station = s {
                        NavigationLink(destination: MetroStationDetailView(station: station)) {
                            VectorMetroStationView(node: node, station: station, x: pt(CGFloat(node.row)).x, y: pt(CGFloat(node.row)).y, lineColor: lineColor, isCurrentLine: line)
                        }
                        .buttonStyle(.plain)
                    } else {
                        VectorMetroStationView(node: node, station: nil, x: pt(CGFloat(node.row)).x, y: pt(CGFloat(node.row)).y, lineColor: lineColor, isCurrentLine: line)
                    }
                }
            }
            .scaleEffect(zoomScale, anchor: .top)
            .frame(width: w, height: totalHeight * zoomScale, alignment: .top)
            }
            .frame(width: w, height: h, alignment: .top)
            .gesture(
                MagnificationGesture()
                    .onChanged { val in
                        let delta = val / lastZoomScale
                        lastZoomScale = val
                        zoomScale = min(max(zoomScale * delta, 0.2), 3.0)
                    }
                    .onEnded { _ in
                        lastZoomScale = 1.0
                    }
            )
            .onAppear {
                if !initialZoomSet {
                    let fitScale = w / 390
                    zoomScale = min(max(fitScale, 0.7), 1.3)
                    initialZoomSet = true
                }
            }
        }
    }
}

