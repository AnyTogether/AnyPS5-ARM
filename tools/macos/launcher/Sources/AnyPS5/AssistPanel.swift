import AnyPS5Core
import SwiftUI

/// Assist: another device helps player 1 (Settings → Controllers → Assist Player 1, and each
/// share play guest's own row). The phone server marks a helping phone's or browser pad's pad and
/// tells the engine whether the Mac's other controllers help; share play marks a guest's.
extension AppModel {
    var assistTarget: AssistTarget { AssistTarget(stored: preferences.assistPlayerOne) }

    /// The setting as the phone server needs it.
    func applyAssist() {
        let target = assistTarget
        remote?.setAssist(devices: target.devices, controllers: target.controllers)
    }

    /// Settings → Controllers: off, the other controllers, or a phone or browser pad connected now
    /// (the chosen one stays listed while it is away).
    func assistRow() -> PanelRow {
        let chosen = assistTarget
        let connected = connectedPhones.map { id in (id: id, name: phones.first { $0.id == id }?.name ?? id) }
        let names = Dictionary(phones.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        let choices = AssistTarget.choices(devices: connected, chosen: chosen, names: names)
        let labels = choices.map { choice -> String in
            switch choice.target {
            case .off: return TA.text(.assistOff)
            case .controllers: return TA.text(.assistControllers)
            case .device: return choice.name ?? ""
            }
        }
        let selected = choices.firstIndex { $0.target == chosen } ?? 0
        let detail = chosen == .off ? TA.text(.assistDetail) : TA.format(.assistOn, labels[selected])
        return PanelRow(id: "padAssist", title: TA.text(.assist), detail: detail, symbol: "person.2.wave.2",
                        kind: .choice(options: labels, selected: selected) { [weak self] index in
            guard choices.indices.contains(index) else { return }
            self?.preferences.assistPlayerOne = choices[index].target.stored
        })
    }

    /// A share play guest with a pad: help player 1 rather than play their own.
    func shareAssistRow(_ userId: String, name: String) -> PanelRow? {
        guard let router = shareSession?.router else { return nil }
        let helping = router.assist.contains(userId)
        return PanelRow(id: "share-assist-\(userId)", title: TA.text(.assistShare), detail: TA.format(.assistShareDetail, name), symbol: "person.2.wave.2",
                        kind: .toggle(helping) { [weak self] on in
            if on { router.assist.insert(userId) } else { router.assist.remove(userId) }
            self?.objectWillChange.send()
        })
    }
}
