import SwiftUI
import CoreLocation
import UserNotifications
import UIKit

enum OnboardingCampaign {
    static let currentUpdateID = "2026_v3_4_commute_redesign_v3"
    static let seenUpdateIDKey = "lastSeenOnboardingUpdateID_v1"
}

enum OnboardingPresentationMode: Equatable {
    case fullFirstLaunch
    case updateWhatsNew
}

enum OnboardingAudience: Equatable {
    case free
    case pro

    nonisolated static func resolve(hasSupport: Bool) -> OnboardingAudience {
        hasSupport ? .pro : .free
    }
}

enum OnboardingNotificationState: Equatable {
    case authorizedActive
    case authorizedAppToggleOff
    case notDetermined
    case denied
}

enum OnboardingLocationState: Equatable {
    case authorized
    case notDetermined
    case deniedOrRestricted
}

struct OnboardingPermissionSnapshot: Equatable {
    var notifications: OnboardingNotificationState
    var location: OnboardingLocationState

    var isNotificationsReady: Bool { notifications == .authorizedActive }
    var isLocationReady: Bool { location == .authorized }
    var needsNotifications: Bool { !isNotificationsReady }
    var needsLocation: Bool { !isLocationReady }
    var needsAnyPermission: Bool { needsNotifications || needsLocation }

    static func from(
        notificationStatus: UNAuthorizationStatus,
        remoteNotificationsEnabled: Bool,
        locationStatus: CLAuthorizationStatus
    ) -> OnboardingPermissionSnapshot {
        let notifState: OnboardingNotificationState
        switch notificationStatus {
        case .authorized, .provisional, .ephemeral:
            notifState = remoteNotificationsEnabled ? .authorizedActive : .authorizedAppToggleOff
        case .notDetermined:
            notifState = .notDetermined
        case .denied:
            notifState = .denied
        @unknown default:
            notifState = .denied
        }

        let locState: OnboardingLocationState
        switch locationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            locState = .authorized
        case .notDetermined:
            locState = .notDetermined
        case .denied, .restricted:
            locState = .deniedOrRestricted
        @unknown default:
            locState = .deniedOrRestricted
        }

        return OnboardingPermissionSnapshot(notifications: notifState, location: locState)
    }
}

enum OnboardingLaunchDecision: Equatable {
    case showFullOnboarding
    case showUpdateOnboarding
    case none

    static func resolve(
        hasCompletedOnboarding: Bool,
        lastSeenUpdateID: String?,
        currentUpdateID: String = OnboardingCampaign.currentUpdateID
    ) -> OnboardingLaunchDecision {
        if !hasCompletedOnboarding {
            return .showFullOnboarding
        }
        if lastSeenUpdateID != currentUpdateID {
            return .showUpdateOnboarding
        }
        return .none
    }
}

enum OnboardingStep: String, CaseIterable, Identifiable {
    case welcome
    case whatsNew
    case quickGuide
    case region
    case passante
    case stations
    case permissions

    var id: String { rawValue }

    static func steps(
        for mode: OnboardingPresentationMode,
        strikeRegion: String,
        includePermissionsStep: Bool
    ) -> [OnboardingStep] {
        switch mode {
        case .updateWhatsNew:
            var steps: [OnboardingStep] = [.whatsNew]
            if includePermissionsStep {
                steps.append(.permissions)
            }
            steps.append(.quickGuide)
            return steps
        case .fullFirstLaunch:
            var steps: [OnboardingStep] = [.welcome]
            if includePermissionsStep {
                steps.append(.permissions)
            }
            steps.append(.region)
            if strikeRegion == "Lombardia" || strikeRegion == "Piemonte" || strikeRegion == "Veneto" {
                steps.append(.passante)
            }
            steps.append(.stations)
            steps.append(.quickGuide)
            return steps
        }
    }
}

struct OnboardingView: View {
    @Binding var showOnboarding: Bool
    let mode: OnboardingPresentationMode
    let initialPermissionSnapshot: OnboardingPermissionSnapshot
    var onOpenCommuteSettings: (() -> Void)? = nil

    @State private var currentStep: OnboardingStep
    @State private var permissionSnapshot: OnboardingPermissionSnapshot
    @State private var shouldIncludePermissionsStep: Bool
    @State private var didOpenSystemSettings = false
    @State private var isRequestingPermissions = false

    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject var locationManager: LocationManager
    @EnvironmentObject var manager: TrainManager
    @EnvironmentObject var passanteManager: PassanteManager

    init(
        showOnboarding: Binding<Bool>,
        mode: OnboardingPresentationMode = .fullFirstLaunch,
        initialPermissionSnapshot: OnboardingPermissionSnapshot = OnboardingPermissionSnapshot(
            notifications: .notDetermined,
            location: .notDetermined
        ),
        onOpenCommuteSettings: (() -> Void)? = nil
    ) {
        self._showOnboarding = showOnboarding
        self.mode = mode
        self.initialPermissionSnapshot = initialPermissionSnapshot
        self.onOpenCommuteSettings = onOpenCommuteSettings
        self._currentStep = State(initialValue: mode == .updateWhatsNew ? .whatsNew : .welcome)
        self._permissionSnapshot = State(initialValue: initialPermissionSnapshot)
        self._shouldIncludePermissionsStep = State(initialValue: initialPermissionSnapshot.needsAnyPermission)
    }

    private var activeSteps: [OnboardingStep] {
        OnboardingStep.steps(
            for: mode,
            strikeRegion: manager.strikeRegion,
            includePermissionsStep: shouldIncludePermissionsStep
        )
    }

    private var isLastStep: Bool {
        currentStep == activeSteps.last
    }

    private var hasActionableInAppPermissions: Bool {
        permissionSnapshot.notifications == .notDetermined ||
        permissionSnapshot.notifications == .authorizedAppToggleOff ||
        permissionSnapshot.location == .notDetermined
    }

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Barra superiore: indicatore step e pulsante Salta
                HStack {
                    HStack(spacing: 6) {
                        ForEach(activeSteps) { step in
                            Capsule()
                                .fill(currentStep == step ? Color.blue : Color.secondary.opacity(0.25))
                                .frame(width: currentStep == step ? 22 : 7, height: 7)
                                .animation(.spring(response: 0.35, dampingFraction: 0.75), value: currentStep)
                        }
                    }

                    Spacer()

                    Button("Salta") {
                        Haptics.play(.light)
                        completeOnboarding()
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.secondary)
                    .opacity(isLastStep ? 0 : 1)
                    .disabled(isLastStep)
                }
                .padding(.horizontal, 24)
                .padding(.top, 14)
                .padding(.bottom, 8)

