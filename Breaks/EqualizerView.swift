//
//  EqualizerView.swift
//  Breaks
//
//  Created by Ethan Zhou on 3/18/26.
//

import SwiftUI

struct EqualizerView: View {
    @Bindable var engine: AudioEngine

    var body: some View {
        VStack(spacing: 20) {
            Text("GRAPHIC EQ")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.top, 16)

            // EQ visualization
            eqCurveView
                .frame(height: 100)
                .padding(.horizontal)

            // Band sliders
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(0..<engine.eqFrequencies.count, id: \.self) { band in
                    bandSlider(band: band)
                }
            }
            .padding(.horizontal)

            Spacer()

            // Reset button
            Button {
                for i in 0..<engine.eqGains.count {
                    engine.updateEQ(band: i, gain: 0)
                }
            } label: {
                Label("Flat", systemImage: "arrow.counterclockwise")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
            }
            .buttonStyle(.bordered)
            .tint(.secondary)
            .padding(.bottom, 20)
        }
        .background(Color(.systemBackground))
    }

    private var eqCurveView: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let midY = h / 2

            ZStack {
                // Grid lines
                ForEach([-12, -6, 0, 6, 12], id: \.self) { db in
                    let y = midY - CGFloat(db) / 12.0 * (h / 2) * 0.8
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: w, y: y))
                    }
                    .stroke(Color.gray.opacity(db == 0 ? 0.4 : 0.15), lineWidth: db == 0 ? 1 : 0.5)
                }

                // EQ curve
                Path { path in
                    let bandCount = engine.eqGains.count
                    for i in 0..<bandCount {
                        let x = w * CGFloat(i) / CGFloat(bandCount - 1)
                        let y = midY - CGFloat(engine.eqGains[i]) / 12.0 * (h / 2) * 0.8
                        if i == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            let prevX = w * CGFloat(i - 1) / CGFloat(bandCount - 1)
                            let prevY = midY - CGFloat(engine.eqGains[i - 1]) / 12.0 * (h / 2) * 0.8
                            let controlX1 = prevX + (x - prevX) / 3
                            let controlX2 = x - (x - prevX) / 3
                            path.addCurve(
                                to: CGPoint(x: x, y: y),
                                control1: CGPoint(x: controlX1, y: prevY),
                                control2: CGPoint(x: controlX2, y: y)
                            )
                        }
                    }
                }
                .stroke(Color.orange, lineWidth: 2)

                // Filled area under curve
                Path { path in
                    let bandCount = engine.eqGains.count
                    path.move(to: CGPoint(x: 0, y: midY))
                    for i in 0..<bandCount {
                        let x = w * CGFloat(i) / CGFloat(bandCount - 1)
                        let y = midY - CGFloat(engine.eqGains[i]) / 12.0 * (h / 2) * 0.8
                        if i == 0 {
                            path.addLine(to: CGPoint(x: x, y: y))
                        } else {
                            let prevX = w * CGFloat(i - 1) / CGFloat(bandCount - 1)
                            let prevY = midY - CGFloat(engine.eqGains[i - 1]) / 12.0 * (h / 2) * 0.8
                            let controlX1 = prevX + (x - prevX) / 3
                            let controlX2 = x - (x - prevX) / 3
                            path.addCurve(
                                to: CGPoint(x: x, y: y),
                                control1: CGPoint(x: controlX1, y: prevY),
                                control2: CGPoint(x: controlX2, y: y)
                            )
                        }
                    }
                    path.addLine(to: CGPoint(x: w, y: midY))
                    path.closeSubpath()
                }
                .fill(Color.orange.opacity(0.15))
            }
        }
    }

    private func bandSlider(band: Int) -> some View {
        VStack(spacing: 6) {
            // dB label
            Text(String(format: "%+.0f", engine.eqGains[band]))
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(engine.eqGains[band] == 0 ? Color.secondary : Color.orange)
                .frame(height: 14)

            // Vertical slider
            GeometryReader { geo in
                let range: Float = 24.0 // -12 to +12
                let normalized = CGFloat((engine.eqGains[band] + 12.0) / range)
                let trackHeight = geo.size.height
                let thumbY = trackHeight * (1 - normalized)

                ZStack(alignment: .bottom) {
                    // Track background
                    Capsule()
                        .fill(Color(.systemGray5))
                        .frame(width: 6)
                        .frame(maxHeight: .infinity)
                        .frame(maxWidth: .infinity)

                    // Active fill
                    Capsule()
                        .fill(Color.orange.opacity(0.6))
                        .frame(width: 6, height: max(0, trackHeight * normalized))
                        .frame(maxWidth: .infinity)
                }
                .overlay(alignment: .top) {
                    // Thumb
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 18, height: 18)
                        .shadow(color: .orange.opacity(0.3), radius: 4)
                        .offset(y: thumbY - 9)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let fraction = 1 - (value.location.y / trackHeight)
                            let clamped = max(0, min(1, Float(fraction)))
                            let gain = clamped * range - 12.0
                            engine.updateEQ(band: band, gain: gain)
                        }
                )
            }
            .frame(height: 200)

            // Frequency label
            Text(engine.eqLabels[band])
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    EqualizerView(engine: AudioEngine())
}
