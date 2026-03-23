//
//  StepGridView.swift
//  Breaks
//
//  Created by Ethan Zhou on 3/18/26.
//

import SwiftUI

struct StepGridView: View {
    @Bindable var engine: AudioEngine
    @State private var showShareSheet = false
    @State private var exportURL: URL?
    @State private var showExportNaming = false
    @State private var exportName = ""

    var body: some View {
        VStack(spacing: 12) {
            transportBar

            // Bar position indicator (only shown for multi-bar patterns)
            if engine.barCount > 1 {
                HStack(spacing: 6) {
                    ForEach(0..<engine.barCount, id: \.self) { bar in
                        let isCurrent = engine.sequencerPlaying && engine.sequencerCurrentStep / 16 == bar
                        Text("Bar \(bar + 1)")
                            .font(TR808.label(10, weight: isCurrent ? .bold : .medium))
                            .foregroundStyle(isCurrent ? TR808.accent : TR808.silverDim)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(isCurrent ? TR808.accent.opacity(0.15) : Color.clear)
                            )
                    }
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                VStack(spacing: 4) {
                    // Step numbers with 808 color groups
                    HStack(spacing: 3) {
                        Color.clear
                            .frame(width: 44, height: 1)
                        ForEach(0..<engine.stepCount, id: \.self) { step in
                            if step > 0 && step % 16 == 0 {
                                Color.clear.frame(width: 4, height: 1)
                            }
                            Text("\(step % 16 + 1)")
                                .font(TR808.readout(8))
                                .foregroundStyle(
                                    step % 4 == 0 ? TR808.stepColor(for: step) : TR808.silverDim
                                )
                                .frame(width: 28)
                        }
                    }

                    // Pad rows
                    ForEach(0..<engine.padCount, id: \.self) { pad in
                        HStack(spacing: 3) {
                            Text(shortLabel(pad))
                                .font(TR808.label(9, weight: .bold))
                                .foregroundStyle(engine.padHasAudio[pad] ? engine.padColors[pad] : TR808.silverDim)
                                .frame(width: 44, alignment: .leading)
                                .lineLimit(1)

                            ForEach(0..<engine.stepCount, id: \.self) { step in
                                if step > 0 && step % 16 == 0 {
                                    Color.clear.frame(width: 4, height: 28)
                                }
                                stepCell(pad: pad, step: step)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
            }

            // Reset & Export buttons
            HStack(spacing: 12) {
                Button {
                    engine.clearPattern()
                } label: {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                        .font(TR808.label(12))
                }
                .buttonStyle(.bordered)
                .tint(TR808.silverDim)

                Button {
                    exportName = ""
                    showExportNaming = true
                } label: {
                    Label(engine.isExporting ? "Exporting…" : "Export WAV",
                          systemImage: engine.isExporting ? "hourglass" : "square.and.arrow.up")
                        .font(TR808.label(12))
                }
                .buttonStyle(.bordered)
                .tint(TR808.accent)
                .disabled(engine.isExporting)
            }
        }
        .alert("Export WAV", isPresented: $showExportNaming) {
            TextField("File name", text: $exportName)
            Button("Cancel", role: .cancel) { }
            Button("Export") {
                let name = exportName.trimmingCharacters(in: .whitespacesAndNewlines)
                let filename = name.isEmpty ? nil : name
                engine.exportPattern(filename: filename) { url in
                    if let url {
                        exportURL = url
                        showShareSheet = true
                    }
                }
            }
        } message: {
            Text("Choose a name for your exported file.")
        }
        .sheet(isPresented: $showShareSheet) {
            if let exportURL {
                ShareSheetView(items: [exportURL])
            }
        }
    }

    private var transportBar: some View {
        HStack(spacing: 16) {
            // Play/Stop
            Button {
                engine.toggleSequencer()
            } label: {
                Image(systemName: engine.sequencerPlaying ? "stop.fill" : "play.fill")
                    .font(.title3)
                    .foregroundStyle(engine.sequencerPlaying ? TR808.ledOn : TR808.accent)
                    .frame(width: 36, height: 36)
            }

            // BPM readout
            VStack(spacing: 1) {
                Text("BPM")
                    .font(TR808.label(9))
                    .foregroundStyle(TR808.silverDim)
                Text("\(Int(engine.bpm))")
                    .font(TR808.readout(18))
                    .foregroundStyle(TR808.cream)
            }
            .frame(width: 44)

            Slider(value: Binding(
                get: { engine.bpm },
                set: { engine.updateBPM($0) }
            ), in: 60...200, step: 1)
            .tint(TR808.accent)

            // LED beat indicator (current beat within current bar)
            HStack(spacing: 3) {
                ForEach(0..<4, id: \.self) { beat in
                    Circle()
                        .fill(engine.sequencerPlaying && (engine.sequencerCurrentStep % 16) / 4 == beat
                              ? TR808.ledOn : TR808.ledOff)
                        .frame(width: 8, height: 8)
                }
            }

            // Bar count selector
            Menu {
                ForEach(1...4, id: \.self) { count in
                    Button("\(count) \(count == 1 ? "Bar" : "Bars")") {
                        engine.setBarCount(count)
                    }
                }
            } label: {
                VStack(spacing: 1) {
                    Text("BARS")
                        .font(TR808.label(9))
                        .foregroundStyle(TR808.silverDim)
                    Text("\(engine.barCount)")
                        .font(TR808.readout(18))
                        .foregroundStyle(TR808.cream)
                }
                .frame(width: 44)
            }
        }
        .padding(.horizontal, 16)
    }

    private func stepCell(pad: Int, step: Int) -> some View {
        let isActive = engine.pattern[pad][step]
        let isCurrent = engine.sequencerPlaying && engine.sequencerCurrentStep == step
        let hasAudio = engine.padHasAudio[pad]
        let stepColor = TR808.stepColor(for: step)
        let isDownbeat = step % 4 == 0

        return Button {
            engine.toggleStep(pad: pad, step: step)
        } label: {
            RoundedRectangle(cornerRadius: 4)
                .fill(cellColor(isActive: isActive, isCurrent: isCurrent, hasAudio: hasAudio, stepColor: stepColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(
                            isCurrent ? TR808.cream.opacity(0.6) :
                                (isDownbeat ? TR808.surfaceLight : Color.clear),
                            lineWidth: isCurrent ? 1.5 : 0.5
                        )
                )
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
    }

    private func cellColor(isActive: Bool, isCurrent: Bool, hasAudio: Bool, stepColor: Color) -> Color {
        if isActive && hasAudio {
            return stepColor.opacity(isCurrent ? 1.0 : 0.75)
        } else if isActive {
            return stepColor.opacity(isCurrent ? 0.4 : 0.25)
        } else {
            return TR808.surface.opacity(isCurrent ? 0.8 : 1.0)
        }
    }

    private func shortLabel(_ pad: Int) -> String {
        let label = engine.padLabels[pad]
        if label.hasPrefix("PAD ") {
            return "P\(pad + 1)"
        }
        return String(label.prefix(5))
    }
}

struct ShareSheetView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    StepGridView(engine: AudioEngine())
        .background(TR808.bg)
        .preferredColorScheme(.dark)
}
