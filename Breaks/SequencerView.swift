//
//  SequencerView.swift
//  Breaks
//
//  Created by Ethan Zhou on 3/18/26.
//

import SwiftUI
import UniformTypeIdentifiers

struct SequencerView: View {
    @Bindable var engine: AudioEngine
    @State private var showImporter = false
    @State private var importPadIndex = 0
    @State private var selectedPadIndex: Int? = nil

    let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // 808 header stripe
                HStack {
                    Rectangle()
                        .fill(TR808.accent)
                        .frame(height: 3)
                }
                .padding(.horizontal, 20)

                Text("SAMPLE PADS")
                    .font(TR808.label(13))
                    .foregroundStyle(TR808.silver)
                    .tracking(2)

                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(0..<engine.padCount, id: \.self) { index in
                        padView(index: index)
                    }
                }
                .padding(.horizontal, 20)

                if engine.isRecording, let padIndex = engine.recordingPadIndex {
                    recordingIndicator(padIndex: padIndex)
                }

                Rectangle()
                    .fill(TR808.surfaceLight)
                    .frame(height: 1)
                    .padding(.horizontal, 20)

                Text("STEP SEQUENCER")
                    .font(TR808.label(13))
                    .foregroundStyle(TR808.silver)
                    .tracking(2)

                StepGridView(engine: engine)
                    .padding(.bottom, 16)
            }
        }
        .background(TR808.bg)
        .preferredColorScheme(.dark)
        .sheet(item: $selectedPadIndex) { index in
            PadDetailSheet(
                engine: engine,
                padIndex: index,
                onImport: {
                    selectedPadIndex = nil
                    importPadIndex = index
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        showImporter = true
                    }
                },
                onRecord: {
                    let pad = index
                    selectedPadIndex = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        engine.startRecording(padIndex: pad)
                    }
                },
                onDismiss: { selectedPadIndex = nil }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    let accessing = url.startAccessingSecurityScopedResource()
                    engine.loadAudioFile(url: url, intoPad: importPadIndex)
                    if accessing { url.stopAccessingSecurityScopedResource() }
                }
            case .failure(let error):
                print("Import error: \(error)")
            }
        }
    }

    private func padView(index: Int) -> some View {
        let color = engine.padColors[index]
        let hasAudio = engine.padHasAudio[index]
        let isPlaying = engine.padIsPlaying[index]
        let isRecordingThis = engine.isRecording && engine.recordingPadIndex == index

        return Button {
            selectedPadIndex = index
        } label: {
            RoundedRectangle(cornerRadius: 10)
                .fill(padFill(color: color, hasAudio: hasAudio, isPlaying: isPlaying, isRecordingThis: isRecordingThis))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(
                            color.opacity(hasAudio ? 0.5 : 0.15),
                            lineWidth: isPlaying ? 2.5 : 1
                        )
                )
                .overlay {
                    VStack(spacing: 4) {
                        if isRecordingThis {
                            Image(systemName: "waveform")
                                .font(.system(size: 18))
                                .foregroundStyle(TR808.ledOn)
                                .symbolEffect(.variableColor.iterative)
                        } else if hasAudio {
                            Image(systemName: "waveform")
                                .font(.system(size: 16))
                                .foregroundStyle(color)
                        } else {
                            Image(systemName: "plus")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(TR808.silverDim)
                        }

                        Text(engine.padLabels[index])
                            .font(TR808.label(8))
                            .foregroundStyle(hasAudio ? color : TR808.silverDim)
                            .lineLimit(1)
                    }
                }
                .frame(height: 64)
        }
        .buttonStyle(.plain)
    }

    private func padFill(color: Color, hasAudio: Bool, isPlaying: Bool, isRecordingThis: Bool) -> some ShapeStyle {
        if isRecordingThis {
            return AnyShapeStyle(TR808.ledOn.opacity(0.15))
        } else if isPlaying {
            return AnyShapeStyle(color.opacity(0.2))
        } else if hasAudio {
            return AnyShapeStyle(color.opacity(0.08))
        } else {
            return AnyShapeStyle(TR808.surface)
        }
    }

    private func recordingIndicator(padIndex: Int) -> some View {
        Button {
            engine.stopRecording()
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(TR808.ledOn)
                    .frame(width: 10, height: 10)

                Text("RECORDING TO PAD \(padIndex + 1)")
                    .font(TR808.label(12, weight: .bold))
                    .foregroundStyle(TR808.ledOn)

                Text("TAP TO STOP")
                    .font(TR808.label(10))
                    .foregroundStyle(TR808.silverDim)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(TR808.ledOn.opacity(0.1))
                    .strokeBorder(TR808.ledOn.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Pad Detail Sheet

struct PadDetailSheet: View {
    @Bindable var engine: AudioEngine
    let padIndex: Int
    let onImport: () -> Void
    let onRecord: () -> Void
    let onDismiss: () -> Void

    @State private var showSoundBrowser = false

    var color: Color { engine.padColors[padIndex] }
    var hasAudio: Bool { engine.padHasAudio[padIndex] }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if hasAudio {
                    WaveformView(
                        waveform: engine.padWaveforms[padIndex],
                        startPoint: Binding(
                            get: { engine.padStartPoints[padIndex] },
                            set: { engine.padStartPoints[padIndex] = $0 }
                        ),
                        endPoint: Binding(
                            get: { engine.padEndPoints[padIndex] },
                            set: { engine.padEndPoints[padIndex] = $0 }
                        ),
                        color: color,
                        duration: engine.padDurations[padIndex],
                        onTrimChanged: { engine.rebuildTrimmedBuffer(for: padIndex) }
                    )
                    .frame(height: 150)
                    .padding(.horizontal)

                    Text(engine.padLabels[padIndex])
                        .font(TR808.label(12, weight: .bold))
                        .foregroundStyle(color)

                    // Gain control
                    HStack(spacing: 10) {
                        Image(systemName: "speaker.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(TR808.silverDim)
                        Slider(
                            value: Binding(
                                get: { engine.padVolumes[padIndex] },
                                set: { engine.updatePadVolume(padIndex, volume: $0) }
                            ),
                            in: -60...12
                        )
                        .tint(color)
                        Image(systemName: "speaker.wave.3.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(TR808.silverDim)
                        Text(gainLabel(engine.padVolumes[padIndex]))
                            .font(TR808.readout(11))
                            .foregroundStyle(TR808.silver)
                            .frame(width: 52, alignment: .trailing)
                    }
                    .padding(.horizontal)

                    // Pitch control
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.down.right")
                            .font(.system(size: 11))
                            .foregroundStyle(TR808.silverDim)
                        Slider(
                            value: Binding(
                                get: { engine.padPitchSemitones[padIndex] },
                                set: { engine.updatePadPitch(padIndex, semitones: $0) }
                            ),
                            in: -12...12,
                            step: 1
                        )
                        .tint(color)
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 11))
                            .foregroundStyle(TR808.silverDim)
                        Text("\(Int(engine.padPitchSemitones[padIndex]))st")
                            .font(TR808.readout(11))
                            .foregroundStyle(TR808.silver)
                            .frame(width: 38, alignment: .trailing)
                    }
                    .padding(.horizontal)

                    // Per-pad EQ
                    VStack(spacing: 8) {
                        HStack {
                            Text("EQ")
                                .font(TR808.label(11, weight: .bold))
                                .foregroundStyle(TR808.silver)
                            Spacer()
                            Button {
                                engine.resetPadEQ(padIndex)
                            } label: {
                                Text("Flat")
                                    .font(TR808.label(10))
                                    .foregroundStyle(TR808.silverDim)
                            }
                        }

                        HStack(alignment: .bottom, spacing: 6) {
                            ForEach(0..<engine.eqFrequencies.count, id: \.self) { band in
                                padEQBand(padIndex: padIndex, band: band, color: color)
                            }
                        }
                        .frame(height: 120)
                    }
                    .padding(.horizontal)

                    // Reverse toggle
                    Button {
                        engine.reversePad(padIndex)
                    } label: {
                        Label(
                            engine.padReversed[padIndex] ? "Reversed" : "Reverse",
                            systemImage: "arrow.left.arrow.right"
                        )
                        .font(TR808.label(12, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(engine.padReversed[padIndex] ? color.opacity(0.25) : TR808.surfaceLight)
                        .foregroundStyle(engine.padReversed[padIndex] ? color : TR808.silver)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .padding(.horizontal)

                    VStack(spacing: 12) {
                        Button {
                            engine.triggerPad(padIndex)
                        } label: {
                            Label("Play Sample", systemImage: "play.fill")
                                .font(TR808.label(14, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(color.opacity(0.15))
                                .foregroundStyle(color)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }

                        HStack(spacing: 12) {
                            Button {
                                showSoundBrowser = true
                            } label: {
                                Label("Sound Kits", systemImage: "square.grid.2x2")
                                    .font(TR808.label(12))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(TR808.accent.opacity(0.15))
                                    .foregroundStyle(TR808.accent)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            }

                            Button {
                                onImport()
                            } label: {
                                Label("Replace", systemImage: "arrow.triangle.2.circlepath")
                                    .font(TR808.label(12))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(TR808.surfaceLight)
                                    .foregroundStyle(TR808.silver)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            }

                            Button(role: .destructive) {
                                engine.clearPad(padIndex)
                            } label: {
                                Label("Clear", systemImage: "trash")
                                    .font(TR808.label(12))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(TR808.stepRed.opacity(0.1))
                                    .foregroundStyle(TR808.stepRed)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                        }
                    }
                    .padding(.horizontal)
                } else {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(TR808.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .strokeBorder(TR808.surfaceLight, lineWidth: 1)
                        )
                        .overlay {
                            VStack(spacing: 10) {
                                Image(systemName: "waveform.slash")
                                    .font(.system(size: 36))
                                    .foregroundStyle(TR808.silverDim.opacity(0.4))
                                Text("EMPTY")
                                    .font(TR808.label(12, weight: .bold))
                                    .foregroundStyle(TR808.silverDim)
                            }
                        }
                        .frame(height: 150)
                        .padding(.horizontal)

                    VStack(spacing: 12) {
                        Button {
                            showSoundBrowser = true
                        } label: {
                            Label("Sound Kits", systemImage: "square.grid.2x2")
                                .font(TR808.label(14, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(TR808.accent.opacity(0.15))
                                .foregroundStyle(TR808.accent)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }

                        Button {
                            onImport()
                        } label: {
                            Label("Import Sample", systemImage: "square.and.arrow.down")
                                .font(TR808.label(14, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(TR808.surfaceLight)
                                .foregroundStyle(TR808.silver)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }

                        Button {
                            onRecord()
                        } label: {
                            Label("Record Sample", systemImage: "mic.circle.fill")
                                .font(TR808.label(14, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(TR808.surfaceLight)
                                .foregroundStyle(TR808.silver)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                    .padding(.horizontal)
                }

                Spacer()
            }
            .padding(.top, 8)
            .background(TR808.bg)
            .navigationTitle("PAD \(padIndex + 1)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { onDismiss() }
                        .font(TR808.label(15, weight: .semibold))
                        .foregroundStyle(TR808.accent)
                }
            }
            .toolbarBackground(TR808.surface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .sheet(isPresented: $showSoundBrowser) {
                SoundBrowserSheet(engine: engine, padIndex: padIndex)
            }
        }
        .preferredColorScheme(.dark)
    }

    private func padEQBand(padIndex: Int, band: Int, color: Color) -> some View {
        VStack(spacing: 4) {
            // dB label
            Text(String(format: "%+.0f", engine.padEQGains[padIndex][band]))
                .font(TR808.readout(8))
                .foregroundStyle(engine.padEQGains[padIndex][band] == 0 ? TR808.silverDim : color)
                .frame(height: 12)

            // Vertical slider
            GeometryReader { geo in
                let range: Float = 24.0
                let normalized = CGFloat((engine.padEQGains[padIndex][band] + 12.0) / range)
                let trackHeight = geo.size.height
                let thumbY = trackHeight * (1 - normalized)

                ZStack(alignment: .bottom) {
                    Capsule()
                        .fill(TR808.surface)
                        .frame(width: 6)
                        .frame(maxHeight: .infinity)
                        .frame(maxWidth: .infinity)

                    Capsule()
                        .fill(color.opacity(0.5))
                        .frame(width: 6, height: max(0, trackHeight * normalized))
                        .frame(maxWidth: .infinity)
                }
                .overlay(alignment: .top) {
                    Circle()
                        .fill(color)
                        .frame(width: 14, height: 14)
                        .shadow(color: color.opacity(0.3), radius: 3)
                        .offset(y: thumbY - 7)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let fraction = 1 - (value.location.y / trackHeight)
                            let clamped = max(0, min(1, Float(fraction)))
                            let gain = clamped * range - 12.0
                            engine.updatePadEQ(padIndex, band: band, gain: gain)
                        }
                )
            }

            // Frequency label
            Text(engine.eqLabels[band])
                .font(TR808.readout(7))
                .foregroundStyle(TR808.silverDim)
        }
    }

    private func gainLabel(_ db: Float) -> String {
        if db <= -60 {
            return "-∞ dB"
        } else if db >= 0 {
            return String(format: "+%.1f dB", db)
        } else {
            return String(format: "%.1f dB", db)
        }
    }
}

// MARK: - Sound Browser Sheet

struct SoundBrowserSheet: View {
    @Bindable var engine: AudioEngine
    let padIndex: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(AudioEngine.soundKits) { kit in
                NavigationLink {
                    SoundKitListView(engine: engine, kit: kit, padIndex: padIndex, dismiss: dismiss)
                } label: {
                    HStack {
                        Image(systemName: "folder.fill")
                            .foregroundStyle(TR808.accent)
                            .frame(width: 28)
                        Text(kit.name)
                            .font(TR808.label(15, weight: .semibold))
                            .foregroundStyle(TR808.cream)
                        Spacer()
                        Text("\(kit.sounds.count)")
                            .font(TR808.label(12))
                            .foregroundStyle(TR808.silverDim)
                    }
                    .padding(.vertical, 6)
                }
                .listRowBackground(TR808.surface)
            }
            .listStyle(.plain)
            .background(TR808.bg)
            .scrollContentBackground(.hidden)
            .navigationTitle("SOUND KITS")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                        .font(TR808.label(15, weight: .semibold))
                        .foregroundStyle(TR808.accent)
                }
            }
            .toolbarBackground(TR808.surface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .onDisappear { engine.stopPreview() }
    }
}

struct SoundKitListView: View {
    @Bindable var engine: AudioEngine
    let kit: AudioEngine.SoundKit
    let padIndex: Int
    let dismiss: DismissAction

    var body: some View {
        List(kit.sounds) { sound in
            HStack {
                Button {
                    engine.previewSound(sound)
                } label: {
                    HStack {
                        Image(systemName: "play.fill")
                            .foregroundStyle(TR808.accent)
                            .frame(width: 24)
                        Text(sound.name)
                            .font(TR808.label(14))
                            .foregroundStyle(TR808.cream)
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    engine.stopPreview()
                    engine.loadBundledSound(sound, intoPad: padIndex)
                    dismiss()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(TR808.accent)
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 4)
            .listRowBackground(TR808.surface)
        }
        .listStyle(.plain)
        .background(TR808.bg)
        .scrollContentBackground(.hidden)
        .navigationTitle(kit.name.uppercased())
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(TR808.surface, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .onDisappear { engine.stopPreview() }
    }
}

// MARK: - Waveform View with Zoom + Start/End Markers

struct WaveformView: View {
    let waveform: [Float]
    @Binding var startPoint: Float
    @Binding var endPoint: Float
    let color: Color
    var duration: Double = 0
    var onTrimChanged: (() -> Void)? = nil

    @State private var draggingStart = false
    @State private var draggingEnd = false
    @State private var zoom: CGFloat = 1.0

    private let handleWidth: CGFloat = 14
    private let minZoom: CGFloat = 1.0
    private let maxZoom: CGFloat = 32.0

    var body: some View {
        VStack(spacing: 8) {
            // Scrollable + zoomable waveform
            GeometryReader { outer in
                let containerWidth = outer.size.width
                let contentWidth = containerWidth * zoom
                let height = outer.size.height

                ScrollView(.horizontal, showsIndicators: true) {
                    waveformContent(contentWidth: contentWidth, height: height)
                        .frame(width: contentWidth, height: height)
                }
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            // Timestamps
            if duration > 0 {
                HStack {
                    Text(formatTimestamp(Double(startPoint) * duration))
                        .font(TR808.readout(10))
                        .foregroundStyle(TR808.silver)
                    Spacer()
                    Text(formatTimestamp(Double(endPoint) * duration))
                        .font(TR808.readout(10))
                        .foregroundStyle(TR808.silver)
                }
                .padding(.horizontal, 4)
            }

            // Zoom control bar
            HStack(spacing: 10) {
                Image(systemName: "minus.magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(TR808.silverDim)

                Slider(value: $zoom, in: minZoom...maxZoom)
                    .tint(TR808.accent)

                Image(systemName: "plus.magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(TR808.silverDim)

                Text("\(String(format: "%.1f", zoom))x")
                    .font(TR808.readout(10))
                    .foregroundStyle(TR808.silver)
                    .frame(width: 36)

                if zoom > 1.0 {
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) {
                            zoom = 1.0
                        }
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 11))
                            .foregroundStyle(TR808.accent)
                    }
                }
            }
            .frame(height: 20)
        }
    }

    private func waveformContent(contentWidth: CGFloat, height: CGFloat) -> some View {
        let startX = CGFloat(startPoint) * contentWidth
        let endX = CGFloat(endPoint) * contentWidth

        return ZStack(alignment: .leading) {
            // Background
            Rectangle()
                .fill(TR808.surfaceDim)

            // Dimmed regions outside trim
            HStack(spacing: 0) {
                Rectangle()
                    .fill(Color.black.opacity(0.5))
                    .frame(width: max(0, startX))
                Spacer(minLength: 0)
                Rectangle()
                    .fill(Color.black.opacity(0.5))
                    .frame(width: max(0, contentWidth - endX))
            }

            // Waveform bars
            if !waveform.isEmpty {
                HStack(alignment: .center, spacing: zoom > 3 ? 2 : 1) {
                    ForEach(0..<waveform.count, id: \.self) { i in
                        let normalized = CGFloat(i) / CGFloat(waveform.count)
                        let isInRange = normalized >= CGFloat(startPoint) && normalized <= CGFloat(endPoint)
                        let barHeight = max(2, CGFloat(waveform[i]) * height * 0.8)
                        RoundedRectangle(cornerRadius: 1)
                            .fill(isInRange ? color : color.opacity(0.15))
                            .frame(height: barHeight)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 8)
            }

            // Start handle
            handleView(label: "S", isActive: draggingStart)
                .offset(x: startX - handleWidth / 2)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { drag in
                            draggingStart = true
                            let newVal = Float(drag.location.x / contentWidth)
                            startPoint = max(0, min(newVal, endPoint - 0.001))
                        }
                        .onEnded { _ in
                                draggingStart = false
                                onTrimChanged?()
                            }
                )

            // End handle
            handleView(label: "E", isActive: draggingEnd)
                .offset(x: endX - handleWidth / 2)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { drag in
                            draggingEnd = true
                            let newVal = Float(drag.location.x / contentWidth)
                            endPoint = min(1, max(newVal, startPoint + 0.001))
                        }
                        .onEnded { _ in
                            draggingEnd = false
                            onTrimChanged?()
                        }
                )
        }
    }

    private func formatTimestamp(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = seconds - Double(mins * 60)
        return String(format: "%d:%05.2f", mins, secs)
    }

    private func handleView(label: String, isActive: Bool) -> some View {
        VStack(spacing: 0) {
            Text(label)
                .font(TR808.readout(8, weight: .bold))
                .foregroundStyle(TR808.bg)
                .frame(width: handleWidth, height: 16)
                .background(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 4,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: 4
                    )
                    .fill(isActive ? TR808.accent : TR808.cream)
                )

            Rectangle()
                .fill(isActive ? TR808.accent : TR808.cream)
                .frame(width: 2)
        }
    }
}

extension Int: @retroactive Identifiable {
    public var id: Int { self }
}

#Preview {
    SequencerView(engine: AudioEngine())
        .preferredColorScheme(.dark)
}
