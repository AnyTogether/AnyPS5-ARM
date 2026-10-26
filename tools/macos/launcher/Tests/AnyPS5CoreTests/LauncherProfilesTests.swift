import Foundation
import XCTest
@testable import AnyPS5Core

final class LauncherProfilesTests: XCTestCase {
    var folder: URL!

    override func setUp() {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("profiles-\(UUID().uuidString.prefix(8))")
    }

    override func tearDown() { try? FileManager.default.removeItem(at: folder) }

    static let fresh = ProfileStore.ExistingSetup(onboarded: false, user: nil, name: "Utku")

    // MARK: The store

    func testAFirstStartHasNoProfileAndAsksForAMode() {
        let store = ProfileStore(folder: folder, existing: Self.fresh)
        XCTAssertTrue(store.book.profiles.isEmpty)
        XCTAssertEqual(store.launchScreen, .welcome)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.file.path), "nothing written until a profile is made")
    }

    func testProfilesAreAddedRenamedAndKeptForTheNextStart() throws {
        let store = ProfileStore(folder: folder, existing: Self.fresh)
        let first = store.add(name: "  Utku  ", mode: .offline)
        XCTAssertEqual(first.name, "Utku", "trimmed")
        XCTAssertEqual(store.book.current, first.id, "the first profile is the one in use")
        XCTAssertEqual(store.book.legacyOwner, first.id, "the saves from before profiles are the first profile's")
        let second = store.add(name: "Selin", mode: .online)
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertNotEqual(first.avatar.color, second.avatar.color, "each profile gets its own colour")
        store.rename(second.id, to: "Selin K.")
        let again = ProfileStore(folder: folder, existing: Self.fresh)
        XCTAssertEqual(again.book.profiles.map(\.name), ["Utku", "Selin K."])
        XCTAssertEqual(again.book.profiles.map(\.mode), [.offline, .online])
        XCTAssertEqual(again.book.current, first.id)
    }

    func testANameIsNeverEmptyNorTooLong() {
        let store = ProfileStore(folder: folder, existing: Self.fresh)
        XCTAssertEqual(store.add(name: "   ", mode: .offline).name, "Player")
        XCTAssertEqual(store.add(name: String(repeating: "a", count: 60), mode: .offline).name.count, LauncherProfile.maxName)
        let profile = store.book.profiles[0]
        store.rename(profile.id, to: "")
        XCTAssertEqual(store.profile(profile.id)?.name, "Player", "an empty rename keeps a name")
    }

    func testOneProfileGoesStraightInAndSeveralAskWhoIsPlaying() {
        let store = ProfileStore(folder: folder, existing: Self.fresh)
        let first = store.add(name: "Utku", mode: .offline)
        XCTAssertEqual(store.launchScreen, .home(first.id))
        store.setAskEveryTime(true)
        XCTAssertEqual(store.launchScreen, .picker, "Ask every time shows the picker with one profile too")
        store.setAskEveryTime(false)
        _ = store.add(name: "Selin", mode: .offline)
        XCTAssertEqual(store.launchScreen, .picker)
    }

    func testTheCurrentProfileAndTheLastOneCannotBeDeleted() throws {
        let store = ProfileStore(folder: folder, existing: Self.fresh)
        let first = store.add(name: "Utku", mode: .offline)
        XCTAssertThrowsError(try store.remove(first.id)) { XCTAssertEqual($0 as? ProfileStore.Refusal, .onlyProfile) }
        let second = store.add(name: "Selin", mode: .offline)
        XCTAssertThrowsError(try store.remove(first.id)) { XCTAssertEqual($0 as? ProfileStore.Refusal, .inUse) }
        try store.remove(second.id)
        XCTAssertEqual(store.book.profiles.map(\.id), [first.id])
    }

    func testSettingsAndModeArePerProfile() {
        let store = ProfileStore(folder: folder, existing: Self.fresh)
        let first = store.add(name: "Utku", mode: .offline)
        let second = store.add(name: "Selin", mode: .offline)
        store.setSettings(first.id, ["theme": .number(2)])
        store.setMode(second.id, .online)
        store.setAccount(second.id, LauncherProfile.Account(userId: "u2", handle: "selin"))
        let again = ProfileStore(folder: folder, existing: Self.fresh)
        XCTAssertEqual(again.profile(first.id)?.settings, ["theme": .number(2)])
        XCTAssertNil(again.profile(second.id)?.settings)
        XCTAssertEqual(again.profile(second.id)?.mode, .online)
        XCTAssertEqual(again.profile(second.id)?.account?.handle, "selin")
    }

    func testTheFirstProfileKeepsTheOldPictureAndOthersGetTheirOwn() {
        let legacy = folder.appendingPathComponent("profile.png")
        let store = ProfileStore(folder: folder.appendingPathComponent("Profiles"), existing: Self.fresh, legacyPicture: legacy)
        let first = store.add(name: "Utku", mode: .offline)
        let second = store.add(name: "Selin", mode: .offline)
        XCTAssertEqual(store.pictureFile(for: first.id), legacy)
        XCTAssertEqual(store.pictureFile(for: second.id), folder.appendingPathComponent("Profiles/\(second.id)/profile.png"))
    }

    // MARK: Migration

    func testAnExistingSignedInUserBecomesTheirProfileWithoutTheWelcome() {
        let user = TogetherUser(id: "u1", handle: "utku", displayName: "Utku Halis", avatar: nil)
        let store = ProfileStore(folder: folder, existing: .init(onboarded: true, user: user, name: "Utku"))
        XCTAssertEqual(store.book.profiles.count, 1)
        let profile = store.book.profiles[0]
        XCTAssertEqual(profile.id, LauncherProfile.legacyID)
        XCTAssertEqual(profile.mode, .online)
        XCTAssertEqual(profile.name, "Utku Halis")
        XCTAssertEqual(profile.account, LauncherProfile.Account(userId: "u1", handle: "utku"))
        XCTAssertEqual(store.book.legacyOwner, profile.id)
        XCTAssertEqual(store.launchScreen, .home(profile.id), "no welcome and no picker after the update")
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.file.path), "the migration is written at once")
    }

    func testAnExistingOfflineSetupBecomesAnOfflineProfile() {
        let store = ProfileStore(folder: folder, existing: .init(onboarded: true, user: nil, name: "Utku"))
        XCTAssertEqual(store.book.profiles.map(\.mode), [.offline])
        XCTAssertEqual(store.book.profiles.map(\.name), ["Utku"])
        XCTAssertEqual(store.launchScreen, .home(LauncherProfile.legacyID))
    }

    func testASignedInUserWhoNeverFinishedTheFirstStartIsMigratedToo() {
        let user = TogetherUser(id: "u1", handle: "utku", displayName: "Utku", avatar: nil)
        let store = ProfileStore(folder: folder, existing: .init(onboarded: false, user: user, name: "Utku"))
        XCTAssertEqual(store.book.profiles.map(\.mode), [.online])
    }

    func testMigrationRunsOnceAndAKeptBookWins() {
        let user = TogetherUser(id: "u1", handle: "utku", displayName: "Utku", avatar: nil)
        let store = ProfileStore(folder: folder, existing: .init(onboarded: true, user: user, name: "Utku"))
        _ = store.add(name: "Selin", mode: .offline)
        let again = ProfileStore(folder: folder, existing: .init(onboarded: true, user: user, name: "Utku"))
        XCTAssertEqual(again.book.profiles.count, 2, "the kept book is read, not migrated again")
    }

    func testABrokenBookFileIsNotTakenForAFirstStart() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("{ not json".utf8).write(to: folder.appendingPathComponent("profiles.json"))
        let store = ProfileStore(folder: folder, existing: .init(onboarded: true, user: nil, name: "Utku"))
        XCTAssertEqual(store.book.profiles.count, 1, "an onboarded user still gets their profile back")
        XCTAssertNotEqual(store.launchScreen, .welcome)
    }

    // MARK: Switching

    func testSwitchingWaitsForTheGameToClose() {
        let store = ProfileStore(folder: folder, existing: Self.fresh)
        let first = store.add(name: "Utku", mode: .offline)
        let second = store.add(name: "Selin", mode: .offline)
        XCTAssertEqual(ProfileSwitch.check(to: second.id, in: store.book, running: "Hollow Knight", starting: nil, syncing: false), .gameRunning("Hollow Knight"))
        XCTAssertEqual(ProfileSwitch.check(to: second.id, in: store.book, running: nil, starting: "Stray", syncing: false), .gameRunning("Stray"))
        XCTAssertEqual(ProfileSwitch.check(to: second.id, in: store.book, running: nil, starting: nil, syncing: true), .syncing)
        XCTAssertEqual(ProfileSwitch.check(to: "nobody", in: store.book, running: nil, starting: nil, syncing: false), .unknown)
        XCTAssertEqual(ProfileSwitch.check(to: first.id, in: store.book, running: nil, starting: nil, syncing: false), .alreadyCurrent)
        XCTAssertNil(ProfileSwitch.check(to: second.id, in: store.book, running: nil, starting: nil, syncing: false))
    }

    func testTheModeChangeWaitsForTheGameToo() {
        XCTAssertEqual(ProfileSwitch.checkModeChange(running: "Stray", starting: nil), .gameRunning("Stray"))
        XCTAssertNil(ProfileSwitch.checkModeChange(running: nil, starting: nil))
    }

    func testThePickerShowsTheCurrentProfileFirst() {
        let store = ProfileStore(folder: folder, existing: Self.fresh)
        let first = store.add(name: "Utku", mode: .offline)
        let second = store.add(name: "Selin", mode: .online)
        store.select(second.id)
        XCTAssertEqual(store.book.pickerOrder.map(\.id), [second.id, first.id])
    }

    // MARK: Personal settings

    func testPersonalSettingsComeOutOfAndGoBackIntoTheSettings() throws {
        let settings = try JSONSerialization.data(withJSONObject: ["theme": 2, "sounds": false, "gamesFolder": "/Games", "language": "tr"])
        let personal = ProfileSettings.pick(["theme", "sounds", "accent"], from: settings)
        XCTAssertEqual(personal, ["theme": .number(2), "sounds": .bool(false)])
        let other = try JSONSerialization.data(withJSONObject: ["theme": 0, "sounds": true, "accent": "red", "gamesFolder": "/Games", "language": "tr"])
        let merged = ProfileSettings.merge(personal, keys: ["theme", "sounds", "accent"], into: other)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: merged) as? [String: Any])
        XCTAssertEqual(object["theme"] as? Int, 2)
        XCTAssertEqual(object["sounds"] as? Bool, false)
        XCTAssertNil(object["accent"], "a personal setting the profile never set goes back to the default")
        XCTAssertEqual(object["gamesFolder"] as? String, "/Games", "the shared settings stay")
    }
}
