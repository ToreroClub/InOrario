import SwiftUI
import Combine
import Foundation
import CoreLocation
import ActivityKit
import StoreKit

struct PulsingCircle: View {
    let color: Color
    @State private var scale: CGFloat = 1.0
    @State private var opacity: Double = 1.0
    
    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .overlay(
                Circle()
                    .stroke(color, lineWidth: 2)
                    .scaleEffect(scale)
                    .opacity(opacity)
            )
            .onAppear {
                DispatchQueue.main.async {
                    withAnimation(Animation.easeInOut(duration: 1.2).repeatForever(autoreverses: false)) {
                        scale = 2.2
                        opacity = 0.0
                    }
                }
            }
    }
}

struct LineArrivalInfo: Identifiable {
    let id: String
    let arrivals: [String]
}

struct AutocompleteField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    let suggestions: [String]
    
    @State private var isDropdownOpen = false
    @State private var filteredSuggestions: [String] = []
    @FocusState private var isFocused: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption.bold())
                .foregroundColor(.secondary)
            
            ZStack(alignment: .trailing) {
                TextField(placeholder, text: $text)
                    .padding(10)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(8)
                    .autocorrectionDisabled(true)
                    .focused($isFocused)
                    .submitLabel(.done)
                    .onSubmit {
                        isFocused = false
                        isDropdownOpen = false
                    }
                    .onChange(of: text) { oldValue, newValue in
                        isDropdownOpen = true
                        updateSuggestions(newValue)
                    }
                    .onTapGesture {
                        isDropdownOpen = true
                        updateSuggestions(text)
                    }
                
                if !text.isEmpty {
                    Button(action: {
                        text = ""
                        filteredSuggestions = []
                        isDropdownOpen = false
                        isFocused = false
                        Haptics.play(.light)
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                            .padding(.trailing, 10)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            
            if isDropdownOpen && !filteredSuggestions.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(filteredSuggestions.prefix(5), id: \.self) { suggestion in
                        Button(action: {
                            text = suggestion
                            isDropdownOpen = false
                            isFocused = false
                            Haptics.play(.medium)
                        }) {
                            HStack {
                                Image(systemName: "building.2.crop.circle.fill")
                                    .foregroundColor(.orange)
                                    .font(.subheadline)
                                Text(suggestion)
                                    .font(.subheadline)
                                    .foregroundColor(.primary)
                                Spacer()
                            }
                            .padding(.vertical, 10)
                            .padding(.horizontal, 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        if suggestion != filteredSuggestions.prefix(5).last {
                            Divider()
                        }
                    }
                }
                .background(Color(.secondarySystemBackground))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                )
                .transition(.opacity)
            }
        }
        .padding(.vertical, 4)
    }
    
    private func updateSuggestions(_ query: String) {
        if query.isEmpty {
            filteredSuggestions = []
        } else {
            filteredSuggestions = suggestions.filter { s in
                s.lowercased().folding(options: .diacriticInsensitive, locale: .current)
                    .contains(query.lowercased().folding(options: .diacriticInsensitive, locale: .current))
            }
        }
    }
}

struct FormattedNewsContentView: View {
    let content: String
    
    private var isStructured: Bool {
        content.contains(" — ") || content.contains("Date:") || content.contains("Data:")
    }
    
    private var keyValues: [(key: String, value: String)] {
        let parts = content.components(separatedBy: " — ")
        var result: [(key: String, value: String)] = []
        for part in parts {
            let kv = part.components(separatedBy: ": ")
            if kv.count >= 2 {
                let key = kv[0].trimmingCharacters(in: .whitespaces)
                let val = kv[1...].joined(separator: ": ").trimmingCharacters(in: .whitespaces)
                result.append((key: key, value: val))
            } else if !part.trimmingCharacters(in: .whitespaces).isEmpty {
                result.append((key: "", value: part.trimmingCharacters(in: .whitespaces)))
            }
        }
        return result
    }
    
    var body: some View {
        if isStructured && !keyValues.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(keyValues.indices, id: \.self) { idx in
                    let item = keyValues[idx]
                    HStack(alignment: .top, spacing: 8) {
                        if !item.key.isEmpty {
                            Text(item.key)
                                .font(.caption.bold())
                                .foregroundColor(.secondary)
                                .frame(width: 70, alignment: .leading)
                        }
                        Text(item.value)
                            .font(.caption)
                            .foregroundColor(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(10)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(8)
        } else {
            Text(content)
                .font(.subheadline)
                .foregroundColor(.primary)
        }
    }
}

struct LavoraMiBannerView: View {
    @AppStorage("lavoramiBannerImpressionCount") private var impressionCount: Int = 0
    @AppStorage("lavoramiBannerIsCollapsed") private var isCollapsed: Bool = false
    
    var body: some View {
        let isExpanded = !isCollapsed && impressionCount < 2
        
        Button {
            if impressionCount < 2 {
                impressionCount += 1
            }
            openLavoraMi()
        } label: {
            if isExpanded {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.title2)
                        .foregroundColor(.orange)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Cantieri, Deviazioni & Linee")
                                .font(.subheadline.bold())
                                .foregroundColor(.primary)
                            Spacer()
                            Button {
                                withAnimation(.spring()) {
                                    isCollapsed = true
                                }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                                    .font(.system(size: 16))
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        
                        Text("In Orario mostra ritardi e partenze in tempo reale. Per approfondimenti su cantieri, deviazioni e fermate sospese (Metro, Bus e Treni), scopri LavoraMi.")
                            .font(.caption)
                            .foregroundColor(.primary.opacity(0.85))
                            .multilineTextAlignment(.leading)
                    }
                }
                .padding(12)
                .background(Color.orange.opacity(0.18))
                .cornerRadius(12)
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.caption.bold())
                    
                    Text("Cantieri & Deviazioni con LavoraMi")
                        .font(.caption.bold())
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Image(systemName: "arrow.up.right.app.fill")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(Color.orange.opacity(0.18))
                .cornerRadius(10)
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func openLavoraMi() {
        if let url = URL(string: "lavorami://"), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        } else if let url = URL(string: "https://apps.apple.com/app/id6760344298") {
            UIApplication.shared.open(url)
        } else if let url = URL(string: "https://lavorami.it") {
            UIApplication.shared.open(url)
        }
    }
}