                // Contenitore pagine
                TabView(selection: $currentStep) {
                    ForEach(activeSteps) { step in
                        stepView(for: step)
                            .tag(step)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                // Pulsanti inferiori
                VStack(spacing: 10) {
                    Button(action: {
                        handleForwardAction()
                    }) {
                        HStack(spacing: 8) {
                            if isRequestingPermissions {
                                ProgressView()
                                    .tint(.white)
                            }
                            Text(primaryButtonTitle)
                                .font(.headline)
                                .bold()

                            Image(systemName: primaryButtonIcon)
                                .font(.subheadline.bold())
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(primaryButtonColor)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .shadow(color: primaryButtonColor.opacity(0.25), radius: 8, x: 0, y: 4)
                    }
                    .disabled(isRequestingPermissions)

                    if currentStep == .permissions && permissionSnapshot.needsAnyPermission && hasActionableInAppPermissions {
                        Button(isLastStep ? "Continua senza attivare" : "Continua comunque") {
                            Haptics.play(.light)
                            completeOrAdvance()
                        }
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.secondary)
                        .padding(.top, 2)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
            }
        }
        .task {
            await refreshPermissionSnapshot(autoEnableIfReturningFromSettings: false)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task {
                    await refreshPermissionSnapshot(autoEnableIfReturningFromSettings: true)
                }
            }
        }
        .onChange(of: locationManager.authorizationStatus) { _, _ in
            Task {
                await refreshPermissionSnapshot(autoEnableIfReturningFromSettings: false)
            }
        }
        .onChange(of: manager.remoteNotificationsEnabled) { _, _ in
            Task {
                await refreshPermissionSnapshot(autoEnableIfReturningFromSettings: false)
            }
        }
        .onChange(of: manager.strikeRegion) { _, newRegion in
            let allows = (newRegion == "Lombardia" || newRegion == "Piemonte" || newRegion == "Veneto")
            if !allows && currentStep == .passante {
                currentStep = .stations
            }
        }
    }

    @ViewBuilder
    private func stepView(for step: OnboardingStep) -> some View {
        switch step {
        case .welcome:
            OnboardingWelcomeView()
        case .whatsNew:
            OnboardingWhatsNewView()
        case .quickGuide:
            OnboardingQuickGuideView(
                isUpdateMode: mode == .updateWhatsNew,
                onOpenCommuteSettings: onOpenCommuteSettings
            )
        case .region:
            OnboardingRegionPickerView()
        case .passante:
            OnboardingPassanteLinePickerView()
        case .stations:
            OnboardingStationsPreferenceView()
        case .permissions:
            OnboardingPermissionsView(
                snapshot: permissionSnapshot,
                initiallyNeededNotifications: initialPermissionSnapshot.needsNotifications,
                initiallyNeededLocation: initialPermissionSnapshot.needsLocation,
                isRequesting: isRequestingPermissions,
                onRequestNotifications: {
                    Task { await handleNotificationsAction() }
                },
                onRequestLocation: {
                    handleLocationAction()
                }
            )
        }
    }

    private var primaryButtonTitle: String {
        if currentStep == .permissions {
            if !permissionSnapshot.needsAnyPermission {
                return isLastStep ? "Tutto pronto, inizia!" : "Continua"
            }
            if hasActionableInAppPermissions {
                let canAskNotif = permissionSnapshot.notifications == .notDetermined || permissionSnapshot.notifications == .authorizedAppToggleOff
                let canAskLoc = permissionSnapshot.location == .notDetermined
                if canAskNotif && canAskLoc {
                    return "Attiva notifiche e posizione"
                } else if canAskNotif {
                    return "Attiva notifiche"
                } else if canAskLoc {
                    return "Attiva posizione"
                }
            }
            return isLastStep ? "Inizia a viaggiare" : "Continua"
        }
        return isLastStep ? "Inizia a viaggiare" : "Continua"
    }

    private var primaryButtonIcon: String {
        if currentStep == .permissions && permissionSnapshot.needsAnyPermission && hasActionableInAppPermissions {
            return "checkmark.shield.fill"
        }
        if currentStep == .permissions && !permissionSnapshot.needsAnyPermission {
            return "checkmark.circle.fill"
        }
        return isLastStep ? "arrow.right" : "chevron.right"
    }

    private var primaryButtonColor: Color {
        if currentStep == .permissions && !permissionSnapshot.needsAnyPermission {
            return .green
        }
        return .blue
    }

    private func handleForwardAction() {
        if currentStep == .permissions && permissionSnapshot.needsAnyPermission && hasActionableInAppPermissions {
            Task {
                await requestAllActionablePermissions()
            }
            return
        }
        Haptics.play(.medium)
        completeOrAdvance()
    }

    private func completeOrAdvance() {
        if isLastStep {
            completeOnboarding()
        } else {
            advanceStep()
        }
    }

    private func advanceStep() {
        let steps = activeSteps
        if let idx = steps.firstIndex(of: currentStep), idx < steps.count - 1 {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                currentStep = steps[idx + 1]
            }
        }
    }

    private func requestAllActionablePermissions() async {
        Haptics.play(.medium)
        isRequestingPermissions = true
        defer { isRequestingPermissions = false }

        if permissionSnapshot.notifications == .notDetermined || permissionSnapshot.notifications == .authorizedAppToggleOff {
            await handleNotificationsAction()
        }
        if permissionSnapshot.location == .notDetermined {
            handleLocationAction()
        }
    }

    @MainActor
    private func handleNotificationsAction() async {
        Haptics.play(.medium)
        switch permissionSnapshot.notifications {
        case .notDetermined:
            let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])) ?? false
            if granted {
                enableAppNotificationSettings()
            }
            await refreshPermissionSnapshot(autoEnableIfReturningFromSettings: false)
        case .authorizedAppToggleOff:
            enableAppNotificationSettings()
            await refreshPermissionSnapshot(autoEnableIfReturningFromSettings: false)
        case .denied:
            didOpenSystemSettings = true
            if let notifUrl = URL(string: UIApplication.openNotificationSettingsURLString),
               UIApplication.shared.canOpenURL(notifUrl) {
                await UIApplication.shared.open(notifUrl)
            } else if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                await UIApplication.shared.open(settingsUrl)
            }
        case .authorizedActive:
            break
        }
    }

    @MainActor
    private func handleLocationAction() {
        Haptics.play(.medium)
        switch permissionSnapshot.location {
        case .notDetermined:
            locationManager.requestAuthorization()
        case .deniedOrRestricted:
            didOpenSystemSettings = true
            if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(settingsUrl)
            }
        case .authorized:
            break
        }
    }

    @MainActor
    private func enableAppNotificationSettings() {
        manager.remoteNotificationsEnabled = true
        if UserDefaults.standard.object(forKey: "strikeNotificationsEnabled_v1") == nil {
            manager.strikeNotificationsEnabled = true
        }
        manager.saveFavorites()
        UIApplication.shared.registerForRemoteNotifications()
        manager.syncRemoteNotifications()
    }

    @MainActor
    private func refreshPermissionSnapshot(autoEnableIfReturningFromSettings: Bool) async {
        locationManager.refreshAuthorizationStatus()
        let settings = await UNUserNotificationCenter.current().notificationSettings()

        if autoEnableIfReturningFromSettings && didOpenSystemSettings {
            let sysGranted = (
                settings.authorizationStatus == .authorized ||
                settings.authorizationStatus == .provisional ||
                settings.authorizationStatus == .ephemeral
            )
            if sysGranted && !manager.remoteNotificationsEnabled {
                enableAppNotificationSettings()
            }
            didOpenSystemSettings = false
        }

        let updated = OnboardingPermissionSnapshot.from(
            notificationStatus: settings.authorizationStatus,
            remoteNotificationsEnabled: manager.remoteNotificationsEnabled,
            locationStatus: locationManager.authorizationStatus
        )

        withAnimation(.easeInOut(duration: 0.2)) {
            permissionSnapshot = updated
            if updated.needsAnyPermission && !shouldIncludePermissionsStep {
                shouldIncludePermissionsStep = true
            }
        }
    }

    private func completeOnboarding() {
        Haptics.play(.medium)
        withAnimation(.easeInOut(duration: 0.25)) {
            showOnboarding = false
        }
    }
}

