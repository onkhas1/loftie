import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255, blue: Double(hex & 0xff) / 255)
    }
}

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
                  blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
    }

    /// Цвет, который сам выбирает вариант под тёмную или светлую тему
    static func adaptive(dark: NSColor, light: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        }
    }
}

private func adaptive(_ dark: NSColor, _ light: NSColor) -> Color {
    Color(nsColor: .adaptive(dark: dark, light: light))
}

/// «Графит и свет»: в тёмной теме графит и пастель, в светлой — молочный фон и насыщенные
/// цвета разделов, чтобы читались на белом. Цвет живёт в свете, кольцах и тонких линиях.
enum Palette {
    static let groundTop = adaptive(NSColor(hex: 0x1C1D22), NSColor(hex: 0xFAFAFC))
    static let groundBottom = adaptive(NSColor(hex: 0x111216), NSColor(hex: 0xEDEEF2))

    static let text = adaptive(NSColor(hex: 0xF2F3F5), NSColor(hex: 0x17181C))
    static let secondary = adaptive(NSColor(white: 1, alpha: 0.6), NSColor(white: 0, alpha: 0.58))
    static let tertiary = adaptive(NSColor(white: 1, alpha: 0.38), NSColor(white: 0, alpha: 0.4))
    static let card = adaptive(NSColor(white: 1, alpha: 0.05), NSColor(white: 0, alpha: 0.045))
    static let cardHover = adaptive(NSColor(white: 1, alpha: 0.09), NSColor(white: 0, alpha: 0.08))
    static let hairline = adaptive(NSColor(white: 1, alpha: 0.07), NSColor(white: 0, alpha: 0.09))
    /// Поля ввода
    static let field = adaptive(NSColor(white: 0, alpha: 0.25), NSColor(white: 0, alpha: 0.055))
    /// Дорожки шкал и прогресса
    static let track = adaptive(NSColor(white: 1, alpha: 0.08), NSColor(white: 0, alpha: 0.08))
    /// Выпадающие меню
    static let popover = adaptive(NSColor(hex: 0x24262C), NSColor(hex: 0xFFFFFF))
    /// Текст на залитых цветом кнопках
    static let onAccent = adaptive(NSColor(hex: 0x15121F), NSColor(hex: 0xFFFFFF))

    static let blue = adaptive(NSColor(hex: 0x7AA7FF), NSColor(hex: 0x3B78F5))
    static let pink = adaptive(NSColor(hex: 0xFF8FB1), NSColor(hex: 0xE2457A))
    static let lilac = adaptive(NSColor(hex: 0xB69CFF), NSColor(hex: 0x8660EC))
    static let mint = adaptive(NSColor(hex: 0x5FD4B0), NSColor(hex: 0x14A07B))
    static let cyan = adaptive(NSColor(hex: 0x67D1E6), NSColor(hex: 0x1597BF))
    static let coral = adaptive(NSColor(hex: 0xFF7A7A), NSColor(hex: 0xE0483F))
}

/// Режим отладочного рендера.
enum Snapshot {
    static var isOn = false
}

extension NotchModel.Page {
    var accent: Color {
        switch self {
        case .home: Palette.blue
        case .favorites: Palette.pink
        case .music: Palette.lilac
        case .note: Palette.mint
        }
    }
}

/// Значок в тонком цветном кольце.
struct IconRing: View {
    let icon: String
    let color: Color
    var size: CGFloat = 30

    var body: some View {
        Circle()
            .fill(color.opacity(0.12))
            .overlay(Circle().strokeBorder(color.opacity(0.55), lineWidth: 1.2))
            .frame(width: size, height: size)
            .overlay(Image(systemName: icon).font(.system(size: size * 0.42, weight: .semibold)).foregroundStyle(color))
    }
}

struct RootView: View {
    @EnvironmentObject var model: NotchModel

    private let panelRadius: CGFloat = 22

