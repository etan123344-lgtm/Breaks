//
//  Theme.swift
//  Breaks
//
//  TR-808 inspired color scheme and typography
//

import SwiftUI

enum TR808 {
    // MARK: - Backgrounds
    static let bg = Color(red: 0.08, green: 0.08, blue: 0.09)           // near-black body
    static let surface = Color(red: 0.14, green: 0.13, blue: 0.14)      // panel surface
    static let surfaceLight = Color(red: 0.20, green: 0.19, blue: 0.20) // raised elements
    static let surfaceDim = Color(red: 0.10, green: 0.10, blue: 0.11)   // recessed areas

    // MARK: - Accent
    static let accent = Color(red: 0.91, green: 0.33, blue: 0.11)       // 808 orange-red
    static let accentDim = Color(red: 0.91, green: 0.33, blue: 0.11).opacity(0.3)

    // MARK: - Text
    static let silver = Color(red: 0.78, green: 0.77, blue: 0.75)       // main text
    static let silverDim = Color(red: 0.50, green: 0.49, blue: 0.47)    // secondary text
    static let cream = Color(red: 0.93, green: 0.90, blue: 0.83)        // display/readout text

    // MARK: - Step Colors (4 groups of 4)
    static let stepRed = Color(red: 0.90, green: 0.22, blue: 0.21)
    static let stepOrange = Color(red: 0.95, green: 0.55, blue: 0.15)
    static let stepYellow = Color(red: 0.95, green: 0.80, blue: 0.20)
    static let stepWhite = Color(red: 0.85, green: 0.84, blue: 0.82)

    static func stepColor(for step: Int) -> Color {
        switch step % 16 {
        case 0..<4:   return stepRed
        case 4..<8:   return stepOrange
        case 8..<12:  return stepYellow
        case 12..<16: return stepWhite
        default:      return stepWhite
        }
    }

    // MARK: - Pad Colors (warm 808 tones)
    static let padColors: [Color] = [
        Color(red: 0.90, green: 0.22, blue: 0.21), // Bass Drum - red
        Color(red: 0.95, green: 0.55, blue: 0.15), // Snare - orange
        Color(red: 0.95, green: 0.80, blue: 0.20), // Low Tom - yellow
        Color(red: 0.85, green: 0.84, blue: 0.82), // Mid Tom - white
        Color(red: 0.70, green: 0.35, blue: 0.15), // Hi Tom - brown
        Color(red: 0.80, green: 0.25, blue: 0.30), // Rimshot - dark red
        Color(red: 0.75, green: 0.65, blue: 0.40), // Clap - gold
        Color(red: 0.60, green: 0.58, blue: 0.55), // Hi-Hat - gray
    ]

    // MARK: - LED
    static let ledOn = Color(red: 1.0, green: 0.25, blue: 0.15)
    static let ledOff = Color(red: 0.25, green: 0.10, blue: 0.08)

    // MARK: - Typography helpers
    static func display(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    static func label(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    static func readout(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}