// MARK: - Header Coordinato per Tutte le Schede
struct OnboardingHeaderView: View {
    let icon: String
    let color: Color
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.12))
                    .frame(width: 72, height: 72)

                Image(systemName: icon)
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundColor(color)
            }
            .padding(.top, 4)

            Text(LocalizedStringKey(title))
                .font(.system(.title2, design: .rounded).weight(.bold))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)

            Text(LocalizedStringKey(subtitle))
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
                .lineSpacing(2)
        }
    }
}

// MARK: - Hero Card Notifiche Piano Free (10 Treni)
struct OnboardingFreeNotificationsHeroCard: View {
    private let freeLimit = TrainManager.freeScheduledNotificationLimit
    private let proLimit = TrainManager.proNotificationLimit

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("NOVITÀ · PIANO FREE")
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(0.5)
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.orange)
                    .clipShape(Capsule())

                Spacer()

                Image(systemName: "bell.badge.fill")
                    .font(.title3.bold())
                    .foregroundColor(.orange)
            }

            Text("Notifiche gratis fino a \(freeLimit) treni")
                .font(.headline.weight(.bold))
                .foregroundColor(.primary)

            Text("Anche con il piano gratuito ora puoi attivare una notifica all'orario che scegli tu fino a \(freeLimit) treni preferiti, per controllare subito ritardi, binario e soppressioni prima di uscire.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineSpacing(2)

            HStack(spacing: 6) {
                Image(systemName: "crown.fill")
                    .font(.caption2)
                    .foregroundColor(.orange)
                Text("Con Pro: monitoraggio continuo fino a \(proLimit) treni + riepilogo programmato")
                    .font(.caption.weight(.medium))
                    .foregroundColor(.primary.opacity(0.85))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemBackground).opacity(0.65))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [Color.orange.opacity(0.16), Color.yellow.opacity(0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.orange.opacity(0.35), lineWidth: 1.2)
        )
    }
}

// MARK: - Hero Card Novità Piano Pro
struct OnboardingProWhatsNewHeroCard: View {
    private let proLimit = TrainManager.proNotificationLimit

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("NOVITÀ · IN ORARIO PRO")
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(0.5)
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.indigo)
                    .clipShape(Capsule())

                Spacer()

                Image(systemName: "crown.fill")
                    .font(.title3.bold())
                    .foregroundColor(.indigo)
            }

            Text("Il tuo In Orario Pro, ancora più potente")
                .font(.headline.weight(.bold))
                .foregroundColor(.primary)

            Text("Monitoraggio continuo fino a \(proLimit) treni, avvisi proattivi con Piano B e riepilogo programmato ora integrati nella nuova app a 5 schede, con Assistente IA diretto dalla Home e stazioni Casa ↔ Lavoro senza limiti.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineSpacing(2)

            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.caption2)
                    .foregroundColor(.indigo)
                Text("Grazie per il supporto: tutte le novità e i widget sono già attivi per te")
                    .font(.caption.weight(.medium))
                    .foregroundColor(.primary.opacity(0.85))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemBackground).opacity(0.65))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [Color.indigo.opacity(0.16), Color.purple.opacity(0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.indigo.opacity(0.35), lineWidth: 1.2)
        )
    }
}

// MARK: - Scheda Aggiornamento: Le Novità di In Orario
struct OnboardingWhatsNewView: View {
    @EnvironmentObject var manager: TrainManager

    private var audience: OnboardingAudience {
        OnboardingAudience.resolve(hasSupport: manager.hasSupport())
    }

    var body: some View {
        VStack(spacing: 16) {
            OnboardingHeaderView(
                icon: "sparkles",
                color: .blue,
                title: "Le Novità di In Orario",
                subtitle: "Abbiamo rinnovato l'app per renderla più chiara, veloce e utile ogni giorno."
            )
            .padding(.top, 8)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    if audience == .pro {
                        OnboardingProWhatsNewHeroCard()
                    } else {
                        OnboardingFreeNotificationsHeroCard()
                    }

                    OnboardingHighlightCard(
                        icon: "square.grid.2x2.fill",
                        color: .blue,
                        title: "App a 5 schede & Home su misura",
                        desc: "Treni, Stazioni, Home, Viaggi e Linee. Scegli cosa mostrare nella Home, righe più compatte e riepilogo immediato degli avvisi."
                    )

                    OnboardingHighlightCard(
                        icon: "tram.fill",
                        color: .indigo,
                        title: "Nuova sezione Linee",
                        desc: "Tutte le linee suburbane, regionali e AV d'Italia con fermate personalizzabili e stato del servizio."
                    )

                    HStack(spacing: 5) {
                        Image(systemName: "bolt.fill")
                            .font(.caption2)
                            .foregroundColor(.secondary.opacity(0.75))
                        Text("App più leggera, cache soluzioni da 30 min e tratte Casa ↔ Lavoro in Abitudini di viaggio.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 4)
                    .padding(.horizontal, 6)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 4)
            }

            Spacer(minLength: 0)
        }
    }
}

// MARK: - Scheda 1 (Nuovi Utenti): Benvenuto su In Orario
struct OnboardingWelcomeView: View {
    @EnvironmentObject var manager: TrainManager

    private var audience: OnboardingAudience {
        OnboardingAudience.resolve(hasSupport: manager.hasSupport())
    }

