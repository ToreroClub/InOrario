import Foundation
import SwiftUI
import Combine
import Speech
import AVFoundation

@MainActor
final class VoiceSearchController: ObservableObject {
    @Published var isListening: Bool = false
    @Published var transcript: String = ""
    @Published var audioLevel: CGFloat = 0.0
    @Published var errorMessage: String? = nil
    @Published var permissionDenied: Bool = false

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "it-IT"))
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var completionHandler: ((String) -> Void)?
    private var hasDeliveredResult = false
    private var userRequestedStop = false
    private var committedTranscript = ""
    private var activeContextualStrings: [String] = []
    private var autoRestartCount = 0
    private var sessionGeneration: UInt64 = 0
    private var isAudioSessionActive = false

    private nonisolated static let audioSessionQueue = DispatchQueue(
        label: "com.toreroclub.inorario.voice.audioSession",
        qos: .userInitiated
    )

    func startListening(contextualStrings: [String], onFinalResult: @escaping (String) -> Void) {
        stopListening(triggerFinal: false)
        sessionGeneration &+= 1
        let generation = sessionGeneration
        errorMessage = nil
        permissionDenied = false
        transcript = ""
        audioLevel = 0.0
        hasDeliveredResult = false
        userRequestedStop = false
        committedTranscript = ""
        activeContextualStrings = contextualStrings
        autoRestartCount = 0
        completionHandler = onFinalResult

        Task {
            let speechAuthorized = await Self.requestSpeechAuthStatus()
            let micAuthorized = await AVAudioApplication.requestRecordPermission()

            guard generation == self.sessionGeneration, !self.userRequestedStop else { return }

            guard speechAuthorized && micAuthorized else {
                self.permissionDenied = true
                self.errorMessage = "Per usare la ricerca vocale abilita Microfono e Riconoscimento Vocale nelle Impostazioni di iPhone."
                return
            }

            await beginAudioRecognition(contextualStrings: contextualStrings, generation: generation)
        }
    }

    func stopListening(triggerFinal: Bool = false) {
        sessionGeneration &+= 1
        userRequestedStop = true

        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil

        if isAudioSessionActive {
            isAudioSessionActive = false
            Self.deactivateAudioSessionAsync()
        }

        let capturedText = VoiceTranscriptCleaner.normalize(transcript)
        isListening = false
        audioLevel = 0.0

        if triggerFinal && !hasDeliveredResult && !capturedText.isEmpty {
            hasDeliveredResult = true
            let handler = completionHandler
            completionHandler = nil
            handler?(capturedText)
        } else if !triggerFinal {
            completionHandler = nil
        }
    }

    private func beginAudioRecognition(contextualStrings: [String], generation: UInt64) async {
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            errorMessage = "Il riconoscimento vocale non è al momento disponibile sul dispositivo."
            return
        }

        do {
            try await Self.activateAudioSession()
        } catch {
            guard generation == sessionGeneration, !userRequestedStop else { return }
            errorMessage = "Impossibile avviare il microfono: \(error.localizedDescription)"
            return
        }

        guard generation == sessionGeneration, !userRequestedStop else {
            if userRequestedStop {
                Self.deactivateAudioSessionAsync()
            }
            return
        }

        isAudioSessionActive = true

        let request = makeRecognitionRequest(contextualStrings: contextualStrings)
        self.recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        Self.attachAudioTap(on: inputNode, format: recordingFormat, request: request) { [weak self] level in
            Task { @MainActor [weak self] in
                guard let self, self.isListening, !self.userRequestedStop else { return }
                self.audioLevel = (self.audioLevel * 0.45) + (level * 0.55)
            }
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
            isListening = true
        } catch {
            stopListening(triggerFinal: false)
            errorMessage = "Errore avvio audio: \(error.localizedDescription)"
            return
        }

        startCurrentRecognitionTask(speechRecognizer: speechRecognizer, request: request)
    }

    private func makeRecognitionRequest(contextualStrings: [String]) -> SFSpeechAudioBufferRecognitionRequest {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // .dictation evita che iOS tagli prematuramente la frase durante brevi pause dell'utente
        request.taskHint = .dictation

        let uniqueContext = Array(Set(contextualStrings.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }))
        if !uniqueContext.isEmpty {
            request.contextualStrings = Array(uniqueContext.prefix(100))
        }
        return request
    }

    private func startCurrentRecognitionTask(
        speechRecognizer: SFSpeechRecognizer,
        request: SFSpeechAudioBufferRecognitionRequest
    ) {
        recognitionTask = Self.startRecognitionTask(recognizer: speechRecognizer, request: request) { [weak self] text, isFinal, errDesc in
            Task { @MainActor [weak self] in
                guard let self, self.isListening, !self.userRequestedStop else { return }

                if let text, !text.isEmpty {
                    let combined = self.committedTranscript.isEmpty ? text : "\(self.committedTranscript) \(text)"
                    self.transcript = VoiceTranscriptCleaner.normalize(combined)
                }

                if isFinal || errDesc != nil {
                    self.restartRecognitionSegment()
                }
            }
        }
    }

    private func restartRecognitionSegment() {
        guard isListening && !userRequestedStop else { return }

        committedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil

        guard autoRestartCount < 5,
              let speechRecognizer, speechRecognizer.isAvailable else {
            // Manteniamo eventuale testo già trascritto nella barra senza avviare la ricerca al posto dell'utente
            if audioEngine.isRunning {
                audioEngine.stop()
                audioEngine.inputNode.removeTap(onBus: 0)
            }
            if isAudioSessionActive {
                isAudioSessionActive = false
                Self.deactivateAudioSessionAsync()
            }
            isListening = false
            audioLevel = 0.0
            return
        }

        autoRestartCount += 1
        let newRequest = makeRecognitionRequest(contextualStrings: activeContextualStrings)
        self.recognitionRequest = newRequest

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        Self.attachAudioTap(on: inputNode, format: format, request: newRequest) { [weak self] level in
            Task { @MainActor [weak self] in
                guard let self, self.isListening, !self.userRequestedStop else { return }
                self.audioLevel = (self.audioLevel * 0.45) + (level * 0.55)
            }
        }

        startCurrentRecognitionTask(speechRecognizer: speechRecognizer, request: newRequest)
    }

    private nonisolated static func activateAudioSession() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            audioSessionQueue.async {
                do {
                    let audioSession = AVAudioSession.sharedInstance()
                    try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
                    try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private nonisolated static func deactivateAudioSessionAsync() {
        audioSessionQueue.async {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    private nonisolated static func requestSpeechAuthStatus() async -> Bool {
        await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status == .authorized)
            }
        }
    }

    private nonisolated static func attachAudioTap(
        on inputNode: AVAudioInputNode,
        format: AVAudioFormat,
        request: SFSpeechAudioBufferRecognitionRequest,
        onLevel: @escaping @Sendable (CGFloat) -> Void
    ) {
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
            onLevel(computeNormalizedRMS(buffer: buffer))
        }
    }

    private nonisolated static func startRecognitionTask(
        recognizer: SFSpeechRecognizer,
        request: SFSpeechAudioBufferRecognitionRequest,
        onEvent: @escaping @Sendable (String?, Bool, String?) -> Void
    ) -> SFSpeechRecognitionTask {
        recognizer.recognitionTask(with: request) { result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let errDesc = error?.localizedDescription
            onEvent(text, isFinal, errDesc)
        }
    }

    private nonisolated static func computeNormalizedRMS(buffer: AVAudioPCMBuffer) -> CGFloat {
        guard let channelData = buffer.floatChannelData?[0] else { return 0.0 }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return 0.0 }
        var sum: Float = 0.0
        for i in 0..<frameLength {
            let sample = channelData[i]
            sum += sample * sample
        }
        let rms = sqrt(sum / Float(frameLength))
        let clamped = min(max((rms * 14.0), 0.0), 1.0)
        return CGFloat(clamped)
    }
}

