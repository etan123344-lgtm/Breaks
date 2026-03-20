//
//  AudioEngine.swift
//  Breaks
//
//  Created by Ethan Zhou on 3/18/26.
//

import AVFoundation
import SwiftUI

@Observable
class AudioEngine {
    // MARK: - Pad State
    let padCount = 8
    var padLabels: [String]
    var padHasAudio: [Bool]
    var padIsPlaying: [Bool]
    var padWaveforms: [[Float]]       // downsampled amplitude data for display
    var padStartPoints: [Float]       // normalized 0–1
    var padEndPoints: [Float]         // normalized 0–1
    var isRecording = false
    var recordingPadIndex: Int? = nil

    // MARK: - Sequencer State
    let stepCount = 16
    var pattern: [[Bool]]             // pattern[pad][step], 8×16
    var bpm: Double = 120.0
    var sequencerPlaying = false
    var sequencerCurrentStep = 0

    // MARK: - EQ State (7-band)
    let eqFrequencies: [Float] = [60, 230, 910, 3600, 7200, 12000, 16000]
    let eqLabels = ["60", "230", "910", "3.6k", "7.2k", "12k", "16k"]
    var eqGains: [Float] = [0, 0, 0, 0, 0, 0, 0] // -12 to +12 dB

    // MARK: - Mixer State
    var compressionMix: Float = 0.0
    var saturationMix: Float = 0.0

    // MARK: - Audio Engine
    private var engine = AVAudioEngine()
    private var players: [AVAudioPlayerNode] = []
    private var padBuffers: [AVAudioPCMBuffer?] = []
    private var eqNode: AVAudioUnitEQ?
    private var distortion: AVAudioUnitDistortion?
    private var submixer: AVAudioMixerNode?

    // Recording
    private var recordingFile: AVAudioFile?
    private var recordingURL: URL?
    private var inputTap = false

    // Sequencer timer
    private var sequencerTimer: DispatchSourceTimer?
    private let sequencerQueue = DispatchQueue(label: "com.breaks.sequencer", qos: .userInteractive)

    // Pad colors
    let padColors: [Color] = [.orange, .cyan, .yellow, .pink, .purple, .green, .red, .mint]

    init() {
        padLabels = (1...8).map { "PAD \($0)" }
        padHasAudio = Array(repeating: false, count: 8)
        padIsPlaying = Array(repeating: false, count: 8)
        padWaveforms = Array(repeating: [], count: 8)
        padStartPoints = Array(repeating: 0, count: 8)
        padEndPoints = Array(repeating: 1, count: 8)
        pattern = Array(repeating: Array(repeating: false, count: 16), count: 8)
        padBuffers = Array(repeating: nil, count: 8)
        setupAudio()
        setupInterruptionHandling()
    }

