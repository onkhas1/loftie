import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255, blue: Double(hex & 0xff) / 255)
    }
}

/// Графит и пастельные цвета разделов. Цвет живёт в свете лампы, кольцах и тонких шкалах, а не в заливках.
enum Palette {
    static let groundTop = Color(hex: 0x1C1D22)
    static let groundBottom = Color(hex: 0x111216)

    static let text = Color(hex: 0xF2F3F5)
    static let secondary = Color.white.opacity(0.6)
    static let tertiary = Color.white.opacity(0.38)
    static let card = Color.white.opacity(0.05)
    static let cardHover = Color.white.opacity(0.09)
    static let hairline = Color.white.opacity(0.07)

    static let blue = Color(hex: 0x7AA7FF)
    static let pink = Color(hex: 0xFF8FB1)
    static let lilac = Color(hex: 0xB69CFF)
    static let mint = Color(hex: 0x5FD4B0)
    static let cyan = Color(hex: 0x67D1E6)
    static let coral = Color(hex: 0xFF7A7A)
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

        VStack(spacing: model.gap) {
            UnevenRoundedRectangle(bottomLeadingRadius: 12, bottomTrailingRadius: 12, style: .continuous)
                .fill(Color.black)
                .frame(width: pill.width, height: pill.height)
                .overlay { if model.showStatuses { CollapsedView() } }

            ZStack(alignment: .top) {
                LinearGradient(colors: [Palette.groundTop, Palette.groundBottom], startPoint: .top, endPoint: .bottom)
                EllipticalGradient(colors: [model.page.accent.opacity(0.3), model.page.accent.opacity(0.08), .clear],
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
        .environment(\.colorScheme, .dark)
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
                .foregroundStyle(Palette.secondary)
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
                        Circle().fill(model.page.accent).frame(width: 7, height: 7)
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
                switch model.page {
                case .home: HomePage()
                case .favorites: FavoritesPage()
                case .music: MusicPage()
                case .note: NotePage()
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
        let selected = model.page == page
        Button {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) { model.page = page }
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
            ForEach(menuBar.apps) { app in
                DropdownRow(action: { close(); menuBar.open(app) }) {
                    Image(nsImage: app.icon).resizable().frame(width: 18, height: 18)
                    Text(app.name)
                }
            }
            DropdownRow(action: { close(); NSWorkspace.shared.open(MenuBarApps.settingsURL) }) {
                Image(systemName: "eye.slash").frame(width: 18)
                Text("Скрыть или вернуть значки…")
            }
            Divider().overlay(Palette.hairline).padding(.vertical, 4)
            HStack {
                Text("Статусы в челке")
                Spacer()
                Toggle("", isOn: $model.showStatuses).toggleStyle(.switch).controlSize(.mini).labelsHidden()
            }
            .font(.system(size: 13))
            .foregroundStyle(Palette.text)
            .padding(.horizontal, 8).padding(.vertical, 5)
            HStack {
                Text("Запускать при входе")
                Spacer()
                Toggle("", isOn: $launchAtLogin).toggleStyle(.switch).controlSize(.mini).labelsHidden()
            }
            .font(.system(size: 13))
            .foregroundStyle(Palette.text)
            .padding(.horizontal, 8).padding(.vertical, 5)
            DropdownRow(action: { close(); AppWindows.shared.showAbout() }) {
                Image(systemName: "info.circle").frame(width: 18)
                Text("О Loftie")
            }
            DropdownRow(action: { NSApp.terminate(nil) }) {
                Image(systemName: "power").frame(width: 18)
                Text("Выйти из Loftie")
            }
        }
        .padding(8)
        .frame(width: 250)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(hex: 0x24262C)))
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
                .padding(.horizontal, 8).padding(.vertical, 5)
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
