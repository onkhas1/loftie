import SwiftUI
import EventKit
import ServiceManagement

enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ on: Bool) {
        if on { try? SMAppService.mainApp.register() } else { try? SMAppService.mainApp.unregister() }
    }
}

/// Вертикальная прокрутка на всю доступную ширину.
struct PageScroll<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView(showsIndicators: false) {
            content.frame(maxWidth: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Главная

struct HomePage: View {
    @EnvironmentObject var stats: SystemStats

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                StatusTile(icon: "internaldrive", color: Palette.blue,
                           value: Fmt.bytes(stats.diskFree), label: "свободно", fraction: 1 - stats.diskUsedFraction)
                trashTile
                StatusTile(icon: "arrow.down", color: Palette.cyan,
                           value: Fmt.speed(stats.down), label: "↑ " + Fmt.speed(stats.up))
                StatusTile(icon: "cpu", color: Palette.pink,
                           value: Fmt.percent(stats.cpu), label: "процессор", fraction: stats.cpu)
            }
            TodayShelf()
        }
    }

    @ViewBuilder private var trashTile: some View {
        switch stats.trash {
        case .size(let bytes):
            StatusTile(icon: "trash", color: bytes > 1_000_000_000 ? Palette.coral : Palette.mint, value: Fmt.bytes(bytes),
                       label: bytes > 1_000_000_000 ? "пора почистить" : "в корзине") {
                NSWorkspace.shared.open(URL(fileURLWithPath: NSHomeDirectory() + "/.Trash"))
            }
        case .noAccess:
            StatusTile(icon: "trash", color: Palette.mint, value: "Корзина", label: "дать доступ") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
            }
        case .unknown:
            StatusTile(icon: "trash", color: Palette.mint, value: "…", label: "в корзине")
        }
    }
}

struct StatusTile: View {
    let icon: String
    let color: Color
    let value: String
    let label: String
    var fraction: Double? = nil
    var action: (() -> Void)? = nil

    @State private var hover = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                IconRing(icon: icon, color: color, size: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(value)
                        .font(.system(size: 15, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Palette.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Text(label)
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            Spacer(minLength: 0)
            // Тонкая шкала в цвете статуса
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.track)
                    if let fraction {
                        Capsule().fill(color.opacity(0.85)).frame(width: max(3, geo.size.width * min(max(fraction, 0), 1)))
                    }
                }
            }
            .frame(height: 3)
            .opacity(fraction == nil ? 0 : 1)
        }
        .padding(.horizontal, 10).padding(.top, 10).padding(.bottom, 9)
        .frame(maxWidth: .infinity, minHeight: 64, maxHeight: 64)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(hover && action != nil ? Palette.cardHover : Palette.card))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture { action?() }
    }
}

struct TodayShelf: View {
    @EnvironmentObject var reminders: RemindersStore
    @EnvironmentObject var model: NotchModel
    @State private var newTitle = ""
    @FocusState private var focused: Bool

    var body: some View {
        Shelf {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text("Сегодня").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.text)
                    if !reminders.items.isEmpty {
                        Text("\(reminders.items.count)").font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Palette.tertiary)
                    }
                    Spacer()
                    if reminders.access == .granted { addField }
                }
                content
            }
        }
        .onChange(of: focused) { _, value in model.pinned = value }
    }

    private var addField: some View {
        HStack(spacing: 6) {
            Image(systemName: "plus").font(.system(size: 10, weight: .bold)).foregroundStyle(Palette.blue)
            TextField("Добавить на сегодня", text: $newTitle)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($focused)
                .onSubmit { reminders.add(newTitle); newTitle = "" }
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .frame(width: 220)
        .background(Capsule().fill(Palette.field))
    }

    @ViewBuilder private var content: some View {
        switch reminders.access {
        case .unknown:
            hint("Подключи Напоминания, и здесь появится план дня", button: "Подключить") { reminders.requestAccess() }
        case .denied:
            hint("Нет доступа к Напоминаниям", button: "Открыть настройки") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders")!)
            }
        case .granted:
            if reminders.items.isEmpty {
                Text("На сегодня пусто").font(.system(size: 12)).foregroundStyle(Palette.tertiary)
            } else {
                PageScroll {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 18), GridItem(.flexible())], alignment: .leading, spacing: 7) {
                        ForEach(reminders.items, id: \.calendarItemIdentifier) { item in
                            ReminderRow(reminder: item) {
                                withAnimation(.easeOut(duration: 0.2)) { reminders.complete(item) }
                            }
                        }
                    }
                }
            }
        }
    }

    private func hint(_ text: String, button: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Text(text).font(.system(size: 12)).foregroundStyle(Palette.secondary)
            Button(action: action) {
                Text(button).font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 11).padding(.vertical, 4)
                    .background(Capsule().fill(Palette.blue.opacity(0.18)))
                    .foregroundStyle(Palette.blue)
            }
            .buttonStyle(.plain)
        }
    }
}

