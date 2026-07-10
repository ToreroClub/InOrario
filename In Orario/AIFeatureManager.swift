import Foundation
import SwiftUI
import Combine
import BackgroundTasks

// MARK: - Model Definitions

struct AIModelOption: Identifiable, Codable, Equatable {
    let id: String
    let displayName: String
    let tagline: String
    let fileName: String
    let downloadURL: String
    let sizeBytes: Int64
    let qualityStars: Int
    let ramRequiredMB: Int
    let minFreeSpaceGB: Double  // spazio minimo consigliato per installarlo
    
    var formattedSize: String {
        let mb = Double(sizeBytes) / 1_000_000
        if mb >= 1000 { return String(format: "%.1f GB", mb / 1000) }
        return String(format: "%.0f MB", mb)
    }
}

enum SpaceAlertLevel {
    case none
    case warning(message: String, actionLabel: String)
    case critical(message: String, freedMB: Int)
    case upgradeAvailable(toModel: AIModelOption)
}

// MARK: - AIFeatureManager

@MainActor
class AIFeatureManager: NSObject, ObservableObject, URLSessionDownloadDelegate {
    static let shared = AIFeatureManager()
    
    // MARK: - Persisted State
    @AppStorage("selectedModelID") var selectedModelID: String = "qwen3-0.6b-q3"
    @AppStorage("isLocalModelInstalled") var isLocalModelInstalled: Bool = false
    @AppStorage("lastLocalAIExecutionDate") private var lastExecutionDateStr: String = ""
    @AppStorage("premium_preferLocalAI") var preferLocalAI: Bool = false
    @AppStorage("aiModeChoice") var aiModeChoice: AIMode = .none  // none / local / cloud
    @AppStorage("spaceAlertDismissedAt") private var spaceAlertDismissedAtStr: String = ""
    @AppStorage("pendingDownloadModelID") var pendingModelID: String = ""
    
    // MARK: - Published State
    @Published var isDownloadingModel: Bool = false
    @Published var downloadProgress: Double = 0.0
    @Published var spaceAlertLevel: SpaceAlertLevel = .none
    @Published var freeDiskSpaceGB: Double = 0
    
    private var downloadTask: URLSessionDownloadTask?
    
