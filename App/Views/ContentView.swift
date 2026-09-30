// ContentView.swift
//
// The Saudio dashboard. Layout follows the mockup: sidebar on the left, reference /
// transcript / text / generate / player in the middle, voice controls on the right.
// All logic lives in SaudioEngine.swift; this file is only the screen.

import AppKit
import SwiftUI

// MARK: - Theme

enum SaudioTheme {
    static var accent: Color { Color(red: 0.40, green: 0.36, blue: 0.96) }
    static var accent2: Color { Color(red: 0.33, green: 0.55, blue: 0.99) }
    static var ink: Color { Color(red: 0.11, green: 0.12, blue: 0.32) }
    static var muted: Color { Color(red: 0.43, green: 0.46, blue: 0.64) }
    static var line: Color { Color(red: 0.84, green: 0.86, blue: 0.96) }
    static var good: Color { Color(red: 0.16, green: 0.72, blue: 0.45) }
    static var bad: Color { Color(red: 0.85, green: 0.25, blue: 0.30) }

    static var gradient: LinearGradient {
        LinearGradient(colors: [accent, accent2], startPoint: .leading, endPoint: .trailing)
    }
    static var background: LinearGradient {
        LinearGradient(colors: [Color(red: 0.96, green: 0.97, blue: 1.0),
                                Color(red: 0.92, green: 0.93, blue: 1.0)],
                       startPoint: .top, endPoint: .bottom)
    }
}

struct SaudioCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 18).fill(Color.white.opacity(0.78)))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.95), lineWidth: 1))
            .shadow(color: Color(red: 0.3, green: 0.3, blue: 0.7).opacity(0.08), radius: 12, y: 4)
    }
}

extension View {
    func saudioCard() -> some View { modifier(SaudioCard()) }
}

struct SaudioHeading: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .bold))
            .tracking(1.6)
            .foregroundStyle(SaudioTheme.muted)
    }
}

// MARK: - Root

enum SaudioPage: Hashable {
    case voiceStudio, library, settings, about
}

struct ContentView: View {
    @State private var engine = SaudioEngine()
    @State private var page: SaudioPage = .voiceStudio

    var body: some View {
        HStack(spacing: 0) {
            SaudioSidebar(page: $page)
            Divider()
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    SaudioStatusPill(engine: engine)
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)

                switch page {
                case .voiceStudio:
                    SaudioVoiceStudioView(engine: engine, openSettings: { page = .settings })
                case .library:
                    SaudioLibraryView(engine: engine, openStudio: { page = .voiceStudio })
                case .settings:
                    SaudioSettingsView(engine: engine)
                case .about:
                    SaudioAboutView()
                }
            }
        }
        .frame(minWidth: 1120, minHeight: 780)
        .background(SaudioTheme.background)
        .preferredColorScheme(.light)
    }
}

// MARK: - Sidebar

