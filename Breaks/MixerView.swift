//
//  MixerView.swift
//  Breaks
//
//  Created by Ethan Zhou on 3/18/26.
//

import SwiftUI

struct MixerView: View {
    @Bindable var engine: AudioEngine

    var body: some View {
        VStack(spacing: 24) {
            Text("MIXER")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.top, 16)

            HStack(spacing: 60) {
                mixerChannel(
                    label: "COMP",
                    value: engine.compressionMix,
                    color: .cyan,
                    onChange: { engine.updateCompressionMix($0) }
                )

                mixerChannel(
                    label: "SAT",
                    value: engine.saturationMix,
                    color: .pink,
                    onChange: { engine.updateSaturationMix($0) }
                )
            }
            .padding(.top, 20)

            Spacer()
        }
        .background(Color(.systemBackground))
    }

    private func mixerChannel(label: String, value: Float, color: Color, onChange: @escaping (Float) -> Void) -> some View {
        VStack(spacing: 16) {
            // Dry/Wet percentage
            Text("\(Int(value * 100))%")
                .font(.system(size: 24, weight: .bold, design: .monospaced))
                .foregroundStyle(value > 0 ? color : .secondary)

            // Vertical slider
            ZStack {
                // Background track
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.systemGray6))
                    .frame(width: 60)

                // Filled portion
                GeometryReader { geo in
                    VStack {
                        Spacer()
                        RoundedRectangle(cornerRadius: 8)
                            .fill(
                                LinearGradient(
                                    colors: [color.opacity(0.3), color.opacity(0.8)],
                                    startPoint: .bottom,
                                    endPoint: .top
                                )
                            )
                            .frame(width: 60, height: geo.size.height * CGFloat(value))
                    }
                }

                // Level markers
                GeometryReader { geo in
                    ForEach(0..<11, id: \.self) { i in
                        let y = geo.size.height * CGFloat(1.0 - Double(i) / 10.0)
                        HStack {
                            Rectangle()
                                .fill(Color.white.opacity(0.2))
                                .frame(width: i % 5 == 0 ? 40 : 20, height: 1)
                        }
                        .frame(width: 60)
                        .position(x: 30, y: y)
                    }
                }

                // Thumb / fader cap
                GeometryReader { geo in
                    let thumbY = geo.size.height * CGFloat(1.0 - value)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color)
                        .frame(width: 56, height: 12)
                        .shadow(color: color.opacity(0.5), radius: 6)
                        .position(x: 30, y: thumbY)
                }

                // Gesture overlay
                GeometryReader { geo in
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { drag in
                                    let fraction = 1.0 - Float(drag.location.y / geo.size.height)
                                    let clamped = max(0, min(1, fraction))
                                    onChange(clamped)
                                }
                        )
                }
            }
            .frame(width: 60, height: 350)

            // Labels
            VStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundStyle(color)

                HStack(spacing: 16) {
                    Text("DRY")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(value < 0.5 ? .primary : .secondary)
                    Text("WET")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(value >= 0.5 ? .primary : .secondary)
                }
            }
        }
    }
}

#Preview {
    MixerView(engine: AudioEngine())
}
