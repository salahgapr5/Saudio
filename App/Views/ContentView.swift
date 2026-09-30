import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var referenceName = "No reference audio selected"
    @State private var referenceTranscript = ""
    @State private var text = ""
    @State private var cfg: Double = 6.0
    @State private var textTemperature: Double = 0.6
    @State private var audioTemperature: Double = 0.8
    @State private var textTopK: Double = 50
    @State private var audioTopK: Double = 50
    @State private var includeReference = true
    @State private var showImporter = false
    @State private var status = "Ready"

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("SAUDIO")
                            .font(.system(size: 26, weight: .bold))
                        Text("AI VOICE STUDIO")
                            .font(.system(size: 10, weight: .medium))
                            .tracking(2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text(status)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(24)

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        section("REFERENCE AUDIO") {
                            HStack(spacing: 14) {
                                Image(systemName: "waveform")
                                    .font(.system(size: 25))
                                    .frame(width: 48, height: 48)
                                    .background(.white.opacity(0.08))
                                    .clipShape(RoundedRectangle(cornerRadius: 12))

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(referenceName)
                                        .lineLimit(1)
                                    Text("WAV / MP3 / M4A")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Button("UPLOAD") {
                                    showImporter = true
                                }
                                .buttonStyle(.borderedProminent)
                            }
                            .padding(16)
                            .background(.white.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }

                        section("REFERENCE TRANSCRIPT") {
                            TextEditor(text: $referenceTranscript)
                                .frame(minHeight: 100)
                                .padding(8)
                                .scrollContentBackground(.hidden)
                                .background(.white.opacity(0.05))
                                .clipShape(RoundedRectangle(cornerRadius: 12))

                            HStack {
                                Text("Edit the transcript if needed.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button("✨ AUTO TRANSCRIBE") {
                                    status = "Transcription ready"
                                }
                                .buttonStyle(.bordered)
                            }
                        }

                        section("NEW VOICE TEXT") {
                            TextEditor(text: $text)
                                .frame(minHeight: 150)
                                .padding(10)
                                .scrollContentBackground(.hidden)
                                .background(.white.opacity(0.05))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }

                        section("VOICE CONTROLS") {
                            VStack(spacing: 14) {
                                control("CFG SCALE", value: cfg, range: 1...10) {
                                    Slider(value: $cfg, in: 1...10, step: 0.1)
                                }

                                control("TEXT TEMPERATURE", value: textTemperature, range: 0...1) {
                                    Slider(value: $textTemperature, in: 0...1, step: 0.05)
                                }

                                control("AUDIO TEMPERATURE", value: audioTemperature, range: 0...1) {
                                    Slider(value: $audioTemperature, in: 0...1, step: 0.05)
                                }

                                control("TEXT TOP-K", value: textTopK, range: 1...100) {
                                    Slider(value: $textTopK, in: 1...100, step: 1)
                                }

                                control("AUDIO TOP-K", value: audioTopK, range: 1...100) {
                                    Slider(value: $audioTopK, in: 1...100, step: 1)
                                }

                                Toggle("Include reference audio", isOn: $includeReference)
                                    .toggleStyle(.switch)
                            }
                            .padding(16)
                            .background(.white.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }

                        Button {
                            status = "Generating voice…"
                        } label: {
                            HStack {
                                Image(systemName: "waveform.and.mic")
                                Text("GENERATE VOICE")
                                    .fontWeight(.bold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                        }
                        .buttonStyle(.borderedProminent)

                        HStack {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 30))
                            VStack(alignment: .leading) {
                                Text("Generated Voice")
                                    .fontWeight(.semibold)
                                Text("No audio generated yet")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("SAVE WAV") {}
                                .buttonStyle(.bordered)
                                .disabled(true)
                        }
                        .padding(16)
                        .background(.white.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .padding(24)
                }
            }
        }
        .frame(minWidth: 900, minHeight: 720)
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: false
        ) { result in
            if let url = try? result.get().first {
                referenceName = url.lastPathComponent
                status = "Reference loaded"
            }
        }
    }

    private func section<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .tracking(1.4)
                .foregroundStyle(.secondary)

            content()
        }
    }

    private func control<Content: View>(
        _ title: String,
        value: Double,
        range: ClosedRange<Double>,
        @ViewBuilder slider: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title)
                    .font(.caption)
                Spacer()
                Text(String(format: "%.2f", value))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            slider()
        }
    }
}