struct ReminderRow: View {
    let reminder: EKReminder
    let onComplete: () -> Void
    @State private var hover = false

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onComplete) {
                Image(systemName: hover ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13))
                    .foregroundStyle(isOverdue ? Palette.coral : Palette.blue)
            }
            .buttonStyle(.plain)
            .onHover { hover = $0 }
            Text(reminder.title ?? "")
                .font(.system(size: 12))
                .foregroundStyle(Palette.text)
                .lineLimit(1)
                .help(origin)
            Spacer(minLength: 0)
            if let time = timeText {
                Text(time).font(.system(size: 11)).foregroundStyle(isOverdue ? Palette.coral : Palette.tertiary)
            }
        }
    }

    private var isOverdue: Bool {
        guard let date = reminder.dueDateComponents?.date else { return false }
        return date < Calendar.current.startOfDay(for: Date())
    }

    /// «Список «Напоминания» (iCloud) · срок 15 сент.»
    private var origin: String {
        var text = "Список «\(reminder.calendar?.title ?? "?")»"
        if let account = reminder.calendar?.source?.title { text += " (\(account))" }
        if let date = reminder.dueDateComponents?.date {
            text += " · срок " + date.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "ru_RU")))
        }
        return text
    }

    private var timeText: String? {
        if isOverdue { return "просрочено" }
        guard let parts = reminder.dueDateComponents, let hour = parts.hour else { return nil }
        return String(format: "%02d:%02d", hour, parts.minute ?? 0)
    }
}

// MARK: - Избранное

extension FavKind {
    var color: Color {
        switch self {
        case .account: Palette.lilac
        case .link: Palette.blue
        case .clipboard: Palette.mint
        case .file: Palette.pink
        }
    }

    var badgeIcon: String {
        switch self {
        case .account: "person.fill"
        case .link: "link"
        case .clipboard: "doc.on.clipboard"
        case .file: "folder.fill"
        }
    }
}

struct FavoritesPage: View {
    @EnvironmentObject var model: NotchModel
    @EnvironmentObject var favorites: FavoritesStore
    @EnvironmentObject var clipboard: ClipboardHistory
    @AppStorage("favoritesTab") private var tab: FavKind = .link
    @State private var draft: Favorite?
    @State private var copied = false

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            // Рейка категорий — коробки на полке
            VStack(spacing: 4) {
                ForEach(FavKind.allCases) { kind in
                    CategoryRow(kind: kind, count: kind == .clipboard ? clipboard.items.count : favorites.items(of: kind).count,
                                selected: tab == kind) {
                        withAnimation(.easeOut(duration: 0.15)) { tab = kind; draft = nil }
                    }
                }
                Spacer(minLength: 0)
                if copied {
                    Label("Скопировано", systemImage: "checkmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.pink)
                        .transition(.opacity)
                }
            }
            .frame(width: 150)

            if tab == .clipboard {
                ClipboardList(onCopy: flashCopied)
            } else if let editing = draft {
                FavoriteForm(draft: editing, isNew: !favorites.items.contains { $0.id == editing.id }, onSave: { saved in
                    withAnimation { favorites.save(saved) }
                    draft = nil
                }, onCancel: { draft = nil })
            } else if favorites.items(of: tab).isEmpty {
                EmptyFavorites(kind: tab) { add() }
            } else if tab == .account {
                AccountsList(onCopy: { item in tap(item) }, onEdit: { draft = $0 }, onAdd: { add() })
            } else {
                PageScroll {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2), spacing: 8) {
                        ForEach(favorites.items(of: tab)) { item in
                            FavoriteTile(item: item, onTap: { tap(item) }, onEdit: { draft = item },
                                         onDelete: { favorites.remove(item) })
                        }
                        AddTile(color: tab.color) { add() }
                    }
                }
            }
        }
        .onAppear {
            // Отладочный снимок формы
            if let kind = Snapshot.form { tab = kind; draft = Favorite(kind: kind, title: "", value: "") }
        }
    }

    /// Файлы и программы добавляются сразу из окна выбора, остальное — через форму
    private func add() {
        guard tab == .file else {
            draft = Favorite(kind: tab, title: "", value: "")
            return
        }
        guard let url = FilePicker.choose(model) else { return }
        withAnimation { favorites.upsert(Favorite(kind: .file, title: FilePicker.title(for: url), value: url.path)) }
    }

    private func tap(_ item: Favorite) {
        favorites.open(item)
        guard item.kind == .account else { return }
        flashCopied()
    }

    private func flashCopied() {
        withAnimation { copied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) { withAnimation { copied = false } }
    }
}

