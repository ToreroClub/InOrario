import Foundation
import llama

class LocalSLMService: SLMProvider {
    static let shared = LocalSLMService()
    
    private var _model: OpaquePointer?
    private var context: OpaquePointer?
    private var isBackendInitialized = false
    
    var isAvailable: Bool { _model != nil && context != nil }
    
    private init() {
        // Inizializza il backend di llama.cpp all'avvio
        llama_backend_init()
        isBackendInitialized = true
    }
    
    /// Inizializza e carica in memoria RAM il modello quantizzato GGUF
    func initializeModel() async -> Bool {
        guard _model == nil else { return true }
        
        // Usa il percorso del modello attualmente selezionato
        guard let modelPath = AIFeatureManager.shared.modelFilePath,
              FileManager.default.fileExists(atPath: modelPath) else {
            print("[-] Modello locale GGUF non trovato.")
            return false
        }
        
        // 1. Configura i parametri del modello
        var modelParams = llama_model_default_params()
        modelParams.n_gpu_layers = 0 // Disabilita accelerazione Metal che causa crash su Qwen2 su alcuni dispositivi iOS
        
        // 2. Carica il modello da file
        guard let loadedModel = llama_model_load_from_file(modelPath, modelParams) else {
            print("[-] Errore durante il caricamento del file GGUF.")
            return false
        }
        self._model = loadedModel
        
        // 3. Configura il contesto dell'inferenza
        var contextParams = llama_context_default_params()
        contextParams.n_ctx = 1024 // Limite di tokens in input/output per non saturare la RAM
        contextParams.n_batch = 512
        contextParams.n_threads = Int32(ProcessInfo.processInfo.processorCount)
        
        // 4. Inizializza il contesto
        guard let createdContext = llama_init_from_model(loadedModel, contextParams) else {
            print("[-] Errore inizializzazione contesto llama.")
            llama_model_free(loadedModel)
            self._model = nil
            return false
        }
        self.context = createdContext
        
        print("[+] Modello Qwen caricato con successo sul Neural Engine/GPU locale via llama.cpp.")
        return true
    }
    
    func generateSummary(for text: String) async -> String {
        guard let ctx = context, let mdl = _model else {
            return text
        }
        
        let prompt = """
        <|im_start|>system
        Sei un assistente che riassume notizie ferroviarie italiane in 1-2 frasi chiare e dirette. Rispondi solo con il riassunto, senza prefissi o spiegazioni.
        <|im_end|>
        <|im_start|>user
        \(text)
        <|im_end|>
        <|im_start|>assistant
        """
        
        let summary = await runInference(prompt: prompt, context: ctx, model: mdl)
        let cleaned = summary
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "<|im_end|>", with: "")
            .replacingOccurrences(of: "<|im_start|>", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            
        return cleaned.isEmpty ? text : cleaned
    }
    
    /// Formatta tutti gli item (scioperi MIT + InfoLavori Trenitalia) con il modello locale.
    /// Il modello produce solo il campo `content` come testo plain — titolo, data e categoria
    /// vengono preservati dall'item originale in Swift (nessun parsing JSON fragile).
    func formatWithLocalModel(rawItems: [NewsItem]) async -> [NewsItem] {
        guard !rawItems.isEmpty else { return [] }
        guard isAvailable else {
            print("[-] Modello non pronto, fallback sui dati grezzi.")
            return rawItems
        }
        
        var result: [NewsItem] = []
        
        for raw in rawItems {
            if raw.category == "realtime" || raw.category == "lavoro" {
                result.append(raw)
                continue
            }
            
            let cleaned = await generateSummary(for: raw.content)
            
            // Preserva titolo/data/categoria dall'originale, sostituisce solo il content
            result.append(NewsItem(
                title: raw.title,
                content: cleaned,
                isUrgent: raw.isUrgent,
                category: raw.category,
                date: raw.date
            ))
        }
        
        return result
    }
    
