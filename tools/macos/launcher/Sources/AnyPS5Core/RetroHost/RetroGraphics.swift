import Foundation

/// The few graphics settings the in-game menu's Graphics page offers besides the internal
/// resolution (RetroResolution.swift), each a small set of plain values that set one or two core
/// options, and the values the launcher starts a game with when the player has chosen none, as on
/// Windows and Linux (AnyPS5 Desktop's lib/core/retro_host/retro_graphics.dart). The rest of the
/// cores' graphics options stay at their defaults, which defer to each core's own per-game list
/// (SwanStation's `Main_ApplyGameSettings`, LRPS2's game database).
public enum RetroGraphics {
    /// The settings of both consoles, in the order the Graphics page lists them after the internal
    /// resolution.
    public static let settings: [RetroGraphicsSetting] = [
        .smoothTextures, .fixWobbly3d, .widescreenPs1, .sharperTextures, .widescreenPs2,
    ]

    /// Every core option a Graphics row sets, of both consoles.
    public static let keys: Set<String> = Set(settings.flatMap(\.keys))

    /// Every core option a Graphics row sets that is kept per game (`RetroGraphicsSetting.perGame`):
    /// PS1 widescreen's.
    public static let perGameKeys: Set<String> = Set(settings.filter(\.perGame).flatMap(\.keys))

    /// SwanStation's true colour, which removes the console's dithering. Always on: the menu does
    /// not offer it, and SwanStation's per-game list still turns it off for the games it breaks.
    public static let trueColorKey = "swanstation_GPU_TrueColor"

    static let textureFilterKey = "swanstation_GPU_TextureFilter"
    static let pgxpKey = "swanstation_GPU_PGXPEnable"
    static let widescreenHackKey = "swanstation_GPU_WidescreenHack"
    static let aspectRatioKey = "swanstation_Display_AspectRatio"
    static let anisotropicKey = "pcsx2_anisotropic_filtering"
    static let widescreenHintKey = "pcsx2_widescreen_hint"

    /// The core options a game starts with for the settings the player has not chosen (`kept`
    /// holds the values the player chose), and SwanStation's true colour, which the menu does not
    /// offer:
    ///
    /// - PS1: fix wobbly 3D on; true colour on, with SwanStation's scaled dithering left on;
    /// - PS2: sharper textures on.
    ///
    /// Smooth textures and widescreen are not among them: the cores start with the console's own
    /// textures and picture. SwanStation's per-game list turns neither off for the games it breaks
    /// (bilinear filtering seams 2D sprites, fonts and tiled backgrounds), as it does PGXP and true
    /// colour. A setting the player chose any value of is left out whole.
    public static func defaults(kept: [String: String], ps2: Bool) -> [String: String] {
        func chosen(_ setting: RetroGraphicsSetting) -> Bool { setting.keys.contains { kept[$0] != nil } }
        if ps2 { return chosen(.sharperTextures) ? [:] : [anisotropicKey: "16x"] }
        var defaults = [trueColorKey: "true"]
        if !chosen(.fixWobbly3d) { defaults[pgxpKey] = "true" }
        return defaults
    }
}

/// What a Graphics row says under its value.
public enum RetroGraphicsNote: Equatable, Sendable {
    /// Nothing to say: the value chosen is the one the game runs with.
    case none
    /// The value chosen is being applied and shows in a moment.
    case applying
    /// The value chosen takes effect when the game is started again.
    case nextStart
    /// The game runs with the value it started with, and any change takes effect at its next start.
    case changesAtNextStart
    /// The host could not use the internal resolution saved and draws at the largest it can
    /// (`status.resolutionError`). Only the internal resolution says this.
    case refused
}

/// Which setting a Graphics row is; each console has its own widescreen. Its name is the row's id.
public enum RetroGraphicsKind: String, Sendable {
    case smoothTextures, fixWobbly3d, widescreen, sharperTextures
}

/// The launcher's name of a value a Graphics row offers.
public enum RetroGraphicsLevel: Sendable {
    case off, on, smooth, extraSmooth
}

/// A core option and the value it takes.
public struct RetroOptionValue: Equatable, Sendable {
    public let key: String
    public let value: String

    public init(_ key: String, _ value: String) {
        self.key = key
        self.value = value
    }
}

/// One value a setting offers: its name, and the core option values it sets.
public struct RetroGraphicsOffer: Equatable, Sendable {
    public let level: RetroGraphicsLevel
    /// The value each core option takes. The first is the setting's own
    /// (`RetroGraphicsSetting.key`); any other follows it (widescreen's aspect ratio).
    public let options: [RetroOptionValue]

