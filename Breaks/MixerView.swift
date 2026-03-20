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
            // Header stripe
            HStack {
                Rectangle()
                    .fill(TR808.accent)
                    .frame(height: 3)
            }
            .padding(.horizontal, 20)

            Text("MIXER")
                .font(TR808.label(13))
                .foregroundStyle(TR808.silver)
                .tracking(2)

            HStack(spacing: 60) {
                mixerChannel(
                    label: "COMP",
                    value: engine.compressionMix,
                    color: TR808.stepOrange,
                    onChange: { engine.updateCompressionMix($0) }
                )

                mixerChannel(
                    label: "SAT",
                    value: engine.saturationMix,
                    color: TR808.stepRed,
                    onChange: { engine.updateSaturationMix($0) }
                )
            }
            .padding(.top, 20)

            Spacer()
        }
        .background(TR808.bg)
        .preferredColorScheme(.dark)
    }

    private func mixerChannel(label: String, value: Float, color: Color, onChange: @escaping (Float) -> Void) -> some View {
        VStack(spacing: 16) {
            // Dry/Wet percentage
            Text("\(Int(value * 100))%")
                .font(TR808.readout(22))
                .foregroundStyle(value > 0 ? color : TR808.silverDim)

            // Vertical slider
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(TR808.surface)
                    .frame(width: 60)

                // Filled portion
                GeometryReader { geo in
                    VStack {
                        Spacer()
                        RoundedRectangle(cornerRadius: 8)
                            .fill(
                                LinearGradient(
                                    colors: [color.opacity(0.2), color.opacity(0.6)],
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
                                .fill(TR808.silverDim.opacity(0.3))
                                .frame(width: i % 5 == 0 ? 40 : 20, height: 1)
                        }
                        .frame(width: 60)
                        .position(x: 30, y: y)
                    }
                }

                // Fader cap
                GeometryReader { geo in
                    let thumbY = geo.size.height * CGFloat(1.0 - value)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color)
                        .frame(width: 56, height: 12)
                        .shadow(color: color.opacity(0.4), radius: 6)
                        .position(x: 30, y: thumbY)
                }

                // Gesture
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
                    .font(TR808.label(15, weight: .bold))
                    .foregroundStyle(color)

                HStack(spacing: 16) {
                    Text("DRY")
                        .font(TR808.label(9))
                        .foregroundStyle(value < 0.5 ? TR808.silver : TR808.silverDim)
                    Text("WET")
                        .font(TR808.label(9))
                        .foregroundStyle(value >= 0.5 ? TR808.silver : TR808.silverDim)
                }
            }
        }
    }
}

#Preview {
    MixerView(engine: AudioEngine())
        .preferredColorScheme(.dark)
}