/// Аккаунты списком: сервис слева, логин справа, клик копирует логин.
struct AccountsList: View {
    @EnvironmentObject var favorites: FavoritesStore
    let onCopy: (Favorite) -> Void
    let onEdit: (Favorite) -> Void
    let onAdd: () -> Void

    var body: some View {
        PageScroll {
            VStack(spacing: 6) {
                ForEach(favorites.items(of: .account)) { item in
                    AccountRow(item: item, onTap: { onCopy(item) })
                        .contextMenu {
                            Button("Изменить") { onEdit(item) }
                            Button("Удалить", role: .destructive) { favorites.remove(item) }
                        }
                }
                Button(action: onAdd) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus").font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.lilac)
                        Text("Добавить аккаунт").font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 38)
                    .background(RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(Palette.tertiary.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct AccountRow: View {
    let item: Favorite
    let onTap: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Text(item.title)
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.text)
                    .lineLimit(1)
                    .frame(width: 150, alignment: .leading)
                Text(item.value)
                    .font(.system(size: 13)).foregroundStyle(Palette.secondary)
                    .lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 8)
                Image(systemName: "doc.on.doc").font(.system(size: 11))
                    .foregroundStyle(hover ? Palette.lilac : Palette.tertiary)
            }
            .padding(.horizontal, 14)
            .frame(height: 38)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(hover ? Palette.cardHover : Palette.card))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help("Скопировать «\(item.value)»")
    }
}

struct CategoryRow: View {
    let kind: FavKind
    let count: Int
    let selected: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                IconRing(icon: kind.badgeIcon, color: kind.color, size: 24)
                Text(kind.title).font(.system(size: 12, weight: selected ? .semibold : .medium))
                    .foregroundStyle(selected ? Palette.text : Palette.secondary)
                Spacer(minLength: 0)
                Text("\(count)").font(.system(size: 11, weight: .medium)).monospacedDigit()
                    .foregroundStyle(Palette.tertiary)
            }
            .padding(.horizontal, 7).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(selected ? Palette.cardHover : (hover ? Palette.card : .clear)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

struct FavoriteTile: View {
    let item: Favorite
    let onTap: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 11) {
                FavoriteIcon(item: item)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.text)
                    Text(subtitle).font(.system(size: 11)).foregroundStyle(Palette.tertiary)
                }
                .lineLimit(1)
                Spacer(minLength: 0)
                if item.kind == .account {
                    Image(systemName: "doc.on.doc").font(.system(size: 10)).foregroundStyle(Palette.tertiary)
                        .opacity(hover ? 1 : 0)
                }
            }
            .padding(.horizontal, 11)
            .frame(height: 58)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(hover ? Palette.cardHover : Palette.card))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(item.value)
        .contextMenu {
            Button("Изменить", action: onEdit)
            Button("Удалить", role: .destructive, action: onDelete)
        }
    }

    private var subtitle: String {
        switch item.kind {
        case .account: return item.value
        case .link, .clipboard:
            let text = item.value.contains("://") ? item.value : "https://" + item.value
            return URL(string: text)?.host?.replacingOccurrences(of: "www.", with: "") ?? item.value
        case .file:
            return (item.expandedPath as NSString).lastPathComponent
        }
    }
}

/// Иконка избранного: программа или файл как в Finder, у сайта его фавиконка, иначе буква маркером на крафте.
struct FavoriteIcon: View {
    let item: Favorite
    private let size: CGFloat = 38