    var body: some View {
        let expanded = model.expanded
        let pill = model.collapsedSize
        let panel = RoundedRectangle(cornerRadius: panelRadius, style: .continuous)
        let pages = NotchModel.Page.allCases
        let index = Double(pages.firstIndex(of: model.page) ?? 0)
        // Лампа: цветной свет над открытой вкладкой
        let lampX = 0.5 + (index - Double(pages.count - 1) / 2) * 0.13
        let lamp = model.showAbout ? Palette.pink : model.page.accent

        VStack(spacing: model.gap) {
            UnevenRoundedRectangle(bottomLeadingRadius: 12, bottomTrailingRadius: 12, style: .continuous)
                .fill(Color.black)
                .frame(width: pill.width, height: pill.height)
                .overlay { if model.showStatuses { CollapsedView() } }

            ZStack(alignment: .top) {
                LinearGradient(colors: [Palette.groundTop, Palette.groundBottom], startPoint: .top, endPoint: .bottom)
                EllipticalGradient(colors: [lamp.opacity(0.3), lamp.opacity(0.08), .clear],
                                   center: UnitPoint(x: lampX, y: 0), startRadiusFraction: 0, endRadiusFraction: 0.6)
                ExpandedView()
            }
            .frame(width: model.expandedSize.width, height: model.expandedSize.height)
            .clipShape(panel)
            .overlay(panel.strokeBorder(Palette.hairline, lineWidth: 1))
            .overlay(alignment: .topTrailing) {
                if model.settingsOpen {
                    SettingsDropdown()
                        .padding(.top, 44).padding(.trailing, 12)
                        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .topTrailing)))
                }
            }
            .shadow(color: .black.opacity(0.35), radius: 22, y: 12)
            .scaleEffect(expanded ? 1 : 0.6, anchor: .top)
            .opacity(expanded ? 1 : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.locale, Locale(identifier: "ru_RU"))
    }
}

// MARK: - Свёрнутая челка: статусы в «крыльях»

struct CollapsedView: View {
    @EnvironmentObject var model: NotchModel
    @EnvironmentObject var stats: SystemStats

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 10) {
                WingItem(icon: "internaldrive", text: Fmt.shortBytes(Double(stats.diskFree)))
                if case .size(let bytes) = stats.trash {
                    WingItem(icon: "trash", text: Fmt.shortBytes(Double(bytes)))
                }
            }
            .frame(width: model.leftWing)

            Color.clear.frame(width: model.notchSize.width)

            HStack(spacing: 10) {
                WingItem(icon: "arrow.down", text: Fmt.shortBytes(stats.down))
                WingItem(icon: "cpu", text: Fmt.percent(stats.cpu))
            }
            .frame(width: model.rightWingWidth)
        }
        .frame(height: model.notchSize.height)
    }
}

struct WingItem: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
            Text(text).font(.system(size: 11, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.9))
        }
        .lineLimit(1)
        .fixedSize()
    }
}

// MARK: - Открытая панель

struct ExpandedView: View {
    @EnvironmentObject var model: NotchModel
    @Namespace private var tabs

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                HStack(spacing: 4) {
                    ForEach(NotchModel.Page.allCases) { PageTab(page: $0, namespace: tabs) }
                }
                HStack(spacing: 12) {
                    HStack(spacing: 6) {
                        Circle().fill(model.showAbout ? Palette.pink : model.page.accent).frame(width: 7, height: 7)
                        Text("Loftie").font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.text)
                    }
                    Spacer()
                    Text(Date.now, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Palette.tertiary)
                    SettingsButton()
                }
            }
            .frame(height: 30)

            Group {
                if model.showAbout {
                    AboutPanel()
                } else {
                    switch model.page {
                    case .home: HomePage()
                    case .favorites: FavoritesPage()
                    case .music: MusicPage()
                    case .note: NotePage()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .transition(.opacity)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 16)
    }
}

/// Вкладка: текст и цветная черта под выбранной, черта переезжает между вкладками.
struct PageTab: View {
    @EnvironmentObject var model: NotchModel
    let page: NotchModel.Page
    let namespace: Namespace.ID
    @State private var hover = false

