// SaudioEngine.swift
//
// Saudio's voice engine. Everything the dashboard needs to make a voice lives in
// this one file so it can be copied into the production app later:
//
//   reference audio + transcript + text + settings  ->  WAV data
//
// It drives the existing Gloam engine (EngineKit) with the Dia2 1B model and uses
// Whisper (SpeechKit) for the word timings Dia2 needs from a reference clip.
// The UI (SaudioViews.swift / ContentView.swift) only talks to `SaudioEngine`.

import AVFoundation
import AppKit
import EngineKit
import Foundation
import Observation
import SpeechKit
import StudioKit
import UniformTypeIdentifiers

// MARK: - Errors

enum SaudioError: LocalizedError {
    case noReference
    case whisperMissing
    case noSpeechInReference
    case modelMissing
    case emptyText

    var errorDescription: String? {
        switch self {
        case .noReference:
            "Choose a reference audio file first, or turn off “Include reference audio”."
        case .whisperMissing:
            "Download the Whisper model in Settings first. Saudio uses it to time the words in your reference clip."
        case .noSpeechInReference:
            "No speech was found in the reference clip. Try a clearer clip of one person talking."
        case .modelMissing:
            "The Dia2 model isn't installed yet. Open Settings and import your Dia2 model folder."
        case .emptyText:
            "Type the text you want to turn into speech."
        }
    }
}

// MARK: - Text chunking

/// Dia2 stays reliable for roughly 45 seconds of speech per pass, so long text is
/// cut into sentence-aligned pieces and the audio is joined afterwards.
enum SaudioText {
    static func chunks(from raw: String, maxWords: Int) -> [String] {
        var cleaned = raw
        for tag in ["[S1]", "[S2]"] { cleaned = cleaned.replacingOccurrences(of: tag, with: " ") }
        cleaned = cleaned.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return [] }

        var sentences: [String] = []
        cleaned.enumerateSubstrings(in: cleaned.startIndex..<cleaned.endIndex,
                                    options: .bySentences) { sub, _, _, _ in
            if let s = sub?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
                sentences.append(s)
            }
        }
        if sentences.isEmpty { sentences = [cleaned] }

        var chunks: [String] = []
        var current: [String] = []

        func flush() {
            if !current.isEmpty {
                chunks.append(current.joined(separator: " "))
                current = []
            }
        }

        for sentence in sentences {
            let words = sentence.split(whereSeparator: { $0 == " " }).map(String.init)
            if words.count > maxWords {
                flush()
                var index = 0
                while index < words.count {
                    let end = min(index + maxWords, words.count)
                    chunks.append(words[index..<end].joined(separator: " "))
                    index = end
                }
                continue
            }
            if current.count + words.count > maxWords { flush() }
            current.append(contentsOf: words)
        }
        flush()
        return chunks
    }
}

// MARK: - Player

@MainActor @Observable
final class SaudioPlayer {
    @ObservationIgnored private var player: AVAudioPlayer?
    private(set) var hasAudio = false
    private(set) var duration: Double = 0

    var volume: Float = 0.9 {
        didSet { player?.volume = volume }
    }
    var rate: Float = 1.0 {
        didSet { player?.rate = rate }
    }

    var currentTime: Double { player?.currentTime ?? 0 }
    var isPlaying: Bool { player?.isPlaying ?? false }

    func load(wav: Data) throws {
        player?.stop()
        let p = try AVAudioPlayer(data: wav)
        p.enableRate = true
        p.rate = rate
        p.volume = volume
        p.prepareToPlay()
        player = p
        duration = p.duration
        hasAudio = true
    }

    func toggle() {
        guard let p = player else { return }
        if p.isPlaying {
            p.pause()
        } else {
            if p.currentTime >= p.duration - 0.05 { p.currentTime = 0 }
            p.play()
        }
    }

    func seek(to seconds: Double) {
        player?.currentTime = max(0, min(seconds, duration))
    }

    func stop() {
        player?.stop()
    }
}

// MARK: - Library

struct SaudioVoice: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var name: String
    var transcript: String
    var fileName: String
}

@MainActor @Observable
final class SaudioLibrary {
    private(set) var voices: [SaudioVoice] = []
    private let root: URL

    init() {
        let folder = StoragePaths.appSupport
            .appendingPathComponent("Saudio", isDirectory: true)
            .appendingPathComponent("Library", isDirectory: true)
        root = folder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let index = folder.appendingPathComponent("voices.json")
        if let data = try? Data(contentsOf: index),
           let decoded = try? JSONDecoder().decode([SaudioVoice].self, from: data) {
            voices = decoded
        }
    }

    func fileURL(for voice: SaudioVoice) -> URL {
        root.appendingPathComponent(voice.fileName)
    }

