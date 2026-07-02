import Foundation
import SwiftUI
import Combine

@MainActor
class AIFeatureManager: NSObject, ObservableObject, URLSessionDownloadDelegate {
    static let shared = AIFeatureManager()
    
    @AppStorage("isLocalModelInstalled") var isLocalModelInstalled: Bool = false
    @AppStorage("lastLocalAIExecutionDate") private var lastExecutionDateStr: String = ""
    @AppStorage("premium_preferLocalAI") var preferLocalAI: Bool = false
    
    @Published var isDownloadingModel: Bool = false
    @Published var downloadProgress: Double = 0.0
    
    private var downloadTask: URLSessionDownloadTask?
    
    // Rende privato l'init per garantire il pattern Singleton conforme a NSObject
    private override init() {
        super.init()
    }
    
    var isHardwareCompatible: Bool {
        let bytesInGB: UInt64 = 1024 * 1024 * 1024
        let requiredMemory = 5.5 * Double(bytesInGB)
        let physicalMemory = Double(ProcessInfo.processInfo.physicalMemory)
        
        #if targetEnvironment(simulator)
        return true
        #else
        return physicalMemory >= requiredMemory
        #endif
    }
    
    func canRunFreeLocalAI() -> Bool {
        guard isHardwareCompatible, isLocalModelInstalled else { return false }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "Europe/Rome")
        let todayStr = formatter.string(from: Date())
        
        return lastExecutionDateStr != todayStr
    }
    
    func recordLocalAIExecution() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "Europe/Rome")
        lastExecutionDateStr = formatter.string(from: Date())
    }
    
    func downloadLocalModel() {
        guard isHardwareCompatible, !isDownloadingModel else { return }
        
        // Link diretto LFS ufficiale da Hugging Face per Qwen 2.5 0.5B Instruct Q4_K_M (circa 350MB)
        guard let url = URL(string: "https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q4_k_m.gguf") else {
            return
        }
        
        isDownloadingModel = true
        downloadProgress = 0.0
        
        let configuration = URLSessionConfiguration.default
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        
        downloadTask = session.downloadTask(with: url)
        downloadTask?.resume()
    }
    
    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        isDownloadingModel = false
        downloadProgress = 0.0
    }
    
    func removeLocalModel() {
        let fileManager = FileManager.default
        if let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
            let modelURL = documentsURL.appendingPathComponent("qwen-0.5b-instruct.gguf")
            try? fileManager.removeItem(at: modelURL)
        }
        isLocalModelInstalled = false
        preferLocalAI = false
    }
    
    // MARK: - URLSessionDownloadDelegate
    
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        Task { @MainActor in
            self.downloadProgress = progress
        }
    }
    
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let fileManager = FileManager.default
        guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            Task { @MainActor in
                self.isDownloadingModel = false
            }
            return
        }
        
        let destinationURL = documentsURL.appendingPathComponent("qwen-0.5b-instruct.gguf")
        
        // Rimuove file preesistente
        try? fileManager.removeItem(at: destinationURL)
        
        do {
            try fileManager.moveItem(at: location, to: destinationURL)
            
            // Esclude il file del modello dal backup di iCloud
            var urlToExclude = destinationURL
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            try? urlToExclude.setResourceValues(resourceValues)
            
            Task { @MainActor in
                self.isLocalModelInstalled = true
                self.isDownloadingModel = false
            }
            print("[+] Modello Qwen scaricato, escluso da backup iCloud e salvato a: \(destinationURL.path)")
        } catch {
            print("[-] Errore nel salvataggio del modello scaricato: \(error.localizedDescription)")
            Task { @MainActor in
                self.isDownloadingModel = false
            }
        }
    }
    
    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            print("[-] Download interrotto con errore: \(error.localizedDescription)")
            Task { @MainActor in
                self.isDownloadingModel = false
            }
        }
    }
}