    var body: some View {
        switch item.kind {
        case .file:
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.expandedPath)).resizable()
                .frame(width: size, height: size)
        case .link:
            if let host = host, !Snapshot.isOn {
                AsyncImage(url: URL(string: "https://icons.duckduckgo.com/ip3/\(host).ico")) { phase in
                    if let image = phase.image {
                        image.resizable().interpolation(.high).frame(width: 22, height: 22)
                            .frame(width: size, height: size)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.92)))
                    } else {
                        letter
                    }
                }
            } else {
                letter
            }
        case .account, .clipboard:
            letter
        }
    }

    private var host: String? {
        let text = item.value.contains("://") ? item.value : "https://" + item.value
        return URL(string: text)?.host
    }

    private var letter: some View {
        let color = item.kind.color
        return Circle()
            .fill(color.opacity(0.14))
            .overlay(Circle().strokeBorder(color.opacity(0.55), lineWidth: 1.2))
            .frame(width: size, height: size)
            .overlay(Text(String(item.title.prefix(1)).uppercased())
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(color))
    }
}

struct AddTile: View {
    var color: Color = Palette.blue
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "plus").font(.system(size: 13, weight: .bold))
                    .foregroundStyle(color)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(color.opacity(hover ? 0.22 : 0.12)))
                Text("Добавить").font(.system(size: 12, weight: .medium))
                    .foregroundStyle(hover ? Palette.text : Palette.secondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 11)
            .frame(height: 58)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Palette.tertiary.opacity(hover ? 0.6 : 0.3), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

/// Форма закладки: компактная карточка по центру. Enter сохраняет, Esc отменяет.
struct FavoriteForm: View {
    @EnvironmentObject var model: NotchModel
    @State var draft: Favorite
    let isNew: Bool
    let onSave: (Favorite) -> Void
    let onCancel: () -> Void

    private enum Slot { case value, title }
    @FocusState private var focus: Slot?

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 11) {
                IconRing(icon: draft.kind.badgeIcon, color: draft.kind.color, size: 28)
                Text(heading).font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.text)
            }

            VStack(spacing: 8) {
                switch draft.kind {
                case .link:
                    IconField(icon: "link", prompt: "Ссылка", text: $draft.value)
                        .focused($focus, equals: .value)
                    IconField(icon: "textformat", prompt: "Название", text: $draft.title)
                        .focused($focus, equals: .title)
                case .account:
                    IconField(icon: "at", prompt: "Логин, почта или никнейм", text: $draft.value)
                        .focused($focus, equals: .value)
                    IconField(icon: "globe", prompt: "Сервис", text: $draft.title)
                        .focused($focus, equals: .title)
                case .file, .clipboard:
                    HStack(spacing: 10) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: draft.expandedPath)).resizable().frame(width: 22, height: 22)
                        Text(draft.value.isEmpty ? "Ничего не выбрано" : (draft.value as NSString).abbreviatingWithTildeInPath)
                            .font(.system(size: 12)).foregroundStyle(Palette.secondary)
                            .lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button("Другой…", action: pick).controlSize(.small)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Palette.field))
                    IconField(icon: "textformat", prompt: "Название", text: $draft.title)
                        .focused($focus, equals: .title)
                }
            }
            .onSubmit(submit)

            HStack(spacing: 14) {
                Spacer()
                Button("Отмена", action: onCancel)
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.secondary)
                    .keyboardShortcut(.cancelAction)
                Button(action: submit) {
                    Text(isNew ? "Добавить" : "Сохранить").font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 16).padding(.vertical, 6)
                        .background(Capsule().fill(draft.kind.color.opacity(canSave ? 1 : 0.35)))
                        .foregroundStyle(Palette.onAccent)
                }
                .buttonStyle(.plain)
                .disabled(!canSave)
            }
        }
        .padding(14)
        .frame(width: 420)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Palette.card))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Пока форма открыта, панель не сворачивается от ухода курсора
        .onAppear {
            model.pinned = true
            // Панель не активирует приложение сама: делаем её ключевой, чтобы курсор сразу встал в поле
            NSApp.windows.first { $0 is NotchPanel }?.makeKey()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                focus = draft.kind == .file ? .title : .value
            }
        }
        .onDisappear { model.pinned = false }
    }

    private var heading: String {
        switch draft.kind {
        case .link: isNew ? "Новая ссылка" : "Ссылка"
        case .account: isNew ? "Новый аккаунт" : "Аккаунт"
        case .file, .clipboard: "Файл или программа"
        }
    }

    private var canSave: Bool {
        !draft.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submit() {
        guard canSave else { return }
        onSave(draft)
    }

    private func pick() {
        guard let url = FilePicker.choose(model) else { return }
        draft.value = url.path
        draft.title = FilePicker.title(for: url)
    }
}