struct SaudioSidebar: View {
    @Binding var page: SaudioPage

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12).fill(SaudioTheme.gradient)
                    Image(systemName: "waveform")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("SAUDIO")
                        .font(.system(size: 22, weight: .heavy))
                        .tracking(3)
                        .foregroundStyle(SaudioTheme.ink)
                    Text("AI VOICE STUDIO")
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(2)
                        .foregroundStyle(SaudioTheme.muted)
                }
            }
            .padding(.bottom, 24)

            item("Voice Studio", "mic", .voiceStudio)
            item("Library", "folder", .library)
            item("Settings", "gearshape", .settings)
            item("About", "info.circle", .about)

            Spacer()
            Text("Better voices.\nBigger ideas.")
                .font(.system(size: 11))
                .foregroundStyle(SaudioTheme.accent)
        }
        .padding(20)
        .frame(width: 236)
        .background(Color.white.opacity(0.35))
    }

    private func item(_ title: String, _ icon: String, _ target: SaudioPage) -> some View {
        Button {
            page = target
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon).frame(width: 22)
                Text(title).font(.system(size: 14, weight: page == target ? .semibold : .regular))
                Spacer()
            }
            .foregroundStyle(page == target ? SaudioTheme.accent : SaudioTheme.ink.opacity(0.75))
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(page == target ? SaudioTheme.accent.opacity(0.12) : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct SaudioStatusPill: View {
    let engine: SaudioEngine

    var body: some View {
        let busy = engine.isBusy
        let problem = engine.errorMessage != nil
        HStack(spacing: 8) {
            Circle()
                .fill(problem ? SaudioTheme.bad : (busy ? SaudioTheme.accent2 : SaudioTheme.good))
                .frame(width: 9, height: 9)
            Text(engine.statusLine)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(SaudioTheme.ink)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Capsule().fill(Color.white.opacity(0.85)))
        .overlay(Capsule().stroke(SaudioTheme.line, lineWidth: 1))
    }
}

// MARK: - Voice Studio

struct SaudioVoiceStudioView: View {
    @Bindable var engine: SaudioEngine
    let openSettings: () -> Void

    var body: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 20) {
                VStack(spacing: 16) {
                    if !engine.dia2Installed || engine.whisperFolder == nil {
                        setupBanner
                    }
                    referenceCard
                    transcriptCard
                    textCard
                    generateBar
                    playerCard
                }
                VStack(spacing: 16) {
                    includeCard
                    controlsCard
                    exportCard
                }
                .frame(width: 340)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
            .padding(.top, 8)
        }
    }

    // Setup banner

    private var setupBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(SaudioTheme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Finish setup to generate voices")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SaudioTheme.ink)
                Text(setupText)
                    .font(.system(size: 12))
                    .foregroundStyle(SaudioTheme.muted)
            }
            Spacer()
            Button("Open Settings", action: openSettings)
                .buttonStyle(.borderedProminent)
                .tint(SaudioTheme.accent)
        }
        .saudioCard()
    }

    private var setupText: String {
        var needs: [String] = []
        if !engine.dia2Installed { needs.append("import your Dia2 model") }
        if engine.whisperFolder == nil { needs.append("download the Whisper model") }
        return needs.joined(separator: " and ").capitalizedFirst + "."
    }

    // Reference audio

    private var referenceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SaudioHeading(title: "REFERENCE AUDIO")
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14).fill(SaudioTheme.gradient)
                    Image(systemName: "waveform")
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(.white)
                }
                .frame(width: 66, height: 66)

                VStack(alignment: .leading, spacing: 4) {
                    Text(engine.referenceName.isEmpty ? "No reference audio selected" : engine.referenceName)
                        .font(.system(size: 15))
                        .foregroundStyle(SaudioTheme.ink)
                        .lineLimit(1)
                    Text("WAV / MP3 / M4A")
                        .font(.system(size: 12))
                        .foregroundStyle(SaudioTheme.muted)
                    if engine.referenceURL != nil {
                        Button("Save to Library") { engine.saveReferenceToLibrary() }
                            .buttonStyle(.link)
                            .font(.system(size: 12))
                    }
                }
                Spacer()
                gradientButton("UPLOAD", "square.and.arrow.up") { engine.chooseReferenceAudio() }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.7)))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(SaudioTheme.line, lineWidth: 1))
        }
        .saudioCard()
    }

    // Transcript

    private var transcriptCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SaudioHeading(title: "REFERENCE TRANSCRIPT")
            SaudioTextArea(text: $engine.transcript,
                           placeholder: "Paste or edit the reference transcript here…",
                           minHeight: 84)
            HStack {
                Text("Edit the transcript if needed.")
                    .font(.system(size: 12))
                    .foregroundStyle(SaudioTheme.muted)
                Spacer()
                gradientButton("AUTO TRANSCRIBE", "sparkles") { engine.autoTranscribe() }
                    .disabled(engine.isBusy || engine.referenceURL == nil)
                    .opacity(engine.isBusy || engine.referenceURL == nil ? 0.5 : 1)
            }
        }
        .saudioCard()
    }

    // New text

    private var textCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SaudioHeading(title: "NEW VOICE TEXT")
            SaudioTextArea(text: $engine.text,
                           placeholder: "Enter the text you want to convert to speech…",
                           minHeight: 150)
                .onChange(of: engine.text) { _, newValue in
                    if newValue.count > 2000 { engine.text = String(newValue.prefix(2000)) }
                }
            HStack {
                Spacer()
                Text("\(engine.text.count) / 2000")
                    .font(.system(size: 11))
                    .foregroundStyle(SaudioTheme.muted)
            }
        }
        .saudioCard()
    }

    // Generate

    private var generateBar: some View {
        VStack(spacing: 8) {
            if engine.isBusy {
                HStack(spacing: 12) {
                    ProgressView().controlSize(.small)
                    Text(engine.statusLine)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(SaudioTheme.ink)
                    Spacer()
                    if case .generating = engine.phase {
                        Button("STOP") { engine.cancelGeneration() }
                            .buttonStyle(.bordered)
                            .tint(SaudioTheme.bad)
                    }
                }
                .padding(.horizontal, 18)
                .frame(height: 54)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.85)))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(SaudioTheme.line, lineWidth: 1))
            } else {
                Button {
                    engine.generate()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "waveform")
                            .padding(8)
                            .background(Circle().fill(Color.white.opacity(0.22)))
                        Text("GENERATE VOICE")
                            .font(.system(size: 16, weight: .bold))
                            .tracking(1.5)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(RoundedRectangle(cornerRadius: 14).fill(SaudioTheme.gradient))
                }
                .buttonStyle(.plain)
            }
            messageLine
        }
    }

    @ViewBuilder
    private var messageLine: some View {
        if let error = engine.errorMessage {
            Text(error)
                .font(.system(size: 12))
                .foregroundStyle(SaudioTheme.bad)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if let info = engine.infoMessage {
            Text(info)
                .font(.system(size: 12))
                .foregroundStyle(SaudioTheme.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // Player

    private var playerCard: some View {
        let player = engine.player
        return HStack(spacing: 16) {
            TimelineView(.periodic(from: .now, by: 0.1)) { _ in
                Button {
                    player.toggle()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 58, height: 58)
                        .background(Circle().fill(SaudioTheme.gradient))
                }
                .buttonStyle(.plain)
                .disabled(!player.hasAudio)
                .opacity(player.hasAudio ? 1 : 0.5)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("Generated Voice")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SaudioTheme.ink)
                Text(playerSubtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(SaudioTheme.muted)
            }
            .frame(width: 150, alignment: .leading)

            TimelineView(.periodic(from: .now, by: 0.1)) { _ in
                HStack(spacing: 10) {
                    Slider(
                        value: Binding(get: { player.currentTime },
                                       set: { player.seek(to: $0) }),
                        in: 0...max(player.duration, 0.01))
                        .tint(SaudioTheme.accent)
                        .disabled(!player.hasAudio)
                    Text("\(timeString(player.currentTime)) / \(timeString(player.duration))")
                        .font(.system(size: 12).monospacedDigit())
                        .foregroundStyle(SaudioTheme.muted)
                        .frame(width: 84)
                }
            }

            Image(systemName: "speaker.wave.2")
                .foregroundStyle(SaudioTheme.accent)
            Slider(value: Binding(get: { Double(player.volume) },
                                  set: { player.volume = Float($0) }),
                   in: 0...1)
                .tint(SaudioTheme.accent)
                .frame(width: 80)
        }
        .saudioCard()
    }

    private var playerSubtitle: String {
        guard engine.player.hasAudio else { return "No audio generated yet" }
        if let seed = engine.lastSeed {
            return String(format: "%.1f s · seed %llu", engine.generatedSeconds, seed)
        }
        return String(format: "%.1f s", engine.generatedSeconds)
    }

    private func timeString(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    // Right column

    private var includeCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "slider.horizontal.3")
                .foregroundStyle(SaudioTheme.accent)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 6) {
                SaudioHeading(title: "INCLUDE REFERENCE AUDIO")
                Text("Use the reference audio to guide the generation style, tone and voice.")
                    .font(.system(size: 13))
                    .foregroundStyle(SaudioTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Toggle("", isOn: $engine.includeReference)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(SaudioTheme.accent)
        }
        .saudioCard()
    }

    private var controlsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "slider.horizontal.below.rectangle")
                    .foregroundStyle(SaudioTheme.accent)
                SaudioHeading(title: "VOICE CONTROLS")
            }
            SaudioSliderRow(icon: "cube", title: "CFG SCALE",
                            value: $engine.cfgScale, range: 1...10, step: 0.1, format: "%.1f")
            SaudioSliderRow(icon: "doc.text", title: "TEXT TEMPERATURE",
                            value: $engine.textTemperature, range: 0...1, step: 0.05, format: "%.2f")
            SaudioSliderRow(icon: "waveform", title: "AUDIO TEMPERATURE",
                            value: $engine.audioTemperature, range: 0...1, step: 0.05, format: "%.2f")
            SaudioSliderRow(icon: "list.bullet", title: "TEXT TOP-K",
                            value: $engine.textTopK, range: 1...100, step: 1, format: "%.0f")
            SaudioSliderRow(icon: "music.note", title: "AUDIO TOP-K",
                            value: $engine.audioTopK, range: 1...100, step: 1, format: "%.0f")

            Divider()
            HStack(spacing: 10) {
                Image(systemName: "dice").foregroundStyle(SaudioTheme.accent).frame(width: 24)
                Text("SEED")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(SaudioTheme.ink)
                TextField("Random", text: $engine.seedText)
                    .textFieldStyle(.roundedBorder)
                Button("Reuse last") {
                    if let seed = engine.lastSeed { engine.seedText = String(seed) }
                }
                .buttonStyle(.link)
                .font(.system(size: 12))
                .disabled(engine.lastSeed == nil)
            }
        }
        .saudioCard()
    }

    private var exportCard: some View {
        HStack(spacing: 12) {
            Button {
                engine.saveWAV()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.down.to.line")
                    Text("SAVE WAV").font(.system(size: 13, weight: .bold)).tracking(1)
                }
                .foregroundStyle(SaudioTheme.accent)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(RoundedRectangle(cornerRadius: 12).fill(SaudioTheme.accent.opacity(0.10)))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(SaudioTheme.line, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(engine.generatedWAV == nil)
            .opacity(engine.generatedWAV == nil ? 0.5 : 1)

            Text("SPEED")
                .font(.system(size: 11, weight: .semibold))
                .tracking(1)
                .foregroundStyle(SaudioTheme.muted)

            Menu {
                ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { value in
                    Button(speedLabel(value)) { engine.player.rate = Float(value) }
                }
            } label: {
                HStack {
                    Text(speedLabel(Double(engine.player.rate)))
                        .foregroundStyle(SaudioTheme.ink)
                    Spacer()
                    Image(systemName: "chevron.down").font(.system(size: 10))
                        .foregroundStyle(SaudioTheme.muted)
                }
                .padding(.horizontal, 12)
                .frame(width: 92, height: 44)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.9)))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(SaudioTheme.line, lineWidth: 1))
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
        }
        .saudioCard()
    }

    private func speedLabel(_ value: Double) -> String {
        value == value.rounded() ? String(format: "%.1fx", value) : String(format: "%.2gx", value)
    }

    // Shared button

    private func gradientButton(_ title: String, _ icon: String,
                                action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                Text(title).font(.system(size: 12, weight: .bold)).tracking(1)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .frame(height: 40)
            .background(RoundedRectangle(cornerRadius: 11).fill(SaudioTheme.gradient))
        }
        .buttonStyle(.plain)
    }
}

