import AppKit
import EventKit
import SwiftUI

/// Обычные окна приложения: приветствие при первом запуске и «О приложении».
final class AppWindows {
    static let shared = AppWindows()
    private var windows: [String: NSWindow] = [:]

    func showWelcome(reminders: RemindersStore, stats: SystemStats) {
        show(id: "welcome", title: "Добро пожаловать в Loftie",
             view: WelcomeView(close: { [weak self] in self?.close("welcome") })
                .environmentObject(reminders).environmentObject(stats))
    }

    private func show<V: View>(id: String, title: String, view: V) {
        if let window = windows[id] {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        let host = NSHostingController(rootView: view
            .environment(\.locale, Locale(identifier: "ru_RU")))
        let window = NSWindow(contentViewController: host)
        window.title = title
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.appearance = Theme.current.appearance
        window.backgroundColor = .adaptive(dark: NSColor(hex: 0x16171B), light: NSColor(hex: 0xF4F4F7))
        window.isReleasedWhenClosed = false
        window.center()
        windows[id] = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// Новая тема — и открытым окнам тоже
    func apply(_ appearance: NSAppearance?) {
        windows.values.forEach { $0.appearance = appearance }
    }

    private func close(_ id: String) {
        windows[id]?.close()
    }
}

/// Контакты автора и донат.
enum Author {
    static let name = "Александр Сахно"
    static let telegram = URL(string: "https://t.me/onkhas")!
    static let github = URL(string: "https://github.com/onkhas1/loftie")!
    static let email = URL(string: "mailto:byonkhas@gmail.com")!
    /// Страница CloudTips «на кофе»
    static let donate: URL? = URL(string: "https://pay.cloudtips.ru/p/1a375628")
}

private struct WindowBackground: View {
    var accent: Color = Palette.blue
    var body: some View {
        ZStack {
            LinearGradient(colors: [Palette.groundTop, Palette.groundBottom], startPoint: .top, endPoint: .bottom)
            EllipticalGradient(colors: [accent.opacity(0.28), accent.opacity(0.06), .clear],
                               center: UnitPoint(x: 0.5, y: 0), startRadiusFraction: 0, endRadiusFraction: 0.65)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Приветствие

struct WelcomeView: View {
    @EnvironmentObject var reminders: RemindersStore
    @EnvironmentObject var stats: SystemStats
    let close: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 8) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 72, height: 72)
                Text("Loftie").font(.system(size: 24, weight: .bold)).foregroundStyle(Palette.text)
                Text("Всё нужное — прямо в челке").font(.system(size: 13)).foregroundStyle(Palette.secondary)
            }
            .padding(.top, 26)

            VStack(alignment: .leading, spacing: 12) {
                Point(icon: "cursorarrow.motionlines", color: Palette.blue,
                      title: "Наведи курсор на челку", text: "Панель выедет сама. Уведёшь курсор — спрячется.")
                Point(icon: "gauge.with.dots.needle.33percent", color: Palette.mint,
                      title: "Статусы всегда на виду", text: "Диск, корзина, сеть и процессор — по бокам от челки.")
                Point(icon: "square.grid.2x2", color: Palette.pink,
                      title: "Четыре вкладки", text: "План на день, избранное и буфер, музыка, запись мыслей голосом.")
            }
            .padding(.horizontal, 28)

            VStack(alignment: .leading, spacing: 8) {
                Text("Доступы — по желанию").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.tertiary)
                Permission(title: "Напоминания", text: "план на сегодня на главной",
                           granted: reminders.access == .granted) { reminders.requestAccess() }
                Permission(title: "Полный доступ к диску", text: "чтобы видеть размер корзины",
                           granted: isTrashReadable) {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
                }
                Text("Микрофон и распознавание речи спросим при первой записи.")
                    .font(.system(size: 11)).foregroundStyle(Palette.tertiary)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.card))
            .padding(.horizontal, 22)

            Button(action: close) {
                Text("Начать").font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity).padding(.vertical, 9)
                    .background(Capsule().fill(Palette.blue))
                    .foregroundStyle(Palette.onAccent)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 22)
            .padding(.bottom, 22)
        }
        .frame(width: 440)
        .background(WindowBackground())
    }

    private var isTrashReadable: Bool {
        if case .size = stats.trash { return true }
        return false
    }
}

private struct Point: View {
    let icon: String
    let color: Color
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            IconRing(icon: icon, color: color, size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.text)
                Text(text).font(.system(size: 12)).foregroundStyle(Palette.secondary)
            }
        }
    }
}

private struct Permission: View {
    let title: String
    let text: String
    let granted: Bool
    let action: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.text)
                Text(text).font(.system(size: 11)).foregroundStyle(Palette.tertiary)
            }
            Spacer()
            if granted {
                Label("Есть", systemImage: "checkmark").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.mint)
            } else {
                Button(action: action) {
                    Text("Разрешить").font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 11).padding(.vertical, 4)
                        .background(Capsule().fill(Palette.blue.opacity(0.18)))
                        .foregroundStyle(Palette.blue)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - О приложении (внутри панели)

struct AboutPanel: View {
    @EnvironmentObject var model: NotchModel

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            // Слева — что это
            VStack(spacing: 6) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 64, height: 64)
                Text("Loftie").font(.system(size: 18, weight: .bold)).foregroundStyle(Palette.text)
                Text("Версия \(version)").font(.system(size: 11)).foregroundStyle(Palette.tertiary)
                Text("Всё нужное — прямо в челке")
                    .font(.system(size: 11)).foregroundStyle(Palette.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(width: 190)
            .frame(maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.card))

            // Справа — автор, контакты, кофе
            VStack(alignment: .leading, spacing: 10) {
                Text("Автор — \(Author.name)").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.text)
                HStack(spacing: 8) {
                    ContactChip(icon: "paperplane.fill", color: Palette.blue, text: "@onkhas", url: Author.telegram)
                    ContactChip(icon: "chevron.left.forwardslash.chevron.right", color: Palette.lilac, text: "GitHub", url: Author.github)
                    ContactChip(icon: "envelope.fill", color: Palette.mint, text: "Почта", url: Author.email)
                }
                Text("Loftie полностью бесплатный — пользуйся на здоровье. Если зашёл и хочется сказать спасибо, можно угостить автора чашкой кофе. Это не обязательно.")
                    .font(.system(size: 12)).foregroundStyle(Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                HStack {
                    Button {
                        if let url = Author.donate { NSWorkspace.shared.open(url) }
                    } label: {
                        Label("Угостить кофе", systemImage: "cup.and.saucer.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 14).padding(.vertical, 6)
                            .background(Capsule().fill(Palette.pink))
                            .foregroundStyle(Palette.onAccent)
                    }
                    .buttonStyle(.plain)
                    .disabled(Author.donate == nil)
                    Spacer()
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) { model.showAbout = false }
                    } label: {
                        Text("Назад").font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.card))
        }
    }
}

private struct ContactChip: View {
    let icon: String
    let color: Color
    let text: String
    let url: URL
    @State private var hover = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 10, weight: .semibold)).foregroundStyle(color)
            Text(text).font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.text)
        }
        .fixedSize()
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(hover ? color.opacity(0.2) : Palette.card)
                .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(color.opacity(0.35), lineWidth: 1))
        )
        .contentShape(Rectangle())
        .onTapGesture { NSWorkspace.shared.open(url) }
        .onHover { hover = $0 }
        .help(url.absoluteString.replacingOccurrences(of: "mailto:", with: ""))
    }
}
