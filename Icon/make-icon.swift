// Рисует иконку Loftie: графитовый квадрат macOS, чёрная челка, цветной свет лампы.
// Запуск: swift make-icon.swift <папка-вывода>  → AppIcon.iconset + AppIcon.icns
import AppKit
import SwiftUI

func color(_ hex: UInt32) -> Color {
    Color(red: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255, blue: Double(hex & 0xff) / 255)
}

struct Icon: View {
    var body: some View {
        let tile = RoundedRectangle(cornerRadius: 185, style: .continuous)
        ZStack {
            Color.clear
            ZStack(alignment: .top) {
                LinearGradient(colors: [color(0x2B2D35), color(0x121317)], startPoint: .top, endPoint: .bottom)
                // Свет лампы из-под челки: голубой → сиреневый → розовый
                EllipticalGradient(colors: [color(0x7AA7FF).opacity(0.85), color(0xB69CFF).opacity(0.45),
                                            color(0xFF8FB1).opacity(0.18), .clear],
                                   center: UnitPoint(x: 0.5, y: 0.13), startRadiusFraction: 0, endRadiusFraction: 0.62)
                // Челка
                UnevenRoundedRectangle(bottomLeadingRadius: 44, bottomTrailingRadius: 44, style: .continuous)
                    .fill(Color.black)
                    .frame(width: 330, height: 108)
                // Четыре вкладки — четыре цветные точки
                HStack(spacing: 46) {
                    ForEach([0x7AA7FF, 0xFF8FB1, 0xB69CFF, 0x5FD4B0] as [UInt32], id: \.self) { hex in
                        Circle().fill(color(hex)).frame(width: 46, height: 46)
                            .shadow(color: color(hex).opacity(0.7), radius: 18)
                    }
                }
                .padding(.top, 560)
            }
            .frame(width: 824, height: 824)
            .clipShape(tile)
            .overlay(tile.strokeBorder(Color.white.opacity(0.08), lineWidth: 3))
            .shadow(color: .black.opacity(0.35), radius: 20, y: 12)
        }
        .frame(width: 1024, height: 1024)
    }
}

let out = URL(fileURLWithPath: CommandLine.arguments[1])
let iconset = out.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

MainActor.assumeIsolated {
    let renderer = ImageRenderer(content: Icon())
    renderer.scale = 1
    guard let cg = renderer.cgImage else { fatalError("render failed") }
    let base = NSBitmapImageRep(cgImage: cg)
    for size in [16, 32, 128, 256, 512] {
        for scale in [1, 2] {
            let px = size * scale
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                                       samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                       colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            NSGraphicsContext.current?.imageInterpolation = .high
            base.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
            NSGraphicsContext.restoreGraphicsState()
            let name = scale == 1 ? "icon_\(size)x\(size).png" : "icon_\(size)x\(size)@2x.png"
            try! rep.representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent(name))
        }
    }
    try! base.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent("AppIcon-1024.png"))
}
