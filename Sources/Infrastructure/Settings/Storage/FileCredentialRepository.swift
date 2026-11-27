import Domain
import Foundation

/// Fork: credentials in one 0600 JSON file instead of the Keychain. A Keychain
/// item is tied to the app's signature and to the tool that created it, so a
/// locally built ClaudeBar asked for the login password on every read after a
/// rebuild (2026-11-27). Values never reach the log.
public final class FileCredentialRepository: CredentialRepository, @unchecked Sendable {
    /// `~/.claudebar/credentials.json`
    public static let shared = FileCredentialRepository()

    private let url: URL
    private let lock = NSLock()

    public init(url: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claudebar/credentials.json")) {
        self.url = url
    }

    public func save(_ value: String, forKey key: String) {
        _ = change { $0[key] = value }
    }

    public func get(forKey key: String) -> String? {
        lock.withLock { read()[key] }
    }

    @discardableResult
    public func delete(forKey key: String) -> Bool {
        change { $0[key] = nil }
    }

    public func exists(forKey key: String) -> Bool {
        get(forKey: key) != nil
    }

    private func read() -> [String: String] {
        guard let data = try? Data(contentsOf: url) else { return [:] }
        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }

    /// Read, change, write back whole: a temporary file created 0600 and
    /// renamed over the old one, so the file is never readable by others or
    /// half written.
    private func change(_ edit: (inout [String: String]) -> Void) -> Bool {
        lock.withLock {
            var values = read()
            edit(&values)
            let folder = url.deletingLastPathComponent()
            let temporary = folder.appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString)")
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                        attributes: [.posixPermissions: 0o700])
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.sortedKeys]
                guard FileManager.default.createFile(atPath: temporary.path, contents: try encoder.encode(values),
                                                     attributes: [.posixPermissions: 0o600]) else {
                    AppLog.credentials.error("Credential file write failed")
                    return false
                }
                guard rename(temporary.path, url.path) == 0 else {
                    try? FileManager.default.removeItem(at: temporary)
                    AppLog.credentials.error("Credential file replace failed")
                    return false
                }
                return true
            } catch {
                try? FileManager.default.removeItem(at: temporary)
                AppLog.credentials.error("Credential file write failed: \(error.localizedDescription)")
                return false
            }
        }
    }
}
