import AnyPS5Core
import SwiftUI

/// The lock state beside a direct conversation's name: end-to-end encrypted (with a seal once the
/// safety number was compared), not encrypted, or encrypted but the other person has no device.
/// Clicking it opens the encryption sheet.
struct E2EELockPill: View {
    let conversation: TogetherConversation
    let lock: TogetherE2EEBook.Lock
    @EnvironmentObject private var model: AppModel
    @Environment(\.scale) private var scale

    static let warning = Color(red: 1, green: 0.78, blue: 0.42)

    var body: some View {
        let compared = lock == .on && model.e2ee?.isCompared(conversation) == true
        HStack(spacing: 5 * scale) {
            Image(systemName: symbol).font(.system(size: 10 * scale, weight: .bold))
            Text(TChat.text(lock == .off ? .e2eeOff : .e2eeOn)).font(.display(12 * scale, .semibold))
            if compared {
                Image(systemName: "checkmark.seal.fill").font(.system(size: 10 * scale, weight: .bold)).foregroundStyle(model.accent)
                    .transition(.scale(scale: 0.5).combined(with: .opacity))
            }
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, 9 * scale)
        .padding(.vertical, 4 * scale)
        .background(Capsule().fill(fill))
        .overlay(Capsule().strokeBorder(stroke, lineWidth: 1))
        .contentShape(Capsule())
        .onTapGesture { model.openEncryptionSheet(conversation.id) }
        .help(TChat.text(lock == .off ? .e2eeOff : .e2eeOn) + (compared ? " · " + TChat.text(.e2eeCompared) : ""))
        .animation(Motion.focus, value: compared)
        .animation(Motion.focus, value: lock)
    }

    private var symbol: String {
        switch lock {
        case .on: return "lock.fill"
        case .off: return "lock.open"
        case .noDevice: return "lock.trianglebadge.exclamationmark"
        case .waiting: return "lock"
        }
    }

    private var foreground: Color {
        switch lock {
        case .on: return .white
        case .noDevice: return Self.warning
        case .off, .waiting: return .white.opacity(0.55)
        }
    }

    private var fill: Color {
        switch lock {
        case .on: return model.accent.opacity(0.24)
        case .noDevice: return Self.warning.opacity(0.12)
        case .off, .waiting: return .white.opacity(0.06)
        }
    }

    private var stroke: Color {
        switch lock {
        case .on: return model.accent.opacity(0.55)
        case .noDevice: return Self.warning.opacity(0.35)
        case .off, .waiting: return .white.opacity(0.08)
        }
    }
}

/// In the thread until dismissed: someone's devices changed, so the safety number should be
/// compared again.
struct E2EENoticeBar: View {
    let conversation: TogetherConversation
    let notice: TogetherE2EEBook.Notice
    @EnvironmentObject private var model: AppModel
    @Environment(\.scale) private var scale

    var body: some View {
        HStack(spacing: 12 * scale) {
            Image(systemName: "lock.rotation").font(.system(size: 14 * scale, weight: .semibold)).foregroundStyle(model.accent)
            Text(notice.theirs ? TChat.format(.e2eeDevicesChanged, model.e2eeName(conversation)) : TChat.text(.e2eeMyDevicesChanged))
                .font(.display(13 * scale, .semibold)).foregroundStyle(.white.opacity(0.85))
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8 * scale)
            pill(TChat.text(.e2eeCompare), filled: true) { model.openEncryptionSheet(conversation.id) }
            pill(TChat.text(.e2eeDismiss), filled: false) { model.dismissE2EENotice(conversation.id) }
        }
        .padding(.leading, 14 * scale).padding(.trailing, 10 * scale).padding(.vertical, 9 * scale)
        .background(
            RoundedRectangle(cornerRadius: 14 * scale, style: .continuous).fill(Color.white.opacity(0.06))
                .overlay(alignment: .leading) { Capsule().fill(model.accent).frame(width: 3 * scale).padding(.vertical, 8 * scale) }
        )
    }

    private func pill(_ title: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.display(13 * scale, .semibold)).foregroundStyle(.white)
                .padding(.horizontal, 12 * scale).padding(.vertical, 6 * scale)
                .background(Capsule().fill(filled ? model.accent.opacity(0.85) : Color.white.opacity(0.1)))
        }
        .buttonStyle(.plain)
    }
}

/// Where the field would be while the other person has no device that reads sealed messages.
struct E2EEComposerNotice: View {
    let conversation: TogetherConversation
    @EnvironmentObject private var model: AppModel
    @Environment(\.scale) private var scale

