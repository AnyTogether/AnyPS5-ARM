import AnyPS5Core
import Foundation
import LiveKit
import os

/// LiveKit's one audio engine in this app, shared by everything that goes through the media
/// server (SfuAudioPlan): the host's game sound needs it without a device; party voice and
/// watching need it on the microphone and speakers, and come first.
@MainActor
public final class SfuAudio {
    public static let shared = SfuAudio()
    static let log = Logger(subsystem: "org.anyps5.launcher", category: "media-server")

    private weak var host: SfuShareHost?
    private var voices = 0
    private var watchers = 0

    private init() {}

    var plan: SfuAudioPlan { SfuAudioPlan.mode(gameSound: host != nil, voice: voices > 0, watching: watchers > 0) }

    func hosting(_ host: SfuShareHost?) async {
        self.host = host
        await apply()
    }

    func voice(_ on: Bool) async {
        voices = max(0, voices + (on ? 1 : -1))
        await apply()
    }

    func watching(_ on: Bool) async {
        watchers = max(0, watchers + (on ? 1 : -1))
        await apply()
    }

    /// The engine's mode and the game sound as the plan says: the game sound goes before the
    /// engine changes mode, and comes back after.
    private func apply() async {
        let plan = plan
        if !plan.gameSound { await host?.setGameSound(false) }
        if AudioManager.shared.isManualRenderingMode != plan.deviceless {
            do {
                try AudioManager.shared.setManualRenderingMode(plan.deviceless)
            } catch {
                SfuAudio.log.error("media server: audio engine mode: \(String(describing: error), privacy: .public)")
            }
        }
        if plan.gameSound { await host?.setGameSound(true) }
    }
}