    func add(name: String, transcript: String, from source: URL) throws {
        let id = UUID().uuidString
        let ext = source.pathExtension.isEmpty ? "wav" : source.pathExtension
        let fileName = "\(id).\(ext)"
        try FileManager.default.copyItem(at: source, to: root.appendingPathComponent(fileName))
        voices.insert(SaudioVoice(id: id, name: name, transcript: transcript, fileName: fileName),
                      at: 0)
        try save()
    }

    func remove(_ voice: SaudioVoice) {
        try? FileManager.default.removeItem(at: fileURL(for: voice))
        voices.removeAll { $0.id == voice.id }
        try? save()
    }

    private func save() throws {
        let data = try JSONEncoder().encode(voices)
        try data.write(to: root.appendingPathComponent("voices.json"), options: .atomic)
    }
}

// MARK: - Engine

@MainActor @Observable
final class SaudioEngine {
    enum Phase: Equatable {
        case idle
        case transcribing
        case loadingModel
        case generating(chunk: Int, of: Int)
        case importingModel
    }

    // Inputs (bound to the dashboard)
    var referenceName = ""
    var transcript = ""
    var text = ""
    var cfgScale: Double = 6.0
    var textTemperature: Double = 0.6
    var audioTemperature: Double = 0.8
    var textTopK: Double = 50
    var audioTopK: Double = 50
    var includeReference = true
    var seedText = ""

    // State the dashboard shows
    private(set) var referenceURL: URL?
    private(set) var phase: Phase = .idle
    private(set) var errorMessage: String?
    private(set) var infoMessage: String?
    private(set) var generatedWAV: Data?
    private(set) var generatedSeconds: Double = 0
    private(set) var lastSeed: UInt64?
    private(set) var dia2Installed = false

    let player = SaudioPlayer()
    let library = SaudioLibrary()
    let whisper: WhisperModelManager
    let whisperVariant = WhisperModelCatalog.defaultVariant

    @ObservationIgnored private let engine: GloamEngine
    @ObservationIgnored private var generateTask: Task<Void, Never>?
    @ObservationIgnored private var alignedWords: [AlignedWord]?

    // Chosen by the user's model: dia2-1b-mlx-4bit  ->  folder "dia2@1b-4bit".
    static let dia2QuantRaw = "1b-4bit"

    static var dia2Directory: URL {
        StoragePaths.models.appendingPathComponent(
            BackendID.dia2.diskFolder(quantRaw: dia2QuantRaw), isDirectory: true)
    }

    private static var referenceDirectory: URL {
        StoragePaths.appSupport
            .appendingPathComponent("Saudio", isDirectory: true)
            .appendingPathComponent("Reference", isDirectory: true)
    }

    init() {
        let modelsRoot = StoragePaths.models
        try? FileManager.default.createDirectory(at: modelsRoot, withIntermediateDirectories: true)

        MLXModelProvider.configureMemory(cacheLimitBytes: 1 << 30)
        let folderName = BackendID.dia2.diskFolder(quantRaw: SaudioEngine.dia2QuantRaw)
        let resolver: @Sendable (BackendID) -> String? = { backend in
            guard backend == .dia2 else { return nil }
            let dir = modelsRoot.appendingPathComponent(folderName, isDirectory: true)
            let hasConfig = FileManager.default.fileExists(
                atPath: dir.appendingPathComponent("config.json").path)
            return hasConfig ? dir.path : nil
        }
        engine = GloamEngine(provider: MLXModelProvider(modelPathResolver: resolver))
        whisper = WhisperModelManager(root: modelsRoot.appendingPathComponent("whisper"),
                                      uiTest: false)
        refreshModelState()
    }

    // MARK: Derived state

    var isBusy: Bool { phase != .idle }

    var statusLine: String {
        if let errorMessage, phase == .idle { return errorMessage.isEmpty ? "Ready" : "Needs attention" }
        switch phase {
        case .idle: return "Ready"
        case .transcribing: return "Reading reference…"
        case .loadingModel: return "Loading Dia2…"
        case .generating(let chunk, let total):
            return total > 1 ? "Generating \(chunk) of \(total)…" : "Generating…"
        case .importingModel: return "Installing model…"
        }
    }

    var whisperFolder: URL? {
        whisper.state(for: whisperVariant) == .ready
            ? whisper.directory(for: whisperVariant) : nil
    }

    func refreshModelState() {
        let fm = FileManager.default
        let dir = SaudioEngine.dia2Directory
        dia2Installed = fm.fileExists(atPath: dir.appendingPathComponent("config.json").path)
            && fm.fileExists(atPath: dir.appendingPathComponent("model.safetensors").path)
        whisper.refresh()
    }

