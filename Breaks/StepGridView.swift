//
//  StepGridView.swift
//  Breaks
//
//  Created by Ethan Zhou on 3/18/26.
//

import SwiftUI

struct StepGridView: View {
    @Bindable var engine: AudioEngine

    var body: some View {
        VStack(spacing: 12) {
            // Transport bar
            transportBar

            // Step grid
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(spacing: 4) {
                    // Step numbers
                    HStack(spacing: 3) {
                        Color.clear
                            .frame(width: 44, height: 1)
                        ForEach(0..<engine.stepCount, id: \.self) { step in
                            Text("\(step + 1)")
                                .font(.system(size: 8, weight: .medium, design: .monospaced))
                                .foregroundStyle(step % 4 == 0 ? .primary : .secondary)
                                .frame(width: 28)
                        }
                    }

                    // Pad rows
                    ForEach(0..<engine.padCount, id: \.self) { pad in
                        HStack(spacing: 3) {
                            // Pad label
                            Text(shortLabel(pad))
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(engine.padHasAudio[pad] ? engine.padColors[pad] : .secondary)
                                .frame(width: 44, alignment: .leading)
                                .lineLimit(1)

                            // Step cells
                            ForEach(0..<engine.stepCount, id: \.self) { step in
                                stepCell(pad: pad, step: step)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
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
                    .foregroundStyle(engine.sequencerPlaying ? .red : .green)
                    .frame(width: 36, height: 36)
            }

            // BPM
            VStack(spacing: 1) {
                Text("BPM")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text("\(Int(engine.bpm))")
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
            }
            .frame(width: 44)

            Slider(value: Binding(
                get: { engine.bpm },
                set: { engine.updateBPM($0) }
            ), in: 60...200, step: 1)
            .tint(.orange)

            // Beat indicator
            HStack(spacing: 2) {
                ForEach(0..<4, id: \.self) { beat in
                    Circle()
                        .fill(engine.sequencerPlaying && engine.sequencerCurrentStep / 4 == beat
                              ? Color.orange : Color.gray.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private func stepCell(pad: Int, step: Int) -> some View {
        let isActive = engine.pattern[pad][step]
        let isCurrent = engine.sequencerPlaying && engine.sequencerCurrentStep == step
        let hasAudio = engine.padHasAudio[pad]
        let color = engine.padColors[pad]
        let isDownbeat = step % 4 == 0

        return Button {
            engine.toggleStep(pad: pad, step: step)
        } label: {
            RoundedRectangle(cornerRadius: 4)
                .fill(cellColor(isActive: isActive, isCurrent: isCurrent, hasAudio: hasAudio, color: color))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(
                            isCurrent ? Color.white.opacity(0.7) :
                                (isDownbeat ? Color.white.opacity(0.1) : Color.clear),
                            lineWidth: isCurrent ? 1.5 : 0.5
                        )
                )
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
    }

    private func cellColor(isActive: Bool, isCurrent: Bool, hasAudio: Bool, color: Color) -> Color {
        if isActive && hasAudio {
            return color.opacity(isCurrent ? 1.0 : 0.75)
        } else if isActive {
            return color.opacity(isCurrent ? 0.5 : 0.3)
        } else {
            return Color(.systemGray5).opacity(isCurrent ? 0.5 : 0.25)
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

#Preview {
    StepGridView(engine: AudioEngine())
}
