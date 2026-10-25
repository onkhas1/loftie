import AppKit
import Combine
import SwiftUI

/// Тема оформления: как в системе, светлая или тёмная.
enum Theme: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "Авто"
        case .light: "Светлая"
        case .dark: "Тёмная"
        }
    }

    var appearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }

    static var current: Theme {
        Theme(rawValue: UserDefaults.standard.string(forKey: "theme") ?? "") ?? .system
    }
}

/// Общее состояние панели: свёрнута или открыта, размеры челки.
final class NotchModel: ObservableObject {
    enum Page: String, CaseIterable, Identifiable {
        case home, favorites, music, note
        var id: String { rawValue }
        var title: String {
            switch self {
            case .home: "Главная"
            case .favorites: "Избранное"
            case .music: "Музыка"
            case .note: "Запись"
            }
        }
        var icon: String {
            switch self {
            case .home: "square.grid.2x2"
            case .favorites: "star"
            case .music: "music.note"
            case .note: "mic"
            }
        }
    }

    @Published var expanded = false
    @Published var page: Page = .home {
        didSet { settingsOpen = false; showAbout = false }
    }
    /// «О Loftie» открыто прямо в панели вместо текущей вкладки
    @Published var showAbout = false
    /// Открыто выпадающее меню шестерёнки
    @Published var settingsOpen = false
    @Published var theme = Theme.current {
        didSet { UserDefaults.standard.set(theme.rawValue, forKey: "theme") }
    }
    /// Статусы по бокам от челки; без них пилюля шириной с саму челку
    @Published var showStatuses = UserDefaults.standard.object(forKey: "showStatuses") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showStatuses, forKey: "showStatuses") }
    }
    @Published var notchSize = CGSize(width: 185, height: 32)
    /// Пока true, панель не сворачивается от ухода курсора (идёт ввод текста, открыта форма).
    var pinned = false
    /// Открыто системное окно выбора файла. Оно живёт в отдельном процессе macOS,
    /// поэтому клики в нём выглядят как клики мимо панели — их нельзя считать уходом.
    var pickingFile = false

    let expandedSize = CGSize(width: 680, height: 256)
    /// Зазор между челкой и открытой панелью
    let gap: CGFloat = 8
    let leftWing: CGFloat = 104
    let rightWingWidth: CGFloat = 104
    var collapsedSize: CGSize {
        let wings = showStatuses ? leftWing + rightWingWidth : 0
        return CGSize(width: notchSize.width + wings, height: notchSize.height)
    }
    /// Сдвиг пилюли относительно центра челки, когда крылья разной ширины
    var pillOffset: CGFloat { (rightWingWidth - leftWing) / 2 }
}

