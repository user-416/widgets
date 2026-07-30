#!/usr/bin/env swift
// Generates the Widgets app icon (1024×1024 PNG) — a 3×3 contribution-graph
// grid in shades of green on a dark teal background. Mirrors the design of
// `web/favicon.svg` but tuned for the iOS app-icon size and contrast.
//
// iOS 14+ accepts a single 1024×1024 image; Xcode auto-generates the smaller
// sizes at build time. We write to AppIcon.appiconset/AppIcon.png and update
// the Contents.json to reference it.
//
// Usage:
//   ./scripts/generate-app-icon.swift
// (Run from repo root; writes ios/Widgets/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png)

import AppKit
import CoreGraphics

let size: CGFloat = 1024
let bgColor = NSColor(red: 4/255, green: 47/255, blue: 36/255, alpha: 1) // deep forest green

// Same density pattern as web/favicon.svg.
// l0 = unlit (visible but very dim), l1..l4 increasing brightness.
let palette: [NSColor] = [
    NSColor(red: 16/255,  green:  60/255, blue:  46/255, alpha: 1), // l0 — barely-visible cell, like an unlit day
    NSColor(red: 167/255, green: 243/255, blue: 208/255, alpha: 1), // l1 — pale green
    NSColor(red:  52/255, green: 211/255, blue: 153/255, alpha: 1), // l2 — mid green
    NSColor(red:  16/255, green: 185/255, blue: 129/255, alpha: 1), // l3 — bright
    NSColor(red:   4/255, green: 120/255, blue:  87/255, alpha: 1), // l4 — deep
]

// 3×3 levels (top→bottom, left→right). Same shape as favicon.svg with one
// tweak: the corners are dimmer so the eye lands on the bright center.
let levels: [[Int]] = [
    [1, 2, 3],
    [3, 4, 3],
    [2, 3, 1],
]

let outDir = "ios/Widgets/Resources/Assets.xcassets/AppIcon.appiconset"
let outFile = "\(outDir)/AppIcon.png"

let img = NSImage(size: NSSize(width: size, height: size))
img.lockFocus()

// Background — solid color. iOS will round the corners with its own mask,
// so we don't draw the rounded corner ourselves.
bgColor.setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: size, height: size)).fill()

// Grid layout. Total grid takes ~70% of the icon, with margins around it.
let gridFraction: CGFloat = 0.72
let gridSize = size * gridFraction
let gridOrigin = (size - gridSize) / 2
let cellGap: CGFloat = gridSize * 0.06
let cellSize = (gridSize - 2 * cellGap) / 3
let cellRadius = cellSize * 0.18 // matches iOS app-icon corner-radius "feel"

for row in 0..<3 {
    for col in 0..<3 {
        let lvl = levels[row][col]
        let color = palette[max(0, min(palette.count - 1, lvl))]
        // CG y-axis points up; row 0 should be at the top, so flip.
        let visualRow = 2 - row
        let x = gridOrigin + CGFloat(col) * (cellSize + cellGap)
        let y = gridOrigin + CGFloat(visualRow) * (cellSize + cellGap)
        let rect = NSRect(x: x, y: y, width: cellSize, height: cellSize)
        let path = NSBezierPath(roundedRect: rect, xRadius: cellRadius, yRadius: cellRadius)
        color.setFill()
        path.fill()
    }
}

img.unlockFocus()

guard let tiff = img.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let pngData = bitmap.representation(using: .png, properties: [:]) else {
    fputs("Failed to encode PNG\n", stderr)
    exit(1)
}

try FileManager.default.createDirectory(
    atPath: outDir, withIntermediateDirectories: true
)
try pngData.write(to: URL(fileURLWithPath: outFile))
print("Wrote \(pngData.count) bytes → \(outFile)")

// Update Contents.json to reference the single-size icon (Xcode 14+ pattern).
let contentsJSON = """
{
  "images" : [
    {
      "filename" : "AppIcon.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
"""
try contentsJSON.write(
    toFile: "\(outDir)/Contents.json",
    atomically: true,
    encoding: .utf8
)
print("Wrote \(outDir)/Contents.json")