extension String {
    fileprivate var capitalizedFirst: String {
        guard let head = self.first else { return self }
        return head.uppercased() + String(self.dropFirst())
    }
}

// MARK: - Reusable pieces

struct SaudioTextArea: View {
    @Binding var text: String
    let placeholder: String
    let minHeight: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $text)
                .font(.system(size: 14))
                .foregroundStyle(SaudioTheme.ink)
                .scrollContentBackground(.hidden)
                .padding(6)
            if text.isEmpty {
                Text(placeholder)
                    .font(.system(size: 14))
                    .foregroundStyle(SaudioTheme.muted.opacity(0.8))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 14)
                    .allowsHitTesting(false)
            }
        }
        .frame(minHeight: minHeight)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.9)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(SaudioTheme.line, lineWidth: 1))
    }
}

struct SaudioSliderRow: View {
    let icon: String
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let format: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(SaudioTheme.accent)
                .frame(width: 24)
                .padding(.top, 2)
            VStack(spacing: 2) {
                HStack {
                    Text(title)
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(SaudioTheme.ink)
                    Spacer()
                    Text(String(format: format, value))
                        .font(.system(size: 13).monospacedDigit())
                        .foregroundStyle(SaudioTheme.ink)
                        .frame(width: 58, height: 26)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.9)))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(SaudioTheme.line, lineWidth: 1))
                }
                Slider(value: $value, in: range, step: step)
                    .tint(SaudioTheme.accent)
                HStack {
                    Text(String(format: format, range.lowerBound))
                    Spacer()
                    Text(String(format: format, range.upperBound))
                }
                .font(.system(size: 10))
                .foregroundStyle(SaudioTheme.muted)
            }
        }
    }
}