    private func setupInterruptionHandling() {
        #if os(iOS)
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            guard let info = notification.userInfo,
                  let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

            if type == .ended {
                try? AVAudioSession.sharedInstance().setActive(true)
                self?.ensureEngineRunning()
            }
        }
        #endif
    }

    private func setupAudio() {
        #if os(iOS)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setActive(true)
        } catch {
            print("Audio session error: \(error)")
        }
        #endif

        let mainMixer = engine.mainMixerNode
        let format = mainMixer.outputFormat(forBus: 0)
        let stereoFormat = AVAudioFormat(standardFormatWithSampleRate: format.sampleRate, channels: 2)!
        let monoFormat = AVAudioFormat(standardFormatWithSampleRate: format.sampleRate, channels: 1)!

        // Submixer for all pads
        let sub = AVAudioMixerNode()
        engine.attach(sub)
        submixer = sub

        // Create 8 player nodes
        for _ in 0..<padCount {
            let player = AVAudioPlayerNode()
            engine.attach(player)
            players.append(player)
            engine.connect(player, to: sub, format: monoFormat)
        }

        // EQ
        let eq = AVAudioUnitEQ(numberOfBands: eqFrequencies.count)
        for (i, freq) in eqFrequencies.enumerated() {
            let band = eq.bands[i]
            band.filterType = .parametric
            band.frequency = freq
            band.bandwidth = 1.0
            band.gain = 0
            band.bypass = false
        }
        eqNode = eq
        engine.attach(eq)

        // Distortion for saturation
        let dist = AVAudioUnitDistortion()
        dist.loadFactoryPreset(.drumsBitBrush)
        dist.wetDryMix = 0
        distortion = dist
        engine.attach(dist)

        // Signal chain: submixer -> EQ -> distortion -> mainMixer
        engine.connect(sub, to: eq, format: stereoFormat)
        engine.connect(eq, to: dist, format: stereoFormat)
        engine.connect(dist, to: mainMixer, format: stereoFormat)

        do {
            try engine.start()
        } catch {
            print("Engine start error: \(error)")
        }
    }

    private func ensureEngineRunning() {
        guard !engine.isRunning else { return }
        do {
            try engine.start()
        } catch {
            print("Engine restart error: \(error)")
        }
    }

    // MARK: - Pad Playback

    func triggerPad(_ index: Int) {
        guard index < padCount, let fullBuffer = padBuffers[index] else { return }
        ensureEngineRunning()
        let player = players[index]
        if player.isPlaying {
            player.stop()
        }

        // Calculate trimmed region from start/end points
        let totalFrames = Int(fullBuffer.frameLength)
        let startFrame = Int(Float(totalFrames) * padStartPoints[index])
        let endFrame = Int(Float(totalFrames) * padEndPoints[index])
        let trimmedLength = max(1, endFrame - startFrame)

        guard let trimmedBuffer = AVAudioPCMBuffer(
            pcmFormat: fullBuffer.format,
            frameCapacity: AVAudioFrameCount(trimmedLength)
        ) else { return }
        trimmedBuffer.frameLength = AVAudioFrameCount(trimmedLength)

        let srcData = fullBuffer.floatChannelData![0]
        let dstData = trimmedBuffer.floatChannelData![0]
        for i in 0..<trimmedLength {
            let srcIdx = startFrame + i
            dstData[i] = srcIdx < totalFrames ? srcData[srcIdx] : 0
        }

        padIsPlaying[index] = true
        player.scheduleBuffer(trimmedBuffer, at: nil, options: []) { [weak self] in
            DispatchQueue.main.async {
                self?.padIsPlaying[index] = false
            }
        }
        player.play()
    }

    // MARK: - Recording

    func startRecording(padIndex: Int) {
        guard !isRecording else { return }

        // Set UI state on main thread first, then do audio work in background
        recordingPadIndex = padIndex

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            #if os(iOS)
            do {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
                try session.setActive(true)
            } catch {
                print("Session error: \(error)")
                DispatchQueue.main.async {
                    self.recordingPadIndex = nil
                }
                return
            }
            #endif

            // Stop engine before touching input node to avoid deadlock
            self.engine.stop()

            let inputNode = self.engine.inputNode
            let hwFormat = inputNode.outputFormat(forBus: 0)
            let recordFormat: AVAudioFormat
            if hwFormat.channelCount == 0 {
                recordFormat = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
            } else {
                recordFormat = hwFormat
            }

            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("pad_\(padIndex)_\(UUID().uuidString).caf")
            self.recordingURL = url

            do {
                let file = try AVAudioFile(forWriting: url, settings: recordFormat.settings)
                self.recordingFile = file

                inputNode.installTap(onBus: 0, bufferSize: 4096, format: recordFormat) { buffer, _ in
                    try? file.write(from: buffer)
                }
                self.inputTap = true

                try self.engine.start()

                // Only flip isRecording after engine is successfully running
                DispatchQueue.main.async {
                    self.isRecording = true
                }
            } catch {
                print("Recording setup error: \(error)")
                // Try to restart engine for playback
                try? self.engine.start()
                DispatchQueue.main.async {
                    self.isRecording = false
                    self.recordingPadIndex = nil
                }
            }
        }
    }

    func stopRecording() {
        guard isRecording, let padIndex = recordingPadIndex else { return }

        // Immediately update UI so the button is responsive
        isRecording = false
        recordingPadIndex = nil
        let url = recordingURL
        recordingURL = nil

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            self.engine.stop()

            if self.inputTap {
                self.engine.inputNode.removeTap(onBus: 0)
                self.inputTap = false
            }
            self.recordingFile = nil

            do {
                try self.engine.start()
            } catch {
                print("Engine restart error: \(error)")
            }

            if let url {
                DispatchQueue.main.async {
                    self.loadAudioFile(url: url, intoPad: padIndex)
                }
            }
        }
    }

    // MARK: - Import Audio

    func loadAudioFile(url: URL, intoPad padIndex: Int) {
        guard padIndex < padCount else { return }

        do {
            let file = try AVAudioFile(forReading: url)
            let processingFormat = AVAudioFormat(standardFormatWithSampleRate: file.processingFormat.sampleRate, channels: 1)!
            let frameCount = AVAudioFrameCount(file.length)
            guard let fileBuffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frameCount) else { return }
            try file.read(into: fileBuffer)

            // Convert to mono if needed
            let buffer: AVAudioPCMBuffer
            if file.processingFormat.channelCount > 1 {
                guard let monoBuffer = AVAudioPCMBuffer(pcmFormat: processingFormat, frameCapacity: frameCount) else { return }
                monoBuffer.frameLength = fileBuffer.frameLength
                let monoData = monoBuffer.floatChannelData![0]
                let leftData = fileBuffer.floatChannelData![0]
                let rightData = fileBuffer.floatChannelData![1]
                for i in 0..<Int(fileBuffer.frameLength) {
                    monoData[i] = (leftData[i] + rightData[i]) * 0.5
                }
                buffer = monoBuffer
            } else {
                buffer = fileBuffer
            }

            // Resample if needed to match engine sample rate
            let engineRate = engine.mainMixerNode.outputFormat(forBus: 0).sampleRate
            if file.processingFormat.sampleRate != engineRate {
                if let resampled = resample(buffer: buffer, from: file.processingFormat.sampleRate, to: engineRate) {
                    padBuffers[padIndex] = resampled
                } else {
                    padBuffers[padIndex] = buffer
                }
            } else {
                padBuffers[padIndex] = buffer
            }

            let waveform = self.generateWaveform(from: self.padBuffers[padIndex]!)

            DispatchQueue.main.async {
                self.padHasAudio[padIndex] = true
                self.padWaveforms[padIndex] = waveform
                self.padStartPoints[padIndex] = 0
                self.padEndPoints[padIndex] = 1
                let filename = url.deletingPathExtension().lastPathComponent
                if !filename.hasPrefix("pad_") {
                    self.padLabels[padIndex] = String(filename.prefix(10)).uppercased()
                }
            }
        } catch {
            print("Load audio error: \(error)")
        }
    }

    private func generateWaveform(from buffer: AVAudioPCMBuffer, sampleCount: Int = 200) -> [Float] {
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return [] }
        let data = buffer.floatChannelData![0]
        let samplesPerBin = max(1, frameCount / sampleCount)
        var waveform: [Float] = []
        for bin in 0..<sampleCount {
            let start = bin * samplesPerBin
            let end = min(start + samplesPerBin, frameCount)
            guard start < frameCount else { break }
            var maxAmp: Float = 0
            for i in start..<end {
                maxAmp = max(maxAmp, abs(data[i]))
            }
            waveform.append(maxAmp)
        }
        // Normalize to 0–1
        let peak = waveform.max() ?? 1
        if peak > 0 {
            waveform = waveform.map { $0 / peak }
        }
        return waveform
    }

    private func resample(buffer: AVAudioPCMBuffer, from sourceRate: Double, to destRate: Double) -> AVAudioPCMBuffer? {
        let ratio = destRate / sourceRate
        let newLength = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
        let destFormat = AVAudioFormat(standardFormatWithSampleRate: destRate, channels: 1)!
        guard let newBuffer = AVAudioPCMBuffer(pcmFormat: destFormat, frameCapacity: newLength) else { return nil }
        newBuffer.frameLength = newLength

        let srcData = buffer.floatChannelData![0]
        let dstData = newBuffer.floatChannelData![0]
        for i in 0..<Int(newLength) {
            let srcIndex = Double(i) / ratio
            let low = Int(srcIndex)
            let high = min(low + 1, Int(buffer.frameLength) - 1)
            let frac = Float(srcIndex - Double(low))
            dstData[i] = srcData[low] * (1 - frac) + srcData[high] * frac
        }
        return newBuffer
    }

    func clearPad(_ index: Int) {
        guard index < padCount else { return }
        padBuffers[index] = nil
        padHasAudio[index] = false
        padWaveforms[index] = []
        padStartPoints[index] = 0
        padEndPoints[index] = 1
        padLabels[index] = "PAD \(index + 1)"
        if players[index].isPlaying {
            players[index].stop()
        }
        padIsPlaying[index] = false
    }

    // MARK: - Sequencer Transport

    func toggleSequencer() {
        if sequencerPlaying {
            stopSequencer()
        } else {
            startSequencer()
        }
    }

    func startSequencer() {
        guard !sequencerPlaying else { return }
        ensureEngineRunning()
        sequencerPlaying = true
        sequencerCurrentStep = 0
        scheduleSequencerTimer()
    }

    func stopSequencer() {
        sequencerPlaying = false
        sequencerTimer?.cancel()
        sequencerTimer = nil
        sequencerCurrentStep = 0
    }

    private func scheduleSequencerTimer() {
        sequencerTimer?.cancel()
        let interval = 60.0 / bpm / 4.0 // 16th note interval
        let timer = DispatchSource.makeTimerSource(queue: sequencerQueue)
        timer.schedule(deadline: .now(), repeating: interval)
        timer.setEventHandler { [weak self] in
            self?.sequencerTick()
        }
        sequencerTimer = timer
        timer.resume()
    }

    private func sequencerTick() {
        let step = sequencerCurrentStep
        for pad in 0..<padCount {
            if pattern[pad][step] && padHasAudio[pad] {
                triggerPad(pad)
            }
        }
        DispatchQueue.main.async {
            self.sequencerCurrentStep = (step + 1) % self.stepCount
        }
    }

    func updateBPM(_ newBPM: Double) {
        bpm = newBPM
        if sequencerPlaying {
            scheduleSequencerTimer()
        }
    }

    func toggleStep(pad: Int, step: Int) {
        guard pad < padCount, step < stepCount else { return }
        pattern[pad][step].toggle()
    }

    // MARK: - EQ Controls

    func updateEQ(band: Int, gain: Float) {
        guard let eq = eqNode, band < eq.bands.count else { return }
        eqGains[band] = gain
        eq.bands[band].gain = gain
    }

    // MARK: - Mixer Controls

    func updateCompressionMix(_ value: Float) {
        compressionMix = value
    }

    func updateSaturationMix(_ value: Float) {
        saturationMix = value
        distortion?.wetDryMix = value * 50
    }
}
