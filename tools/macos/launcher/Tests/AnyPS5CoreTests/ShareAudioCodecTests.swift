import XCTest
@testable import AnyPS5Core

/// The viewer's hello and the SDP changes that get the game's sound to them as stereo Opus.
final class ShareAudioCodecTests: XCTestCase {
    func testTheHelloRoundTripsAndPicksOpus() {
        let hello = ShareAudioHello(codecs: [.opus, .pcm])
        XCTAssertEqual(hello.text, #"{"type":"audio-hello","v":1,"codecs":["opus","pcm"]}"#)
        XCTAssertEqual(ShareAudioHello(text: hello.text), hello)
        XCTAssertEqual(hello.chosen, .opus)
        XCTAssertEqual(ShareAudioHello(codecs: [.pcm]).chosen, .pcm)
        // A newer viewer's codecs the host does not know are left out; a later version still reads.
        XCTAssertEqual(ShareAudioHello(text: #"{"type":"audio-hello","v":2,"codecs":["lyra","pcm"]}"#)?.codecs, [.pcm])
        XCTAssertEqual(ShareAudioHello(text: #"{"type":"audio-hello","v":2,"codecs":["lyra","pcm"]}"#)?.chosen, .pcm)
        XCTAssertNil(ShareAudioHello(text: #"{"type":"pad-hello","codecs":["opus"]}"#))
        XCTAssertNil(ShareAudioHello(text: "not json"))
        XCTAssertNil(ShareAudioHello(text: #"{"type":"audio-hello"}"#))
    }

    let answer = [
        "v=0", "o=- 1 2 IN IP4 127.0.0.1", "s=-", "t=0 0",
        "m=video 9 UDP/TLS/RTP/SAVPF 96", "a=mid:0", "a=recvonly", "a=rtpmap:96 H264/90000",
        "a=fmtp:96 level-asymmetry-allowed=1;packetization-mode=1;profile-level-id=640c1f",
        "m=application 9 UDP/DTLS/SCTP webrtc-datachannel", "a=mid:1",
        "m=audio 9 UDP/TLS/RTP/SAVPF 111 63", "a=mid:2", "a=recvonly", "a=rtpmap:111 opus/48000/2",
        "a=fmtp:111 minptime=10;useinbandfec=1", "a=rtpmap:63 red/48000/2", "a=fmtp:63 111/111", "",
    ].joined(separator: "\r\n")

    func testAViewerAsksForStereoAndTheHostForTheRate() {
        let viewer = ShareAudioSDP.stereoOpus(answer)
        XCTAssertTrue(viewer.contains("a=fmtp:111 minptime=10;useinbandfec=1;stereo=1;sprop-stereo=1\r\n"))
        // Nothing else changes.
        XCTAssertTrue(viewer.contains("a=fmtp:96 level-asymmetry-allowed=1;packetization-mode=1;profile-level-id=640c1f\r\n"))
        XCTAssertTrue(viewer.contains("a=fmtp:63 111/111\r\n"))
        let host = ShareAudioSDP.stereoOpus(viewer, kbps: 128)
        XCTAssertTrue(host.contains("a=fmtp:111 minptime=10;useinbandfec=1;stereo=1;sprop-stereo=1;maxaveragebitrate=128000;usedtx=0\r\n"))
        // Applying it twice changes nothing more.
        XCTAssertEqual(ShareAudioSDP.stereoOpus(host, kbps: 128), host)
        // A format line missing altogether is added after its rtpmap; no Opus leaves it alone.
        let bare = answer.replacingOccurrences(of: "a=fmtp:111 minptime=10;useinbandfec=1\r\n", with: "")
        XCTAssertTrue(ShareAudioSDP.stereoOpus(bare).contains("a=rtpmap:111 opus/48000/2\r\na=fmtp:111 stereo=1;sprop-stereo=1\r\n"))
        let noOpus = "v=0\r\nm=video 9 UDP/TLS/RTP/SAVPF 96\r\na=rtpmap:96 H264/90000\r\n"
        XCTAssertEqual(ShareAudioSDP.stereoOpus(noOpus, kbps: 128), noOpus)
        // Off by 0 or by a value given: replaced.
        let mono = answer.replacingOccurrences(of: "minptime=10;useinbandfec=1", with: "stereo=0;usedtx=1")
        XCTAssertTrue(ShareAudioSDP.stereoOpus(mono, kbps: 96).contains("a=fmtp:111 stereo=1;usedtx=0;sprop-stereo=1;maxaveragebitrate=96000;useinbandfec=1\r\n"))
    }

    func testTheHostAsksForShortFramesInTheAudioSectionOnly() {
        let host = ShareAudioSDP.stereoOpus(answer, kbps: 128, frameMs: 10)
        let audio = host.components(separatedBy: "m=audio")[1]
        XCTAssertTrue(audio.hasSuffix("a=fmtp:63 111/111\r\na=ptime:10\r\n"))
        XCTAssertFalse(host.components(separatedBy: "m=audio")[0].contains("a=ptime"))
        // Once only, and an existing one is replaced.
        XCTAssertEqual(ShareAudioSDP.stereoOpus(host, kbps: 128, frameMs: 10), host)
        XCTAssertEqual(ShareAudioSDP.stereoOpus(host, kbps: 128, frameMs: 20).components(separatedBy: "a=ptime:").count, 2)
        XCTAssertTrue(ShareAudioSDP.stereoOpus(host, kbps: 128, frameMs: 20).contains("a=ptime:20\r\n"))
        // Audio in the middle: before the next section.
        let middle = answer.replacingOccurrences(of: "\r\n\r\n", with: "\r\n") + "m=application 9 UDP/DTLS/SCTP webrtc-datachannel\r\na=mid:3\r\n"
        XCTAssertTrue(ShareAudioSDP.stereoOpus(middle, kbps: 128, frameMs: 10).contains("a=fmtp:63 111/111\r\na=ptime:10\r\nm=application"))
    }

    func testOnlyAnAudioSectionTakingOpusCounts() {
        XCTAssertTrue(ShareAudioSDP.takesOpus(answer))
        XCTAssertFalse(ShareAudioSDP.takesOpus(answer.replacingOccurrences(of: "m=audio 9 ", with: "m=audio 0 ")))
        XCTAssertFalse(ShareAudioSDP.takesOpus(answer.replacingOccurrences(of: "a=mid:2\r\na=recvonly", with: "a=mid:2\r\na=inactive")))
        XCTAssertFalse(ShareAudioSDP.takesOpus(answer.replacingOccurrences(of: "a=rtpmap:111 opus/48000/2", with: "a=rtpmap:0 PCMU/8000")))
        // The old answers: no audio section at all.
        let old = answer.components(separatedBy: "m=audio")[0]
        XCTAssertFalse(ShareAudioSDP.takesOpus(old))
        // Audio before the video works too, and plain \n.
        let reordered = "v=0\nm=audio 9 UDP/TLS/RTP/SAVPF 111\na=rtpmap:111 opus/48000/2\nm=video 9 UDP/TLS/RTP/SAVPF 96\n"
        XCTAssertTrue(ShareAudioSDP.takesOpus(reordered))
    }
}
