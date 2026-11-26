@testable import DataSources
import Foundation
import Providers
import Quotas
import Testing

/// Copilot's usage history: the gateway's usage file, its own account's
/// requests, tokens with no cost (GitHub bills credits, not tokens).
@MainActor
@Suite
struct CopilotUsageHistoryTests {
    private let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    private static let ref = "309fa6c92411e48ad145f5b0a9903349c923761f0e20809d901a89f1eed32804"

    private func history(gatewayAuth: String) throws -> UsageHistory {
        let definition = try #require(try ProviderFactory.builtIn("copilot").defaultAccountHistory(gatewayAuth: gatewayAuth))
        return UsageHistory(log: DataSources.makeUsageLog(definition, scripts: ProviderFactory.builtInScripts,
                                                          environment: { _ in nil }, homeDirectory: home))
    }

    private func write(_ lines: [String]) throws {
        let dir = home.appendingPathComponent(".local/share/llm-archive/usage")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try lines.joined(separator: "\n").write(to: dir.appendingPathComponent("usage-today.jsonl"), atomically: true, encoding: .utf8)
    }

    private static func line(ref: String, input: Int) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return #"{"v":1,"id":"\#(UUID().uuidString)","at":"\#(formatter.string(from: Date()))","provider":"copilot","auth_ref":"\#(ref)","model":"copilot/claude-opus-5.5","tokens":{"input":\#(input),"output":100,"reasoning":0,"cache_read":1000,"cache_write":0}}"#
    }

    @Test func `should count its own gateway account's tokens and no cost`() async throws {
        try write([Self.line(ref: Self.ref, input: 10), Self.line(ref: "someone-else", input: 99_999)])
        let history = try history(gatewayAuth: "copilot-1.json")
        await history.read()
        let today = try #require(history.report?.today)
        #expect([today.inputTokens, today.outputTokens, today.cacheReadTokens] == [10, 100, 1000] as [Int])
        #expect(today.totalCost == 0)
        #expect(!history.knowsCost)
    }

    @Test func `should have no usage history before its gateway account is set`() throws {
        #expect(try ProviderFactory.builtIn("copilot").defaultAccountHistory == nil)
    }
}
