//
//  AudioEngine.swift
//  Breaks
//
//  Created by Ethan Zhou on 3/18/26.
//

import AVFoundation
import AudioToolbox
import SwiftUI

// MARK: - TapeEffect (custom AU for wow/flutter/warble)

/// Processes audio through a modulated delay line to emulate cassette tape artifacts:
/// slow pitch drift (wow), fast pitch wobble (flutter), random warble, and treble roll-off.
final class TapeEffectAU: AUAudioUnit {
    private var inputBus: AUAudioUnitBus!
    private var outputBus: AUAudioUnitBus!
    private var _inputBusses: AUAudioUnitBusArray!
    private var _outputBusses: AUAudioUnitBusArray!

    // Delay lines (per-channel circular buffers)
    private let maxChannels = 2
    private var delayBuffers: [[Float]] = []
    private var writeIndices: [Int] = []
    private let delayBufferSize = 8192

    // LFO phases
    private var wowPhase: Double = 0
    private var flutterPhase: Double = 0
    // One-pole low-pass for treble roll-off (per-channel)
    private var lpfState: [Float] = [0, 0]

    // Noise state (UInt32 for LCG)
    private var noiseSeed: UInt32 = 12345

    /// Mix amount 0–1, set from main thread
    var mix: Float = 0.0

    private var sampleRate: Double = 44100

    override init(componentDescription: AudioComponentDescription, options: AudioComponentInstantiationOptions = []) throws {
        try super.init(componentDescription: componentDescription, options: options)
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
        inputBus = try AUAudioUnitBus(format: format)
        outputBus = try AUAudioUnitBus(format: format)
        _inputBusses = AUAudioUnitBusArray(audioUnit: self, busType: .input, busses: [inputBus])
        _outputBusses = AUAudioUnitBusArray(audioUnit: self, busType: .output, busses: [outputBus])
        delayBuffers = (0..<maxChannels).map { _ in Array(repeating: 0, count: delayBufferSize) }
        writeIndices = Array(repeating: 0, count: maxChannels)
    }

    override var inputBusses: AUAudioUnitBusArray { _inputBusses }
    override var outputBusses: AUAudioUnitBusArray { _outputBusses }

    override func allocateRenderResources() throws {
        try super.allocateRenderResources()
        sampleRate = inputBus.format.sampleRate
        delayBuffers = (0..<maxChannels).map { _ in Array(repeating: 0, count: delayBufferSize) }
        writeIndices = Array(repeating: 0, count: maxChannels)
        wowPhase = 0
        flutterPhase = 0
        noiseSeed = 12345
        lpfState = [0, 0]
    }