/// Поле ввода с иконкой слева
struct IconField: View {
    let icon: String
    let prompt: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: icon).font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Palette.tertiary)
                .frame(width: 16)
            // Своя подсказка: системная в поле без фокуса рисуется цветом текста
            ZStack(alignment: .leading) {
                if text.isEmpty {
                    Text(prompt).font(.system(size: 13)).foregroundStyle(Palette.tertiary)
                        .lineLimit(1).allowsHitTesting(false)
                }
                TextField("", text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.text)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Palette.field))
    }
}

/// Системное окно выбора файла или программы; панель на это время не сворачивается.
enum FilePicker {
    static func choose(_ model: NotchModel) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Добавить"
        model.pickingFile = true
        defer { model.pickingFile = false }
        NSApp.activate(ignoringOtherApps: true)
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// «Telegram» для Telegram.app, имя папки или файла как в Finder
    static func title(for url: URL) -> String {
        FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }
}

/// Пустая категория: что сюда класть и кнопка «Добавить».
struct EmptyFavorites: View {
    let kind: FavKind
    let add: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            IconRing(icon: kind.badgeIcon, color: kind.color, size: 44)
            Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.text)
            Text(hint).font(.system(size: 12)).foregroundStyle(Palette.secondary).multilineTextAlignment(.center)
            Button(action: add) {
                Label("Добавить", systemImage: "plus").font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(Capsule().fill(kind.color.opacity(0.18)))
                    .foregroundStyle(kind.color)
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.card))
    }

    private var title: String {
        switch kind {
        case .account: "Аккаунтов пока нет"
        case .link: "Ссылок пока нет"
        case .file: "Файлов пока нет"
        case .clipboard: ""
        }
    }

    private var hint: String {
        switch kind {
        case .account: "Логины и почты, которые вечно ищешь.\nКлик — и логин скопирован. Пароли тут не хранятся."
        case .link: "Сайты, таблицы, доски — всё, что открываешь каждый день."
        case .file: "Папки, документы и программы под рукой."
        case .clipboard: ""
        }
    }
}

/// Последние пять скопированных текстов: клик возвращает в буфер.
struct ClipboardList: View {
    @EnvironmentObject var clipboard: ClipboardHistory
    let onCopy: () -> Void

    var body: some View {
        if clipboard.items.isEmpty {
            VStack(spacing: 8) {
                IconRing(icon: "doc.on.clipboard", color: Palette.mint, size: 44)
                Text("Буфер пока пуст").font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.text)
                Text("Скопируй любой текст — здесь сохранятся последние \(clipboard.limit).\nПароли сюда не попадают.")
                    .font(.system(size: 12)).foregroundStyle(Palette.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.card))
        } else {
            VStack(spacing: 4) {
                ForEach(clipboard.items) { item in
                    ClipboardRow(item: item) { clipboard.copy(item); onCopy() }
                        .contextMenu {
                            Button("Удалить") { clipboard.remove(item) }
                            Button("Очистить всё", role: .destructive) { clipboard.clear() }
                        }
                }
                Spacer(minLength: 0)
            }
        }
    }
}

struct ClipboardRow: View {
    let item: ClipboardHistory.Item
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(item.text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces))
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.text)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if hover {
                    Image(systemName: "doc.on.doc").font(.system(size: 10)).foregroundStyle(Palette.mint)
                } else {
                    Text(item.date, format: .relative(presentation: .named))
                        .font(.system(size: 11)).foregroundStyle(Palette.tertiary)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(hover ? Palette.cardHover : Palette.card))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(String(item.text.prefix(500)))
    }
}

// MARK: - Музыка

struct MusicPage: View {
    @EnvironmentObject var media: MediaController

