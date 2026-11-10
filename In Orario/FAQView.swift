import SwiftUI

struct FAQItem: Identifiable {
    let id = UUID()
    let question: String
    let answer: String
}

struct FAQSectionData: Identifiable {
    let id = UUID()
    let title: String
    let icon: String
    let color: Color
    let items: [FAQItem]
}

struct FAQView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var manager: TrainManager
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = true
    @State private var showFeedbackSheet = false
    @State private var expandedItemIDs: Set<UUID> = []
    
    private let faqSections: [FAQSectionData] = [
        FAQSectionData(
            title: "Trucchi e Funzionalità Utili",
            icon: "sparkles",
            color: .indigo,
            items: [
                FAQItem(
                    question: "Come vedere le partenze della metropolitana al volo?",
                    answer: "Dalla schermata con le fermate di un treno, tieni premuto a lungo sulla riga di una stazione con coincidenza metropolitana (ad es. Milano Centrale, Garibaldi, Cadorna, Repubblica, ecc.): si aprirà subito il menù contestuale con i prossimi orari delle linee della metropolitana!"
                ),
                FAQItem(
                    question: "Come salvare una stazione, un treno o un viaggio nei preferiti?",
                    answer: "Tocca l'icona della stella (⭐) in alto a destra quando consulti il tabellone di una stazione o le fermate di un treno per aggiungerlo ai tuoi preferiti.\n\nPer salvare una tratta o viaggio frequente, cerca la soluzione tra due stazioni e tocca 'Aggiungi ai Viaggi Preferiti'."
                ),
                FAQItem(
                    question: "Come funziona la funzionalità 'Segnala' (Crowdsourcing)?",
                    answer: "Dalla schermata del dettaglio treno puoi toccare l'icona 'Segnala' per condividere informazioni utili in tempo reale con gli altri pendolari: ritardo effettivo, affollamento delle carrozze o variazioni improvvise del binario. Le segnalazioni aiutano l'intera community di In Orario!"
                )
            ]
        ),
        FAQSectionData(
            title: "Notifiche e Live Activity",
            icon: "bell.badge.fill",
            color: .orange,
            items: [
                FAQItem(
                    question: "Quanti treni posso monitorare contemporaneamente?",
                    answer: "Con il piano gratuito puoi attivare la notifica o la Live Activity per 1 treno alla volta. Passando a In Orario Pro sblocchi il monitoraggio simultaneo fino a 10 treni, Live Activities ad alta frequenza, notifiche push dedicate per gli scioperi e la selezione dei giorni della settimana."
                ),
                FAQItem(
                    question: "Perché le notifiche o la Live Activity non si aggiornano?",
                    answer: "Assicurati di aver concesso i permessi per le notifiche e le Attività in Tempo Reale nelle impostazioni di iOS. Verifica anche che il risparmio energetico dell'iPhone non blocchi i dati in background."
                )
            ]
        ),
        FAQSectionData(
            title: "Treni e Tabelloni",
            icon: "train.side.front.car",
            color: .blue,
            items: [
                FAQItem(
                    question: "Da dove provengono le informazioni sui treni?",
                    answer: "I dati in tempo reale sono sincronizzati direttamente con i sistemi ufficiali delle stazioni ferroviarie (RFI, Trenitalia e Trenord)."
                ),
                FAQItem(
                    question: "Perché il binario o il ritardo cambiano all'ultimo momento?",
                    answer: "I binari e i ritardi vengono assegnati e aggiornati continuamente dai sistemi di gestione del traffico in stazione man mano che il treno si avvicina."
                )
            ]
        ),
        FAQSectionData(
            title: "Intelligenza Artificiale",
            icon: "brain.head.profile",
            color: .purple,
            items: [
                FAQItem(
                    question: "Qual è la differenza tra IA Locale e Cloud In Orario?",
                    answer: "IA Locale (Apple Intelligence) elabora le informazioni direttamente sul tuo iPhone in modo completamente gratuito, privato e offline.\n\nCloud In Orario utilizza invece server dedicati ad alte prestazioni per il riepilogo intelligente di scioperi e lavori programmati ed è inclusa nel piano In Orario Pro."
                )
            ]
        ),
        FAQSectionData(
            title: "Il Progetto In Orario",
            icon: "heart.fill",
            color: .red,
            items: [
                FAQItem(
                    question: "L'app In Orario è davvero gratuita?",
                    answer: "Sì! In Orario è un progetto indipendente sviluppato nel tempo libero per rendere la vita dei pendolari più semplice, senza pubblicità. Per accedere alle funzionalità avanzate (IA su server, notifiche push scioperi, monitoraggio fino a 10 treni e Live Activities ad alta frequenza) puoi attivare In Orario Pro."
                )
            ]
        )
    ]

    var body: some View {
        List {
            Section(header: Label("Supporto ed Azioni", systemImage: "wrench.and.screwdriver.fill")
                .font(.subheadline.bold())
                .foregroundColor(.blue)
            ) {
                Button(action: {
                    Haptics.play(.medium)
                    showFeedbackSheet = true
                }) {
                    Label("Segnala Bug o Feedback", systemImage: "ladybug.fill")
                        .foregroundColor(.red)
                        .font(.body.weight(.medium))
                }
                
                Button(action: {
                    Haptics.play(.medium)
                    hasCompletedOnboarding = false
                    dismiss()
                }) {
                    Label("Riproduci Tutorial Iniziale", systemImage: "graduationcap.fill")
                        .foregroundColor(.blue)
                        .font(.body.weight(.medium))
                }
            }
            
            ForEach(faqSections) { section in
                Section(header: Label(section.title, systemImage: section.icon)
                    .font(.subheadline.bold())
                    .foregroundColor(section.color)
                ) {
                    ForEach(section.items) { item in
                        DisclosureGroup(
                            isExpanded: Binding(
                                get: { expandedItemIDs.contains(item.id) },
                                set: { isExpanding in
                                    if isExpanding {
                                        expandedItemIDs.insert(item.id)
                                    } else {
                                        expandedItemIDs.remove(item.id)
                                    }
                                }
                            )
                        ) {
                            Text(item.answer)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .padding(.vertical, 4)
                        } label: {
                            Text(item.question)
                                .font(.body.weight(.medium))
                                .foregroundColor(.primary)
                        }
                    }
                }
            }
            
            Section(header: Label("Legale e Privacy", systemImage: "hand.raised.fill")
                .font(.subheadline.bold())
                .foregroundColor(.green)
            ) {
                Link(destination: URL(string: "https://inorario.toreroclub.com/#privacy")!) {
                    HStack {
                        Label("Informativa sulla Privacy", systemImage: "lock.shield.fill")
                            .foregroundColor(.primary)
                            .font(.body.weight(.medium))
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }

                Link(destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!) {
                    HStack {
                        Label("Termini d'Uso (EULA)", systemImage: "doc.text.fill")
                            .foregroundColor(.primary)
                            .font(.body.weight(.medium))
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Domande Frequenti")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showFeedbackSheet) {
            FeedbackFormView()
                .environmentObject(manager)
        }
    }
}
