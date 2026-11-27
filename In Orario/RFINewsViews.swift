import SwiftUI
import UIKit

// MARK: - Info Lavori (RFI Notices) Card & Detail Sheet

struct RFILavoroCardView: View {
    let item: NewsItem
    let showRegionBadge: Bool
    let onTap: () -> Void
    @Environment(\.openURL) private var openURL

    private var shouldShowWorkLocation: Bool {
        guard let loc = item.workLocation, !loc.isEmpty else { return false }
        let titleNorm = item.title.lowercased()
        let locNorm = loc.lowercased()
        return !titleNorm.contains(locNorm)
    }

    private var footerMetaText: String? {
        var parts: [String] = []
        if let company = item.meta?.company, !company.isEmpty {
            parts.append(company)
        }
        if showRegionBadge, let regions = item.regions, !regions.isEmpty, regions != ["Tutte"] {
            let label = regions.count > 2
                ? "\(regions.prefix(2).joined(separator: ", ")) +\(regions.count - 2)"
                : regions.joined(separator: ", ")
            parts.append(label)
        } else if let service = item.meta?.service, !service.isEmpty {
            // Mostra solo i primi 2 tipi di servizio per evitare chip troppo lunghi
            let servList = service.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            if !servList.isEmpty {
                let shortServ = servList.count > 2 ? "\(servList.prefix(2).joined(separator: ", "))…" : servList.joined(separator: ", ")
                parts.append(shortServ)
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                // 1. Titolo pulito (max 2 righe) + chevron
                HStack(alignment: .top, spacing: 10) {
                    Text(item.title)
                        .font(.headline)
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)

                    Spacer(minLength: 4)

                    if item.hasNoticeDetail {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)
                            .padding(.top, 3)
                    }
                }

                // 2. Quando (periodo di validità) e Dove (luogo del cantiere)
                VStack(alignment: .leading, spacing: 4) {
                    if let validity = item.validity, !validity.isEmpty {
                        HStack(spacing: 5) {
                            Image(systemName: "calendar")
                                .font(.caption2.weight(.semibold))
                            Text(validity)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                        }
                        .foregroundColor(.blue)
                    }

                    if shouldShowWorkLocation, let loc = item.workLocation {
                        HStack(spacing: 5) {
                            Image(systemName: "mappin.and.ellipse")
                                .font(.caption2.weight(.semibold))
                            Text(loc)
                                .font(.caption.weight(.medium))
                                .lineLimit(1)
                        }
                        .foregroundColor(.secondary)
                    }
                }

                // 3. Cosa (sintesi pulita, 3 righe max)
                Text(item.content)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                // 4. Footer pulito (Impresa · Servizio/Regione)
                if let footer = footerMetaText {
                    Text(footer)
                        .font(.caption2.weight(.medium))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .padding(.top, 2)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(16)
        }
        .buttonStyle(.plain)
        .contextMenu {
            if item.hasNoticeDetail {
                Button {
                    onTap()
                } label: {
                    Label("Apri dettagli completi", systemImage: "doc.text.magnifyingglass")
                }
            }
            if let url = item.resolvedSourceURL {
                Button {
                    openURL(url)
                } label: {
                    Label("Visualizza notizia completa", systemImage: "safari")
                }
            }
        }
    }
}

struct RFILavoroDetailSheet: View {
    let item: NewsItem
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    headerCard

