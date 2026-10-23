import Foundation

/// The last `length` seconds of a recording, as encoded video frames and audio chunks, for a
/// clip saved after the fact (the console's "save the last 30 seconds"). A clip has to start at a
/// key frame, so the video kept reaches back to the key frame before the window; older frames
/// and audio are let go as new ones come.
public struct ClipBuffer<Payload> {
    public struct Item {
        public let payload: Payload
        public let time: Double
        public let key: Bool
    }

    public struct Clip {
        public let video: [Item]
        public let audio: [Item]
    }

    public let length: Double
    private var video: [Item] = []
    private var audio: [Item] = []

    public init(length: Double) {
        self.length = length
    }

    public var videoCount: Int { video.count }
    public var audioCount: Int { audio.count }

    public mutating func addVideo(_ payload: Payload, at time: Double, key: Bool) {
        video.append(Item(payload: payload, time: time, key: key))
        trim(before: time - length)
    }

    public mutating func addAudio(_ payload: Payload, at time: Double) {
        audio.append(Item(payload: payload, time: time, key: true))
        // Audio from before the oldest frame kept (or, with no frames, from longer ago than a
        // clip) can no longer be in one.
        let from = video.first?.time ?? time - length
        guard let first = audio.first, first.time < from - 1 else { return }
        if let start = audio.firstIndex(where: { $0.time >= from }) { audio.removeFirst(start) } else { audio.removeAll() }
    }

    public mutating func clear() {
        video.removeAll()
        audio.removeAll()
    }

    /// The kept frames from the last key frame at or before the window's start, and the audio
    /// from that frame on; nil before any key frame.
    public func clip() -> Clip? {
        guard let newest = video.last?.time, let start = keyIndex(atOrBefore: newest - length) ?? video.firstIndex(where: \.key) else { return nil }
        let from = video[start].time
        return Clip(video: Array(video[start...]), audio: audio.filter { $0.time >= from })
    }

    private func keyIndex(atOrBefore time: Double) -> Int? {
        video.lastIndex { $0.key && $0.time <= time }
    }

    /// Lets go of what lies before the key frame a clip of the window would start at, once that
    /// is more than a second's worth, so a frame added costs little.
    private mutating func trim(before time: Double) {
        guard let first = video.first, first.time < time - 1, let start = keyIndex(atOrBefore: time), start > 0 else { return }
        let from = video[start].time
        video.removeFirst(start)
        if let audioStart = audio.firstIndex(where: { $0.time >= from }), audioStart > 0 { audio.removeFirst(audioStart) }
    }
}
