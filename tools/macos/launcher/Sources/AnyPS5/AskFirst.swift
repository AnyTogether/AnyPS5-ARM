import AnyPS5Core
import SwiftUI

/// Social steps that cannot be taken back ask first, in place: pressing the row turns it into the
/// question, the step itself and Cancel, with Cancel focused, so a pad's confirm button pressed
/// twice by habit never removes someone or leaves a party. Back (✕, Escape) answers Cancel.
extension AppModel {
    /// `row` as it shows: itself, asking first when pressed, or the question while it asks. The
    /// step is `confirm` when given, else the row's own title (a row that names something, such
    /// as a games folder, rather than the step).
    func askingFirst(_ row: PanelRow, question: String, confirm: String? = nil) -> [PanelRow] {
        guard case .action(let destructive, let run) = row.kind else { return [row] }
        guard askingRow == row.id else {
            return [PanelRow(id: row.id, title: row.title, detail: row.detail, symbol: row.symbol,
                             kind: .action(destructive: destructive) { [weak self] in self?.ask(row.id) }, person: row.person)]
        }
        return [
            PanelRow(id: row.id + "-ask", title: question, symbol: "exclamationmark.triangle.fill", kind: .info(""), wraps: true),
            PanelRow(id: row.id + "-yes", title: confirm ?? row.title, symbol: row.symbol, kind: .action(destructive: true) { [weak self] in
                self?.askingRow = nil
                run()
            }),
            PanelRow(id: row.id + "-cancel", title: T.text(.cancel), symbol: "arrow.uturn.backward", kind: .action(destructive: false) { [weak self] in
                self?.cancelAsk()
            }),
        ]
    }

    /// The question comes in place of the row, Cancel focused.
    func ask(_ id: String) {
        withAnimation(Motion.focus) { askingRow = id }
        panelFocusID = id + "-cancel"
    }

    /// Cancel or Back: the row again, focused. False when nothing was asking.
    @discardableResult
    func cancelAsk() -> Bool {
        guard let id = askingRow else { return false }
        withAnimation(Motion.focus) { askingRow = nil }
        panelFocusID = id
        Sounds.shared.play(.back)
        return true
    }
}