final class NotchPanel: NSPanel {
    init(frame: NSRect) {
        super.init(contentRect: frame,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isMovable = false
        hidesOnDeactivate = false
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // По умолчанию macOS сдвигает окна ниже строки меню, а нам нужно ровно у верхнего края
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// Держит окно, следит за курсором и открывает/закрывает панель.
final class NotchController: NSObject {
    let model = NotchModel()
    let stats = SystemStats()
    let favorites = FavoritesStore()
    let media = MediaController()
    let reminders = RemindersStore()
    let menuBar = MenuBarApps()
    let clipboard = ClipboardHistory()
    let voice = VoiceNote()

    private var panel: NotchPanel!
    private var monitors: [Any] = []
    private var hoverWork: DispatchWorkItem?
    private var leaveWork: DispatchWorkItem?
    private var notchCenterX: CGFloat = 0
    private var screenTop: CGFloat = 0
    private var menuOpen = false
    private var themeWatch: AnyCancellable?

    private let spring = Animation.spring(response: 0.38, dampingFraction: 0.82)

    override init() {
        super.init()
        panel = NotchPanel(frame: .zero)
        let root = RootView()
            .environmentObject(model)
            .environmentObject(stats)
            .environmentObject(favorites)
            .environmentObject(media)
            .environmentObject(reminders)
            .environmentObject(menuBar)
            .environmentObject(clipboard)
            .environmentObject(voice)
        let host = NSHostingView(rootView: root)
        host.sizingOptions = []
        panel.contentView = host
        panel.ignoresMouseEvents = true
        // Тема применяется к панели и окнам сразу при переключении
        themeWatch = model.$theme.sink { [weak self] theme in
            self?.panel.appearance = theme.appearance
            AppWindows.shared.apply(theme.appearance)
        }
        layout()
        panel.orderFrontRegardless()

        monitors.append(NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] _ in
            self?.mouseMoved()
        } as Any)
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
            self?.mouseMoved()
            return event
        } as Any)
        // Клик мимо панели закрывает её, даже если идёт ввод
        monitors.append(NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self, self.model.expanded, !self.menuOpen, !self.model.pickingFile,
                  !self.expandedRect.contains(NSEvent.mouseLocation) else { return }
            self.collapse()
        } as Any)

        // Пока открыто выпадающее меню (шестерёнка, правый клик), панель не сворачивается
        NotificationCenter.default.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { [weak self] _ in
            self?.menuOpen = true
        }
        NotificationCenter.default.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.menuOpen = false
            self.mouseMoved()
        }

        // Первый запуск: приветствие с доступами
        if !UserDefaults.standard.bool(forKey: "welcomeShown") {
            UserDefaults.standard.set(true, forKey: "welcomeShown")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                guard let self, !CommandLine.arguments.contains("--snapshot") else { return }
                AppWindows.shared.showWelcome(reminders: self.reminders, stats: self.stats)
            }
        }

        NotificationCenter.default.addObserver(self, selector: #selector(layout),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    /// Экран с челкой, если он есть, иначе основной.
    private var screen: NSScreen {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    @objc private func layout() {
        let screen = self.screen
        let frame = screen.frame
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            let width = frame.width - left.width - right.width
            model.notchSize = CGSize(width: width, height: screen.safeAreaInsets.top)
            notchCenterX = frame.minX + left.width + width / 2
        } else {
            // Нет челки (внешний монитор): рисуем свою «челку» по центру строки меню
            model.notchSize = CGSize(width: 180, height: NSStatusBar.system.thickness)
            notchCenterX = frame.midX
        }
        screenTop = frame.maxY
        let size = CGSize(width: max(model.expandedSize.width, 560) + 80,
                          height: model.notchSize.height + model.gap + model.expandedSize.height + 50)
        panel.setFrame(NSRect(x: notchCenterX - size.width / 2, y: screenTop - size.height,
                              width: size.width, height: size.height), display: true)
    }

    private var collapsedRect: NSRect {
        let size = model.collapsedSize
        return NSRect(x: notchCenterX + model.pillOffset - size.width / 2, y: screenTop - size.height,
                      width: size.width, height: size.height + 2)
    }

    /// Челка, зазор и панель под ней: курсор может спокойно спуститься с челки на панель.
    private var expandedRect: NSRect {
        let size = model.expandedSize
        let height = model.notchSize.height + model.gap + size.height
        let panel = NSRect(x: notchCenterX - size.width / 2, y: screenTop - height,
                           width: size.width, height: height + 2)
        return panel.union(collapsedRect)
    }

    private func mouseMoved() {
        let point = NSEvent.mouseLocation
        if !model.expanded {
            guard collapsedRect.contains(point) else {
                hoverWork?.cancel(); hoverWork = nil
                return
            }
            guard hoverWork == nil else { return }
            // Небольшая задержка: «навёлся и подержал», чтобы не открывалось случайно
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.hoverWork = nil
                if self.collapsedRect.contains(NSEvent.mouseLocation) { self.expand() }
            }
            hoverWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22, execute: work)
        } else {
            // Пока открыто меню шестерёнки, оно само закрывается при уходе курсора, панель ждёт
            if expandedRect.insetBy(dx: -10, dy: -10).contains(point) || model.pinned || menuOpen || model.settingsOpen || model.pickingFile {
                leaveWork?.cancel(); leaveWork = nil
                return
            }
            guard leaveWork == nil else { return }
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.leaveWork = nil
                if !self.model.pinned, !self.menuOpen, !self.model.settingsOpen, !self.model.pickingFile, !self.expandedRect.insetBy(dx: -10, dy: -10).contains(NSEvent.mouseLocation) {
                    self.collapse()
                }
            }
            leaveWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
        }
    }

    private func expand() {
        guard !model.expanded else { return }
        panel.ignoresMouseEvents = false
        stats.refreshSlow()
        media.active = true
        reminders.refresh()
        menuBar.refresh()
        model.page = .home
        withAnimation(spring) { model.expanded = true }
    }

    /// Отладка: снимает настоящее окно панели во всех состояниях и вызывает done.
    @MainActor func snapshot(to url: URL, done: @escaping () -> Void) {
        Snapshot.isOn = true
        menuBar.refresh()
        media.active = true
        panel.ignoresMouseEvents = true
        let shots: [(Bool, NotchModel.Page, Bool, String)] = [
            (false, .home, false, "-collapsed"), (true, .home, false, ""), (true, .favorites, false, "-favorites"),
            (true, .music, false, "-music"), (true, .note, false, "-note"), (true, .home, true, "-settings"),
            (true, .favorites, false, "-clipboard"), (true, .note, false, "-recording"), (true, .home, false, "-about"),
            (true, .home, false, "-light"), (true, .favorites, false, "-light-favorites"), (true, .music, false, "-light-music"),
            (true, .note, false, "-light-note"), (true, .home, true, "-light-settings"), (true, .home, false, "-light-about"),
            (true, .favorites, false, "-accounts"), (true, .favorites, false, "-form-link"), (true, .favorites, false, "-form-account"),
            (true, .favorites, false, "-light-form-link")]
        let savedTheme = model.theme
        func shoot(_ index: Int) {
            guard index < shots.count else { model.theme = savedTheme; done(); return }
            let (expanded, page, settings, suffix) = shots[index]
            UserDefaults.standard.set(suffix == "-clipboard" ? "clipboard" : suffix == "-accounts" ? "account" : "link",
                                      forKey: "favoritesTab")
            Snapshot.form = suffix.hasSuffix("form-link") ? .link : suffix.hasSuffix("form-account") ? .account : nil
            // Сначала уводим со страницы, чтобы форма открылась заново
            model.page = .home
            if suffix == "-recording" {
                // Показ состояния записи без микрофона
                voice.transcript = "Купить билеты на субботу и не забыть зарядку"
                voice.level = 0.4
                voice.state = .recording
            }
            model.expanded = expanded
            model.theme = suffix.hasPrefix("-light") ? .light : .dark
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.model.page = page
            self.model.settingsOpen = settings
            self.model.showAbout = suffix.hasSuffix("-about")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                if let view = self.panel.contentView,
                   let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                    view.cacheDisplay(in: view.bounds, to: rep)
                    // Подкладываем светлые «обои», окно само прозрачное
                    let image = NSImage(size: view.bounds.size)
                    image.lockFocus()
                    NSColor(red: 0.86, green: 0.88, blue: 0.92, alpha: 1).setFill()
                    view.bounds.fill()
                    rep.draw(in: view.bounds)
                    image.unlockFocus()
                    if let tiff = image.tiffRepresentation,
                       let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                        let name = url.deletingPathExtension().lastPathComponent + suffix + ".png"
                        try? png.write(to: url.deletingLastPathComponent().appendingPathComponent(name))
                    }
                }
                shoot(index + 1)
            }
            }
        }
        shoot(0)
    }

    private func collapse() {
        guard model.expanded else { return }
        model.pinned = false
        model.settingsOpen = false
        model.showAbout = false
        media.active = false
        panel.makeFirstResponder(nil)
        panel.ignoresMouseEvents = true
        withAnimation(spring) { model.expanded = false }
    }
}
