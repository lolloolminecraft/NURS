import AppIntents
import Foundation

/// Performs a quick GitHub status check without opening the NM interface.
/// Intended for use from a personal Shortcuts automation.
struct NMCheckPS4Intent: AppIntent {
    static var title: LocalizedStringResource = "Проверить PS4 14.00"
    static var description = IntentDescription(
        "Получает текущий статус из GitHub. При значимом изменении Nurs-Mode сохраняет новость и создаёт локальное уведомление."
    )

    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let success = await NMBackgroundMonitor.check()
        if success {
            return .result(dialog: "Nurs-Mode проверил статус PS4 14.00")
        } else {
            return .result(dialog: "Nurs-Mode не смог проверить GitHub. Попробуй позже.")
        }
    }
}

struct NMAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: NMCheckPS4Intent(),
            phrases: [
                "Проверь PS4 через \(.applicationName)",
                "Check PS4 with \(.applicationName)"
            ],
            shortTitle: "Проверить PS4",
            systemImageName: "gamecontroller.fill"
        )
    }
}
