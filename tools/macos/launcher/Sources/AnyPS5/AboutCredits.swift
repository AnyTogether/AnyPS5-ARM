import AnyPS5Core
import SwiftUI

/// Settings › About's credits, as on Windows and Linux: the owner centred above, then up to
/// twelve contributors. ← and → go from face to face, ✕ or Return opens the selected one's GitHub
/// profile, and ← on the owner leaves the rows as from any other row.
struct PanelCredits {
    struct Face: Equatable {
        let name: String
        let avatar: String?
        let page: URL
        let contributions: Int
    }

    let owner: Face
    let people: [Face]
    /// The face the keys and the pad are on: 0 the owner, then `people` in order.
    let selected: Int
    let select: (Int) -> Void
    let open: (Int) -> Void
    /// A click on a face: the focus goes there and it opens.
    let click: (Int) -> Void

    /// The owner, then the others: the order ← and → go through.
    var faces: [Face] { [owner] + people }
}

extension AppModel {
    /// The credits, then See all on GitHub, in Settings › About.
    func creditRows() -> [PanelRow] {
        loadContributorsIfNeeded()
        let list = contributors ?? []
        let fromGitHub = list.first { $0.login.lowercased() == GithubContributors.ownerLogin }
        let owner = PanelCredits.Face(name: GithubContributors.ownerName, avatar: fromGitHub?.avatar,
                                      page: fromGitHub?.page ?? GithubContributors.ownerPage, contributions: fromGitHub?.contributions ?? 0)
        let people = list.filter { $0.login.lowercased() != GithubContributors.ownerLogin }.prefix(GithubContributors.shown)
            .map { PanelCredits.Face(name: $0.login, avatar: $0.avatar, page: $0.page, contributions: $0.contributions) }
        let faces = [owner] + people
        let credits = PanelCredits(owner: owner, people: people, selected: min(max(0, contributorFace), faces.count - 1),
                                   select: { [weak self] face in
                                       guard let self else { return }
                                       let next = min(max(0, face), faces.count - 1)
                                       if self.contributorFace != next { self.contributorFace = next }
                                   },
                                   open: { [weak self] face in self?.openLink(faces[min(max(0, face), faces.count - 1)].page) },
                                   click: { [weak self] face in self?.clickContributor(face) })
        return [
            PanelRow(id: "contributorsGrid", title: T.text(.contributors), kind: .credits(credits)),
            PanelRow(id: "contributorsAll", title: T.text(.seeAllContributors), detail: GithubContributors.allPage.absoluteString.replacingOccurrences(of: "https://", with: ""),
                     symbol: "person.3", kind: .action(destructive: false) { [weak self] in self?.openLink(GithubContributors.allPage) }),
        ]
    }

    /// Asks GitHub once, the first time About is drawn; the tests give a source or none.
    func loadContributorsIfNeeded() {
        guard contributors == nil, !contributorsAsked, let source = contributorsSource else { return }
        contributorsAsked = true
        Task { @MainActor [weak self] in
            let people = await source()
            self?.contributors = people
        }
    }

    /// ← or → on the credits: the face before or after, true when there was one.
    func stepCredits(_ credits: PanelCredits, by delta: Int) -> Bool {
        let next = credits.selected + delta
        guard credits.faces.indices.contains(next) else { return false }
        credits.select(next)
        Sounds.shared.play(.move)
        return true
    }

    /// A face clicked: the credits row takes the focus, the face is selected and it opens.
    func clickContributor(_ face: Int) {
        let categories = panelCategories()
        guard categories.indices.contains(panelCategory) else { return }
        let rows = categories[panelCategory].rows
        guard let index = rows.firstIndex(where: { $0.id == "contributorsGrid" }), case .credits(let credits) = rows[index].kind else { return }
        if overlayHasCategories { panelInRows = true }
        settingsSearchFocused = false
        settingsTyping = false
        if rowEditor.editing != nil { rowEditor.stop() }
        focusRow(index, in: rows)
        credits.select(face)
        Sounds.shared.play(.select)
        credits.open(face)
    }
}

/// The credits row: the owner above, the others wrapped beneath, the selected face wearing the
/// row's focus fill while the row has the focus.
struct CreditsView: View {
    let credits: PanelCredits
    let focused: Bool
    @Environment(\.scale) private var scale

