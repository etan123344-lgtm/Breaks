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
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text("SAMPLE PADS")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.top, 12)

                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(0..<engine.padCount, id: \.self) { index in
                        padView(index: index)
                    }
                }
                .padding(.horizontal, 20)

                if engine.isRecording, let padIndex = engine.recordingPadIndex {
                    recordingIndicator(padIndex: padIndex)
                }

                Divider()
                    .padding(.horizontal, 16)

                Text("STEP SEQUENCER")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)

                StepGridView(engine: engine)
                    .padding(.bottom, 16)
            }
        }
        .background(Color(.systemBackground))
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
            RoundedRectangle(cornerRadius: 14)
                .fill(padFill(color: color, hasAudio: hasAudio, isPlaying: isPlaying, isRecordingThis: isRecordingThis))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(
                            color.opacity(hasAudio ? 0.6 : 0.2),
                            lineWidth: isPlaying ? 3 : 1.5
                        )
                )
                .overlay {
                    VStack(spacing: 6) {
                        if isRecordingThis {
                            Image(systemName: "waveform")
                                .font(.title2)
                                .foregroundStyle(.red)
                                .symbolEffect(.variableColor.iterative)
                        } else if hasAudio {
                            Image(systemName: "waveform")
                                .font(.title3)
                                .foregroundStyle(color)
                        } else {
                            Image(systemName: "plus.circle")
                                .font(.title3)
                                .foregroundStyle(color.opacity(0.5))
                        }

                        Text(engine.padLabels[index])
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(hasAudio ? color : color.opacity(0.4))
                            .lineLimit(1)
                    }
                }
                .frame(height: 64)
        }
        .buttonStyle(.plain)
    }

    private func padFill(color: Color, hasAudio: Bool, isPlaying: Bool, isRecordingThis: Bool) -> some ShapeStyle {
        if isRecordingThis {
            return AnyShapeStyle(Color.red.opacity(0.15))
        } else if isPlaying {
            return AnyShapeStyle(color.opacity(0.25))
        } else if hasAudio {
            return AnyShapeStyle(color.opacity(0.1))
        } else {
            return AnyShapeStyle(Color(.systemGray6))
        }
    }

    private func recordingIndicator(padIndex: Int) -> some View {
        Button {
            engine.stopRecording()
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(.red)
                    .frame(width: 10, height: 10)

                Text("RECORDING TO PAD \(padIndex + 1)")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(.red)

                Text("— TAP TO STOP")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.red.opacity(0.1))
                    .strokeBorder(Color.red.opacity(0.3), lineWidth: 1)
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

    var color: Color { engine.padColors[padIndex] }
    var hasAudio: Bool { engine.padHasAudio[padIndex] }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if hasAudio {
                    // Waveform with start/end markers
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
                        color: color
                    )
                    .frame(height: 150)
                    .padding(.horizontal)

                    Text(engine.padLabels[padIndex])
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(color)

                    // Loaded pad actions
                    VStack(spacing: 12) {
                        Button {
                            engine.triggerPad(padIndex)
                        } label: {
                            Label("Play Sample", systemImage: "play.fill")
                                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(color.opacity(0.15))
                                .foregroundStyle(color)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }

                        HStack(spacing: 12) {
                            Button {
                                onImport()
                            } label: {
                                Label("Replace", systemImage: "arrow.triangle.2.circlepath")
                                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(Color(.systemGray5))
                                    .foregroundStyle(.primary)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }

                            Button(role: .destructive) {
                                engine.clearPad(padIndex)
                            } label: {
                                Label("Clear", systemImage: "trash")
                                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(Color.red.opacity(0.1))
                                    .foregroundStyle(.red)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        }
                    }
                    .padding(.horizontal)
                } else {
                    // Empty state
                    RoundedRectangle(cornerRadius: 20)
                        .fill(color.opacity(0.05))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .strokeBorder(color.opacity(0.3), lineWidth: 1.5)
                        )
                        .overlay {
                            VStack(spacing: 10) {
                                Image(systemName: "waveform.slash")
                                    .font(.system(size: 40))
                                    .foregroundStyle(.secondary.opacity(0.4))
                                Text("EMPTY")
                                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(height: 150)
                        .padding(.horizontal)

                    VStack(spacing: 12) {
                        Button {
                            onImport()
                        } label: {
                            Label("Import Sample", systemImage: "square.and.arrow.down")
                                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(color.opacity(0.15))
                                .foregroundStyle(color)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }

                        Button {
                            onRecord()
                        } label: {
                            Label("Record Sample", systemImage: "mic.circle.fill")
                                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color(.systemGray5))
                                .foregroundStyle(.primary)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    .padding(.horizontal)
                }

                Spacer()
            }
            .padding(.top, 8)
            .navigationTitle("PAD \(padIndex + 1)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { onDismiss() }
                        .font(.system(.body, design: .monospaced, weight: .semibold))
                }
            }
        }
    }
}

// MARK: - Waveform View with Start/End Markers

struct WaveformView: View {
    let waveform: [Float]
    @Binding var startPoint: Float
    @Binding var endPoint: Float
    let color: Color

    @State private var draggingStart = false
    @State private var draggingEnd = false

    private let handleWidth: CGFloat = 14

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let startX = CGFloat(startPoint) * w
            let endX = CGFloat(endPoint) * w

            ZStack(alignment: .leading) {
                // Background
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemGray6))

                // Dimmed regions outside start/end
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(Color.black.opacity(0.4))
                        .frame(width: max(0, startX))
                    Spacer(minLength: 0)
                    Rectangle()
                        .fill(Color.black.opacity(0.4))
                        .frame(width: max(0, w - endX))
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))

                // Waveform bars
                if !waveform.isEmpty {
                    HStack(alignment: .center, spacing: 1) {
                        ForEach(0..<waveform.count, id: \.self) { i in
                            let normalized = CGFloat(i) / CGFloat(waveform.count)
                            let isInRange = normalized >= CGFloat(startPoint) && normalized <= CGFloat(endPoint)
                            let barHeight = max(2, CGFloat(waveform[i]) * h * 0.8)
                            RoundedRectangle(cornerRadius: 1)
                                .fill(isInRange ? color : color.opacity(0.2))
                                .frame(height: barHeight)
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 8)
                }

                // Start handle
                handleView(position: startX, label: "S", isActive: draggingStart)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { drag in
                                draggingStart = true
                                let newVal = Float(drag.location.x / w)
                                startPoint = max(0, min(newVal, endPoint - 0.02))
                            }
                            .onEnded { _ in draggingStart = false }
                    )

                // End handle
                handleView(position: endX, label: "E", isActive: draggingEnd)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { drag in
                                draggingEnd = true
                                let newVal = Float(drag.location.x / w)
                                endPoint = min(1, max(newVal, startPoint + 0.02))
                            }
                            .onEnded { _ in draggingEnd = false }
                    )
            }
        }
    }

    private func handleView(position: CGFloat, label: String, isActive: Bool) -> some View {
        VStack(spacing: 0) {
            // Top tab
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .frame(width: handleWidth, height: 16)
                .background(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 4,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: 4
                    )
                    .fill(isActive ? color : color.opacity(0.8))
                )

            // Vertical line
            Rectangle()
                .fill(isActive ? color : color.opacity(0.8))
                .frame(width: 2)
        }
        .offset(x: position - handleWidth / 2)
    }
}

extension Int: @retroactive Identifiable {
    public var id: Int { self }
}

#Preview {
    SequencerView(engine: AudioEngine())
}