    override var internalRenderBlock: AUInternalRenderBlock {
        // Capture state for the render thread
        let delaySize = delayBufferSize

        return { [unowned self] actionFlags, timestamp, frameCount, outputBusNumber, outputData, renderEvent, pullInputBlock in

            guard let pullInputBlock = pullInputBlock else {
                return kAudioUnitErr_NoConnection
            }

            // Pull input audio
            var pullFlags: AudioUnitRenderActionFlags = []
            let status = pullInputBlock(&pullFlags, timestamp, frameCount, 0, outputData)
            guard status == noErr else { return status }

            let mix = self.mix
            guard mix > 0.001 else { return noErr } // Bypass when fully dry

            let frames = Int(frameCount)
            let sr = self.sampleRate

            // LFO rates
            let wowRate = 1.2 / sr       // ~1.2 Hz
            let flutterRate = 7.5 / sr    // ~7.5 Hz

            // Modulation depths in samples
            let wowDepth = 80.0 * Double(mix)
            let flutterDepth = 16.0 * Double(mix)
            let noiseDepth: Float = 2.0 * mix

            // Low-pass coefficient: more mix = more treble loss
            let lpfCoeff: Float = 1.0 - (0.4 * mix)  // 1.0 = no filter, 0.6 = noticeable roll-off

            let bufferListPtr = UnsafeMutableAudioBufferListPointer(outputData)

            let channelCount = min(bufferListPtr.count, self.maxChannels)

            for i in 0..<frames {
                // Advance LFOs once per sample (shared across channels)
                let wow = sin(self.wowPhase * .pi * 2) * wowDepth
                let flutter = sin(self.flutterPhase * .pi * 2) * flutterDepth

                self.wowPhase += wowRate
                if self.wowPhase >= 1.0 { self.wowPhase -= 1.0 }
                self.flutterPhase += flutterRate
                if self.flutterPhase >= 1.0 { self.flutterPhase -= 1.0 }

                // Noise once per sample
                self.noiseSeed = self.noiseSeed &* 1103515245 &+ 12345
                let noiseSample = Float(Int32(bitPattern: self.noiseSeed >> 1)) / Float(Int32.max)
                let noise = noiseSample * noiseDepth

                let totalDelay = 200.0 + wow + flutter + Double(noise)

                for ch in 0..<channelCount {
                    guard let data = bufferListPtr[ch].mData?.assumingMemoryBound(to: Float.self) else { continue }
                    let dry = data[i]

                    // Write into this channel's delay buffer
                    self.delayBuffers[ch][self.writeIndices[ch]] = dry

                    // Read from modulated position
                    let readPos = Double(self.writeIndices[ch]) - totalDelay
                    let readPosWrapped = ((readPos.truncatingRemainder(dividingBy: Double(delaySize))) + Double(delaySize))
                        .truncatingRemainder(dividingBy: Double(delaySize))

                    let low = Int(readPosWrapped)
                    let high = (low + 1) % delaySize
                    let frac = Float(readPosWrapped - Double(low))
                    let wet = self.delayBuffers[ch][low] * (1 - frac) + self.delayBuffers[ch][high] * frac

                    // One-pole low-pass (treble roll-off)
                    self.lpfState[ch] = lpfCoeff * wet + (1 - lpfCoeff) * self.lpfState[ch]

                    // Mix dry/wet
                    data[i] = dry * (1 - mix) + self.lpfState[ch] * mix

                    self.writeIndices[ch] = (self.writeIndices[ch] + 1) % delaySize
                }
            }

            return noErr
        }
    }

    /// Register this AU so it can be instantiated by component description.
    static let desc = AudioComponentDescription(
        componentType: kAudioUnitType_Effect,
        componentSubType: fourCC("tape"),
        componentManufacturer: fourCC("Brks"),
        componentFlags: 0,
        componentFlagsMask: 0
    )

    private static func fourCC(_ string: String) -> FourCharCode {
        var result: FourCharCode = 0
        for char in string.utf8.prefix(4) {
            result = (result << 8) | FourCharCode(char)
        }
        return result
    }

    static func register() {
        AUAudioUnit.registerSubclass(
            TapeEffectAU.self,
            as: desc,
            name: "Breaks: Tape",
            version: 1
        )
    }
}

// MARK: - PadVoice (lock-free, render-thread safe)

/// Holds per-pad audio state that the render thread reads directly.
/// Triggering a pad just resets the read position — zero latency.
final class PadVoice: @unchecked Sendable {
    /// Retained reference so the buffer memory stays alive while rendering.
    private var _buffer: AVAudioPCMBuffer?
    private var samples: UnsafePointer<Float>?
    private var sampleCount: Int = 0

    /// Current read position — written by trigger(), read by render().
    private(set) var readPosition: Double = 0
    private(set) var active: Bool = false

    /// Per-pad volume (0.0–1.0). Written from main thread, read from render thread.
    var volume: Float = 1.0

    /// Playback rate for varispeed pitch. 1.0 = normal, 2.0 = octave up, 0.5 = octave down.
    var rate: Double = 1.0

    var hasBuffer: Bool { _buffer != nil }

    var duration: Double {
        guard sampleCount > 0 else { return 0 }
        return Double(sampleCount) / (_buffer?.format.sampleRate ?? 44100)
    }

