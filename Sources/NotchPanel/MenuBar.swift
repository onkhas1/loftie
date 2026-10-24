import AppKit
import SwiftUI

/// Приложения, которые живут в строке меню (фоновые, без иконки в Доке).
///
/// В macOS 26 все значки строки меню рисует «Пункт управления», поэтому трюки Bartender
/// хрупкие. Прятать значки — системной настройкой «Разрешить в строке меню»,
/// а Чёлка показывает эти приложения у себя и открывает их по клику.
final class MenuBarApps: ObservableObject {
    struct App: Identifiable {
        let id: String
        let name: String
        let url: URL
        let icon: NSImage
        let tint: Color

        /// Иконка 16×16 для пункта меню
        var menuIcon: NSImage {
            let small = icon.copy() as! NSImage
            small.size = NSSize(width: 16, height: 16)
            return small
        }
    }

    @Published var apps: [App] = []

    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension")!

    func refresh() {
        let own = Bundle.main.bundleIdentifier
        let home = NSHomeDirectory() + "/Applications/"
        apps = NSWorkspace.shared.runningApplications
            .filter { app in
                guard app.activationPolicy == .accessory, app.bundleIdentifier != own,
                      let path = app.bundleURL?.path else { return false }
                // Только установленные программы, без системных служб и вспомогательных процессов
                guard path.hasPrefix("/Applications/") || path.hasPrefix(home) else { return false }
                return !path.contains("/Frameworks/") && app.bundleIdentifier?.hasSuffix(".helper") != true
            }
            .compactMap { (app: NSRunningApplication) -> App? in
                guard let url = app.bundleURL, let id = app.bundleIdentifier else { return nil }
                let name = app.localizedName ?? url.deletingPathExtension().lastPathComponent
                let icon = app.icon ?? NSWorkspace.shared.icon(forFile: url.path)
                return App(id: id, name: name, url: url, icon: icon, tint: Self.averageColor(of: icon))
            }
            .reduce(into: [App]()) { (list: inout [App], app: App) in
                if !list.contains(where: { $0.id == app.id }) { list.append(app) }
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Средний цвет иконки, чтобы подкрасить плитку приложения
    private static func averageColor(of image: NSImage) -> Color {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1, pixelsHigh: 1, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 4, bitsPerPixel: 32) else { return Palette.blue }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: 1, height: 1))
        NSGraphicsContext.restoreGraphicsState()
        guard let color = rep.colorAt(x: 0, y: 0), color.alphaComponent > 0.1 else { return Palette.blue }
        // Убираем прозрачность и чуть поднимаем насыщенность, чтобы не было грязи
        let a = color.alphaComponent
        let base = NSColor(red: color.redComponent / a, green: color.greenComponent / a, blue: color.blueComponent / a, alpha: 1)
        var h: CGFloat = 0, sat: CGFloat = 0, b: CGFloat = 0
        base.usingColorSpace(.deviceRGB)?.getHue(&h, saturation: &sat, brightness: &b, alpha: nil)
        return Color(hue: h, saturation: min(1, sat * 1.3 + 0.1), brightness: max(0.6, b))
    }

    /// Повторный запуск уже работающего приложения: обычно оно показывает своё окно или панель.
    func open(_ app: App) {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: app.url, configuration: config)
    }
}

