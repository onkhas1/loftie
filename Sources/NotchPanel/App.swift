import AppKit

@main
enum LoftieMain {
    static let delegate = AppDelegate()

    static func main() {
        let app = NSApplication.shared
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: NotchController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = NotchController()
        // Отладка: `NotchPanel --snapshot путь.png` рисует открытую панель в картинку и выходит
        let args = CommandLine.arguments
        if let index = args.firstIndex(of: "--snapshot"), index + 1 < args.count {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                MainActor.assumeIsolated {
                    self.controller?.snapshot(to: URL(fileURLWithPath: args[index + 1])) { NSApp.terminate(nil) }
                }
            }
        }
    }
}