    var body: some View {
        VStack(spacing: 16) {
            OnboardingHeaderView(
                icon: "tram.fill",
                color: .blue,
                title: "Benvenuto su In Orario",
                subtitle: "Il tuo compagno per viaggiare in treno con dati ufficiali RFI, partenze, binari e avvisi in tempo reale."
            )
            .padding(.top, 8)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    if audience == .pro {
                        OnboardingProWhatsNewHeroCard()
                    } else {
                        OnboardingFreeNotificationsHeroCard()
                    }

                    OnboardingHighlightCard(
                        icon: "clock.badge.checkmark.fill",
                        color: .blue,
                        title: "Tabelloni e treni in tempo reale",
                        desc: "Controlla partenze, arrivi, binario previsto o confermato, posizione del treno e andamento in tutta Italia."
                    )

                    OnboardingHighlightCard(
                        icon: "iphone.circle.fill",
                        color: .purple,
                        title: "Live Activities, Isola Dinamica e Widget",
                        desc: "Segui il tuo treno sulla schermata di blocco e aggiungi i widget di treni e stazioni direttamente sulla Home di iOS."
                    )
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 4)
            }

            Spacer(minLength: 0)
        }
    }
}

struct OnboardingHighlightCard: View {
    let icon: String
    let color: Color
    let title: String
    let desc: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.12))
                    .frame(width: 38, height: 38)
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(color)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)
                Text(desc)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineSpacing(2)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
    }
}

// MARK: - Scheda 2: La Tua Regione
struct OnboardingRegionPickerView: View {
    @EnvironmentObject var manager: TrainManager
    @EnvironmentObject var locationManager: LocationManager
    @State private var detectedRegion: String? = nil
    
    private let regions = [
        "Tutte", "Abruzzo", "Basilicata", "Calabria", "Campania",
        "Emilia-Romagna", "Friuli Venezia Giulia", "Lazio", "Liguria",
        "Lombardia", "Marche", "Molise", "Piemonte", "Puglia",
        "Sardegna", "Sicilia", "Toscana", "Trentino-Alto Adige",
        "Umbria", "Valle d'Aosta", "Veneto"
    ]
    
    var body: some View {
        VStack(spacing: 16) {
            OnboardingHeaderView(
                icon: "map.fill",
                color: .red,
                title: "La Tua Regione",
                subtitle: "Ricevi scioperi, avvisi e notizie di circolazione rilevanti per la tua area geografica."
            )
            .padding(.top, 8)
            
            // Badge rilevamento GPS (se disponibile)
            if let detected = detectedRegion {
                HStack(spacing: 8) {
                    Image(systemName: "location.fill")
                        .foregroundColor(.green)
                        .font(.caption.bold())
                    Text("Rilevata dal GPS: \(detected)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.primary)
                    Spacer()
                    if manager.strikeRegion == detected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.subheadline)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.green.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.horizontal, 24)
            }
            
            // Lista selezioni regione con auto-scroll sul focus
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 8) {
                        ForEach(regions, id: \.self) { region in
                            let isSelected = manager.strikeRegion == region
                            Button {
                                Haptics.play(.light)
                                manager.strikeRegion = region
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    proxy.scrollTo(region, anchor: .center)
                                }
                            } label: {
                                HStack {
                                    Text(region == "Tutte" ? "🇮🇹 Nazionale / Tutte le regioni" : region)
                                        .font(.subheadline.weight(isSelected ? .bold : .medium))
                                        .foregroundColor(.primary)
                                    
                                    Spacer()
                                    
                                    if isSelected {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.red)
                                            .font(.subheadline)
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(isSelected ? Color.red.opacity(0.1) : Color(.secondarySystemGroupedBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(isSelected ? Color.red.opacity(0.4) : Color.primary.opacity(0.06), lineWidth: isSelected ? 1.5 : 0.5)
                                )
                            }
                            .buttonStyle(.plain)
                            .id(region)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 4)
                }
                .onChange(of: manager.strikeRegion) { _, newRegion in
                    withAnimation(.easeInOut(duration: 0.35)) {
                        proxy.scrollTo(newRegion, anchor: .center)
                    }
                }
                .onAppear {
                    tryDetectRegion()
                }
                .task {
                    if manager.strikeRegion != "Tutte" {
                        try? await Task.sleep(nanoseconds: 350_000_000)
                        guard !Task.isCancelled else { return }
                        withAnimation(.easeInOut(duration: 0.35)) {
                            proxy.scrollTo(manager.strikeRegion, anchor: .center)
                        }
                    }
                }
            }
            
            Spacer(minLength: 0)
        }
        .onAppear {
            tryDetectRegion()
            locationManager.requestLocation(force: true)
        }
        .onChange(of: locationManager.userLocation) { _, _ in
            tryDetectRegion()
        }
    }
    
    private func tryDetectRegion() {
        guard let loc = locationManager.userLocation else { return }
        CLGeocoder().reverseGeocodeLocation(loc) { placemarks, _ in
            guard let admin = placemarks?.first?.administrativeArea else { return }
            let matched = regions.first {
                $0.localizedCaseInsensitiveCompare(admin) == .orderedSame ||
                admin.localizedCaseInsensitiveContains($0) ||
                $0.localizedCaseInsensitiveContains(admin)
            }
            if let matched = matched {
                DispatchQueue.main.async {
                    self.detectedRegion = matched
                    if self.manager.strikeRegion == "Tutte" {
                        self.manager.strikeRegion = matched
                    }
                }
            }
        }
    }
}

// MARK: - Scheda 3: Passante e Linee S (Lombardia, Piemonte, Veneto)
struct OnboardingPassanteLinePickerView: View {
    @EnvironmentObject var passanteManager: PassanteManager
    @EnvironmentObject var manager: TrainManager
    @State private var previewLine: SuburbanLine? = nil
    @State private var isStopsExpanded: Bool = false
    
    private let columns = [
        GridItem(.adaptive(minimum: 70, maximum: 85), spacing: 10)
    ]
    
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                OnboardingHeaderView(
                    icon: "tram.fill",
                    color: .green,
                    title: "Passante e Linee Suburbane",
                    subtitle: "Seleziona le linee S che prendi abitualmente ed espandi il tracciato per indicare le tue fermate preferite."
                )
                .padding(.top, 8)
                
                // Griglia linee S
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(SuburbanData.shared.allLines) { line in
                        let isSelected = passanteManager.selectedSuburbanLines.contains(line.id)
                        Button {
                            Haptics.play(.light)
                            passanteManager.toggleSuburbanLine(line.id)
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                previewLine = line
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(line.id)
                                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                                
                                if isSelected {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10, weight: .bold))
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(isSelected ? line.color : Color(.secondarySystemGroupedBackground))
                            .foregroundColor(isSelected ? .white : .primary)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(line.color, lineWidth: isSelected ? 0 : 1.5)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 4)
                