    public init(_ level: RetroGraphicsLevel, _ options: [RetroOptionValue]) {
        self.level = level
        self.options = options
    }

    /// The value it sets `key` to, or nil for an option it does not set.
    public func value(of key: String) -> String? { options.first { $0.key == key }?.value }
}

/// A graphics setting of one console's core, as a Graphics row offers it.
public struct RetroGraphicsSetting: Equatable, Sendable {
    /// Which setting it is.
    public let kind: RetroGraphicsKind
    /// It is LRPS2's (a PS2 game's); otherwise SwanStation's.
    public let ps2: Bool
    /// It changes only what the core draws with the GPU, so it is offered only while the host does
    /// (`status.hardware`).
    public let needsGpu: Bool
    /// The values offered, in the row's order.
    public let offers: [RetroGraphicsOffer]
    /// The value chosen is kept for the game it was chosen in only, not for every game of its
    /// console: one that suits some games and breaks others, which the core's per-game list does
    /// not turn off.
    public let perGame: Bool

    public init(kind: RetroGraphicsKind, ps2: Bool, needsGpu: Bool, offers: [RetroGraphicsOffer], perGame: Bool = false) {
        self.kind = kind
        self.ps2 = ps2
        self.needsGpu = needsGpu
        self.offers = offers
        self.perGame = perGame
    }

    /// The core option the row shows: the one whose chosen value says which value is chosen.
    public var key: String { offers[0].options[0].key }

    /// Every core option the setting sets, in the order its offers name them.
    public var keys: [String] {
        var keys: [String] = []
        for offer in offers {
            for option in offer.options where !keys.contains(option.key) { keys.append(option.key) }
        }
        return keys
    }

    /// SwanStation's texture filtering: nearest (the console's own look), bilinear, or xBR.
    public static let smoothTextures = RetroGraphicsSetting(kind: .smoothTextures, ps2: false, needsGpu: true, offers: [
        RetroGraphicsOffer(.off, [RetroOptionValue(RetroGraphics.textureFilterKey, "Nearest")]),
        RetroGraphicsOffer(.smooth, [RetroOptionValue(RetroGraphics.textureFilterKey, "Bilinear")]),
        RetroGraphicsOffer(.extraSmooth, [RetroOptionValue(RetroGraphics.textureFilterKey, "xBR")]),
    ])

    /// SwanStation's PGXP geometry correction, which keeps polygons and their textures from
    /// wobbling. Its culling and texture correction stay at their defaults, both on.
    public static let fixWobbly3d = RetroGraphicsSetting(kind: .fixWobbly3d, ps2: false, needsGpu: true, offers: [
        RetroGraphicsOffer(.off, [RetroOptionValue(RetroGraphics.pgxpKey, "false")]),
        RetroGraphicsOffer(.on, [RetroOptionValue(RetroGraphics.pgxpKey, "true")]),
    ])

    /// SwanStation's widescreen hack, with the 16:9 aspect ratio it needs: the two change together.
    /// It widens the view of 3D games and breaks 2D and pre-rendered ones, and SwanStation's
    /// per-game list turns it off for no game, so it is never chosen for the player, and a game it
    /// is chosen in keeps it for itself only.
    public static let widescreenPs1 = RetroGraphicsSetting(kind: .widescreen, ps2: false, needsGpu: false, offers: [
        RetroGraphicsOffer(.off, [RetroOptionValue(RetroGraphics.widescreenHackKey, "false"), RetroOptionValue(RetroGraphics.aspectRatioKey, "4:3")]),
        RetroGraphicsOffer(.on, [RetroOptionValue(RetroGraphics.widescreenHackKey, "true"), RetroOptionValue(RetroGraphics.aspectRatioKey, "16:9")]),
    ], perGame: true)

    /// LRPS2's anisotropic filtering, off or at its largest (16x), which cost nothing measurable.
    public static let sharperTextures = RetroGraphicsSetting(kind: .sharperTextures, ps2: true, needsGpu: true, offers: [
        RetroGraphicsOffer(.off, [RetroOptionValue(RetroGraphics.anisotropicKey, "disabled")]),
        RetroGraphicsOffer(.on, [RetroOptionValue(RetroGraphics.anisotropicKey, "16x")]),
    ])