    private lazy var backgroundSession: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: "com.inorario.ai.download")
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()
    
    // MARK: - Catalog
    static let catalog: [AIModelOption] = [
        AIModelOption(
            id: "qwen2.5-0.5b-q4",
            displayName: "Compatto",
            tagline: "Ottimo rapporto qualità/spazio",
            fileName: "qwen2.5-0.5b-instruct-q4km.gguf",
            downloadURL: "https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q4_k_m.gguf",
            sizeBytes: 400_000_000,
            qualityStars: 3,
            ramRequiredMB: 600,
            minFreeSpaceGB: 1.5
        )
    ]
    
    enum AIMode: String, Codable {
        case none   // nessuna IA
        case local  // modello locale
        case cloud  // cloud (premium)
    }
    
    // MARK: - Init
    private override init() {
        super.init()
        
        // Impostiamo il default corretto in base all'hardware e supportiamo la migrazione a Apple Intelligence
        if isAppleIntelligenceAvailable {
            if selectedModelID == "qwen3-0.6b-q3" || selectedModelID.isEmpty || selectedModelID.starts(with: "qwen") {
                selectedModelID = "apple_intelligence"
                aiModeChoice = .local
            }
        } else {
            if selectedModelID == "qwen3-0.6b-q3" || selectedModelID == "apple_intelligence" {
                selectedModelID = "qwen2.5-0.5b-q4"
            }
        }
        
        // Safety check: remove corrupted/tiny models (e.g. 404 HTML pages) to prevent startup crashes
        if let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let modelPath = docs.appendingPathComponent(selectedModel.fileName).path
            if FileManager.default.fileExists(atPath: modelPath) {
                if let attrs = try? FileManager.default.attributesOfItem(atPath: modelPath),
                   let size = attrs[.size] as? Int64, size < 10_000_000 { // Less than 10MB is definitely not a GGUF
                    try? FileManager.default.removeItem(atPath: modelPath)
                    self.isLocalModelInstalled = false
                    if self.aiModeChoice == .local { self.aiModeChoice = .none }
                    print("[-] Rimossa versione corrotta del modello (dimensione troppo piccola).")
                }
            }
        }
        
        refreshFreeSpace()
        Task {
            let tasks = await backgroundSession.tasks.2 // array of URLSessionDownloadTask
            if let task = tasks.first {
                await MainActor.run {
                    self.downloadTask = task
                    self.isDownloadingModel = true
                }
            } else if !self.pendingModelID.isEmpty {
                await MainActor.run {
                    self.pendingModelID = ""
                    self.isDownloadingModel = false
                }
            }
        }
    }
    
    // MARK: - Hardware Check
    var isHardwareCompatible: Bool {
        let bytesInGB: UInt64 = 1024 * 1024 * 1024
        let requiredMemory = 2.7 * Double(bytesInGB) // Supporta iPhone SE 2 (3GB RAM) e iPhone 11 (4GB RAM)
        let physicalMemory = Double(ProcessInfo.processInfo.physicalMemory)
        #if targetEnvironment(simulator)
        return true
        #else
        return physicalMemory >= requiredMemory
        #endif
    }
    
    // MARK: - Disk Space
    func refreshFreeSpace() {
        if let attrs = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()),
           let free = attrs[.systemFreeSize] as? Int64 {
            freeDiskSpaceGB = Double(free) / 1_000_000_000
        }
        evaluateSpaceAlert()
    }
    
    var recommendedModel: AIModelOption {
        return Self.catalog[0] // Solo Compatto (Qwen 0.5B) rimasto
    }
    
    var isAppleIntelligenceAvailable: Bool {
        if #available(iOS 26.0, *) {
            // Se AppleFoundationModelProvider è disponibile, ritorna vero
            return AppleFoundationModelProvider().isAvailable
        }
        return false
    }
    
    var isAppleIntelligenceSelected: Bool {
        isAppleIntelligenceAvailable && selectedModelID == "apple_intelligence"
    }
    
    var selectedModel: AIModelOption {
        Self.catalog.first { $0.id == selectedModelID } ?? Self.catalog[0]
    }
    
    var installedModelURL: URL? {
        guard isLocalModelInstalled else { return nil }
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        let url = docs.appendingPathComponent(selectedModel.fileName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
    
    var modelFilePath: String? {
        installedModelURL?.path
    }
    
    // MARK: - Space Alert
    func dismissSpaceAlert() {
        spaceAlertLevel = .none
    }
    
    func evaluateSpaceAlert() {
        spaceAlertLevel = .none
    }
    
    // MARK: - Daily Check
    func performDailySpaceCheck() {
        // Disattivato
    }
    
    // MARK: - Usage Gating
    func canRunFreeLocalAI() -> Bool {
        guard aiModeChoice == .local else { return false }
        let hasModel = isAppleIntelligenceSelected || (isHardwareCompatible && isLocalModelInstalled)
        return hasModel
    }
    
    func recordLocalAIExecution() {
        // Rimosso limite di esecuzione giornaliero per l'IA locale (on-device).
    }
    
    // MARK: - Download
    func downloadModel(_ model: AIModelOption) {
        guard isHardwareCompatible, !isDownloadingModel else { return }
        guard let url = URL(string: model.downloadURL) else { return }
        
        pendingModelID = model.id
        isDownloadingModel = true
        downloadProgress = 0.0
        
        downloadTask = backgroundSession.downloadTask(with: url)
        downloadTask?.resume()
    }
    
    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        pendingModelID = ""
        isDownloadingModel = false
        downloadProgress = 0.0
    }
    
    // MARK: - Remove
    func removeCurrentModel() {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        // Rimuovi tutti i file .gguf presenti
        for model in Self.catalog {
            let url = docs.appendingPathComponent(model.fileName)
            try? FileManager.default.removeItem(at: url)
        }
        isLocalModelInstalled = false
        if aiModeChoice == .local { aiModeChoice = .none }
        refreshFreeSpace()
    }
    
    func removeModel(withFileName fileName: String) {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let url = docs.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: url)
    }
    
    // MARK: - Switch Model
    func switchTo(_ model: AIModelOption) {
        if isDownloadingModel {
            cancelDownload()
        }
        
        let bothFit = freeDiskSpaceGB > Double(selectedModel.sizeBytes + model.sizeBytes) / 1_000_000_000 + 0.5
        if !bothFit {
            removeCurrentModel()
        }
        
        self.selectedModelID = model.id
        self.aiModeChoice = .local
        
        // Avvia il download con un piccolissimo ritardo per consentire la cancellazione del task precedente
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.downloadModel(model)
        }
    }
    

    
    // MARK: - URLSessionDownloadDelegate
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        Task { @MainActor in self.downloadProgress = progress }
    }
    
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        if let httpResponse = downloadTask.response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            print("[-] Errore download: Status code \(httpResponse.statusCode)")
            Task { @MainActor in self.isDownloadingModel = false }
            return
        }
        
        let fileManager = FileManager.default
        let tempURL = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        
        do {
            try fileManager.moveItem(at: location, to: tempURL)
        } catch {
            print("[-] Error saving temporary file: \(error)")
            Task { @MainActor in self.isDownloadingModel = false }
            return
        }
        
        Task { @MainActor in
            guard let docsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
                self.isDownloadingModel = false
                try? fileManager.removeItem(at: tempURL)
                return
            }
            
            let modelID = self.pendingModelID
            guard !modelID.isEmpty,
                  let model = AIFeatureManager.catalog.first(where: { $0.id == modelID }) else {
                self.isDownloadingModel = false
                try? fileManager.removeItem(at: tempURL)
                return
            }
            
            let destinationURL = docsURL.appendingPathComponent(model.fileName)
            try? fileManager.removeItem(at: destinationURL)
            do {
                try fileManager.moveItem(at: tempURL, to: destinationURL)
                var urlToExclude = destinationURL
                var resourceValues = URLResourceValues()
                resourceValues.isExcludedFromBackup = true
                try? urlToExclude.setResourceValues(resourceValues)
                
                // Rimuovi il vecchio modello (ora che il nuovo è installato)
                let previousID = self.selectedModelID
                if previousID != modelID {
                    if let old = AIFeatureManager.catalog.first(where: { $0.id == previousID }) {
                        self.removeModel(withFileName: old.fileName)
                    }
                }
                
                self.selectedModelID = modelID
                self.isLocalModelInstalled = true
                self.aiModeChoice = .local
                self.preferLocalAI = true
                self.pendingModelID = ""
                self.refreshFreeSpace()
                print("[+] Modello \(model.displayName) installato in: \(destinationURL.path)")
            } catch {
                print("[-] Errore salvataggio modello finale: \(error)")
                try? fileManager.removeItem(at: tempURL)
            }
            self.isDownloadingModel = false
        }
    }
    
    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            print("[-] Download interrotto: \(error.localizedDescription)")
            Task { @MainActor in self.isDownloadingModel = false }
        }
    }
}

// MARK: - AppStorage support for AIMode
extension AIFeatureManager.AIMode: RawRepresentable {
    // Already has RawValue via String enum
}