                // Anteprima tracciato linea selezionata
                if let line = previewLine {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            HStack(spacing: 6) {
                                Text(line.id)
                                    .font(.system(.caption, design: .rounded).weight(.bold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(line.color)
                                    .foregroundColor(.white)
                                    .clipShape(Capsule())
                                
                                Text(line.name)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(.primary)
                            }
                            
                            Spacer()
                            
                            Text("\(line.stations.count) fermate")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        
                        // Tracciato: Capolinea 1 -> Tratto Centrale -> Capolinea 2
                        HStack(alignment: .center, spacing: 6) {
                            // Capolinea 1
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 4) {
                                    Circle().fill(line.color).frame(width: 7, height: 7)
                                    Text("Partenza")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(.secondary)
                                }
                                Text(line.stations.first?.name.formattedStationName ?? "")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.85)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            
                            // Connettore centrale
                            VStack(spacing: 3) {
                                HStack(spacing: 0) {
                                    Rectangle()
                                        .fill(line.color.opacity(0.35))
                                        .frame(height: 2)
                                    
                                    Image(systemName: "tram.fill")
                                        .font(.system(size: 11))
                                        .foregroundColor(line.color)
                                        .padding(.horizontal, 4)
                                    
                                    Rectangle()
                                        .fill(line.color.opacity(0.35))
                                        .frame(height: 2)
                                }
                                
                                let isPassante = line.stations.contains(where: { $0.name.contains("Passante") || $0.name == "Porta Venezia" || $0.name == "Dateo" })
                                Text(isPassante ? "Passante Ferroviario" : "Tratto Urbano")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(line.color)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity)
                            
                            // Capolinea 2
                            VStack(alignment: .trailing, spacing: 3) {
                                HStack(spacing: 4) {
                                    Text("Arrivo")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(.secondary)
                                    Circle().fill(line.color).frame(width: 7, height: 7)
                                }
                                Text(line.stations.last?.name.formattedStationName ?? "")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.85)
                            }
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(Color(.tertiarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        
                        // Pulsante Chevron per mostrare/nascondere tutte le fermate
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                isStopsExpanded.toggle()
                            }
                            Haptics.play(.light)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: isStopsExpanded ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                                    .foregroundColor(line.color)
                                    .font(.subheadline.bold())
                                
                                Text(isStopsExpanded ? "Nascondi elenco fermate" : "Mostra tutte le fermate (\(line.stations.count))")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(.primary)
                                
                                Spacer()
                                
                                let favCount = line.stations.filter { passanteManager.isFavoriteSuburbanStation($0.name) }.count
                                if favCount > 0 {
                                    Text("\(favCount) preferite")
                                        .font(.caption2.bold())
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(Color.orange.opacity(0.15))
                                        .foregroundColor(.orange)
                                        .clipShape(Capsule())
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(Color(.tertiarySystemGroupedBackground).opacity(0.7))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        
                        // Elenco espanso fermate con "Scegli le tue preferite"
                        if isStopsExpanded {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Scegli le tue preferite")
                                            .font(.subheadline.weight(.bold))
                                            .foregroundColor(.primary)
                                        Text("Tocca per indicare le stazioni che usi più spesso su questa linea")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                }
                                .padding(.top, 4)
                                .padding(.horizontal, 2)
                                
                                VStack(spacing: 2) {
                                    ForEach(Array(line.stations.enumerated()), id: \.element.name) { index, station in
                                        let isFav = passanteManager.isFavoriteSuburbanStation(station.name)
                                        let isFirst = index == 0
                                        let isLast = index == line.stations.count - 1
                                        
                                        Button {
                                            Haptics.play(.light)
                                            passanteManager.toggleFavoriteSuburbanStation(station.name)
                                        } label: {
                                            HStack(spacing: 12) {
                                                // Tracciato grafico fermata
                                                ZStack {
                                                    VStack(spacing: 0) {
                                                        Rectangle()
                                                            .fill(isFirst ? Color.clear : line.color.opacity(0.35))
                                                            .frame(width: 2)
                                                        Rectangle()
                                                            .fill(isLast ? Color.clear : line.color.opacity(0.35))
                                                            .frame(width: 2)
                                                    }
                                                    .frame(height: 36)
                                                    
                                                    Circle()
                                                        .fill(isFav ? Color.orange : line.color)
                                                        .frame(width: isFav ? 11 : 8, height: isFav ? 11 : 8)
                                                        .overlay(
                                                            Circle()
                                                                .stroke(Color(.systemBackground), lineWidth: 1.5)
                                                        )
                                                }
                                                .frame(width: 18)
                                                
                                                Text(station.name.formattedStationName)
                                                    .font(.subheadline.weight(isFav ? .bold : .medium))
                                                    .foregroundColor(isFav ? .primary : .secondary)
                                                
                                                Spacer()
                                                
                                                Image(systemName: isFav ? "star.fill" : "star")
                                                    .foregroundColor(isFav ? .orange : Color(.tertiaryLabel))
                                                    .font(.subheadline)
                                            }
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 4)
                                            .background(isFav ? Color.orange.opacity(0.08) : Color.clear)
                                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            .padding(.top, 4)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    .padding(14)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(line.color.opacity(0.3), lineWidth: 1)
                    )
                    .padding(.horizontal, 24)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "hand.tap.fill")
                            .foregroundColor(.secondary)
                            .font(.subheadline)
                        Text("Tocca una linea per selezionarla e visualizzarne il tracciato.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity)
                    .background(Color(.secondarySystemGroupedBackground).opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(.horizontal, 24)
                }
                
                // Nota informativa
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .foregroundColor(.secondary)
                        .font(.caption)
                    Text("Potrai sempre modificare le linee e le singole fermate nelle Impostazioni.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 24)
                .padding(.top, 4)
                .padding(.bottom, 12)
            }
        }
        .onAppear {
            if previewLine == nil {
                if manager.strikeRegion == "Piemonte" {
                    previewLine = SuburbanData.shared.allLines.first(where: { $0.id == "S6" }) ?? SuburbanData.shared.allLines.first
                } else {
                    previewLine = SuburbanData.shared.allLines.first(where: { passanteManager.selectedSuburbanLines.contains($0.id) }) ?? SuburbanData.shared.allLines.first
                }
            }
        }
    }
}

// MARK: - Scheda 4: Stazioni Frequenti
struct OnboardingStationsPreferenceView: View {
    @EnvironmentObject var manager: TrainManager
    @EnvironmentObject var locationManager: LocationManager
    @State private var showSearchSheet = false
    @State private var searchStationName = ""
    @State private var searchStationID = ""
    
    // Hub di riferimento per ciascuna regione italiana
    private static let regionHubs: [String: String] = [
        "Abruzzo": "PESCARA",
        "Basilicata": "POTENZA CENTRALE",
        "Calabria": "REGGIO DI CALABRIA CENTRALE",
        "Campania": "NAPOLI CENTRALE",
        "Emilia-Romagna": "BOLOGNA CENTRALE",
        "Friuli Venezia Giulia": "TRIESTE CENTRALE",
        "Lazio": "ROMA TERMINI",
        "Liguria": "GENOVA PIAZZA PRINCIPE",
        "Lombardia": "MILANO CENTRALE",
        "Marche": "ANCONA",
        "Molise": "CAMPOBASSO",
        "Piemonte": "TORINO PORTA NUOVA",
        "Puglia": "BARI CENTRALE",
        "Sardegna": "CAGLIARI",
        "Sicilia": "PALERMO CENTRALE",
        "Toscana": "FIRENZE SANTA MARIA NOVELLA",
        "Trentino-Alto Adige": "TRENTO",
        "Umbria": "PERUGIA",
        "Valle d'Aosta": "AOSTA",
        "Veneto": "VENEZIA S.LUCIA",
        "Tutte": "MILANO CENTRALE"
    ]
    
    // 4 stazioni principali per ogni regione italiana
    private static let regionMajorStations: [String: [String]] = [
        "Abruzzo": ["PESCARA", "L'AQUILA", "CHIETI", "TERAMO"],
        "Basilicata": ["POTENZA CENTRALE", "MATERA", "FERRANDINA SCALO-MATERA", "METAPONTO"],
        "Calabria": ["REGGIO DI CALABRIA CENTRALE", "LAMEZIA TERME CENTRALE", "COSENZA", "CATANZARO LIDO"],
        "Campania": ["NAPOLI CENTRALE", "SALERNO", "CASERTA", "BENEVENTO"],
        "Emilia-Romagna": ["BOLOGNA CENTRALE", "PARMA", "MODENA", "REGGIO EMILIA"],
        "Friuli Venezia Giulia": ["TRIESTE CENTRALE", "UDINE", "PORDENONE", "GORIZIA CENTRALE"],
        "Lazio": ["ROMA TERMINI", "ROMA TIBURTINA", "ROMA OSTIENSE", "FIUMICINO AEROPORTO"],
        "Liguria": ["GENOVA PIAZZA PRINCIPE", "GENOVA BRIGNOLE", "LA SPEZIA CENTRALE", "SAVONA"],
        "Lombardia": ["MILANO CENTRALE", "MILANO PORTA GARIBALDI", "MILANO CADORNA", "BRESCIA"],
        "Marche": ["ANCONA", "PESARO", "S.BENEDETTO DEL TRONTO", "CIVITANOVA MARCHE-MONTEGRANARO"],
        "Molise": ["CAMPOBASSO", "TERMOLI", "ISERNIA", "VENAFRO"],
        "Piemonte": ["TORINO PORTA NUOVA", "TORINO PORTA SUSA", "NOVARA", "ALESSANDRIA"],
        "Puglia": ["BARI CENTRALE", "LECCE", "FOGGIA", "TARANTO"],
        "Sardegna": ["CAGLIARI", "SASSARI", "OLBIA", "ORISTANO"],
        "Sicilia": ["PALERMO CENTRALE", "CATANIA CENTRALE", "MESSINA CENTRALE", "SIRACUSA"],
        "Toscana": ["FIRENZE SANTA MARIA NOVELLA", "PISA CENTRALE", "LIVORNO CENTRALE", "AREZZO"],
        "Trentino-Alto Adige": ["TRENTO", "BOLZANO", "ROVERETO", "MERANO"],
        "Umbria": ["PERUGIA", "TERNI", "FOLIGNO", "ASSISI"],
        "Valle d'Aosta": ["AOSTA", "CHATILLON-SAINT-VINCENT", "VERRES", "PONT-SAINT-MARTIN"],
        "Veneto": ["VENEZIA S.LUCIA", "VERONA PORTA NUOVA", "PADOVA", "VICENZA"],
        "Tutte": ["MILANO CENTRALE", "ROMA TERMINI", "BOLOGNA CENTRALE", "NAPOLI CENTRALE"]
    ]
    
    /// Stazioni suggerite: 1 grande stazione della regione selezionata + 3 stazioni più vicine (se GPS disponibile)
    /// oppure le 4 stazioni principali della regione selezionata (se GPS non disponibile)
    private var displayedCandidates: [Station] {
        let region = manager.strikeRegion
        let hubName = Self.regionHubs[region] ?? "MILANO CENTRALE"
        let hubStation = manager.resolveStation(name: hubName)
        let hubKey = hubStation.name.lowercased()
        
        if let userLoc = locationManager.userLocation {
            let validCandidates = manager.allRFIStations.compactMap { st -> (station: RFIStation, dist: CLLocationDistance)? in
                guard let lat = st.lat, let lon = st.lon else { return nil }
                let loc = CLLocation(latitude: lat, longitude: lon)
                let dist = loc.distance(from: userLoc)
                return (st, dist)
            }
            .sorted { $0.dist < $1.dist }
            
            var results: [Station] = [hubStation]
            for item in validCandidates {
                let st = item.station
                let candidate = Station(name: st.name, rfiID: st.rfiID, vtID: st.vtID, lat: st.lat, lon: st.lon)
                let candKey = candidate.name.lowercased()
                
                if candKey != hubKey && !results.contains(where: { $0.name.lowercased() == candKey }) {
                    results.append(candidate)
                }
                
                if results.count == 4 {
                    break
                }
            }
            return results
        } else {
            let names = Self.regionMajorStations[region] ?? Self.regionMajorStations["Tutte"]!
            return names.map { manager.resolveStation(name: $0) }
        }
    }
    
    /// Stazioni aggiunte dall'utente (es. tramite ricerca) che non sono già presenti nei suggerimenti
    private var addedCustomStations: [Station] {
        let candidateKeys = Set(displayedCandidates.map { $0.name.lowercased() })
        return manager.myStations.filter { !candidateKeys.contains($0.name.lowercased()) }
    }
    
    var body: some View {
        VStack(spacing: 16) {
            OnboardingHeaderView(
                icon: "star.fill",
                color: .orange,
                title: "Stazioni Frequenti",
                subtitle: "Salva le stazioni da cui parti più spesso per consultarne i tabelloni con un solo tocco."
            )
            .padding(.top, 8)
            
            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    // Stazioni rilevate da GPS o suggerite per la regione selezionata
                    let candidates = displayedCandidates
                    if !candidates.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(locationManager.userLocation != nil ? "STAZIONI SUGGERITE E VICINE" : "STAZIONI SUGGERITE")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 4)
                            
                            VStack(spacing: 8) {
                                ForEach(candidates) { station in
                                    stationRow(station: station, isCustomAdded: false)
                                }
                            }
                        }
                    }
                    
                    // Stazioni aggiunte dall'utente (es. da ricerca) mostrate direttamente sopra la barra di ricerca
                    if !addedCustomStations.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("STAZIONI AGGIUNTE")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 4)
                            