    /// LRPS2's widescreen patch from its game database, applied when the game boots, only for a
    /// game it has a patch for, so one choice suits every PS2 game. Its 16:10, 21:9 and 32:9 values
    /// are not offered (LRPS2 never parses `enabled (32:9)`), and it is never chosen for the player.
    public static let widescreenPs2 = RetroGraphicsSetting(kind: .widescreen, ps2: true, needsGpu: false, offers: [
        RetroGraphicsOffer(.off, [RetroOptionValue(RetroGraphics.widescreenHintKey, "disabled")]),
        RetroGraphicsOffer(.on, [RetroOptionValue(RetroGraphics.widescreenHintKey, "enabled (16:9)")]),
    ])
}

/// One value a Graphics row shows.
public struct RetroGraphicsValue: Equatable, Sendable {
    /// The value the launcher offers, or nil for one it does not, which the row shows only while
    /// the host has it chosen.
    public let offer: RetroGraphicsOffer?
    /// The host's label of the setting's own option at this value.
    public let label: String

    public init(offer: RetroGraphicsOffer?, label: String) {
        self.offer = offer
        self.label = label
    }
}

/// A graphics setting of a running game, as its Graphics row offers it.
public struct RetroGraphicsChoice: Equatable, Sendable {
    public let setting: RetroGraphicsSetting
    /// The values shown, in the setting's order, a chosen value no offer has last.
    public let values: [RetroGraphicsValue]
    /// The index into `values` of the value chosen.
    public let selected: Int
    public let note: RetroGraphicsNote

    /// The choice `status` allows for `setting`, or nil when the row is not shown: no status yet,
    /// a game of the other console, a setting that needs the GPU while the host draws without it,
    /// or a host that does not list the setting's option.
    ///
    /// A value is offered only when the host lists every option it sets with that value among the
    /// option's `values`, so the host's own limits hold. The value chosen is the offer whose every
    /// option has its value chosen. When none has (a value the launcher does not offer, or
    /// widescreen's hack without its aspect ratio), the setting's option is shown with the host's
    /// label, so the row never claims a value the game does not have, and choosing an offer sets
    /// it whole.
    public static func of(_ status: RetroStatus?, _ setting: RetroGraphicsSetting) -> RetroGraphicsChoice? {
        guard let status, (status.console == RetroConsole.ps2) == setting.ps2 else { return nil }
        if setting.needsGpu, !status.hardware { return nil }
        guard let option = status.options[setting.key] else { return nil }
        func listed(_ offer: RetroGraphicsOffer) -> Bool {
            offer.options.allSatisfy { status.options[$0.key]?.values.contains($0.value) ?? false }
        }
        func chosenWhole(_ offer: RetroGraphicsOffer) -> Bool {
            offer.options.allSatisfy { part in status.options[part.key].map { $0.values[$0.selected] == part.value } ?? false }
        }
        var values: [RetroGraphicsValue] = []
        for offer in setting.offers where listed(offer) {
            let index = offer.value(of: setting.key).flatMap { option.values.firstIndex(of: $0) } ?? option.selected
            values.append(RetroGraphicsValue(offer: offer, label: option.labels[index]))
        }
        var selected = values.firstIndex { $0.offer.map(chosenWhole) ?? false } ?? -1
        if selected < 0 {
            selected = values.count
            values.append(RetroGraphicsValue(offer: nil, label: option.labels[option.selected]))
        }
        return RetroGraphicsChoice(setting: setting, values: values, selected: selected, note: note(status, setting))
    }

    private static func note(_ status: RetroStatus, _ setting: RetroGraphicsSetting) -> RetroGraphicsNote {
        let options = setting.keys.compactMap { status.options[$0] }
        let settled = options.allSatisfy { $0.values[$0.selected] == $0.activeValue }
        if options.contains(where: \.restart) { return settled ? .changesAtNextStart : .nextStart }
        return settled && !status.graphicsPending ? .none : .applying
    }

    /// The core option values to send for the value at `index`: those that differ from what the
    /// host has chosen, in the offer's order, also for the value chosen when one of its other
    /// options differs (widescreen's aspect ratio); empty when the host has them all, or for a
    /// value the launcher does not offer.
    public func changesFor(_ status: RetroStatus, _ index: Int) -> [RetroOptionValue] {
        guard values.indices.contains(index), let offer = values[index].offer else { return [] }
        return offer.options.filter { part in
            guard let option = status.options[part.key] else { return false }
            return option.values[option.selected] != part.value
        }
    }
}