                    if let blocks = item.blocks, !blocks.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                                renderBlock(block)
                            }
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.secondarySystemGroupedBackground))
                        .cornerRadius(16)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            FormattedNewsContentView(content: item.content)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.secondarySystemGroupedBackground))
                        .cornerRadius(16)
                    }

                    if let attachments = item.attachments, !attachments.isEmpty {
                        attachmentsCard(attachments)
                    }

                    if let url = item.resolvedSourceURL {
                        Button {
                            openURL(url)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "safari.fill")
                                    .font(.headline)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Visualizza notizia completa")
                                        .font(.subheadline.weight(.semibold))
                                    Text("Apri l'avviso ufficiale sul sito RFI / Trenitalia")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .font(.caption.weight(.bold))
                            }
                            .foregroundColor(.blue)
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.secondarySystemGroupedBackground))
                            .cornerRadius(16)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Dettaglio Lavori")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                UserInterestTelemetryManager.shared.recordInfomobilityView(item: item)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Chiudi") { dismiss() }
                        .fontWeight(.semibold)
                }
                if let url = item.resolvedSourceURL {
                    ToolbarItem(placement: .topBarTrailing) {
                        ShareLink(item: url) {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
            }
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(item.title)
                .font(.title3.weight(.bold))
                .foregroundColor(.primary)

            if let subtitle = item.subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.secondary)
            }

            if let validity = item.validity, !validity.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.blue)
                    Text("Quando: \(validity)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.primary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(10)
            }

            if let workLoc = item.workLocation, !workLoc.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.orange)
                    Text("Dove: \(workLoc)")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.primary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(10)
            }

            if let full = item.fullTitle, !full.isEmpty, full != item.title {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Linee coinvolte")
                        .font(.caption.weight(.bold))
                        .foregroundColor(.secondary)
                    Text(full)
                        .font(.caption)
                        .foregroundColor(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.tertiarySystemGroupedBackground))
                .cornerRadius(10)
            }

            if let meta = item.meta {
                let rows: [(String, String, String)] = [
                    ("tram.fill", "Servizio", meta.service ?? ""),
                    ("building.2.fill", "Impresa", meta.company ?? ""),
                    ("wrench.and.screwdriver.fill", "Causa", meta.cause ?? ""),
                    ("map.fill", "Regione", meta.region ?? "")
                ].filter { !$0.2.isEmpty }

                if !rows.isEmpty {
                    Divider()
                        .padding(.vertical, 2)

                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: row.0)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .frame(width: 16)
                                    .padding(.top, 2)
                                Text(row.1)
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(.secondary)
                                    .frame(width: 62, alignment: .leading)
                                Text(row.2)
                                    .font(.caption)
                                    .foregroundColor(.primary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
    }

    @ViewBuilder
    private func renderBlock(_ block: NewsContentBlock) -> some View {
        switch block.type {
        case "heading":
            if let heading = block.heading, !heading.isEmpty {
                Text(heading)
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(.primary)
                    .padding(.top, 4)
            }

        case "text":
            if let paragraphs = block.paragraphs, !paragraphs.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                        Text(paragraph)
                            .font(.subheadline)
                            .foregroundColor(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

        case "list":
            if let items = block.items, !items.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, entry in
                        HStack(alignment: .top, spacing: 8) {
                            Circle()
                                .fill(Color.blue)
                                .frame(width: 5, height: 5)
                                .padding(.top, 7)
                            Text(entry)
                                .font(.subheadline)
                                .foregroundColor(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.leading, 2)
            }

        case "table":
            if let sections = block.tableSections, !sections.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                        RFIScheduleTableView(section: section)
                    }
                }
            }

        default:
            EmptyView()
        }
    }

    private func attachmentsCard(_ attachments: [NewsAttachment]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Documenti allegati")
                .font(.subheadline.weight(.bold))
                .foregroundColor(.primary)

            ForEach(Array(attachments.enumerated()), id: \.offset) { _, att in
                if let url = URL(string: att.url) {
                    Button {
                        openURL(url)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "doc.fill")
                                .foregroundColor(.red)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(att.title)
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(.primary)
                                    .multilineTextAlignment(.leading)
                                if let size = att.size, !size.isEmpty {
                                    Text(size)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                        .padding(10)
                        .background(Color(.tertiarySystemGroupedBackground))
                        .cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
    }
}

struct RFIScheduleTableView: View {
    let section: NewsTableSection

    private var headers: [String] {
        section.headers ?? []
    }

    private var rows: [[String]] {
        section.rows ?? []
    }

    private var columnCount: Int {
        max(headers.count, rows.map(\.count).max() ?? 0)
    }

    private func columnWidth(for index: Int) -> CGFloat {
        let header = (index < headers.count ? headers[index] : "").lowercased()
        if header.contains("provvediment") || header.contains("note") || header.contains("variazion") || header.contains("dettagl") {
            return 240
        }
        if header == "ora" || header.contains("orario") {
            return 58
        }
        if header.contains("treno") || header.contains("bus") {
            return 84
        }
        if header.contains("partenza") || header.contains("arrivo") || header.contains("stazione") || header.contains("fermata") {
            return 125
        }
        return columnCount <= 3 ? 140 : 105
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title = section.title, !title.isEmpty {
                Text(title)
                    .font(.caption.weight(.bold))
                    .foregroundColor(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.blue.opacity(0.12))
            }

            if columnCount > 0 {
                ScrollView(.horizontal, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 0) {
                        if !headers.isEmpty {
                            HStack(alignment: .top, spacing: 0) {
                                ForEach(0..<columnCount, id: \.self) { col in
                                    let text = col < headers.count ? headers[col] : ""
                                    Text(text)
                                        .font(.caption2.weight(.bold))
                                        .foregroundColor(.secondary)
                                        .frame(width: columnWidth(for: col), alignment: .leading)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 8)
                                }
                            }
                            .background(Color(.tertiarySystemFill))
                        }

                        ForEach(Array(rows.enumerated()), id: \.offset) { rowIdx, row in
                            Divider()
                            HStack(alignment: .top, spacing: 0) {
                                ForEach(0..<columnCount, id: \.self) { col in
                                    let cell = col < row.count ? row[col] : ""
                                    let hdr = (col < headers.count ? headers[col] : "").lowercased()
                                    let isTime = hdr == "ora" || hdr.contains("orario")
                                    let isTrain = col == 0 && (hdr.contains("treno") || hdr.contains("bus"))

                                    Text(cell)
                                        .font(isTrain ? .caption.weight(.bold) : .caption)
                                        .monospacedDigit()
                                        .foregroundColor(isTime ? .blue : .primary)
                                        .frame(width: columnWidth(for: col), alignment: .leading)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 8)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .background(rowIdx % 2 == 1 ? Color(.tertiarySystemFill).opacity(0.35) : Color.clear)
                        }
                    }
                }
            }

            if let truncated = section.truncatedRows, truncated > 0 {
                Text("+ altri \(truncated) treni/corse — consulta la notizia completa qui sotto.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.tertiarySystemFill).opacity(0.4))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(.separator).opacity(0.5), lineWidth: 0.5)
        )
    }
}

// MARK: - Info Mobilità (RFI Updates) Clean Card + Expandable Scansione Oraria

struct RFIRealtimeCardView: View {
    let item: NewsItem
    let isExpanded: Bool
    let showRegionBadge: Bool
    let onToggle: () -> Void
    @Environment(\.openURL) private var openURL

    private var statusColor: Color {
        switch item.eventStatus {
        case "suspended": return .red
        case "slowed", "ongoing": return .orange
        case "resolved": return .green
        default: return item.isUrgent ? .orange : .green
        }
    }

    private var statusIcon: String {
        switch item.eventStatus {
        case "suspended": return "exclamationmark.octagon.fill"
        case "slowed": return "exclamationmark.triangle.fill"
        case "ongoing": return "dot.radiowaves.left.and.right"
        case "resolved": return "checkmark.circle.fill"
        default: return item.isUrgent ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
        }
    }

    private var statusTitle: String {
        if let label = item.eventStatusLabel, !label.isEmpty {
            return label
        }
        return item.isRealtimeResolved ? "Tornata regolare" : "In corso"
    }

    private var regionFooterText: String? {
        guard let regions = item.regions, !regions.isEmpty, regions != ["Tutte"] else {
            return nil
        }
        if !showRegionBadge && regions.count == 1 {
            return nil
        }
        if regions.count > 2 {
            return "\(regions.prefix(2).joined(separator: ", ")) +\(regions.count - 2)"
        }
        return regions.joined(separator: ", ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Intestazione tappabile per espandere / comprimere la scansione oraria
            Button(action: onToggle) {
                VStack(alignment: .leading, spacing: 8) {
                    // 1. Pill di stato a sinistra + orario aggiornamento e chevron a destra
                    HStack(spacing: 8) {
                        HStack(spacing: 5) {
                            Image(systemName: statusIcon)
                                .font(.caption2.weight(.bold))
                            Text(statusTitle)
                                .font(.caption.weight(.semibold))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(statusColor.opacity(0.15))
                        .foregroundColor(statusColor)
                        .clipShape(Capsule())

                        Spacer(minLength: 4)

                        if let compactTime = item.formattedCompactUpdateTime {
                            HStack(spacing: 4) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.caption2)
                                Text(compactTime)
                                    .font(.caption.weight(.medium))
                                    .monospacedDigit()
                            }
                            .foregroundColor(.secondary)
                        }

                        if item.hasRealtimeDetail {
                            Image(systemName: "chevron.down")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.secondary)
                                .frame(width: 22, height: 22)
                                .rotationEffect(.degrees(isExpanded ? 180 : 0))
                                .animation(.easeInOut(duration: 0.22), value: isExpanded)
                        }
                    }

                    // 2. Titolo breve e nitido (es. "Linea Milano – Bologna AV")
                    Text(item.title)
                        .font(.headline)
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.leading)

                    // 3. Sintesi pulita dell'evento (altezza stabile per evitare salti durante l'espansione)
                    if !item.content.isEmpty && item.content != item.title {
                        Text(item.content)
                            .font(.subheadline)
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    // 4. Effetti sulla mobilità in evidenza (se presenti)
                    if let effects = item.mobilityEffects, !effects.isEmpty {
                        HStack(alignment: .top, spacing: 7) {
                            Image(systemName: item.isRealtimeResolved ? "info.circle.fill" : "clock.badge.exclamationmark.fill")
                                .font(.caption)
                                .foregroundColor(statusColor)
                                .padding(.top, 2)
                            Text(effects)
                                .font(.caption)
                                .foregroundColor(.primary)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(statusColor.opacity(0.08))
                        .cornerRadius(8)
                    }

                    // 5. Footer: scansione oraria sintetica (inizio -> fine/agg.) + regione
                    HStack(spacing: 10) {
                        timingSummaryBar
                        Spacer(minLength: 4)
                        if let regText = regionFooterText {
                            HStack(spacing: 3) {
                                Image(systemName: "mappin.and.ellipse")
                                    .font(.caption2)
                                Text(regText)
                                    .font(.caption2.weight(.medium))
                                    .lineLimit(1)
                            }
                            .foregroundColor(.secondary)
                        }
                    }
                    .padding(.top, 2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // 6. Espansione inline con scansione oraria completa (timeline) + link notizia completa
            if isExpanded {
                Divider()
                    .padding(.vertical, 2)

                VStack(alignment: .leading, spacing: 12) {
                    if let place = item.placeAndDate, !place.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "mappin.and.ellipse")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(place)
                                .font(.caption.weight(.medium))
                                .foregroundColor(.secondary)
                        }
                    }

                    if let timeline = item.timeline, !timeline.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(timeline.enumerated()), id: \.offset) { idx, entry in
                                timelineRow(entry: entry, isLast: idx == timeline.count - 1)
                            }
                        }
                    }

                    if let url = item.resolvedSourceURL {
                        Button {
                            openURL(url)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "safari")
                                Text("Visualizza notizia completa")
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .font(.caption2.weight(.bold))
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.blue)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(Color.blue.opacity(0.08))
                            .cornerRadius(10)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .transition(.opacity)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
        .clipped()
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(item.isRealtimeResolved ? Color.clear : statusColor.opacity(0.35), lineWidth: 1)
        )
        .contextMenu {
            if item.hasRealtimeDetail {
                Button {
                    onToggle()
                } label: {
                    Label(isExpanded ? "Comprimi cronologia" : "Espandi cronologia", systemImage: isExpanded ? "chevron.up" : "clock.arrow.circlepath")
                }
            }
            if let url = item.resolvedSourceURL {
                Button {
                    openURL(url)
                } label: {
                    Label("Visualizza notizia completa", systemImage: "safari")
                }
            }
            Button {
                UIPasteboard.general.string = "\(item.fullTitle ?? item.title)\n\(item.content)"
            } label: {
                Label("Copia testo", systemImage: "doc.on.doc")
            }
        }
    }

    @ViewBuilder
    private var timingSummaryBar: some View {
        let startStr = item.formattedStartedAt
        let lastStr = item.formattedLastUpdatedAt
        let endStr = item.formattedEndedAt

        if startStr != nil || lastStr != nil {
            HStack(spacing: 10) {
                if let start = startStr {
                    HStack(spacing: 4) {
                        Image(systemName: "play.circle.fill")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text("Inizio \(start)")
                            .font(.caption2.weight(.medium))
                            .foregroundColor(.secondary)
                    }
                }

                if item.isRealtimeResolved {
                    if let end = endStr ?? lastStr, end != startStr {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption2)
                                .foregroundColor(.green)
                            Text("Fine \(end)")
                                .font(.caption2.weight(.semibold))
                                .foregroundColor(.green)
                        }
                    }
                } else {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 6, height: 6)
                        if let last = lastStr, last != startStr {
                            Text("In corso · \(last)")
                                .font(.caption2.weight(.semibold))
                                .foregroundColor(statusColor)
                        } else {
                            Text("In corso")
                                .font(.caption2.weight(.semibold))
                                .foregroundColor(statusColor)
                        }
                    }
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.85)
        }
    }

    private func timelineRow(entry: NewsTimelineEntry, isLast: Bool) -> some View {
        let isRes = entry.isResolution == true
        let isInit = entry.isInitial == true
        let dotColor: Color = isRes ? .green : (isInit ? .secondary : statusColor)

        let whenText: String = {
            if let rel = NewsItem.formatRelativeRomeDateTime(iso: entry.timestamp, fallback: nil) {
                return rel
            }
            let bits = [entry.dateDisplay, entry.timeDisplay].compactMap { $0 }.filter { !$0.isEmpty }
            return bits.joined(separator: " · ")
        }()

        return HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(dotColor.opacity(0.18))
                        .frame(width: 18, height: 18)
                    Circle()
                        .fill(dotColor)
                        .frame(width: 8, height: 8)
                }
                .padding(.top, 2)

                if !isLast {
                    Rectangle()
                        .fill(Color(.separator).opacity(0.6))
                        .frame(width: 1.5)
                        .frame(maxHeight: .infinity)
                        .padding(.vertical, 3)
                }
            }
            .frame(width: 18)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(entry.label ?? (isInit ? "Inizio evento" : "Aggiornamento"))
                        .font(.caption.weight(.bold))
                        .foregroundColor(isRes ? .green : (isInit ? .secondary : .primary))

                    if !whenText.isEmpty {
                        Text(whenText)
                            .font(.caption2.weight(.semibold))
                            .monospacedDigit()
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(.tertiarySystemFill))
                            .cornerRadius(5)
                    }
                }

                if let paragraphs = entry.paragraphs {
                    ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, p in
                        Text(p)
                            .font(.subheadline)
                            .foregroundColor(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if let eff = entry.effects, !eff.isEmpty {
                    Text("Effetti sulla mobilità: \(eff)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.bottom, isLast ? 0 : 14)
        }
    }
}
