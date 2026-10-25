import AnyPS5Core
import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// A picture being cut square for the profile: the source read upright, and where the square is.
struct PictureCrop {
    let image: CGImage
    var zoom: Double = 1
    var offset: CGPoint = .zero
    /// The settings panel's place to go back to.
    var returnCategory = 0
    var returnRow = 0

    static let zoomRange: ClosedRange<Double> = 1...4

    var rect: CGRect { ProfilePicture.crop(width: image.width, height: image.height, zoom: zoom, offset: offset) }
}

/// Settings → Behaviour → Profile Picture: choosing a picture, cutting it square, keeping it in
/// Application Support/AnyPS5/profile.png for the top bar, and AnyTogether's avatar both ways.
extension AppModel {
    // MARK: Rows

    func profilePictureRows() -> [PanelRow] {
        var rows = [
            PanelRow(id: "picture", title: T.text(.profilePicture), detail: T.text(profilePicture == nil ? .profilePictureNone : .profilePictureDetail),
                     kind: .action(destructive: false) { [weak self] in self?.chooseProfilePicture() },
                     person: PanelPerson(name: preferences.profileName, avatar: nil, picture: profilePicture)),
        ]
        if togetherUser != nil, profilePicture != nil {
            rows.append(PanelRow(id: "pictureUpload", title: T.text(.profilePictureUpload), detail: pictureBusy ? T.text(.profileLoading) : T.text(.profilePictureUploadDetail),
                                 symbol: "icloud.and.arrow.up", kind: .action(destructive: false) { [weak self] in self?.uploadProfilePicture() }))
        }
        if let avatar = togetherUser?.avatar, !avatar.isEmpty {
            rows.append(PanelRow(id: "pictureFromTogether", title: T.text(.profilePictureFromTogether), detail: T.text(.profilePictureFromTogetherDetail),
                                 symbol: "icloud.and.arrow.down", kind: .action(destructive: false) { [weak self] in self?.useTogetherPicture() }))
        }
        if profilePicture != nil {
            rows.append(PanelRow(id: "pictureRemove", title: T.text(.profilePictureRemove), symbol: "xmark.circle",
                                 kind: .action(destructive: true) { [weak self] in self?.removeProfilePicture() }))
        }
        return rows
    }

    // MARK: Choosing and cutting

    func loadProfilePicture() {
        profilePicture = NSImage(contentsOf: ProfilePicture.file)
    }