enum VoiceTranscriptCleaner {
    static func normalize(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "" }

        // Normalizza spazi e forme spezzate dal dettato iOS
        text = text.replacingOccurrences(of: #"\bporta\s+mi\b"#, with: "portami", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: #"\bdopo\s+domani\b"#, with: "dopodomani", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: #"\bca\s+dorna\b"#, with: "Cadorna", options: [.regularExpression, .caseInsensitive])

        // Converte orari parlati "alle 18 e 19" / "delle 11 e 34" -> "alle 18:19" / "delle 11:34"
        if let hmRegex = try? NSRegularExpression(
            pattern: #"\b(alle|delle|verso\s+le|dopo\s+le|prima\s+delle|intorno\s+alle)\s+(\d{1,2})\s+e\s+(\d{2})\b"#,
            options: .caseInsensitive
        ) {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            let matches = hmRegex.matches(in: text, range: range).reversed()
            for m in matches {
                if let rPrep = Range(m.range(at: 1), in: text),
                   let rH = Range(m.range(at: 2), in: text),
                   let rM = Range(m.range(at: 3), in: text),
                   let fullR = Range(m.range, in: text),
                   let hh = Int(text[rH]), let mm = Int(text[rM]),
                   (0...23).contains(hh), (0...59).contains(mm) {
                    let replacement = "\(text[rPrep]) \(hh):\(String(format: "%02d", mm))"
                    text.replaceSubrange(fullR, with: replacement)
                }
            }
        }

        text = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