    func loadBuffer(_ buffer: AVAudioPCMBuffer?) {
        active = false
        _buffer = buffer
        samples = buffer.flatMap { UnsafePointer($0.floatChannelData?[0]) }
        sampleCount = buffer.map { Int($0.frameLength) } ?? 0
        readPosition = 0.0
    }

    func trigger() {
        readPosition = 0.0
        active = true
    }

    func stop() {
        active = false
    }

    /// Called on the real-time audio render thread.
    func render(into output: UnsafeMutablePointer<Float>, frameCount: Int) {
        guard active, let samples = samples else {
            output.update(repeating: 0, count: frameCount)
            return
        }

        let gain = volume
        let playbackRate = rate
        let maxPos = Double(sampleCount - 1)

        for i in 0..<frameCount {
            if readPosition >= maxPos {
                // Zero-fill remainder and stop
                output.advanced(by: i).update(repeating: 0, count: frameCount - i)
                active = false
                return
            }

            // Linear interpolation between adjacent samples
            let low = Int(readPosition)
            let high = min(low + 1, sampleCount - 1)
            let frac = Float(readPosition - Double(low))
            output[i] = (samples[low] * (1 - frac) + samples[high] * frac) * gain

            readPosition += playbackRate
        }
    }
}

// MARK: - AudioEngine

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
    var padVolumes: [Float]           // 0.0–1.0
    var padPitchSemitones: [Float]    // -12 to +12
    var padDurations: [Double]            // total duration in seconds
    var padReversed: [Bool]               // whether pad audio is reversed
    var isRecording = false
    var recordingPadIndex: Int? = nil

    // MARK: - Sequencer State
    var barCount: Int = 1             // 1–4 bars
    var stepCount: Int { barCount * 16 }
    var pattern: [[Bool]]             // pattern[pad][step], 8×N
    var bpm: Double = 120.0
    var sequencerPlaying = false
    var sequencerCurrentStep = 0

    // MARK: - EQ State (7-band)
    let eqFrequencies: [Float] = [60, 230, 910, 3600, 7200, 12000, 16000]
    let eqLabels = ["60", "230", "910", "3.6k", "7.2k", "12k", "16k"]
    var eqGains: [Float] = [0, 0, 0, 0, 0, 0, 0] // -12 to +12 dB

    // MARK: - Mixer State
    var tapeMix: Float = 0.0

    // MARK: - Audio Engine
    private var engine = AVAudioEngine()
    private var voices: [PadVoice] = []
    private var sourceNodes: [AVAudioSourceNode] = []
    private var padBuffers: [AVAudioPCMBuffer?] = []       // full (untrimmed) buffers for waveform/trim editing
    private var eqNode: AVAudioUnitEQ?
    private var tapeEffect: AVAudioUnit?
    private var tapeAU: TapeEffectAU?
    private var submixer: AVAudioMixerNode?
    private var engineSampleRate: Double = 44100
    private var playerFormat: AVAudioFormat!

    // Recording
    private var recordingFile: AVAudioFile?
    private var recordingURL: URL?
    private var inputTap = false

    // Sequencer timing
    private let sequencerQueue = DispatchQueue(label: "com.breaks.sequencer", qos: .userInteractive)
    private var sequencerOrigin: DispatchTime = .now()
    private var sequencerStepIndex: Int = 0
    private var sequencerGeneration: Int = 0

    // Pad colors (TR-808)
    let padColors: [Color] = TR808.padColors

    init() {
        padLabels = (1...8).map { "PAD \($0)" }
        padHasAudio = Array(repeating: false, count: 8)
        padIsPlaying = Array(repeating: false, count: 8)
        padWaveforms = Array(repeating: [], count: 8)
        padStartPoints = Array(repeating: 0, count: 8)
        padEndPoints = Array(repeating: 1, count: 8)
        padVolumes = Array(repeating: 1.0, count: 8)
        padPitchSemitones = Array(repeating: 0, count: 8)
        padDurations = Array(repeating: 0, count: 8)
        padReversed = Array(repeating: false, count: 8)
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
        engineSampleRate = format.sampleRate > 0 ? format.sampleRate : 44100
        let stereoFormat = AVAudioFormat(standardFormatWithSampleRate: engineSampleRate, channels: 2)!
        let monoFormat = AVAudioFormat(standardFormatWithSampleRate: engineSampleRate, channels: 1)!
        playerFormat = monoFormat

        // Submixer for all pads
        let sub = AVAudioMixerNode()
        engine.attach(sub)
        submixer = sub

        // Create 8 source nodes with render callbacks (replaces AVAudioPlayerNode)
        for _ in 0..<padCount {
            let voice = PadVoice()
            voices.append(voice)

            let sourceNode = AVAudioSourceNode(format: monoFormat) { [voice] _, _, frameCount, audioBufferList -> OSStatus in
                let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
                let output = ablPointer[0].mData!.assumingMemoryBound(to: Float.self)
                voice.render(into: output, frameCount: Int(frameCount))
                return noErr
            }
            sourceNodes.append(sourceNode)
            engine.attach(sourceNode)
            engine.connect(sourceNode, to: sub, format: monoFormat)
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

        // Tape effect
        TapeEffectAU.register()
        let tapeNode = AVAudioUnitEffect(audioComponentDescription: TapeEffectAU.desc)
        tapeEffect = tapeNode
        tapeAU = tapeNode.auAudioUnit as? TapeEffectAU
        engine.attach(tapeNode)

        // Signal chain: submixer -> EQ -> tape -> mainMixer
        engine.connect(sub, to: eq, format: stereoFormat)
        engine.connect(eq, to: tapeNode, format: stereoFormat)
        engine.connect(tapeNode, to: mainMixer, format: stereoFormat)

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

    func rebuildTrimmedBuffer(for index: Int) {
        guard index < padCount, let fullBuffer = padBuffers[index] else {
            voices[index].loadBuffer(nil)
            return
        }
        let totalFrames = Int(fullBuffer.frameLength)
        let startFrame = Int(Float(totalFrames) * padStartPoints[index])
        let endFrame = Int(Float(totalFrames) * padEndPoints[index])
        let trimmedLength = max(1, endFrame - startFrame)

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: playerFormat,
            frameCapacity: AVAudioFrameCount(trimmedLength)
        ) else { return }
        buffer.frameLength = AVAudioFrameCount(trimmedLength)

        let srcData = fullBuffer.floatChannelData![0]
        let dstData = buffer.floatChannelData![0]
        for i in 0..<trimmedLength {
            let srcIdx = startFrame + i
            dstData[i] = srcIdx < totalFrames ? srcData[srcIdx] : 0
        }

        // Apply short fade in/out to prevent clicks (~64 samples ≈ 1.5ms at 44.1kHz)
        let fadeSamples = min(16, trimmedLength / 2)
        for i in 0..<fadeSamples {
            let gain = Float(i) / Float(fadeSamples)
            dstData[i] *= gain
            dstData[trimmedLength - 1 - i] *= gain
        }

        voices[index].loadBuffer(buffer)
    }

    private func rebuildAllTrimmedBuffers() {
        for i in 0..<padCount where padBuffers[i] != nil {
            rebuildTrimmedBuffer(for: i)
        }
    }

    func triggerPad(_ index: Int) {
        guard index < padCount else { return }
        let voice = voices[index]
        if !voice.hasBuffer {
            rebuildTrimmedBuffer(for: index)
        }
        guard voice.hasBuffer else { return }
        ensureEngineRunning()
        // Just reset the read position — the render callback is already
        // running on the audio thread, so playback starts on the very
        // next audio buffer with zero scheduling overhead.
        voice.trigger()
        padIsPlaying[index] = true

        // Schedule UI reset when sample finishes
        let dur = voice.duration
        DispatchQueue.main.asyncAfter(deadline: .now() + dur) { [weak self] in
            guard let self else { return }
            if !self.voices[index].active {
                self.padIsPlaying[index] = false
            }
        }
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

            // Rebuild all existing trimmed buffers after engine restart
            self.rebuildAllTrimmedBuffers()

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
            let frameCount = AVAudioFrameCount(file.length)
            guard let fileBuffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frameCount) else { return }
            try file.read(into: fileBuffer)

            // Target format: mono float at the engine's sample rate
            let engineRate = engineSampleRate

            // Convert to mono standard float at file's sample rate first
            let fileMonoFormat = AVAudioFormat(standardFormatWithSampleRate: file.processingFormat.sampleRate, channels: 1)!
            let monoBuffer: AVAudioPCMBuffer

            if file.processingFormat.channelCount > 1 {
                guard let mb = AVAudioPCMBuffer(pcmFormat: fileMonoFormat, frameCapacity: frameCount) else { return }
                mb.frameLength = fileBuffer.frameLength
                let monoData = mb.floatChannelData![0]
                let leftData = fileBuffer.floatChannelData![0]
                let rightData = fileBuffer.floatChannelData![1]
                for i in 0..<Int(fileBuffer.frameLength) {
                    monoData[i] = (leftData[i] + rightData[i]) * 0.5
                }
                monoBuffer = mb
            } else if file.processingFormat != fileMonoFormat {
                // Convert to standard float if needed (e.g. Int16 files)
                guard let mb = AVAudioPCMBuffer(pcmFormat: fileMonoFormat, frameCapacity: frameCount) else { return }
                guard let converter = AVAudioConverter(from: file.processingFormat, to: fileMonoFormat) else { return }
                mb.frameLength = frameCount
                try converter.convert(to: mb, from: fileBuffer)
                monoBuffer = mb
            } else {
                monoBuffer = fileBuffer
            }

            // Resample to engine rate if needed
            if file.processingFormat.sampleRate != engineRate {
                if let resampled = resample(buffer: monoBuffer, from: file.processingFormat.sampleRate, to: engineRate) {
                    padBuffers[padIndex] = resampled
                } else {
                    padBuffers[padIndex] = monoBuffer
                }
            } else {
                padBuffers[padIndex] = monoBuffer
            }

            let waveform = self.generateWaveform(from: self.padBuffers[padIndex]!)

            self.rebuildTrimmedBuffer(for: padIndex)

            DispatchQueue.main.async {
                self.padHasAudio[padIndex] = true
                self.padWaveforms[padIndex] = waveform
                self.padStartPoints[padIndex] = 0
                self.padEndPoints[padIndex] = 1
                self.padDurations[padIndex] = self.voices[padIndex].duration
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

    func updatePadVolume(_ index: Int, volume: Float) {
        guard index < padCount else { return }
        padVolumes[index] = volume
        voices[index].volume = volume
    }

    func updatePadPitch(_ index: Int, semitones: Float) {
        guard index < padCount else { return }
        padPitchSemitones[index] = semitones
        voices[index].rate = pow(2.0, Double(semitones) / 12.0)
    }

    func clearPad(_ index: Int) {
        guard index < padCount else { return }
        voices[index].loadBuffer(nil)
        padBuffers[index] = nil
        padHasAudio[index] = false
        padWaveforms[index] = []
        padStartPoints[index] = 0
        padEndPoints[index] = 1
        padDurations[index] = 0
        padLabels[index] = "PAD \(index + 1)"
        padVolumes[index] = 1.0
        voices[index].volume = 1.0
        padPitchSemitones[index] = 0
        voices[index].rate = 1.0
        padReversed[index] = false
        padIsPlaying[index] = false
    }

    func reversePad(_ index: Int) {
        guard index < padCount, let fullBuffer = padBuffers[index] else { return }
        let frameCount = Int(fullBuffer.frameLength)
        guard frameCount > 1 else { return }

        DispatchQueue.global(qos: .userInitiated).async { [self] in
            let data = fullBuffer.floatChannelData![0]
            // Reverse sample data in-place
            for i in 0..<frameCount / 2 {
                let j = frameCount - 1 - i
                let tmp = data[i]
                data[i] = data[j]
                data[j] = tmp
            }

            // Flip start/end points so the trim region stays on the same audio
            let newStart = 1.0 - self.padEndPoints[index]
            let newEnd = 1.0 - self.padStartPoints[index]

            // Reverse the waveform display data (no need to regenerate)
            let reversedWaveform = self.padWaveforms[index].reversed() as [Float]

            // Rebuild trimmed buffer off main thread
            self.rebuildTrimmedBuffer(for: index)

            DispatchQueue.main.async {
                self.padReversed[index].toggle()
                self.padStartPoints[index] = newStart
                self.padEndPoints[index] = newEnd
                self.padWaveforms[index] = reversedWaveform
            }
        }
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
        sequencerStepIndex = 0
        sequencerGeneration += 1
        sequencerOrigin = .now()
        let gen = sequencerGeneration
        sequencerQueue.async { [weak self] in
            self?.sequencerTick(generation: gen)
        }
    }

    func stopSequencer() {
        sequencerPlaying = false
        sequencerGeneration += 1
        sequencerCurrentStep = 0
    }

    private func sequencerTick(generation: Int) {
        guard sequencerPlaying, generation == sequencerGeneration else { return }

        let step = sequencerCurrentStep
        for pad in 0..<padCount {
            if pattern[pad][step] && padHasAudio[pad] {
                triggerPad(pad)
            }
        }

        let nextStep = (step + 1) % stepCount
        DispatchQueue.main.async {
            self.sequencerCurrentStep = nextStep
        }

        // Schedule the next tick at an absolute deadline to prevent drift.
        sequencerStepIndex += 1
        let stepInterval = 60.0 / bpm / 4.0
        let nextDeadline = sequencerOrigin + stepInterval * Double(sequencerStepIndex)
        let gen = generation
        sequencerQueue.asyncAfter(deadline: nextDeadline) { [weak self] in
            self?.sequencerTick(generation: gen)
        }
    }

    func updateBPM(_ newBPM: Double) {
        bpm = newBPM
        if sequencerPlaying {
            sequencerOrigin = .now()
            sequencerStepIndex = 1
        }
    }

    func toggleStep(pad: Int, step: Int) {
        guard pad < padCount, step < stepCount else { return }
        pattern[pad][step].toggle()
    }

    func clearPattern() {
        for pad in 0..<padCount {
            for step in 0..<stepCount {
                pattern[pad][step] = false
            }
        }
    }

    func setBarCount(_ newCount: Int) {
        let clamped = max(1, min(4, newCount))
        let newStepCount = clamped * 16
        let oldStepCount = pattern.isEmpty ? 0 : pattern[0].count

        if newStepCount == oldStepCount { return }

        for pad in 0..<padCount {
            if newStepCount > oldStepCount {
                pattern[pad].append(contentsOf: Array(repeating: false, count: newStepCount - oldStepCount))
            } else {
                pattern[pad] = Array(pattern[pad].prefix(newStepCount))
            }
        }
        barCount = clamped

        if sequencerCurrentStep >= newStepCount {
            sequencerCurrentStep = 0
        }
    }

    // MARK: - Bundled Sounds

    struct BundledSound: Identifiable, Hashable {
        let id: String
        let name: String
        let url: URL
    }

    static var bundledSounds: [BundledSound] {
        guard let urls = Bundle.main.urls(forResourcesWithExtension: "wav", subdirectory: nil) else {
            return []
        }
        return urls
            .map { url in
                let name = url.deletingPathExtension().lastPathComponent
                return BundledSound(id: name, name: name, url: url)
            }
            .sorted { $0.name < $1.name }
    }

    func loadBundledSound(_ sound: BundledSound, intoPad padIndex: Int) {
        loadAudioFile(url: sound.url, intoPad: padIndex)
    }

    // MARK: - EQ Controls

    func updateEQ(band: Int, gain: Float) {
        guard let eq = eqNode, band < eq.bands.count else { return }
        eqGains[band] = gain
        eq.bands[band].gain = gain
    }

    // MARK: - Mixer Controls

    func updateTapeMix(_ value: Float) {
        tapeMix = value
        tapeAU?.mix = value
    }

    // MARK: - Export

    var isExporting = false
    var exportedFileURL: URL?

    func exportPattern(filename: String? = nil, completion: @escaping (URL?) -> Void) {
        guard !isExporting else { completion(nil); return }
        isExporting = true

        // Snapshot current state for the background thread
        let bpm = self.bpm
        let stepCount = self.stepCount
        let padCount = self.padCount
        let pattern = self.pattern
        let eqGains = self.eqGains
        let eqFrequencies = self.eqFrequencies
        let tapeMix = self.tapeMix
        let sampleRate = self.engineSampleRate

        // Snapshot per-pad state and buffers (nil = pad has no audio)
        var padSnapshots: [(buffer: AVAudioPCMBuffer, volume: Float, rate: Double)?] = []
        for i in 0..<padCount {
            guard padHasAudio[i], i < voices.count, voices[i].hasBuffer,
                  let fullBuffer = padBuffers[i] else {
                padSnapshots.append(nil)
                continue
            }
            let totalFrames = Int(fullBuffer.frameLength)
            let startFrame = Int(Float(totalFrames) * padStartPoints[i])
            let endFrame = Int(Float(totalFrames) * padEndPoints[i])
            let trimmedLength = max(1, endFrame - startFrame)

            let fmt = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
            guard let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(trimmedLength)) else {
                padSnapshots.append(nil)
                continue
            }
            buf.frameLength = AVAudioFrameCount(trimmedLength)
            let srcData = fullBuffer.floatChannelData![0]
            let dstData = buf.floatChannelData![0]
            for j in 0..<trimmedLength {
                let srcIdx = startFrame + j
                dstData[j] = srcIdx < totalFrames ? srcData[srcIdx] : 0
            }
            let fadeSamples = min(16, trimmedLength / 2)
            for j in 0..<fadeSamples {
                let gain = Float(j) / Float(fadeSamples)
                dstData[j] *= gain
                dstData[trimmedLength - 1 - j] *= gain
            }

            padSnapshots.append((buf, padVolumes[i], pow(2.0, Double(padPitchSemitones[i]) / 12.0)))
        }

        let exportFilename = filename

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let url = self?.performOfflineRender(
                bpm: bpm,
                stepCount: stepCount,
                padCount: padCount,
                pattern: pattern,
                padSnapshots: padSnapshots,
                eqGains: eqGains,
                eqFrequencies: eqFrequencies,
                tapeMix: tapeMix,
                sampleRate: sampleRate,
                filename: exportFilename
            )
            DispatchQueue.main.async {
                self?.isExporting = false
                self?.exportedFileURL = url
                completion(url)
            }
        }
    }

    private func performOfflineRender(
        bpm: Double,
        stepCount: Int,
        padCount: Int,
        pattern: [[Bool]],
        padSnapshots: [(buffer: AVAudioPCMBuffer, volume: Float, rate: Double)?],
        eqGains: [Float],
        eqFrequencies: [Float],
        tapeMix: Float,
        sampleRate: Double,
        filename: String? = nil
    ) -> URL? {
        let maxFrames: AVAudioFrameCount = 4096
        let monoFormat = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let stereoFormat = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!

        // Build offline engine — must enable manual rendering BEFORE connecting nodes
        let offlineEngine = AVAudioEngine()
        do {
            try offlineEngine.enableManualRenderingMode(.offline, format: stereoFormat, maximumFrameCount: maxFrames)
        } catch {
            print("Offline engine setup error: \(error)")
            return nil
        }

        // Create voices and source nodes for offline rendering
        var offlineVoices: [PadVoice] = []
        let sub = AVAudioMixerNode()
        offlineEngine.attach(sub)

        for i in 0..<padCount {
            let voice = PadVoice()
            if let snap = padSnapshots[i] {
                voice.loadBuffer(snap.buffer)
                voice.volume = snap.volume
                voice.rate = snap.rate
            }
            offlineVoices.append(voice)

            let sourceNode = AVAudioSourceNode(format: monoFormat) { [voice] _, _, frameCount, audioBufferList -> OSStatus in
                let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
                let output = ablPointer[0].mData!.assumingMemoryBound(to: Float.self)
                voice.render(into: output, frameCount: Int(frameCount))
                return noErr
            }
            offlineEngine.attach(sourceNode)
            offlineEngine.connect(sourceNode, to: sub, format: monoFormat)
        }

        // EQ
        let eq = AVAudioUnitEQ(numberOfBands: eqFrequencies.count)
        for (i, freq) in eqFrequencies.enumerated() {
            let band = eq.bands[i]
            band.filterType = .parametric
            band.frequency = freq
            band.bandwidth = 1.0
            band.gain = eqGains[i]
            band.bypass = false
        }
        offlineEngine.attach(eq)

        // Tape effect
        let tapeNode = AVAudioUnitEffect(audioComponentDescription: TapeEffectAU.desc)
        offlineEngine.attach(tapeNode)
        (tapeNode.auAudioUnit as? TapeEffectAU)?.mix = tapeMix

        // Signal chain: sub -> EQ -> tape -> mainMixer
        let mainMixer = offlineEngine.mainMixerNode
        offlineEngine.connect(sub, to: eq, format: stereoFormat)
        offlineEngine.connect(eq, to: tapeNode, format: stereoFormat)
        offlineEngine.connect(tapeNode, to: mainMixer, format: stereoFormat)

        do {
            try offlineEngine.start()
        } catch {
            print("Offline engine start error: \(error)")
            return nil
        }

        // Calculate total frames to render
        let stepInterval = 60.0 / bpm / 4.0
        let framesPerStep = Int(stepInterval * sampleRate)
        let longestPadDuration = padSnapshots.compactMap { snap -> Double? in
            guard let snap else { return nil }
            guard snap.buffer.frameLength > 0 else { return nil }
            return Double(snap.buffer.frameLength) / sampleRate / snap.rate
        }.max() ?? 0
        let tailFrames = Int(longestPadDuration * sampleRate)
        let totalFrames = framesPerStep * stepCount + tailFrames

        // Output file
        let safeName = filename ?? "Breaks_Export_\(Int(Date().timeIntervalSince1970))"
        let wavFilename = safeName.hasSuffix(".wav") ? safeName : "\(safeName).wav"
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(wavFilename)
        guard let outputFile = try? AVAudioFile(
            forWriting: outputURL,
            settings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: 2,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false
            ]
        ) else {
            print("Could not create output file")
            return nil
        }

        // Render loop — process step-by-step for accurate timing
        guard let renderBuffer = AVAudioPCMBuffer(pcmFormat: stereoFormat, frameCapacity: maxFrames) else {
            return nil
        }

        // Helper to render an exact number of frames (in chunks of maxFrames)
        func renderFrames(_ count: Int) -> Bool {
            var remaining = count
            while remaining > 0 {
                let chunk = min(AVAudioFrameCount(remaining), maxFrames)
                do {
                    let status = try offlineEngine.renderOffline(chunk, to: renderBuffer)
                    switch status {
                    case .success:
                        try outputFile.write(from: renderBuffer)
                    case .error:
                        return false
                    default:
                        break
                    }
                } catch {
                    print("Render error: \(error)")
                    return false
                }
                remaining -= Int(chunk)
            }
            return true
        }

        // Render each step: trigger pads, then render exactly framesPerStep
        for step in 0..<stepCount {
            for pad in 0..<padCount {
                if pattern[pad][step], let snap = padSnapshots[pad], snap.buffer.frameLength > 0 {
                    offlineVoices[pad].trigger()
                }
            }
            if !renderFrames(framesPerStep) {
                offlineEngine.stop()
                return nil
            }
        }

        // Render tail so last triggered samples ring out
        if tailFrames > 0 {
            if !renderFrames(tailFrames) {
                offlineEngine.stop()
                return nil
            }
        }

        offlineEngine.stop()
        return outputURL
    }
}