// MARK: - Library

struct SaudioLibraryView: View {
    @Bindable var engine: SaudioEngine
    let openStudio: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Library")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(SaudioTheme.ink)
                        Text("Reference voices you saved. Pick one to use it in Voice Studio.")
                            .font(.system(size: 13))
                            .foregroundStyle(SaudioTheme.muted)
                    }
                    Spacer()
                    Button("Save current reference") { engine.saveReferenceToLibrary() }
                        .buttonStyle(.borderedProminent)
                        .tint(SaudioTheme.accent)
                        .disabled(engine.referenceURL == nil)
                }

                if engine.library.voices.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "folder")
                            .font(.system(size: 30))
                            .foregroundStyle(SaudioTheme.accent)
                        Text("No saved voices yet")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(SaudioTheme.ink)
                        Text("Upload a reference in Voice Studio, then choose Save to Library.")
                            .font(.system(size: 13))
                            .foregroundStyle(SaudioTheme.muted)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(40)
                    .saudioCard()
                } else {
                    ForEach(engine.library.voices) { voice in
                        HStack(spacing: 14) {
                            Image(systemName: "waveform")
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                                .background(RoundedRectangle(cornerRadius: 12).fill(SaudioTheme.gradient))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(voice.name)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(SaudioTheme.ink)
                                Text(voice.transcript.isEmpty ? "No transcript saved" : voice.transcript)
                                    .font(.system(size: 12))
                                    .foregroundStyle(SaudioTheme.muted)
                                    .lineLimit(2)
                            }
                            Spacer()
                            Button("Use") {
                                engine.useLibraryVoice(voice)
                                openStudio()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(SaudioTheme.accent)
                            Button(role: .destructive) {
                                engine.library.remove(voice)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.bordered)
                        }
                        .saudioCard()
                    }
                }
            }
            .padding(24)
        }
    }
}