    /// The open panel, and nothing else: the picture goes on to the crop.
    func chooseProfilePicture() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image]
        panel.prompt = T.text(.chooseFile)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        cropPicture(try? Data(contentsOf: url))
    }

    /// Opens the crop on a picture file's bytes.
    func cropPicture(_ data: Data?) {
        guard let data, let image = ProfilePicture.read(data) else { return show(T.text(.profilePictureUnreadable), symbol: "exclamationmark.triangle.fill") }
        guard min(image.width, image.height) >= ProfilePicture.uploadMinSide else { return show(T.text(.profilePictureTooSmall), symbol: "exclamationmark.triangle.fill") }
        pictureCrop = PictureCrop(image: image, returnCategory: panelCategory, returnRow: panelRow)
        withAnimation(Motion.overlay) { overlay = .cropPicture }
        Sounds.shared.play(.select)
    }

    /// The crop's keys: ← → zoom, Select saves, Back cancels.
    func cropCommand(_ command: Command) {
        switch command {
        case .left, .right:
            guard var crop = pictureCrop else { return }
            crop.zoom = min(max(crop.zoom + (command == .right ? 0.25 : -0.25), PictureCrop.zoomRange.lowerBound), PictureCrop.zoomRange.upperBound)
            pictureCrop = crop
            Sounds.shared.play(.move)
        case .select: saveCrop()
        case .back, .options: endCrop(saved: false)
        default: break
        }
    }

    func saveCrop() {
        guard let crop = pictureCrop, let png = ProfilePicture.png(crop.image, crop: crop.rect) else { return }
        do {
            try FileManager.default.createDirectory(at: ProfilePicture.file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try png.write(to: ProfilePicture.file, options: .atomic)
            profilePicture = NSImage(data: png)
            endCrop(saved: true)
            show(T.text(.profilePictureSaved), symbol: "person.crop.circle.fill.badge.checkmark")
        } catch {
            show(T.text(.profilePictureUnreadable) + ": " + error.localizedDescription, symbol: "exclamationmark.triangle.fill")
        }
    }

    /// Back to the settings row the picture was chosen from.
    func endCrop(saved: Bool) {
        let place = pictureCrop.map { ($0.returnCategory, $0.returnRow) } ?? (0, 0)
        pictureCrop = nil
        withAnimation(Motion.overlay) {
            overlay = .settings
            panelCategory = place.0
            panelRow = place.1
            panelInRows = true
        }
        Sounds.shared.play(saved ? .select : .back)
    }

    func removeProfilePicture() {
        try? FileManager.default.removeItem(at: ProfilePicture.file)
        profilePicture = nil
        show(T.text(.profilePictureRemoved), symbol: "person.crop.circle")
    }

    // MARK: AnyTogether

    /// The kept picture as the account's avatar (PUT /me/avatar).
    func uploadProfilePicture() {
        guard togetherUser != nil, !pictureBusy, let data = try? Data(contentsOf: ProfilePicture.file) else { return }
        if ProfilePicture.uploadProblem(data) != nil { return show(T.text(.profilePictureUploadFailed), symbol: "exclamationmark.triangle.fill") }
        pictureBusy = true
        Task { @MainActor in
            defer { self.pictureBusy = false }
            do {
                _ = try await self.together.uploadAvatar(data)
                self.togetherUser = self.together.user
                self.loadTogetherProfile()
                self.show(T.text(.profilePictureUploaded), symbol: "checkmark.circle.fill")
            } catch {
                self.show(T.text(.profilePictureUploadFailed) + ": " + self.togetherMessage(error), symbol: "exclamationmark.triangle.fill")
            }
        }
    }

    /// The account's avatar as the picture here.
    func useTogetherPicture() {
        guard let address = togetherUser?.avatar.flatMap(URL.init(string:)), !pictureBusy else { return }
        pictureBusy = true
        Task { @MainActor in
            defer { self.pictureBusy = false }
            guard let (data, response) = try? await URLSession.shared.data(from: address), (response as? HTTPURLResponse)?.statusCode == 200,
                  let png = ProfilePicture.png(fromSquare: data) else {
                return self.show(T.text(.profilePictureDownloadFailed), symbol: "exclamationmark.triangle.fill")
            }
            do {
                try FileManager.default.createDirectory(at: ProfilePicture.file.deletingLastPathComponent(), withIntermediateDirectories: true)
                try png.write(to: ProfilePicture.file, options: .atomic)
                self.profilePicture = NSImage(data: png)
                self.show(T.text(.profilePictureSaved), symbol: "person.crop.circle.fill.badge.checkmark")
            } catch {
                self.show(T.text(.profilePictureDownloadFailed), symbol: "exclamationmark.triangle.fill")
            }
        }
    }

    /// Opens the crop on a picture without the open panel (offscreen previews).
    func previewCrop(_ image: CGImage, zoom: Double, offset: CGPoint) {
        pictureCrop = PictureCrop(image: image, zoom: zoom, offset: offset)
        overlay = .cropPicture
    }
}