    var body: some View {
        HStack(spacing: 24) {
            Spacer(minLength: 0)
            artwork
            VStack(alignment: .leading, spacing: 4) {
                Spacer(minLength: 0)
                if let source = media.source {
                    HStack(spacing: 5) {
                        Image(nsImage: source.icon).resizable().frame(width: 14, height: 14)
                        Text(source.name).font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.tertiary)
                    }
                }
                Text(media.track?.title ?? "Ничего не играет")
                    .font(.system(size: 20, weight: .semibold)).foregroundStyle(Palette.text).lineLimit(1)
                if let artist = media.track?.artist {
                    Text(artist).font(.system(size: 13)).foregroundStyle(Palette.secondary).lineLimit(1)
                }
                if media.track?.duration != nil {
                    TimelineView(.periodic(from: .now, by: 1)) { context in progress(at: context.date) }
                        .padding(.top, 8)
                }
                HStack(spacing: 22) {
                    MediaButton(icon: "backward.fill", size: 17) { media.send(.previous) }
                    Button { media.send(.toggle) } label: {
                        Image(systemName: media.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 19))
                            .foregroundStyle(Palette.onAccent)
                            .frame(width: 48, height: 48)
                            .background(Circle().fill(Palette.lilac))
                    }
                    .buttonStyle(.plain)
                    MediaButton(icon: "forward.fill", size: 17) { media.send(.next) }
                }
                .padding(.top, 8)
                Spacer(minLength: 0)
            }
            .frame(width: 300, alignment: .leading)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder private var artwork: some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        if let image = media.track?.artwork {
            Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                .frame(width: 150, height: 150)
                .clipShape(shape)
                .shadow(color: .black.opacity(0.4), radius: 14, y: 8)
        } else {
            shape
                .fill(RadialGradient(colors: [Palette.lilac.opacity(0.35), Palette.lilac.opacity(0.08)],
                                     center: .topLeading, startRadius: 0, endRadius: 210))
                .overlay(shape.strokeBorder(Palette.lilac.opacity(0.35), lineWidth: 1))
                .overlay(Image(systemName: "music.note").font(.system(size: 46, weight: .medium)).foregroundStyle(Palette.lilac))
                .frame(width: 150, height: 150)
        }
    }

    private func progress(at now: Date) -> some View {
        let duration = media.track?.duration ?? 0
        let position = media.track?.position(at: now, playing: media.isPlaying) ?? 0
        return VStack(spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.track)
                    Capsule().fill(Palette.lilac)
                        .frame(width: duration > 0 ? geo.size.width * min(position / duration, 1) : 0)
                }
            }
            .frame(height: 3)
            HStack {
                Text(Self.time(position))
                Spacer()
                Text(Self.time(duration))
            }
            .font(.system(size: 10, weight: .medium)).monospacedDigit()
            .foregroundStyle(Palette.tertiary)
        }
    }

    private static func time(_ seconds: Double) -> String {
        let total = max(0, Int(seconds))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

struct MediaButton: View {
    let icon: String
    let size: CGFloat
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: size))
                .foregroundStyle(hover ? Palette.text : Palette.secondary)
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

// MARK: - Запись

