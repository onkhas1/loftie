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

    func showAbout() {
        show(id: "about", title: "О Loftie", view: AboutView())
    }

    private func show<V: View>(id: String, title: String, view: V) {
        if let window = windows[id] {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        let host = NSHostingController(rootView: view
            .environment(\.colorScheme, .dark)
            .environment(\.locale, Locale(identifier: "ru_RU")))
        let window = NSWindow(contentViewController: host)
        window.title = title
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(red: 0.09, green: 0.09, blue: 0.11, alpha: 1)
        window.isReleasedWhenClosed = false
        window.center()
        windows[id] = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
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
                    .foregroundStyle(Color(hex: 0x0E1526))
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

// MARK: - О приложении

struct AboutView: View {
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 6) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 72, height: 72)
                Text("Loftie").font(.system(size: 22, weight: .bold)).foregroundStyle(Palette.text)
                Text("Версия \(version)").font(.system(size: 12)).foregroundStyle(Palette.tertiary)
                Text("Панель в челке MacBook. Бесплатно и с открытым кодом.")
                    .font(.system(size: 12)).foregroundStyle(Palette.secondary)
            }
            .padding(.top, 26)

            VStack(alignment: .leading, spacing: 2) {
                Text("Автор — \(Author.name)").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.tertiary)
                    .padding(.horizontal, 8).padding(.bottom, 4)
                LinkRow(icon: "paperplane.fill", color: Palette.blue, title: "Telegram", detail: "@onkhas", url: Author.telegram)
                LinkRow(icon: "chevron.left.forwardslash.chevron.right", color: Palette.lilac,
                        title: "GitHub", detail: "onkhas1/loftie", url: Author.github)
                LinkRow(icon: "envelope.fill", color: Palette.mint, title: "Почта", detail: "byonkhas@gmail.com", url: Author.email)
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.card))
            .padding(.horizontal, 22)

            VStack(spacing: 10) {
                Text("Loftie полностью бесплатный — пользуйся на здоровье. Если зашёл и хочется сказать спасибо, можно угостить автора чашкой кофе. Это не обязательно.")
                    .font(.system(size: 12)).foregroundStyle(Palette.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    if let url = Author.donate { NSWorkspace.shared.open(url) }
                } label: {
                    Label(Author.donate == nil ? "Ссылка на кофе появится скоро" : "Угостить кофе",
                          systemImage: "cup.and.saucer.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity).padding(.vertical, 9)
                        .background(Capsule().fill(Palette.pink.opacity(Author.donate == nil ? 0.12 : 1)))
                        .foregroundStyle(Author.donate == nil ? Palette.pink : Color(hex: 0x2A0F18))
                }
                .buttonStyle(.plain)
                .disabled(Author.donate == nil)
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 22)
        }
        .frame(width: 400)
        .background(WindowBackground(accent: Palette.pink))
    }
}

private struct LinkRow: View {
    let icon: String
    let color: Color
    let title: String
    let detail: String
    let url: URL
    @State private var hover = false

    var body: some View {
        Button { NSWorkspace.shared.open(url) } label: {
            HStack(spacing: 10) {
                IconRing(icon: icon, color: color, size: 26)
                Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.text)
                Spacer()
                Text(detail).font(.system(size: 12)).foregroundStyle(Palette.secondary)
                Image(systemName: "arrow.up.right").font(.system(size: 9, weight: .bold)).foregroundStyle(Palette.tertiary)
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(hover ? Palette.cardHover : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}
