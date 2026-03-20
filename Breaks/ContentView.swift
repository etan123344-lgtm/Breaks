//
//  ContentView.swift
//  Breaks
//
//  Created by Ethan Zhou on 3/18/26.
//

import SwiftUI

struct ContentView: View {
    @State private var engine = AudioEngine()

    var body: some View {
        TabView {
            Tab("Sequencer", systemImage: "square.grid.4x3.fill") {
                SequencerView(engine: engine)
            }

            Tab("EQ", systemImage: "slider.vertical.3") {
                EqualizerView(engine: engine)
            }

            Tab("Mixer", systemImage: "dial.low.fill") {
                MixerView(engine: engine)
            }
        }
        .tint(.orange)
    }
}

#Preview {
    ContentView()
}
