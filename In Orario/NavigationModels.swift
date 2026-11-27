import SwiftUI
import Combine

enum MainTab: String, CaseIterable, Codable, Identifiable, Hashable {
    case trains
    case stations
    case home
    case trips
    case lines

    nonisolated static let launchStorageKey = "preferredLaunchTab"

    nonisolated static let barOrder: [MainTab] = [
        .trains,
        .stations,
        .home,
        .trips,
        .lines
    ]

    nonisolated var id: String { rawValue }

    nonisolated var title: String {
        switch self {
        case .trains: return "Treni"
        case .stations: return "Stazioni"
        case .home: return "Home"
        case .trips: return "Viaggi"
        case .lines: return "Linee"
        }
    }

    nonisolated var subtitle: String {
        switch self {
        case .trains: return "Treni salvati e monitoraggio in tempo reale"
        case .stations: return "Partenze, arrivi e stato delle stazioni"
        case .home: return "Panoramica rapida della tua giornata ferroviaria"
        case .trips: return "Tratte abituali, soluzioni salvate e Piano B"
        case .lines: return "Linee suburbane, regionali e direttrici"
        }
    }

    nonisolated var systemImage: String {
        switch self {
        case .trains: return "tram.fill"
        case .stations: return "building.2.fill"
        case .home: return "house"
        case .trips: return "map"
        case .lines: return "point.topleft.down.curvedto.point.bottomright.up"
        }
    }

    nonisolated var activeSystemImage: String {
        switch self {
        case .trains: return "tram.fill"
        case .stations: return "building.2.fill"
        case .home: return "house.fill"
        case .trips: return "map.fill"
        case .lines: return "point.topleft.down.curvedto.point.bottomright.up.fill"
        }
    }

    nonisolated var defaultSearchScope: SearchScope {
        switch self {
        case .trips:
            return .solutions
        case .home, .trains, .stations, .lines:
            return .trainsAndStations
        }
    }

    nonisolated var defaultHistoryTabIndex: Int {
        switch self {
        case .trains: return 2
        case .stations: return 1
        case .trips: return 0
        case .home, .lines: return 0
        }
    }

    nonisolated static func resolvedLaunchTab(rawValue: String?) -> MainTab {
        guard let rawValue, let tab = MainTab(rawValue: rawValue) else {
            return .home
        }
        return tab
    }
}

enum SearchScope: String, CaseIterable, Codable, Identifiable, Hashable {
    case trainsAndStations
    case solutions

    nonisolated var id: String { rawValue }

    nonisolated var title: String {
        switch self {
        case .trainsAndStations: return "Treni e Stazioni"
        case .solutions: return "Soluzioni"
        }
    }

    nonisolated var systemImage: String {
        switch self {
        case .trainsAndStations: return "magnifyingglass"
        case .solutions: return "map.fill"
        }
    }
}

struct SearchPresentationRequest: Identifiable, Equatable {
    let id = UUID()
    let scope: SearchScope
    let initialAssistantMode: Bool
    let autoStartVoice: Bool
    let initialQuery: String?
    let initialOriginName: String?
    let initialOriginID: String?
    let initialDestName: String?
    let initialDestID: String?
    let autoSearchSolutions: Bool

    init(
        scope: SearchScope,
        initialAssistantMode: Bool = false,
        autoStartVoice: Bool = false,
        initialQuery: String? = nil,
        initialOriginName: String? = nil,
        initialOriginID: String? = nil,
        initialDestName: String? = nil,
        initialDestID: String? = nil,
        autoSearchSolutions: Bool = false
    ) {
        self.scope = scope
        self.initialAssistantMode = initialAssistantMode
        self.autoStartVoice = autoStartVoice
        self.initialQuery = initialQuery
        self.initialOriginName = initialOriginName
        self.initialOriginID = initialOriginID
        self.initialDestName = initialDestName
        self.initialDestID = initialDestID
        self.autoSearchSolutions = autoSearchSolutions
    }
}

@MainActor
final class MainNavigationCoordinator: ObservableObject {
    @Published var selectedTab: MainTab {
        didSet {
            mountedTabs.insert(selectedTab)
        }
    }
    @Published var mountedTabs: Set<MainTab>
    @Published var popToRootTokens: [MainTab: UUID] = [:]
    @Published var activeSearchRequest: SearchPresentationRequest? = nil
    @Published var pendingLineIDToOpen: String? = nil

    init(launchTabRawValue: String? = UserDefaults.standard.string(forKey: MainTab.launchStorageKey)) {
        let initialTab = MainTab.resolvedLaunchTab(rawValue: launchTabRawValue)
        self.selectedTab = initialTab
        self.mountedTabs = [initialTab, .home]
    }

    func selectTab(_ tab: MainTab) {
        if selectedTab == tab {
            popToRootTokens[tab] = UUID()
            Haptics.play(.light)
            return
        }
        mountedTabs.insert(tab)
        selectedTab = tab
        Haptics.play(.soft)
    }

    func openContextualSearch(for tab: MainTab? = nil) {
        let targetTab = tab ?? selectedTab
        activeSearchRequest = SearchPresentationRequest(
            scope: targetTab.defaultSearchScope,
            initialAssistantMode: targetTab == .home,
            autoStartVoice: false
        )
        Haptics.play(.light)
    }

    func openAssistantSearch(for tab: MainTab? = nil, autoStartVoice: Bool = true) {
        let targetTab = tab ?? selectedTab
        activeSearchRequest = SearchPresentationRequest(
            scope: targetTab.defaultSearchScope,
            initialAssistantMode: true,
            autoStartVoice: autoStartVoice
        )
        Haptics.play(.medium)
    }

    func openSearch(
        scope: SearchScope,
        assistantMode: Bool = false,
        autoStartVoice: Bool = false,
        initialQuery: String? = nil,
        initialOriginName: String? = nil,
        initialOriginID: String? = nil,
        initialDestName: String? = nil,
        initialDestID: String? = nil,
        autoSearchSolutions: Bool = false
    ) {
        activeSearchRequest = SearchPresentationRequest(
            scope: scope,
            initialAssistantMode: assistantMode,
            autoStartVoice: autoStartVoice,
            initialQuery: initialQuery,
            initialOriginName: initialOriginName,
            initialOriginID: initialOriginID,
            initialDestName: initialDestName,
            initialDestID: initialDestID,
            autoSearchSolutions: autoSearchSolutions
        )
    }

    func openLineDetail(lineID: String) {
        mountedTabs.insert(.lines)
        selectedTab = .lines
        pendingLineIDToOpen = lineID
        Haptics.play(.soft)
    }
}