                            VStack(spacing: 8) {
                                ForEach(addedCustomStations) { station in
                                    stationRow(station: station, isCustomAdded: true)
                                }
                            }
                        }
                    }
                    
                    // Cerca un'altra stazione
                    Button {
                        showSearchSheet = true
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.secondary)
                            Text("Cerca un'altra stazione...")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Spacer()
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(.blue)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 13)
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 4)
            }
            
            Spacer(minLength: 0)
        }
        .onAppear {
            if locationManager.authorizationStatus == .authorizedWhenInUse || locationManager.authorizationStatus == .authorizedAlways {
                locationManager.requestLocation(force: true)
            }
        }
        .sheet(isPresented: $showSearchSheet) {
            StationSelectionSheet(
                selectedName: $searchStationName,
                selectedID: $searchStationID,
                onStationSelected: { station in
                    manager.addMyStation(station)
                },
                title: "Aggiungi Stazione",
                autoFocusSearch: true
            )
            .environmentObject(manager)
            .environmentObject(locationManager)
        }
        .onChange(of: searchStationID) { _, newID in
            guard !newID.isEmpty, !searchStationName.isEmpty else { return }
            let resolved = manager.resolveStation(name: searchStationName)
            manager.addMyStation(resolved)
            searchStationName = ""
            searchStationID = ""
        }
    }
    
    @ViewBuilder
    private func stationRow(station: Station, isCustomAdded: Bool) -> some View {
        let isFav = manager.isMyStation(station)
        HStack {
            Image(systemName: "building.2.crop.circle.fill")
                .foregroundColor(.orange)
                .font(.title3)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(station.name.formattedStationName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)
                
                if let lat = station.lat, let lon = station.lon, let userLoc = locationManager.userLocation {
                    let d = userLoc.distance(from: CLLocation(latitude: lat, longitude: lon))
                    let distStr = d < 1000 ? "\(Int(d))m da te" : String(format: "%.1fkm da te", d / 1000.0)
                    Text(distStr)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } else if isCustomAdded {
                    Text("Aggiunta manualmente")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            Button {
                Haptics.play(.medium)
                if isFav {
                    manager.removeMyStation(station)
                } else {
                    manager.addMyStation(station)
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: isFav ? "checkmark" : "plus")
                        .font(.caption.bold())
                    Text(isFav ? "Aggiunta" : "Aggiungi")
                        .font(.caption.weight(.semibold))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(isFav ? Color.blue.opacity(0.12) : Color(.tertiarySystemGroupedBackground))
                .foregroundColor(isFav ? .blue : .primary)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - Scheda Guida Rapida & Funzioni Smart (Ultima pagina)
struct OnboardingQuickGuideView: View {
    @EnvironmentObject var manager: TrainManager
    let isUpdateMode: Bool
    var onOpenCommuteSettings: (() -> Void)? = nil

    var body: some View {
        let isPro = manager.hasSupport()
        VStack(spacing: 16) {
            OnboardingHeaderView(
                icon: isUpdateMode ? "hand.draw.fill" : "sparkles",
                color: .purple,
                title: isUpdateMode ? "Come orientarti al volo" : "Tutto Pronto per il Viaggio",
                subtitle: isUpdateMode
                    ? "Pochi gesti rapidi per usare al meglio tutte le nuove funzioni."
                    : "Pochi gesti rapidi e funzioni smart per viaggiare senza stress."
            )
            .padding(.top, 8)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    // Card dedicata Casa <-> Lavoro in Abitudini di viaggio
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top, spacing: 14) {
                            ZStack {
                                Circle()
                                    .fill(Color.blue.opacity(0.12))
                                    .frame(width: 38, height: 38)
                                Image(systemName: "clock.arrow.2.circlepath")
                                    .font(.system(size: 17, weight: .bold))
                                    .foregroundColor(.blue)
                            }

                            VStack(alignment: .leading, spacing: 3) {
                                Text("Tratte Casa ↔ Lavoro")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(.primary)
                                Text(isPro
                                     ? "Imposta le tue stazioni di Casa e Lavoro e i tuoi orari: avrai monitoraggio automatico, Piano B e tratta sempre pronta in Home e Viaggi."
                                     : "Imposta fino a \(SupporterCommuteManager.maxStationsPerSide) stazioni di Casa e Lavoro e i tuoi orari: troverai la tratta pronta in Home e Viaggi con tutte le partenze combinate.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineSpacing(2)
                            }
                        }

                        if let onOpenCommuteSettings {
                            Button {
                                Haptics.play(.medium)
                                onOpenCommuteSettings()
                            } label: {
                                HStack(spacing: 6) {
                                    Text("Raggiungi le impostazioni qui per configurarle")
                                        .font(.caption.weight(.semibold))
                                    Image(systemName: "arrow.up.right")
                                        .font(.caption2.bold())
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 9)
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(14)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.blue.opacity(0.24), lineWidth: 1)
                    )

                    // Card: Gesti rapidi uniformati ovunque
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top, spacing: 14) {
                            ZStack {
                                Circle()
                                    .fill(Color.purple.opacity(0.12))
                                    .frame(width: 38, height: 38)
                                Image(systemName: "hand.draw.fill")
                                    .font(.system(size: 17, weight: .bold))
                                    .foregroundColor(.purple)
                            }

                            VStack(alignment: .leading, spacing: 3) {
                                Text("Swipe rapidi ovunque")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(.primary)
                                Text("Scorri a sinistra per aggiungere o togliere dai preferiti. Sui treni, scorri a destra per l'Isola Dinamica (si chiude da sola all'arrivo!).")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineSpacing(2)
                            }
                        }

                        HStack(spacing: 8) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.left")
                                    .font(.system(size: 10, weight: .bold))
                                Image(systemName: "star.fill")
                                    .font(.system(size: 10, weight: .bold))
                                Text("Preferiti")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(Color.orange.opacity(0.14))
                            .foregroundColor(.orange)
                            .clipShape(Capsule())

                            HStack(spacing: 4) {
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 10, weight: .bold))
                                Image(systemName: "platter.filled.top.iphone")
                                    .font(.system(size: 10, weight: .bold))
                                Text("Isola Dinamica")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(Color.purple.opacity(0.14))
                            .foregroundColor(.purple)
                            .clipShape(Capsule())
                        }
                        .padding(.leading, 52)
                    }
                    .padding(14)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
                    )

                    OnboardingHighlightCard(
                        icon: "magnifyingglass.circle.fill",
                        color: .indigo,
                        title: "Ricerca veloce & Assistente IA",
                        desc: "Tocca la barra in alto nella Home per cercare treni, stazioni o fare domande in linguaggio naturale, anche con la voce."
                    )

                    OnboardingHighlightCard(
                        icon: "arrow.left.arrow.right",
                        color: .teal,
                        title: "Viaggi e Tratte sempre pronti",
                        desc: "Cambia data e ora in un tap, inverti partenza e arrivo e scorri verso sinistra su una tratta per salvarla nei segnalibri."
                    )

                    OnboardingHighlightCard(
                        icon: "square.grid.2x2.fill",
                        color: .green,
                        title: "Coincidenze Metro & Widget iOS",
                        desc: "Tieni premuta una fermata del treno per vedere le coincidenze metro, o aggiungi i Widget Treni e Stazioni personalizzabili alla Home."
                    )
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 4)
            }

            Spacer(minLength: 0)
        }
    }
}