    var body: some View {
        HStack(spacing: 12 * scale) {
            Image(systemName: "lock.trianglebadge.exclamationmark").font(.system(size: 16 * scale, weight: .semibold)).foregroundStyle(E2EELockPill.warning)
            Text(TChat.format(.e2eeNoDevice, model.e2eeName(conversation))).font(.display(14 * scale, .medium)).foregroundStyle(.white.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18 * scale)
        .padding(.vertical, 14 * scale)
        .background(RoundedRectangle(cornerRadius: 16 * scale, style: .continuous).fill(Color.white.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 16 * scale, style: .continuous).strokeBorder(Color.white.opacity(0.1), style: StrokeStyle(lineWidth: 1, dash: [5 * scale, 4 * scale])))
        .onTapGesture { model.openEncryptionSheet(conversation.id) }
    }
}

/// A sealed message's bubble as it opened here: its words and attachment, or why it cannot be
/// read (never its stand-in text).
struct SealedMessageContent: View {
    let message: TogetherMessage
    let mine: Bool
    @EnvironmentObject private var model: AppModel
    @Environment(\.scale) private var scale

    var body: some View {
        switch model.e2ee?.opened(message) {
        case .payload(let payload):
            if let attachment = payload.attachment { media(attachment) }
            if let text = payload.text, !text.isEmpty { textBubble(text) }
        case .beforeDevice:
            failure(TChat.text(.e2eeBeforeDevice), symbol: "clock.badge.xmark")
        case .undecryptable:
            failure(TChat.text(.e2eeUndecryptable), symbol: "lock.slash")
        case nil:
            failure(TChat.text(.e2eePreview), symbol: "lock")
        }
    }

    @ViewBuilder private func media(_ attachment: TogetherE2EE.Attachment) -> some View {
        if let plain = message.attachment, plain.media == nil {
            // Removed, or one of the two blocked the other: as for a plain message.
            AttachmentBubble(attachment: plain, mine: mine)
        } else if let shown = model.sealedMedia(attachment) {
            AttachmentBubble(attachment: TogetherAttachment(media: shown), mine: mine)
        } else {
            AttachmentBubble(attachment: TogetherAttachment(media: TogetherMedia(id: attachment.mediaId, kind: attachment.kind, width: attachment.width, height: attachment.height,
                                                                                  durationMs: attachment.durationMs, url: nil, sealed: true)), mine: mine)
                .onAppear { if let media = message.attachment?.media { model.loadSealedMedia(attachment, from: media) } }
        }
    }

    private func textBubble(_ text: String) -> some View {
        Text(text)
            .font(.display(16 * scale))
            .foregroundStyle(.white)
            .padding(.horizontal, 14 * scale)
            .padding(.vertical, 9 * scale)
            .background(RoundedRectangle(cornerRadius: 18 * scale, style: .continuous).fill(mine ? model.accent.opacity(0.85) : Color.white.opacity(0.1)))
            .textSelection(.enabled)
    }

    private func failure(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.display(14 * scale, .medium))
            .italic()
            .foregroundStyle(.white.opacity(0.55))
            .padding(.horizontal, 14 * scale)
            .padding(.vertical, 10 * scale)
            .background(RoundedRectangle(cornerRadius: 18 * scale, style: .continuous).strokeBorder(Color.white.opacity(0.15), style: StrokeStyle(lineWidth: 1, dash: [4 * scale, 3 * scale])))
    }
}

/// The side sheet over Messages about a direct conversation's encryption: what it means, the
/// safety number in twelve groups of five (the first two rows one person's, the last two the
/// other's), "We compared them", both people's devices, and that a new device cannot read older
/// messages.
struct EncryptionSheet: View {
    let menu: MessageActions.Menu
    @EnvironmentObject private var model: AppModel
    @Environment(\.scale) private var scale
    @Environment(\.languageCode) private var languageCode

