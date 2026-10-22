import Foundation
import Security

/// A phone the user allowed once; its key lets it connect again without asking.
public struct PairedDevice: Codable, Equatable, Sendable {
    public let id: String
    public var name: String
    public let key: String
    public let added: Date
}

/// The allowed phones, kept in a JSON file.
public final class PairedDevices: @unchecked Sendable {
    public static var defaultFile: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("AnyPS5/RemoteDevices.json")
    }

    private let file: URL
    private let lock = NSLock()
    private var devices: [PairedDevice]

    public init(file: URL = PairedDevices.defaultFile) {
        self.file = file
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        devices = (try? Data(contentsOf: file)).flatMap { try? decoder.decode([PairedDevice].self, from: $0) } ?? []
    }

    public var all: [PairedDevice] {
        lock.lock()
        defer { lock.unlock() }
        return devices
    }

    public func device(id: String, key: String) -> PairedDevice? {
        lock.lock()
        defer { lock.unlock() }
        return devices.first { $0.id == id && $0.key == key }
    }

    /// Allows the phone with a new random key, replacing an earlier pairing of the same phone.
    @discardableResult
    public func add(id: String, name: String) -> PairedDevice {
        var bytes = [UInt8](repeating: 0, count: 32)
        if SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) != errSecSuccess {
            bytes = (0..<32).map { _ in UInt8.random(in: 0...255) }
        }
        let device = PairedDevice(id: id, name: name, key: Data(bytes).base64EncodedString(), added: Date())
        lock.lock()
        devices.removeAll { $0.id == id }
        devices.append(device)
        save()
        lock.unlock()
        return device
    }

    public func remove(id: String) {
        lock.lock()
        devices.removeAll { $0.id == id }
        save()
        lock.unlock()
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? encoder.encode(devices).write(to: file, options: .atomic)
    }
}