    /// Esegue il loop di inferenza token-by-token su llama.cpp
    private func runInference(prompt: String, context: OpaquePointer, model: OpaquePointer) async -> String {
        let maxContextTokens = 1024
        let maxGenerationTokens = 256
        let maxPromptTokens = maxContextTokens - maxGenerationTokens
        var outputString = ""
        
        // 1. Tokenizzazione
        let vocab = llama_model_get_vocab(model)
        let utf8Count = prompt.utf8.count
        let maxTokenCount = utf8Count + 4
        var tokens = [llama_token](repeating: 0, count: maxTokenCount)
        
        let tokenCount = llama_tokenize(
            vocab,
            prompt,
            Int32(utf8Count),
            &tokens,
            Int32(maxTokenCount),
            false, // add_bos
            true  // parse_special
        )
        
        guard tokenCount > 0 else { return "" }
        
        // Limita i token del prompt per non superare il contesto e lasciare spazio alla generazione
        let actualPromptTokens = min(Int(tokenCount), maxPromptTokens)
        
        // 2. Inizializza il batch di tokens da passare al decoder
        let batchSize = max(actualPromptTokens, 512)
        var batch = llama_batch_init(Int32(batchSize), 0, 1)
        defer { llama_batch_free(batch) }
        
        // Inseriamo i token del prompt nel batch iniziale
        for i in 0..<actualPromptTokens {
            let isLast = (i == actualPromptTokens - 1)
            llama_batch_add(&batch, tokens[i], Int32(i), [0], isLast)
        }
        
        var pos = Int32(actualPromptTokens)
        
        // 3. Loop di generazione (Greedy Sampling)
        for _ in 0..<maxGenerationTokens {
            // Esegui la valutazione dei token attuali nel contesto
            let decodeResult = llama_decode(context, batch)
            if decodeResult != 0 {
                print("[-] Errore durante la decodifica dei token (llama_decode fallito: \(decodeResult)).")
                break
            }
            
            // Pulisci il batch per i prossimi token
            llama_batch_clear(&batch)
            
            // Greedy sampling semplificato
            let sampler = llama_sampler_init_greedy()
            let nextTokenID = llama_sampler_sample(sampler, context, -1) // -1 prende l'ultimo token decodificato
            llama_sampler_free(sampler)
            
            // Condizione di arresto (End of Text o EOS speciale di Qwen: <|im_end|>)
            if nextTokenID == llama_vocab_eos(vocab) || nextTokenID == 151645 { // 151645 è solitamente <|im_end|> in Qwen
                break
            }
            
            // Converti il token generato in stringa UTF-8
            var tokenBytes = [CChar](repeating: 0, count: 256)
            let bytesWritten = llama_token_to_piece(vocab, nextTokenID, &tokenBytes, 256, 0, true)
            if bytesWritten > 0 {
                let piece = String(cString: tokenBytes)
                outputString += piece
            }
            
            // Aggiungi il nuovo token al batch per l'inferenza del passo successivo
            llama_batch_add(&batch, nextTokenID, pos, [0], true)
            pos += 1
            
            // Protezione aggiuntiva per non sforare mai la finestra di contesto
            if pos >= Int32(maxContextTokens) {
                break
            }
        }
        
        return outputString
    }
    
    // Helper interni per gestire il batch
    private func llama_batch_add(_ batch: inout llama_batch, _ id: llama_token, _ pos: Int32, _ seq_ids: [Int32], _ logits: Bool) {
        let index = Int(batch.n_tokens)
        batch.token[index] = id
        batch.pos[index] = pos
        batch.n_seq_id[index] = Int32(seq_ids.count)
        for i in 0..<seq_ids.count {
            batch.seq_id[index]?[i] = seq_ids[i]
        }
        batch.logits[index] = logits ? 1 : 0
        batch.n_tokens += 1
    }
    
    private func llama_batch_clear(_ batch: inout llama_batch) {
        batch.n_tokens = 0
    }
    
    // MARK: - Analisi Ritardi (rule-based, istantanea)
    
    /// Genera una breve descrizione testuale del ritardo di un treno.
    /// Non richiede il modello AI installato — è rule-based e istantanea.
    static func analyzeDelay(minutes: Int, isCancelled: Bool, trainNumber: String) -> String {
        guard UserDefaults.standard.bool(forKey: "ai_delayPredictionEnabled") else { return "" }
        
        if isCancelled {
            return "Il treno \(trainNumber) risulta soppresso. Si consiglia di verificare percorsi alternativi o treni successivi sulla stessa tratta."
        }
        
        switch minutes {
        case 0:
            return ""
        case 1...4:
            return "Ritardo lieve di \(minutes) minuti. Nella norma per le percorrenze regionali."
        case 5...9:
            return "Ritardo di \(minutes) minuti. Potrebbe impattare coincidenze ravvicinate con metro o altri treni."
        case 10...19:
            return "Ritardo di \(minutes) minuti. Verifica le coincidenze previste: potrebbe essere necessario prendere il collegamento successivo."
        case 20...29:
            return "Ritardo significativo: \(minutes) minuti. Probabile impatto su coincidenze. Considera percorsi alternativi se hai urgenza."
        case 30...59:
            return "Ritardo elevato: \(minutes) minuti. Si consiglia di verificare aggiornamenti ufficiali RFI e valutare percorsi alternativi."
        default:
            return "Ritardo critico: oltre \(minutes) minuti. Situazione anomala — verifica comunicazioni ufficiali RFI per aggiornamenti sul servizio."
        }
    }
    
    deinit {
        if let ctx = context { llama_free(ctx) }
        if let mdl = _model { llama_model_free(mdl) }
        if isBackendInitialized { llama_backend_free() }
    }
}
