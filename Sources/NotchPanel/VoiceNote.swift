import AppKit
import AVFoundation
import Speech

/// Быстрая запись: голос → текст (русское распознавание macOS) → заметка во «Входящие» хранилища Obsidian.
final class VoiceNote: ObservableObject {
    enum State: Equatable {
        case idle
        case recording
        case saved(URL)
        case failed(String)
    }

    @Published var state: State = .idle
    @Published var transcript = ""
    @Published var level: CGFloat = 0
    @Published var startedAt = Date()
    @Published private(set) var vaults: [Obsidian.Vault] = []
    @Published var vaultPath: String? = UserDefaults.standard.string(forKey: "obsidianVault") {
        didSet { UserDefaults.standard.set(vaultPath, forKey: "obsidianVault") }
    }

    private let engine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ru-RU"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    init() {
        // Выбор хранилища из версий до 1.0, когда приложение называлось иначе
        if vaultPath == nil, let old = UserDefaults(suiteName: "com.sakhno.chelka")?.string(forKey: "obsidianVault") {
            vaultPath = old
        }
        refreshVaults()
    }

    var obsidianInstalled: Bool { Obsidian.isInstalled }

    /// Выбранное хранилище, иначе открытое последним
    var vault: Obsidian.Vault? {
        guard obsidianInstalled else { return nil }
        return vaults.first { $0.path == vaultPath } ?? vaults.first
    }

    func refreshVaults() { vaults = Obsidian.vaults }

    // MARK: Запись

    func start() {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                guard status == .authorized else {
                    self.state = .failed("Нет доступа к распознаванию речи — разреши в настройках")
                    return
                }
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    DispatchQueue.main.async {
                        granted ? self.begin() : (self.state = .failed("Нет доступа к микрофону — разреши в настройках"))
                    }
                }
            }
        }
    }

    private func begin() {
        guard let recognizer, recognizer.isAvailable else {
            state = .failed("Распознавание русской речи сейчас недоступно")
            return
        }
        transcript = ""
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // Серверное распознавание Apple (как обычная диктовка) расставляет знаки препинания,
        // распознавание на устройстве для русского их не ставит
        request.addsPunctuation = true
        request.requiresOnDeviceRecognition = false
        self.request = request

        let input = engine.inputNode
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { [weak self] buffer, _ in
            request.append(buffer)
            // Громкость для пульсации кольца
            guard let data = buffer.floatChannelData?[0] else { return }
            let count = Int(buffer.frameLength)
            var sum: Float = 0
            for i in 0..<count { sum += data[i] * data[i] }
            let rms = sqrt(sum / Float(max(count, 1)))
            DispatchQueue.main.async { self?.level = min(1, CGFloat(rms) * 12) }
        }
        do {
            engine.prepare()
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            state = .failed("Микрофон не запустился")
            return
        }
        task = recognizer.recognitionTask(with: request) { [weak self] result, _ in
            guard let result else { return }
            DispatchQueue.main.async { self?.transcript = result.bestTranscription.formattedString }
        }
        startedAt = Date()
        state = .recording
    }

    /// Остановить; save — сохранить распознанный текст
    func stop(save: Bool) {
        guard state == .recording else { return }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        level = 0
        // Даём распознаванию дописать последние слова
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            self.task?.cancel()
            self.task = nil
            self.request = nil
            if save, !self.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                self.save(self.transcript)
            } else {
                self.state = .idle
            }
        }
    }

    // MARK: Сохранение

    func save(_ text: String) {
        let body = Self.tidy(text)
        guard !body.isEmpty else { return }
        do {
            let url = try Self.write(body, to: vault)
            state = .saved(url)
            transcript = ""
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                if case .saved = self.state { self.state = .idle }
            }
        } catch {
            state = .failed("Не получилось сохранить заметку")
        }
    }

    /// Заглавная буква в начале и точка в конце, если распознавание их не поставило
    static func tidy(_ text: String) -> String {
        var body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = body.first else { return body }
        body = first.uppercased() + body.dropFirst()
        if let last = body.last, !".!?…".contains(last) { body += "." }
        return body
    }

    /// Куда ляжет заметка: «Входящие» хранилища или ~/Documents/Loftie
    var destinationName: String {
        vault.map { "«Входящие» хранилища «\($0.name)»" } ?? "папку Документы/Loftie"
    }

    private static func write(_ text: String, to vault: Obsidian.Vault?) throws -> URL {
        let folder = vault.map { URL(fileURLWithPath: $0.path).appendingPathComponent("Входящие", isDirectory: true) }
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Loftie", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let now = Date()
        let stamp = DateFormatter()
        stamp.locale = Locale(identifier: "ru_RU")
        stamp.dateFormat = "yyyy-MM-dd HH-mm"
        // Имя файла: время и первые слова
        let words = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.prefix(6).joined(separator: " ")
        let safe = words.components(separatedBy: CharacterSet(charactersIn: "/\\:*?\"<>|#^[]")).joined()
        var url = folder.appendingPathComponent("\(stamp.string(from: now)) \(safe).md")
        var counter = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent("\(stamp.string(from: now)) \(safe) \(counter).md")
            counter += 1
        }

        let iso = DateFormatter()
        iso.dateFormat = "yyyy-MM-dd'T'HH:mm"
        let note = """
        ---
        created: \(iso.string(from: now))
        source: loftie
        tags:
          - входящие
        ---

        \(text)

        """
        try note.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// Открыть сохранённую заметку в Obsidian
    func open(_ url: URL) {
        var parts = URLComponents(string: "obsidian://open")!
        parts.queryItems = [URLQueryItem(name: "path", value: url.path)]
        if let link = parts.url, obsidianInstalled, vault != nil {
            NSWorkspace.shared.open(link)
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }
}