// MARK: - Settings

struct SaudioSettingsView: View {
    @Bindable var engine: SaudioEngine

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Settings")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(SaudioTheme.ink)

                VStack(alignment: .leading, spacing: 10) {
                    SaudioHeading(title: "DIA2 VOICE MODEL")
                    HStack(spacing: 10) {
                        Image(systemName: engine.dia2Installed ? "checkmark.circle.fill" : "circle.dashed")
                            .foregroundStyle(engine.dia2Installed ? SaudioTheme.good : SaudioTheme.muted)
                        Text(engine.dia2Installed ? "Dia2 1B (4-bit) is installed." : "Not installed yet.")
                            .foregroundStyle(SaudioTheme.ink)
                    }
                    Text("Import the dia2-1b-mlx-4bit folder you already have. Saudio copies it into its own storage, because a Mac app can't read files outside its folder on its own.")
                        .font(.system(size: 12))
                        .foregroundStyle(SaudioTheme.muted)
                    HStack {
                        Button(engine.dia2Installed ? "Import again…" : "Import Dia2 model folder…") {
                            engine.chooseDia2ModelFolder()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(SaudioTheme.accent)
                        .disabled(engine.isBusy)
                        if engine.phase == .importingModel {
                            ProgressView().controlSize(.small)
                            Text("Copying about 600 MB…")
                                .font(.system(size: 12))
                                .foregroundStyle(SaudioTheme.muted)
                        }
                    }
                    if let error = engine.errorMessage {
                        Text(error).font(.system(size: 12)).foregroundStyle(SaudioTheme.bad)
                    } else if let info = engine.infoMessage {
                        Text(info).font(.system(size: 12)).foregroundStyle(SaudioTheme.muted)
                    }
                }
                .saudioCard()

                VStack(alignment: .leading, spacing: 10) {
                    SaudioHeading(title: "WHISPER (WORD TIMING AND AUTO TRANSCRIBE)")
                    Text("Dia2 needs to know when each word is spoken in your reference clip. Whisper works that out on your Mac. One download, needs internet.")
                        .font(.system(size: 12))
                        .foregroundStyle(SaudioTheme.muted)
                    whisperRow
                }
                .saudioCard()
            }
            .padding(24)
        }
    }

    @ViewBuilder
    private var whisperRow: some View {
        switch engine.whisper.state(for: engine.whisperVariant) {
        case .ready:
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(SaudioTheme.good)
                Text("Whisper is ready.").foregroundStyle(SaudioTheme.ink)
            }
        case .downloading(let fraction):
            HStack(spacing: 12) {
                ProgressView(value: fraction).frame(width: 220)
                Text(String(format: "%.0f%%", fraction * 100))
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(SaudioTheme.muted)
                Button("Cancel") { engine.whisper.cancelDownload(engine.whisperVariant) }
                    .buttonStyle(.bordered)
            }
        case .failed(let message):
            VStack(alignment: .leading, spacing: 8) {
                Text(message).font(.system(size: 12)).foregroundStyle(SaudioTheme.bad)
                Button("Try again") { engine.whisper.download(engine.whisperVariant) }
                    .buttonStyle(.borderedProminent)
                    .tint(SaudioTheme.accent)
            }
        case .notDownloaded:
            Button("Download Whisper model") { engine.whisper.download(engine.whisperVariant) }
                .buttonStyle(.borderedProminent)
                .tint(SaudioTheme.accent)
        }
    }
}

// MARK: - About

struct SaudioAboutView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("About Saudio")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(SaudioTheme.ink)
            Text("Saudio clones a voice from a short reference clip and reads your text in it. Everything runs on this Mac.")
                .font(.system(size: 14))
                .foregroundStyle(SaudioTheme.ink)
            Text("Voice engine: Dia2 (Apache-2.0) running on MLX. Word timing: Whisper. Built on the open-source Gloam Voice Studio (MIT).")
                .font(.system(size: 12))
                .foregroundStyle(SaudioTheme.muted)
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