    var body: some View {
        let selected = model.page == page && !model.showAbout
        Button {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                model.showAbout = false
                model.page = page
            }
        } label: {
            Text(page.title)
                .font(.system(size: 13, weight: selected ? .semibold : .medium))
                .foregroundStyle(selected ? Palette.text : (hover ? Palette.secondary : Palette.tertiary))
                .fixedSize()
                .padding(.bottom, 8)
                .overlay(alignment: .bottom) {
                    if selected {
                        Capsule().fill(page.accent).frame(height: 2)
                            .matchedGeometryEffect(id: "underline", in: namespace)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

struct SettingsButton: View {
    @EnvironmentObject var model: NotchModel
    @State private var hover = false

    var body: some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { model.settingsOpen.toggle() }
        } label: {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 13))
                .foregroundStyle(model.settingsOpen || hover ? Palette.text : Palette.tertiary)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

/// Своё выпадающее меню: закрывается, когда курсор уходит с него.
struct SettingsDropdown: View {
    @EnvironmentObject var model: NotchModel
    @EnvironmentObject var menuBar: MenuBarApps
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var closeWork: DispatchWorkItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Скрыто из строки меню")
                .font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.tertiary)
                .padding(.horizontal, 8).padding(.bottom, 2)
            ForEach(menuBar.apps.prefix(5)) { app in
                DropdownRow(action: { close(); menuBar.open(app) }) {
                    Image(nsImage: app.icon).resizable().frame(width: 18, height: 18)
                    Text(app.name)
                }
            }
            DropdownRow(action: { close(); NSWorkspace.shared.open(MenuBarApps.settingsURL) }) {
                Image(systemName: "eye.slash").frame(width: 18)
                Text("Скрыть или вернуть значки…")
            }
            Divider().overlay(Palette.hairline).padding(.vertical, 3)
            HStack {
                Text("Тема")
                Spacer()
                HStack(spacing: 2) {
                    ForEach(Theme.allCases) { theme in
                        Button {
                            withAnimation(.easeOut(duration: 0.2)) { model.theme = theme }
                        } label: {
                            Text(theme.title)
                                .font(.system(size: 11, weight: model.theme == theme ? .semibold : .medium))
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Capsule().fill(model.theme == theme ? Palette.cardHover : .clear))
                                .foregroundStyle(model.theme == theme ? Palette.text : Palette.secondary)
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(2)
                .background(Capsule().fill(Palette.card))
            }
            .font(.system(size: 13))
            .foregroundStyle(Palette.text)
            .padding(.horizontal, 8).padding(.vertical, 3)
            HStack {
                Text("Статусы в челке")
                Spacer()
                Toggle("", isOn: $model.showStatuses).toggleStyle(.switch).controlSize(.mini).labelsHidden()
            }
            .font(.system(size: 13))
            .foregroundStyle(Palette.text)
            .padding(.horizontal, 8).padding(.vertical, 3)
            HStack {
                Text("Запускать при входе")
                Spacer()
                Toggle("", isOn: $launchAtLogin).toggleStyle(.switch).controlSize(.mini).labelsHidden()
            }
            .font(.system(size: 13))
            .foregroundStyle(Palette.text)
            .padding(.horizontal, 8).padding(.vertical, 3)
            DropdownRow(action: {
                close()
                withAnimation(.easeOut(duration: 0.2)) { model.showAbout = true }
            }) {
                Image(systemName: "info.circle").frame(width: 18)
                Text("О Loftie")
            }
            DropdownRow(action: { NSApp.terminate(nil) }) {
                Image(systemName: "power").frame(width: 18)
                Text("Выйти из Loftie")
            }
        }
        .padding(8)
        .frame(width: 280)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.popover))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Palette.hairline, lineWidth: 1))
        .shadow(color: .black.opacity(0.45), radius: 18, y: 10)
        .onHover { inside in
            closeWork?.cancel()
            guard !inside else { return }
            let work = DispatchWorkItem { close() }
            closeWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
        }
        .onChange(of: launchAtLogin) { _, on in
            LoginItem.set(on)
            launchAtLogin = LoginItem.isEnabled
        }
    }

    private func close() {
        withAnimation(.easeOut(duration: 0.15)) { model.settingsOpen = false }
    }
}

struct DropdownRow<Label: View>: View {
    let action: () -> Void
    @ViewBuilder var label: Label
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) { label }
                .font(.system(size: 13))
                .foregroundStyle(Palette.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(hover ? Palette.cardHover : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

/// Полка: мягкая подложка без рамки.
struct Shelf<Content: View>: View {
    var padding: CGFloat = 12
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.card))
    }
}