    var body: some View {
        let _ = languageCode
        let rows = model.menuRows(menu)
        let focusedRow = min(menu.row, max(0, rows.count - 1))
        if let conversation = model.menuConversation(menu), let me = model.inbox?.me {
            let lock = model.e2eeLock(conversation) ?? .off
            let name = model.e2eeName(conversation)
            let number = model.e2ee?.safetyNumber(conversation)
            VStack(alignment: .leading, spacing: 18 * scale) {
                header(conversation, lock: lock, name: name)
                Text(detail(lock, name: name))
                    .font(.display(15 * scale, .medium)).foregroundStyle(.white.opacity(0.78))
                    .fixedSize(horizontal: false, vertical: true)
                if let notice = model.e2ee?.notice(conversation.id) {
                    Label(notice.theirs ? TChat.format(.e2eeDevicesChanged, name) : TChat.text(.e2eeMyDevicesChanged), systemImage: "lock.rotation")
                        .font(.display(13 * scale, .semibold)).foregroundStyle(.white.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 12 * scale).padding(.vertical, 9 * scale)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 12 * scale, style: .continuous).fill(model.accent.opacity(0.16)))
                        .overlay(RoundedRectangle(cornerRadius: 12 * scale, style: .continuous).strokeBorder(model.accent.opacity(0.4), lineWidth: 1))
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                if lock == .on, let number {
                    safety(number, conversation: conversation, name: name)
                }
                VStack(alignment: .leading, spacing: 8 * scale) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                        action(row, focused: index == focusedRow).onTapGesture { model.perform(row, in: menu) }
                    }
                }
                if lock != .off { devices(conversation, me: me, name: name) }
                Spacer(minLength: 0)
                HStack(spacing: 18 * scale) {
                    Hint(keys: "↩ / ✕", label: T.text(.hintSelect))
                    Hint(keys: "esc / ○", label: T.text(.hintBack))
                }
            }
            .padding(30 * scale)
            .frame(width: 440 * scale)
            .frame(maxHeight: .infinity, alignment: .topLeading)
            .panelFrost(classic: 0.94)
            .overlay(Rectangle().fill(Color.white.opacity(0.08)).frame(width: 1), alignment: .leading)
            .animation(Motion.focus, value: model.e2ee)
        }
    }

    private func detail(_ lock: TogetherE2EEBook.Lock, name: String) -> String {
        switch lock {
        case .on, .waiting: return TChat.format(.e2eeOnDetail, name)
        case .off: return TChat.format(.e2eeOffDetail, name)
        case .noDevice: return TChat.format(.e2eeNoDevice, name)
        }
    }

    private func header(_ conversation: TogetherConversation, lock: TogetherE2EEBook.Lock, name: String) -> some View {
        let on = lock == .on || lock == .waiting
        return HStack(spacing: 14 * scale) {
            ZStack {
                RoundedRectangle(cornerRadius: 14 * scale, style: .continuous)
                    .fill(on ? model.accent.opacity(0.9) : lock == .noDevice ? E2EELockPill.warning.opacity(0.22) : Color.white.opacity(0.1))
                Image(systemName: lock == .off ? "lock.open.fill" : lock == .noDevice ? "lock.trianglebadge.exclamationmark.fill" : "lock.fill")
                    .font(.system(size: 20 * scale, weight: .semibold))
                    .foregroundStyle(lock == .noDevice ? E2EELockPill.warning : .white)
            }
            .frame(width: 48 * scale, height: 48 * scale)
            VStack(alignment: .leading, spacing: 3 * scale) {
                Text(TChat.text(lock == .off ? .e2eeOff : .e2eeOn)).font(.display(20 * scale, .semibold)).foregroundStyle(.white)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                Text(name).font(.display(13 * scale, .semibold)).textCase(.uppercase).tracking(0.8).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
            }
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text).font(.display(12 * scale, .semibold)).textCase(.uppercase).tracking(0.9).foregroundStyle(.white.opacity(0.5))
    }

    /// The number as people read it aloud: three groups to a row, each person's half apart.
    private func safety(_ number: String, conversation: TogetherConversation, name: String) -> some View {
        let groups = TogetherE2EE.safetyGroups(number)
        let compared = model.e2ee?.isCompared(conversation) == true
        return VStack(alignment: .leading, spacing: 10 * scale) {
            HStack {
                caption(TChat.text(.e2eeSafetyNumber))
                Spacer()
                if compared {
                    Label(TChat.text(.e2eeCompared), systemImage: "checkmark.seal.fill")
                        .font(.display(12 * scale, .semibold)).foregroundStyle(model.accent)
                        .transition(.opacity.combined(with: .scale(scale: 0.8)))
                }
            }
            VStack(spacing: 0) {
                ForEach(0 ..< 4, id: \.self) { row in
                    if row == 2 { Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1).padding(.vertical, 8 * scale) }
                    HStack(spacing: 0) {
                        ForEach(0 ..< 3, id: \.self) { column in
                            let index = row * 3 + column
                            Text(groups.indices.contains(index) ? groups[index] : "")
                                .font(.system(size: 21 * scale, weight: .medium, design: .monospaced))
                                .tracking(1.2)
                                .foregroundStyle(.white.opacity(compared ? 1 : 0.92))
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.vertical, 3 * scale)
                }
            }
            .padding(.vertical, 14 * scale)
            .padding(.horizontal, 10 * scale)
            .background(RoundedRectangle(cornerRadius: 16 * scale, style: .continuous).fill(Color.black.opacity(0.22)))
            .overlay(RoundedRectangle(cornerRadius: 16 * scale, style: .continuous).strokeBorder(compared ? model.accent.opacity(0.7) : Color.white.opacity(0.1), lineWidth: 1))
            .textSelection(.enabled)
            Text(TChat.format(.e2eeSafetyHow, name))
                .font(.display(13 * scale, .medium)).foregroundStyle(.white.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func action(_ row: MessageActions.Row, focused: Bool) -> some View {
        let (title, symbol) = describe(row)
        return HStack(spacing: 14 * scale) {
            Image(systemName: symbol).font(.system(size: 16 * scale, weight: .semibold)).frame(width: 24 * scale)
                .contentTransition(.symbolEffect(.replace))
            Text(title).font(.display(16 * scale, .medium))
            Spacer(minLength: 0)
        }
        .foregroundStyle(focused ? Color.black : .white)
        .padding(.horizontal, 14 * scale)
        .padding(.vertical, 11 * scale)
        .background(FocusFill(RoundedRectangle(cornerRadius: 12 * scale, style: .continuous), focused: focused, idle: Color.white.opacity(0.06)))
        .scaleEffect(focused ? 1.015 : 1)
        .animation(Motion.focus, value: focused)
        .contentShape(Rectangle())
    }

    private func describe(_ row: MessageActions.Row) -> (String, String) {
        switch row {
        case .markCompared(true): return (TChat.text(.e2eeMarkCompared), "checkmark.seal")
        case .markCompared(false): return (TChat.text(.e2eeCompared), "checkmark.seal.fill")
        default: return (TChat.text(.e2eeDismiss), "checkmark")
        }
    }

    private func devices(_ conversation: TogetherConversation, me: String, name: String) -> some View {
        let other = conversation.others(than: me).first?.userId ?? ""
        return VStack(alignment: .leading, spacing: 10 * scale) {
            caption(TChat.text(.e2eeDevices))
            person(TChat.text(.e2eeYou), model.e2ee?.devices(of: me) ?? [])
            person(name, model.e2ee?.devices(of: other) ?? [])
            Label(TChat.text(.e2eeNewDeviceNote), systemImage: "info.circle")
                .font(.display(12 * scale, .medium)).foregroundStyle(.white.opacity(0.45))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2 * scale)
        }
    }

    private func person(_ who: String, _ devices: [TogetherE2EE.Device]) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12 * scale) {
            Text(who).font(.display(13 * scale, .semibold)).foregroundStyle(.white.opacity(0.85)).frame(width: 92 * scale, alignment: .leading).lineLimit(1)
            VStack(alignment: .leading, spacing: 4 * scale) {
                if devices.isEmpty { Text("—").font(.display(13 * scale)).foregroundStyle(.white.opacity(0.4)) }
                // Each device as its kind and the day it was added: never the name its app
                // registered (often the computer's own) or its ID.
                ForEach(devices) { device in
                    let here = device.id == model.e2ee?.device?.deviceId
                    HStack(alignment: .firstTextBaseline, spacing: 7 * scale) {
                        Image(systemName: Self.symbol(device.kind)).font(.system(size: 11 * scale, weight: .semibold)).foregroundStyle(here ? model.accent : .white.opacity(0.45))
                        VStack(alignment: .leading, spacing: 1 * scale) {
                            Text(TChat.name(device.kind)).font(.display(13 * scale, here ? .semibold : .regular)).foregroundStyle(.white.opacity(0.78)).lineLimit(1)
                            if let added = device.added {
                                Text(TChat.format(.e2eeDeviceAdded, Self.day(added))).font(.display(11 * scale, .medium)).foregroundStyle(.white.opacity(0.42)).lineLimit(1)
                            }
                        }
                    }
                }
            }
        }
    }

    static func symbol(_ kind: TogetherE2EE.DeviceKind) -> String {
        switch kind {
        case .windows, .linux: return "desktopcomputer"
        case .mac: return "laptopcomputer"
        case .iphone, .android: return "iphone"
        case .ipad: return "ipad"
        case .browser: return "globe"
        case .device: return "display"
        }
    }

    /// "3 November 2026" in the launcher's language.
    static func day(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = T.locale
        formatter.setLocalizedDateFormatFromTemplate("dMMMMy")
        return formatter.string(from: date)
    }
}
