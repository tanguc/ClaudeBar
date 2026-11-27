import Testing
import Foundation
@testable import Infrastructure

/// Credentials in a 0600 file instead of the Keychain (fork).
@Suite
struct FileCredentialRepositoryTests {
    private let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    private var file: URL { folder.appendingPathComponent("credentials.json") }

    @Test func `should read back a saved key and forget a deleted one`() {
        let store = FileCredentialRepository(url: file)
        #expect(store.get(forKey: "provider.nanogpt.apiKey") == nil)
        store.save("secret", forKey: "provider.nanogpt.apiKey")
        store.save("other", forKey: "provider.zai.apiKey")
        #expect(store.get(forKey: "provider.nanogpt.apiKey") == "secret")
        #expect(store.exists(forKey: "provider.zai.apiKey"))
        #expect(store.delete(forKey: "provider.nanogpt.apiKey"))
        #expect(store.get(forKey: "provider.nanogpt.apiKey") == nil)
        #expect(store.get(forKey: "provider.zai.apiKey") == "other")
        #expect(FileCredentialRepository(url: file).get(forKey: "provider.zai.apiKey") == "other")
    }

    @Test func `should keep the file readable by its owner only`() throws {
        FileCredentialRepository(url: file).save("secret", forKey: "k")
        let mode = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber
        #expect(mode?.intValue == 0o600)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0 != "credentials.json" }
        #expect(leftovers.isEmpty)
    }

    @Test func `should read a missing or broken file as no keys`() throws {
        #expect(FileCredentialRepository(url: file).get(forKey: "k") == nil)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: file)
        #expect(FileCredentialRepository(url: file).get(forKey: "k") == nil)
    }
}
