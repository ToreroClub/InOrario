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
    
    private let brandRed = Color(red: 233/255.0, green: 33/255.0, blue: 33/255.0)
    private let brandRedGradientEnd = Color(red: 237/255.0, green: 39/255.0, blue: 42/255.0)
    
    var body: some View {
        let isExpanded = !isCollapsed && impressionCount < 2
        
        Button {
            if impressionCount < 2 {
                impressionCount += 1
            }
            openLavoraMi()
        } label: {
            if isExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .center, spacing: 12) {
                        // App Icon
                        if let uiImage = UIImage(named: "LavoraMiIcon") {
                            Image(uiImage: uiImage)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 44, height: 44)
                                .cornerRadius(10)
                                .shadow(color: Color.black.opacity(0.1), radius: 2)
                        } else {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(LinearGradient(colors: [brandRed, brandRedGradientEnd], startPoint: .top, endPoint: .bottom))
                                    .frame(width: 44, height: 44)
                                
                                Image(systemName: "square.stack.3d.down.right.fill")
                                    .font(.title3)
                                    .foregroundColor(.white)
                            }
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text("LavoraMi")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                
                                Text("Consigliata")
                                    .font(.system(size: 9, weight: .bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(brandRed.opacity(0.15))
                                    .foregroundColor(brandRed)
                                    .cornerRadius(6)
                            }
                            
                            Text("Scioperi, cantieri e deviazioni a Milano")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Button {
                            withAnimation(.spring()) {
                                isCollapsed = true
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary.opacity(0.6))
                                .font(.system(size: 18))
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    
                    Text("In Orario monitora ritardi e tabelloni dei treni. Per approfondire scioperi del trasporto pubblico, cantieri stradali e deviazioni a Milano, scopri l'app LavoraMi.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineSpacing(2)
                        .multilineTextAlignment(.leading)
                }
                .padding(14)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(16)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(brandRed.opacity(0.25), lineWidth: 1)
                )
            } else {
                HStack(spacing: 10) {
                    if let uiImage = UIImage(named: "LavoraMiIcon") {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 24, height: 24)
                            .cornerRadius(6)
                    } else {
                        ZStack {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(brandRed)
                                .frame(width: 24, height: 24)
                            Image(systemName: "square.stack.3d.down.right.fill")
                                .font(.caption2)
                                .foregroundColor(.white)
                        }
                    }
                    
                    Text("Scioperi e deviazioni Milano su LavoraMi")
                        .font(.caption.bold())
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.caption2.bold())
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(brandRed.opacity(0.2), lineWidth: 1)
                )
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func openLavoraMi() {
        if let url = URL(string: "lavorami://train"), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        } else if let url = URL(string: "lavorami://"), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        } else if let url = URL(string: "lavorami://train") {
            UIApplication.shared.open(url) { success in
                if !success {
                    if let storeUrl = URL(string: "https://apps.apple.com/app/id6760344298") {
                        UIApplication.shared.open(storeUrl)
                    }
                }
            }
        } else if let url = URL(string: "https://apps.apple.com/app/id6760344298") {
            UIApplication.shared.open(url)
        } else if let url = URL(string: "https://lavorami.it") {
            UIApplication.shared.open(url)
        }
    }
}