// MARK: - Scheda Condizionale: Permessi Mancanti (Notifiche e Posizione)
struct OnboardingPermissionsView: View {
    let snapshot: OnboardingPermissionSnapshot
    let initiallyNeededNotifications: Bool
    let initiallyNeededLocation: Bool
    let isRequesting: Bool
    let onRequestNotifications: () -> Void
    let onRequestLocation: () -> Void

    private let freeLimit = TrainManager.freeScheduledNotificationLimit

    private var headerConfig: (icon: String, color: Color, title: String, subtitle: String) {
        if initiallyNeededNotifications && initiallyNeededLocation {
            return (
                "bell.and.waves.left.and.right.fill",
                .orange,
                "Migliora la tua esperienza",
                "Ciao! Avrei bisogno dell'accesso alle notifiche e alla posizione per migliorare la tua esperienza su In Orario."
            )
        } else if initiallyNeededNotifications {
            return (
                "bell.badge.fill",
                .orange,
                "Attiva le notifiche",
                "Ciao! Avrei bisogno dell'accesso alle notifiche per migliorare la tua esperienza: senza notifiche ti perdi ciò per cui è nata l'app."
            )
        } else {
            return (
                "location.fill",
                .blue,
                "Attiva la posizione",
                "Ciao! Avrei bisogno dell'accesso alla posizione per migliorare la tua esperienza e mostrarti subito le stazioni attorno a te."
            )
        }
    }