    // MARK: Reference audio

    func chooseReferenceAudio() {
        let panel = NSOpenPanel()
        panel.title = "Choose reference audio"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.audio]
        if panel.runModal() == .OK, let url = panel.url {
            setReference(from: url)
        }
    }

    func setReference(from source: URL) {
        errorMessage = nil
        infoMessage = nil
        do {
            let dir = SaudioEngine.referenceDirectory
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            for old in (try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil)) ?? [] {
                try? FileManager.default.removeItem(at: old)
            }
            let scoped = source.startAccessingSecurityScopedResource()
            defer { if scoped { source.stopAccessingSecurityScopedResource() } }
            let ext = source.pathExtension.isEmpty ? "wav" : source.pathExtension
            let dest = dir.appendingPathComponent("reference-\(UUID().uuidString).\(ext)")
            try FileManager.default.copyItem(at: source, to: dest)
            referenceURL = dest
            referenceName = source.lastPathComponent
            transcript = ""
            alignedWords = nil
        } catch {
            errorMessage = "Couldn't open that audio file: \(error.localizedDescription)"
        }
    }

    func useLibraryVoice(_ voice: SaudioVoice) {
        referenceURL = library.fileURL(for: voice)
        referenceName = voice.name
        transcript = voice.transcript
        alignedWords = nil
        errorMessage = nil
        infoMessage = "“\(voice.name)” loaded from your library."
    }

    func saveReferenceToLibrary() {
        guard let url = referenceURL else {
            errorMessage = SaudioError.noReference.localizedDescription
            return
        }
        let name = (referenceName as NSString).deletingPathExtension
        do {
            try library.add(name: name.isEmpty ? "Voice" : name, transcript: transcript, from: url)
            infoMessage = "Saved “\(name)” to your library."
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't save to the library: \(error.localizedDescription)"
        }
    }

    // MARK: Auto transcribe

    func autoTranscribe() {
        guard !isBusy else { return }
        errorMessage = nil
        infoMessage = nil
        guard let url = referenceURL else {
            errorMessage = SaudioError.noReference.localizedDescription
            return
        }
        guard let folder = whisperFolder else {
            errorMessage = SaudioError.whisperMissing.localizedDescription
            return
        }
        phase = .transcribing
        Task { [weak self] in
            do {
                let words = try await Dia2Aligner.make(modelFolder: folder)
                    .align(audioURL: url, transcript: nil)
                guard let self else { return }
                if self.referenceURL == url {
                    self.alignedWords = words
                    self.transcript = words
                        .map { $0.w.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                        .joined(separator: " ")
                    if words.isEmpty { self.errorMessage = SaudioError.noSpeechInReference.localizedDescription }
                }
                self.phase = .idle
            } catch {
                self?.errorMessage = error.localizedDescription
                self?.phase = .idle
            }
        }
    }

    // MARK: Generate

    private var parsedSeed: UInt64? {
        UInt64(seedText.trimmingCharacters(in: .whitespaces))
    }

    func generate() {
        guard !isBusy else { return }
        errorMessage = nil
        infoMessage = nil
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = SaudioError.emptyText.localizedDescription
            return
        }
        guard dia2Installed else {
            errorMessage = SaudioError.modelMissing.localizedDescription
            return
        }
        if includeReference && referenceURL == nil {
            errorMessage = SaudioError.noReference.localizedDescription
            return
        }
        generateTask = Task { [weak self] in
            await self?.runGeneration()
            self?.generateTask = nil
        }
    }

    func cancelGeneration() {
        generateTask?.cancel()
        infoMessage = "Stopping after the current part…"
    }

    private func runGeneration() async {
        defer { phase = .idle }
        do {
            var prefix: DialoguePrefix?
            if includeReference, referenceURL != nil {
                phase = .transcribing
                prefix = try await buildPrefix()
            }
            try Task.checkCancellation()

            phase = .loadingModel
            await engine.acknowledgeLicense(for: .dia2)
            try await engine.preload(backend: .dia2)

            let pieces = SaudioText.chunks(from: text, maxWords: 90)
            let baseSeed = parsedSeed ?? UInt64.random(in: 1...UInt64(UInt32.max))
            lastSeed = baseSeed
            let rate = BackendID.dia2.spec.defaultSampleRate
            let gap = [Float](repeating: 0, count: Int(Double(rate) * 0.12))

            var all: [Float] = []
            for (index, piece) in pieces.enumerated() {
                try Task.checkCancellation()
                phase = .generating(chunk: index + 1, of: pieces.count)
                let request = ProviderDialogueRequest(
                    script: ["[S1] \(piece)"],
                    prefixes: [prefix],
                    cfgScale: Float(cfgScale),
                    textTemperature: Float(textTemperature),
                    textTopK: Int(textTopK),
                    audioTemperature: Float(audioTemperature),
                    audioTopK: Int(audioTopK),
                    seed: DialogueSeed.pass(take: baseSeed, index: index))
                let chunk = try await engine.synthesizeDialogue(backend: .dia2, request: request)
                if index > 0 { all.append(contentsOf: gap) }
                all.append(contentsOf: chunk.samples)
            }

            guard !all.isEmpty else { return }
            let normalized = AudioAssembler.normalizePeak(floats: all)
            let wav = WAVEncoder.encode(pcm16: PCM16.data(from: normalized), sampleRate: rate)
            try player.load(wav: wav)
            generatedWAV = wav
            generatedSeconds = Double(normalized.count) / Double(rate)
            infoMessage = String(format: "Done. %.1f seconds of audio.", generatedSeconds)
            player.toggle()
        } catch is CancellationError {
            infoMessage = "Stopped."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// The reference clip as Dia2 wants it: audio at 24 kHz plus a timestamp for
    /// every word. Whisper supplies the timestamps. If the edited transcript has
    /// the same number of words as Whisper heard, the edited spelling is used.
    private func buildPrefix() async throws -> DialoguePrefix {
        guard let refURL = referenceURL else { throw SaudioError.noReference }
        let rate = BackendID.dia2.spec.defaultSampleRate

        var words: [AlignedWord]
        if let cached = alignedWords, !cached.isEmpty {
            words = cached
        } else {
            guard let folder = whisperFolder else { throw SaudioError.whisperMissing }
            words = try await Dia2Aligner.make(modelFolder: folder)
                .align(audioURL: refURL, transcript: nil)
            alignedWords = words
        }
        guard !words.isEmpty else { throw SaudioError.noSpeechInReference }

        let edited = transcript.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        if !edited.isEmpty, edited.count == words.count {
            words = zip(words, edited).map { pair in
                AlignedWord(w: pair.1, start: pair.0.start, end: pair.0.end)
            }
        }

        let data = try Data(contentsOf: refURL)
        let sampleRate = Double(rate)
        let samples = try await Task.detached(priority: .userInitiated) {
            try RefAudioCombiner.decodeMono(data, sampleRate: sampleRate)
        }.value
        let timings = words.map { AlignedWordTiming(text: $0.w, start: $0.start, end: $0.end) }
        return ChatPrefixBudget.trim(timings, samples: samples, sampleRate: rate, maxSeconds: 25)
    }

    // MARK: Save WAV

    func saveWAV() {
        guard let data = generatedWAV else { return }
        let panel = NSSavePanel()
        panel.title = "Save WAV"
        panel.allowedContentTypes = [.wav]
        panel.nameFieldStringValue = "Saudio voice.wav"
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try data.write(to: url, options: .atomic)
                infoMessage = "Saved \(url.lastPathComponent)."
            } catch {
                errorMessage = "Couldn't save the file: \(error.localizedDescription)"
            }
        }
    }

    // MARK: Model setup

    /// Copies the user's existing Dia2 model folder into the app's own storage.
    /// The app is sandboxed, so it can't read the model where it sits in Documents.
    func chooseDia2ModelFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose your Dia2 model folder (dia2-1b-mlx-4bit)"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            importDia2Model(from: url)
        }
    }

    private func importDia2Model(from source: URL) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: source.appendingPathComponent("config.json").path),
              fm.fileExists(atPath: source.appendingPathComponent("model.safetensors").path)
        else {
            errorMessage = "That folder doesn't look like a Dia2 model. It needs config.json and model.safetensors inside."
            return
        }
        errorMessage = nil
        phase = .importingModel
        let destination = SaudioEngine.dia2Directory
        let staging = destination.deletingLastPathComponent()
            .appendingPathComponent(destination.lastPathComponent + ".partial")

        Task { [weak self] in
            let result = await Task.detached(priority: .utility) { () -> Result<Void, Error> in
                do {
                    let fm = FileManager.default
                    try fm.createDirectory(at: destination.deletingLastPathComponent(),
                                           withIntermediateDirectories: true)
                    try? fm.removeItem(at: staging)
                    try? fm.removeItem(at: destination)
                    try fm.copyItem(at: source, to: staging)
                    try fm.moveItem(at: staging, to: destination)
                    return .success(())
                } catch {
                    return .failure(error)
                }
            }.value
            guard let self else { return }
            switch result {
            case .success:
                self.infoMessage = "Dia2 model installed."
            case .failure(let error):
                self.errorMessage = "Couldn't install the model: \(error.localizedDescription)"
            }
            self.phase = .idle
            self.refreshModelState()
        }
    }
}