    var body: some View {
        VStack(spacing: 0) {
            face(0) { on in
                VStack(spacing: 10 * scale) {
                    Text(T.text(.madeBy)).font(.display(13 * scale, .semibold)).foregroundStyle(ink(on).opacity(0.55))
                    ProfileAvatar(url: credits.owner.avatar, name: credits.owner.name, size: 72 * scale, glow: false)
                        .shadow(color: .black.opacity(0.35), radius: 10 * scale, y: 5 * scale)
                    Text(credits.owner.name).font(.display(15 * scale, .semibold)).foregroundStyle(ink(on).opacity(0.92))
                }
            }
            if !credits.people.isEmpty {
                Text(T.text(.contributors)).font(.display(12 * scale, .semibold)).foregroundStyle(.white.opacity(0.45))
                    .padding(.top, 22 * scale).padding(.bottom, 14 * scale)
                CreditsFlow(spacing: 22 * scale, lineSpacing: 14 * scale) {
                    ForEach(Array(credits.people.enumerated()), id: \.offset) { index, person in
                        face(index + 1) { on in
                            HStack(spacing: 10 * scale) {
                                ProfileAvatar(url: person.avatar, name: person.name, size: 44 * scale, glow: false)
                                    .shadow(color: .black.opacity(0.3), radius: 6 * scale, y: 3 * scale)
                                VStack(alignment: .leading, spacing: 2 * scale) {
                                    Text(person.name).font(.display(13 * scale, .semibold)).lineLimit(1).foregroundStyle(ink(on).opacity(0.92))
                                    Text(AppModel.commits(person.contributions)).font(.display(11 * scale)).foregroundStyle(ink(on).opacity(0.5))
                                }
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12 * scale)
    }

    private func ink(_ on: Bool) -> Color { on ? .black : .white }

    private func face<Content: View>(_ index: Int, @ViewBuilder _ content: (Bool) -> Content) -> some View {
        let on = focused && credits.selected == index
        let person = credits.faces[index]
        return Button { credits.click(index) } label: {
            content(on)
                .padding(.horizontal, 12 * scale)
                .padding(.vertical, 8 * scale)
                .background(FocusFill(RoundedRectangle(cornerRadius: 12 * scale, style: .continuous), focused: on, idle: .clear))
                .shadow(color: .white.opacity(on ? 0.22 : 0), radius: 12 * scale)
                .scaleEffect(on ? 1.03 : 1)
                .animation(Motion.focus, value: on)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverTick("contributor-\(index)")
        .accessibilityLabel(index == 0 ? T.text(.madeBy) + " " + person.name : person.name)
        .accessibilityValue(index == 0 ? "" : AppModel.commits(person.contributions))
    }
}

extension AppModel {
    /// "72 commits", "1 commit", "1,180 commits" in the language shown.
    static func commits(_ count: Int) -> String {
        T.format(count == 1 ? .contributorCommitsOne : .contributorCommits, LevelCard.number(count))
    }
}

/// The contributors' faces in lines as wide as the row, each line centred.
struct CreditsFlow: Layout {
    let spacing: CGFloat
    let lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let lines = self.lines(subviews, width: width)
        let height = lines.reduce(0) { $0 + $1.height } + lineSpacing * CGFloat(max(0, lines.count - 1))
        let widest = lines.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? widest, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for line in lines(subviews, width: bounds.width) {
            var x = bounds.midX - line.width / 2
            for index in line.items {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (line.height - size.height) / 2), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += line.height + lineSpacing
        }
    }

    private struct Line {
        var items: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func lines(_ subviews: Subviews, width: CGFloat) -> [Line] {
        var lines: [Line] = []
        var line = Line()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let wider = line.items.isEmpty ? size.width : line.width + spacing + size.width
            if !line.items.isEmpty && wider > width {
                lines.append(line)
                line = Line()
            }
            line.width = line.items.isEmpty ? size.width : line.width + spacing + size.width
            line.height = max(line.height, size.height)
            line.items.append(index)
        }
        if !line.items.isEmpty { lines.append(line) }
        return lines
    }
}