/// Быстрая запись: микрофон или текст → заметка во «Входящие».
struct NotePage: View {
    @EnvironmentObject var voice: VoiceNote
    @EnvironmentObject var model: NotchModel
    @State private var draft = ""
    @State private var pickerOpen = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 10) {
            switch voice.state {
            case .recording: recording
            case .saved(let url): saved(url)
            default: idle
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottom) {
            if pickerOpen { vaultPicker.padding(.bottom, 34) }
        }
        .onAppear { voice.refreshVaults() }
        .onChange(of: voice.state) { _, state in model.pinned = state == .recording || focused }
        .onChange(of: focused) { _, value in model.pinned = value || voice.state == .recording }
    }

    // MARK: Ожидание

    private var idle: some View {
        VStack(spacing: 10) {
            Button { voice.start() } label: {
                IconRing(icon: "mic.fill", color: Palette.mint, size: 50)
            }
            .buttonStyle(.plain)
            .help("Начать запись")
            Text("Нажми на микрофон и говори").font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.text)
            if case .failed(let message) = voice.state {
                Text(message).font(.system(size: 12)).foregroundStyle(Palette.coral)
            }
            HStack(spacing: 8) {
                TextField("…или напиши мысль и нажми ↩", text: $draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .focused($focused)
                    .onSubmit { voice.save(draft); draft = "" }
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .frame(width: 380)
            .background(Capsule().fill(Palette.field))
            destination
        }
    }

    // MARK: Запись идёт

    private var recording: some View {
        VStack(spacing: 10) {
            Button { voice.stop(save: true) } label: {
                ZStack {
                    Circle().fill(Palette.mint.opacity(0.16))
                        .frame(width: 50 + voice.level * 22, height: 50 + voice.level * 22)
                    IconRing(icon: "stop.fill", color: Palette.mint, size: 50)
                }
                .frame(width: 72, height: 72)
                .animation(.easeOut(duration: 0.12), value: voice.level)
            }
            .buttonStyle(.plain)
            .help("Остановить и сохранить")
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text("Слушаю · " + elapsed(context.date))
                    .font(.system(size: 12, weight: .medium)).monospacedDigit().foregroundStyle(Palette.mint)
            }
            Text(voice.transcript.isEmpty ? "Говори, текст появится здесь" : voice.transcript)
                .font(.system(size: 13))
                .foregroundStyle(voice.transcript.isEmpty ? Palette.tertiary : Palette.text)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)
            HStack(spacing: 10) {
                Button("Отмена") { voice.stop(save: false) }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.secondary)
                    .padding(.horizontal, 12).padding(.vertical, 5)
                Button { voice.stop(save: true) } label: {
                    Text("Сохранить").font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 14).padding(.vertical, 5)
                        .background(Capsule().fill(Palette.mint))
                        .foregroundStyle(Palette.onAccent)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Сохранено

    private func saved(_ url: URL) -> some View {
        VStack(spacing: 10) {
            IconRing(icon: "checkmark", color: Palette.mint, size: 50)
            Text("Записано").font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.text)
            Text("Лежит в " + voice.destinationName).font(.system(size: 12)).foregroundStyle(Palette.secondary)
            HStack(spacing: 10) {
                Button { voice.open(url) } label: {
                    Text(voice.vault != nil ? "Открыть в Obsidian" : "Показать в Finder").font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 14).padding(.vertical, 5)
                        .background(Capsule().fill(Palette.mint.opacity(0.18)))
                        .foregroundStyle(Palette.mint)
                }
                .buttonStyle(.plain)
                Button("Ещё одну") { voice.state = .idle }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.secondary)
            }
        }
    }

    // MARK: Куда сохраняется

    private var destination: some View {
        Button {
            guard voice.vaults.count > 0 else { return }
            withAnimation(.easeOut(duration: 0.15)) { pickerOpen.toggle() }
        } label: {
            HStack(spacing: 6) {
                Circle().fill(voice.vault != nil ? Palette.mint : Palette.tertiary).frame(width: 6, height: 6)
                Text(destinationText).font(.system(size: 11, weight: .medium))
                if voice.vaults.count > 0 {
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 8, weight: .bold))
                }
            }
            .foregroundStyle(voice.vault != nil ? Palette.mint : Palette.tertiary)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Capsule().fill(Palette.card))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("Куда сохранять заметки")
    }

    private var destinationText: String {
        guard voice.obsidianInstalled else { return "Obsidian не установлен · сохраню в Документы/Loftie" }
        guard let vault = voice.vault else { return "Хранилище Obsidian не найдено · сохраню в Документы/Loftie" }
        return "Во «Входящие» хранилища «\(vault.name)»"
    }

    private var vaultPicker: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Хранилище Obsidian").font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.tertiary)
                .padding(.horizontal, 8).padding(.bottom, 2)
            ForEach(voice.vaults) { vault in
                DropdownRow(action: {
                    voice.vaultPath = vault.path
                    withAnimation(.easeOut(duration: 0.15)) { pickerOpen = false }
                }) {
                    Image(systemName: "checkmark").frame(width: 14)
                        .opacity(voice.vault == vault ? 1 : 0)
                        .foregroundStyle(Palette.mint)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(vault.name)
                        Text((vault.path as NSString).abbreviatingWithTildeInPath)
                            .font(.system(size: 10)).foregroundStyle(Palette.tertiary).lineLimit(1).truncationMode(.middle)
                    }
                }
            }
        }
        .padding(8)
        .frame(width: 300)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.popover))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Palette.hairline, lineWidth: 1))
        .shadow(color: .black.opacity(0.45), radius: 18, y: 10)
        .onHover { inside in
            guard !inside else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                withAnimation(.easeOut(duration: 0.15)) { pickerOpen = false }
            }
        }
    }

    private func elapsed(_ now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(voice.startedAt)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