/// The small sheet that cuts the picture square: drag it inside the circle, zoom with the slider
/// or ← →, then Save.
struct PictureCropView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scale) private var scale
    @State private var dragFrom: CGPoint?
    @State private var hovering = false

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial).overlay(Color.black.opacity(0.5)).ignoresSafeArea()
                .contentShape(Rectangle()).onTapGesture {}
            if let crop = model.pictureCrop {
                sheet(crop)
            }
        }
    }

    private func sheet(_ crop: PictureCrop) -> some View {
        let side = 360 * scale
        return VStack(spacing: 22 * scale) {
            Text(T.text(.cropTitle)).font(.display(26 * scale, .semibold)).foregroundStyle(.white)
            area(crop, side: side)
            HStack(spacing: 14 * scale) {
                Image(systemName: "minus.magnifyingglass")
                ZoomSlider(value: Binding(get: { model.pictureCrop?.zoom ?? 1 }, set: { model.pictureCrop?.zoom = $0 }), range: PictureCrop.zoomRange)
                    .accessibilityLabel(T.text(.cropZoom))
                Image(systemName: "plus.magnifyingglass")
            }
            .font(.system(size: 15 * scale, weight: .semibold))
            .foregroundStyle(.white.opacity(0.75))
            .frame(width: side)
            HStack(spacing: 14 * scale) {
                ConsoleButton(title: T.text(.cancel), focused: false, minWidth: 150) { model.endCrop(saved: false) }
                ConsoleButton(title: T.text(.cropSave), focused: true, minWidth: 150) { model.saveCrop() }
            }
            HStack(spacing: 22 * scale) {
                Hint(keys: "← →", label: T.text(.cropZoom))
                Hint(keys: "↩ / ✕", label: T.text(.cropSave))
                Hint(keys: "esc / ○", label: T.text(.cancel))
            }
        }
        .padding(.horizontal, 44 * scale)
        .padding(.vertical, 36 * scale)
        .glass(30 * scale, opacity: 0.62)
        .shadow(color: .black.opacity(0.45), radius: 40 * scale, y: 16 * scale)
    }

    /// The picture in a square, dimmed around the circle the avatar will be and lit inside it.
    private func area(_ crop: PictureCrop, side: CGFloat) -> some View {
        let rect = crop.rect
        let margin = side * 0.11
        let circle = side - 2 * margin
        let factor = circle / rect.width
        let picture = Image(decorative: crop.image, scale: 1).resizable().interpolation(.high)
            .frame(width: CGFloat(crop.image.width) * factor, height: CGFloat(crop.image.height) * factor)
            .offset(x: margin - rect.minX * factor, y: margin - rect.minY * factor)
        let placed = ZStack(alignment: .topLeading) { picture }.frame(width: side, height: side, alignment: .topLeading)
        return ZStack {
            Color.black.opacity(0.35)
            placed.opacity(0.3)
            placed.mask(Circle().frame(width: circle, height: circle))
            Circle().strokeBorder(Color.white.opacity(0.85), lineWidth: 2 * scale).frame(width: circle, height: circle)
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: 22 * scale, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22 * scale, style: .continuous).strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
        .overlay(alignment: .bottom) {
            Label(T.text(.cropHint), systemImage: "hand.draw")
                .font(.display(12 * scale, .medium)).foregroundStyle(.white.opacity(0.8))
                .padding(.horizontal, 10 * scale).padding(.vertical, 5 * scale)
                .background(Capsule().fill(Color.black.opacity(0.45)))
                .padding(.bottom, 10 * scale)
        }
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 1).onChanged { drag in
            guard var current = model.pictureCrop else { return }
            let start = dragFrom ?? current.offset
            if dragFrom == nil { dragFrom = start }
            let pixels = CGSize(width: drag.translation.width / factor, height: drag.translation.height / factor)
            current.offset = ProfilePicture.offset(start, movedBy: pixels, width: current.image.width, height: current.image.height, zoom: current.zoom)
            model.pictureCrop = current
        }.onEnded { _ in dragFrom = nil })
        .pointingHand($hovering, cursor: .openHand)
    }
}

/// The crop's zoom: a thin track in the accent and a white knob, dragged or clicked.
private struct ZoomSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    @EnvironmentObject private var model: AppModel
    @Environment(\.scale) private var scale

    var body: some View {
        GeometryReader { proxy in
            let knob = 18 * scale
            let fraction = (min(max(value, range.lowerBound), range.upperBound) - range.lowerBound) / (range.upperBound - range.lowerBound)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.16)).frame(height: 4 * scale)
                Capsule().fill(model.accent).frame(width: max(4 * scale, knob / 2 + (proxy.size.width - knob) * fraction), height: 4 * scale)
                Circle().fill(Color.white).frame(width: knob, height: knob)
                    .shadow(color: .black.opacity(0.35), radius: 4 * scale, y: 1 * scale)
                    .offset(x: (proxy.size.width - knob) * fraction)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                let position = min(max((drag.location.x - knob / 2) / max(1, proxy.size.width - knob), 0), 1)
                value = range.lowerBound + Double(position) * (range.upperBound - range.lowerBound)
            })
        }
        .frame(height: 24 * scale)
    }
}