    var body: some View {
        let cfg = headerConfig
        VStack(spacing: 16) {
            OnboardingHeaderView(
                icon: cfg.icon,
                color: cfg.color,
                title: cfg.title,
                subtitle: cfg.subtitle
            )
            .padding(.top, 8)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    if initiallyNeededNotifications || snapshot.needsNotifications {
                        notificationsCard
                    } else {
                        alreadyActivePill(
                            icon: "bell.badge.fill",
                            text: "Notifiche già attive"
                        )
                    }

                    if initiallyNeededLocation || snapshot.needsLocation {
                        locationCard
                    } else {
                        alreadyActivePill(
                            icon: "location.fill",
                            text: "Posizione già attiva"
                        )
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 4)
            }

            Spacer(minLength: 0)
        }
    }

    private var notificationsCard: some View {
        let isActive = snapshot.isNotificationsReady
        let statusLabel: String = {
            switch snapshot.notifications {
            case .authorizedActive: return "Attive"
            case .authorizedAppToggleOff: return "Disattivate nell'app"
            case .notDetermined: return "Non attive"
            case .denied: return "Bloccate"
            }
        }()

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill((isActive ? Color.green : Color.orange).opacity(0.14))
                        .frame(width: 40, height: 40)
                    Image(systemName: isActive ? "bell.badge.fill" : "bell.slash.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(isActive ? .green : .orange)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Notifiche push")
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(.primary)
                    Text(statusLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(isActive ? .green : .orange)
                }

                Spacer()

                if isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.green)
                }
            }

            Text("Senza le notifiche ti perdi moltissimo: sono il motivo principale per cui esiste In Orario. Ricevi gratis l'avviso all'orario che scegli fino a \(freeLimit) treni, più scioperi, ritardi e cambi binario.")
                .font(.caption)
                .foregroundColor(.secondary)
                .lineSpacing(2)

            if !isActive {
                Button(action: onRequestNotifications) {
                    HStack(spacing: 6) {
                        Image(systemName: snapshot.notifications == .denied ? "gear" : "bell.badge.fill")
                            .font(.caption.bold())
                        Text(notificationActionTitle)
                            .font(.subheadline.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.orange.opacity(0.14))
                    .foregroundColor(.orange)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .disabled(isRequesting)
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                    Text("Notifiche attive — sei coperto!")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.green)
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke((isActive ? Color.green : Color.orange).opacity(0.28), lineWidth: 1)
        )
    }

    private var notificationActionTitle: String {
        switch snapshot.notifications {
        case .notDetermined:
            return "Attiva notifiche"
        case .authorizedAppToggleOff:
            return "Riattiva notifiche nell'app"
        case .denied:
            return "Apri Impostazioni Notifiche"
        case .authorizedActive:
            return "Attive"
        }
    }

    private var locationCard: some View {
        let isActive = snapshot.isLocationReady
        let statusLabel: String = {
            switch snapshot.location {
            case .authorized: return "Attiva"
            case .notDetermined: return "Non attiva"
            case .deniedOrRestricted: return "Negata"
            }
        }()

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill((isActive ? Color.green : Color.blue).opacity(0.14))
                        .frame(width: 40, height: 40)
                    Image(systemName: isActive ? "location.fill" : "location.slash.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(isActive ? .green : .blue)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Posizione (solo mentre usi l'app)")
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(.primary)
                    Text(statusLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(isActive ? .green : .blue)
                }

                Spacer()

                if isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.green)
                }
            }

            Text("Serve solo quando apri In Orario per mostrarti subito la stazione più vicina, le partenze attorno a te e impostare automaticamente la tua regione.")
                .font(.caption)
                .foregroundColor(.secondary)
                .lineSpacing(2)

            if !isActive {
                Button(action: onRequestLocation) {
                    HStack(spacing: 6) {
                        Image(systemName: snapshot.location == .deniedOrRestricted ? "gear" : "location.fill")
                            .font(.caption.bold())
                        Text(snapshot.location == .deniedOrRestricted ? "Apri Impostazioni Posizione" : "Attiva posizione")
                            .font(.subheadline.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.blue.opacity(0.14))
                    .foregroundColor(.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .disabled(isRequesting)
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                    Text("Posizione attiva!")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.green)
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke((isActive ? Color.green : Color.blue).opacity(0.28), lineWidth: 1)
        )
    }

    private func alreadyActivePill(icon: String, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.subheadline.bold())
                .foregroundColor(.green)
            Text(text)
                .font(.subheadline.weight(.medium))
                .foregroundColor(.primary)
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.green.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.green.opacity(0.22), lineWidth: 0.8)
        )
    }
}
