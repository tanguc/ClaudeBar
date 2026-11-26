@testable import DataSources
import Foundation
import Providers
import Quotas
import Testing

/// Claude's usage history as data: `claude.json`'s `usageHistory` read on the
/// gateway's usage file (one line per request through CLIProxyAPI, written by
/// llm-archive), priced with `claude-prices.json`. Each login keeps the lines
/// of its own gateway account.
@MainActor
@Suite
struct ClaudeUsageHistoryTests {
    private let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

    /// The plain login's gateway account and `auth_ref`, the SHA-256 of its name.
    private static let westep = "claude-westep.json"
    private static let westepRef = "0b083adbfdb0b432054cf215dfeda8abf42dc37f0c9e0ae51b7e96ab48f472ca"
    private static let work = "claude-work.json"
    private static let workRef = "46d79a7ac757419568146a2389b0ee3cf622f6fe142f7958e52576c700877628"

    private func history() throws -> UsageHistory {
        let definition = try #require(try ProviderFactory.builtIn("claude").defaultAccountHistory(gatewayAuth: Self.westep))
        return UsageHistory(log: DataSources.makeUsageLog(definition, scripts: ProviderFactory.builtInScripts,
                                                          environment: { _ in nil }, homeDirectory: home))
    }

    private func report() async throws -> DailyUsageReport {
        let history = try history()
        await history.read()
        return try #require(history.report)
    }

    private func write(_ jsonl: String, to name: String = "usage-2026-11-26.jsonl") throws {
        let dir = home.appendingPathComponent(".local/share/llm-archive/usage")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try jsonl.write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    private static func stamp(_ date: Date = Date()) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static var yesterdayNoon: Date {
        let calendar = DataSources.calendar()
        return calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: Date()))!.addingTimeInterval(43_200)
    }

    private static func line(_ model: String = "claude-sonnet-4-6", input: Int = 1000, output: Int = 500, cacheWrite: Int = 0,
                             cacheRead: Int = 0, id: String = UUID().uuidString, at: Date = Date(), ref: String = westepRef) -> String {
        #"{"v":1,"id":"\#(id)","at":"\#(stamp(at))","provider":"claude","auth_ref":"\#(ref)","auth_type":"oauth","model":"\#(model)","tokens":{"input":\#(input),"output":\#(output),"reasoning":0,"cache_read":\#(cacheRead),"cache_write":\#(cacheWrite)}}"#
    }

    @Test func `should show today's tokens and cost from the gateway's usage file`() async throws {
        try write(Self.line())
        let report = try await report()
        #expect(report.today.totalTokens == 1500)
        #expect(report.today.totalCost == Decimal(string: "0.0105"))
        #expect(report.previous.isEmpty)
    }

    @Test func `should show no usage history when there is no usage file`() async throws {
        let history = try history()
        await history.read()
        #expect(history.report == nil)
    }

    @Test func `should count yesterday's usage apart from today's`() async throws {
        try write([Self.line(), Self.line(input: 2000, output: 1000, at: Self.yesterdayNoon)].joined(separator: "\n"))
        let report = try await report()
        #expect(report.today.totalTokens == 1500)
        #expect(report.previous.totalTokens == 3000)
    }

    @Test func `should show cache tokens, cache savings and the hit rate`() async throws {
        try write(Self.line(cacheWrite: 2000, cacheRead: 1_000_000))
        let today = try await report().today
        #expect([today.inputTokens, today.outputTokens, today.cacheCreationTokens, today.cacheReadTokens] == [1000, 500, 2000, 1_000_000] as [Int])
        #expect(today.cachedSavings == Decimal(string: "2.7"))
        #expect(today.cacheHitRate > 0.99)
    }

    @Test func `should count a request once when a replayed batch or the backfill wrote it again`() async throws {
        let line = Self.line(id: "producer/request/attempt")
        try write([line, line].joined(separator: "\n"))
        try write(line, to: "backfill-2026-11-26.jsonl")
        #expect(try await report().today.totalTokens == 1500)
    }

    @Test func `should leave out the requests another gateway account served`() async throws {
        try write([Self.line(), Self.line(input: 9000, ref: Self.workRef)].joined(separator: "\n"))
        #expect(try await report().today.totalTokens == 1500)
    }

    // MARK: - Prices from claude-prices.json

    @Test func `should price models as Anthropic lists them, estimating unknown ones at the newest of their family`() async throws {
        // 1M in / 100K out / 1M cache write / 1M cache read each.
        try write([Self.line("claude-sonnet-4-6", input: 1_000_000, output: 100_000, cacheWrite: 1_000_000, cacheRead: 1_000_000),
                   Self.line("claude-opus-4-99-20260101", input: 1_000_000, output: 0),
                   Self.line("claude-sonnet-6", input: 1_000_000, output: 0),
                   Self.line("glm-4.6", input: 1_000_000, output: 0)].joined(separator: "\n"))
        // Sonnet $8.55, an unknown Opus at Opus 5.5's $4 input, an unknown Sonnet at Sonnet 5.5's $2,
        // a paid gateway's model at the Sonnet estimate $3.
        #expect(try await report().today.totalCost == Decimal(string: "17.55"))
    }

    @Test func `should price the current models at today's list prices`() async throws {
        try write([Self.line("claude-opus-5-5", input: 1_000_000, output: 100_000),
                   Self.line("claude-haiku-4-5-20251001", input: 1_000_000, output: 0, cacheRead: 1_000_000)]
            .joined(separator: "\n"))
        // Opus 5.5: $4 + $2; Haiku 4.5, dated: $1 + $0.10 of cache reads.
        #expect(try await report().today.totalCost == Decimal(string: "7.1"))
    }

    @Test func `should price Sonnet 5.5 cache reads, a short Haiku 5.5 prompt, and a newer Haiku as the current one`() async throws {
        try write([Self.line("claude-sonnet-5-5", input: 0, output: 0, cacheRead: 1_000_000),
                   Self.line("claude-haiku-5-5", input: 50_000, output: 1_000_000, cacheRead: 50_000),
                   Self.line("claude-haiku-6", input: 1_000_000, output: 0)]
            .joined(separator: "\n"))
        // Sonnet 5.5 reads at 0.05× input: $0.10. Haiku 5.5's 100,000-token prompt at its
        // up-to-100K prices: $0.005 + $0.50 + $0.0005. An unlisted Haiku as Haiku 5.5:
        // its 1M-token prompt at the over-100K $0.50.
        #expect(try await report().today.totalCost == Decimal(string: "1.1055"))
    }

    @Test func `should price a Haiku 5.5 request over 100,000 prompt tokens at the higher prices, cache reads and writes included`() async throws {
        try write([Self.line("claude-haiku-5-5", input: 100_000, output: 1_000_000),
                   Self.line("claude-haiku-5-5", input: 1_000, output: 0, cacheRead: 100_000),
                   Self.line("claude-haiku-5-5", input: 0, output: 1_000_000, cacheWrite: 200_000)]
            .joined(separator: "\n"))
        // Exactly 100,000: $0.01 + $0.50. Each other request on its own, over: 1,000 in at $0.50
        // and 100,000 reads at $0.05 = $0.0055; 200,000 five-minute writes at $0.625 and 1M out
        // at $2.50 = $2.625.
        #expect(try await report().today.totalCost == Decimal(string: "3.1405"))
    }

    @Test func `should price a gateway alias at its model's list price`() async throws {
        try write(Self.line("claude-opus-5-5-gmail", input: 1_000_000, output: 100_000))
        #expect(try await report().today.totalCost == Decimal(string: "6"))
    }

    @Test func `should cost nothing and save nothing when the model is open-weight (#190)`() async throws {
        try write(Self.line("qwen3-coder:30b", cacheRead: 1_000_000))
        let today = try await report().today
        #expect(today.totalCost == 0)
        #expect(today.cachedSavings == 0)
        #expect(today.cacheReadTokens == 1_000_000)
        #expect(today.totalTokens == 1500)
    }

    // MARK: - Each login reads its own gateway account

    /// Claude with one added login on the `work` gateway account, every history over `home`.
    private func provider(settings: InMemoryProviderSettings = InMemoryProviderSettings()) throws -> Provider {
        let definition = try ProviderFactory.builtIn("claude")
        let make = { (history: UsageLog.Definition) in
            UsageHistory(log: DataSources.makeUsageLog(history, scripts: ProviderFactory.builtInScripts,
                                                       environment: { _ in nil }, homeDirectory: self.home))
        }
        return Provider(
            definition: definition, settings: settings,
            accounts: [ProviderAccountConfig(accountId: "work", label: "", email: "work@example.com",
                                             probeConfig: ["folder": home.appendingPathComponent("work-claude").path,
                                                           "accountId": "work@example.com", "credentialService": "fixture-work",
                                                           "gatewayAuth": Self.work])],
            makeDataSource: { source, _ in DataSources.make(source, providerId: "claude") },
            usageHistory: definition.defaultAccountHistory(gatewayAuth: Self.westep).map(make),
            makeUsageHistory: { history, _ in make(history) }
        )
    }

    @Test func `should show an added login the requests of its own gateway account, never the default's`() async throws {
        try write([Self.line(), Self.line(input: 2000, output: 1000, ref: Self.workRef)].joined(separator: "\n"))
        let provider = try provider()
        let added = try #require(provider.accounts.first { !$0.isDefault })

        await provider.defaultAccount.usageHistory?.read()
        await added.usageHistory?.read()

        #expect(provider.defaultAccount.usageHistory?.report?.today.totalTokens == 1500)
        #expect(added.usageHistory?.report?.today.totalTokens == 3000)
        #expect(added.usageHistory !== provider.defaultAccount.usageHistory)
    }

    @Test func `should drop an added login's usage history when the login is removed`() throws {
        let provider = try provider()
        let added = try #require(provider.accounts.first { !$0.isDefault })
        #expect(added.usageHistory != nil)

        provider.accounts.remove(added)

        #expect(added.usageHistory == nil)
    }

    @Test func `should match an added login's records by its gateway account's hash, and have no history without one`() throws {
        let definition = try ProviderFactory.builtIn("claude")
        let own = try #require(definition.usageHistory(forAccount: ["folder": "/tmp/work", "gatewayAuth": Self.work]))
        #expect(own.records.shapes.first?.where == Match(path: "$.auth_ref", equals: .string(Self.workRef)))
        #expect(definition.usageHistory(forAccount: ["folder": "/tmp/work"]) == nil)
        #expect(definition.usageHistory(forAccount: [:]) == nil)
    }

    @Test func `should give the plain login no usage history until its gateway account is set`() throws {
        let definition = try ProviderFactory.builtIn("claude")
        #expect(definition.defaultAccountHistory == nil)
        let settings = InMemoryProviderSettings()
        settings.setValue(Self.westep, "gatewayAuth", forProvider: "claude")
        let values = definition.defaultAccountValues(saved: { settings.value($0, forProvider: "claude") })
        #expect(values["gatewayAuth"] == Self.westep)
        #expect(definition.usageHistory(forDefaultAccount: values)?.records.shapes.first?.where
            == Match(path: "$.auth_ref", equals: .string(Self.westepRef)))
    }

    @Test func `should leave the Mac's other apps out of an added login's history`() throws {
        #expect(try ProviderFactory.builtIn("claude").usageHistory?.otherApps?.map(\.label) == ["Claude Desktop"])
        #expect(try ProviderFactory.builtIn("claude").usageHistory(forAccount: ["gatewayAuth": Self.work])?.otherApps == nil)
    }

    // MARK: - Claude Desktop's buddy-tokens.json (#198)

    private func desktop() async throws -> UsageHistory {
        let definition = try #require(try ProviderFactory.builtIn("claude").defaultAccountHistory(gatewayAuth: Self.westep))
        var platform = Platform.current
        platform.applicationData = { home, _ in home.appendingPathComponent("Library/Application Support") }
        let fixturePlatform = platform
        let history = UsageHistory(definition, login: "claude", log: {
            DataSources.makeUsageLog($0, platform: fixturePlatform, scripts: ProviderFactory.builtInScripts,
                                    environment: { _ in nil }, homeDirectory: home)
        })
        await history.read()
        return try #require(history.otherApps.first)
    }

    private func buddyTokens(_ body: String) throws {
        let dir = home.appendingPathComponent("Library/Application Support/Claude")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try body.write(to: dir.appendingPathComponent("buddy-tokens.json"), atomically: true, encoding: .utf8)
    }

    private static func day(daysAgo: Int = 0) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = DataSources.timeZone()
        return formatter.string(from: DataSources.calendar().date(byAdding: .day, value: -daysAgo, to: Date())!)
    }

    @Test func `should show Claude Desktop's tokens today as their own history, with no cost (#198)`() async throws {
        try write(Self.line())
        try buddyTokens(#"{"tokens-today": {"date": "\#(Self.day())", "tokens": 74422}}"#)

        let desktop = try await desktop()

        #expect(desktop.label == "Claude Desktop")
        #expect(desktop.report?.today.totalTokens == 74_422)
        #expect(desktop.knowsCost == false)
    }

    @Test func `should count Claude Desktop's tokens as yesterday's, with nothing today yet, when it wrote them yesterday`() async throws {
        try buddyTokens(#"{"tokens-today": {"date": "\#(Self.day(daysAgo: 1))", "tokens": 61210}}"#)

        let report = try #require(try await desktop().report)

        #expect(report.previous.totalTokens == 61_210)
        #expect(report.today.isEmpty)
    }

    @Test(arguments: [
        "{ nope",
        #"{"something-else": {}}"#,
        #"{"tokens-today": {"tokens": 100}}"#,
        #"{"tokens-today": {"date": "May 28 2026", "tokens": 100}}"#,
        #"{"tokens-today": {"date": "2026-02-30", "tokens": 100}}"#,
        #"{"tokens-today": {"date": "2099-12-31", "tokens": 100}}"#,
    ])
    func `should show nothing for Claude Desktop when its tokens file changes shape`(body: String) async throws {
        try buddyTokens(body)
        #expect(try await desktop().report == nil)
    }

    @Test(arguments: ["-5", "74422.5"])
    func `should show nothing for Claude Desktop when its token count is negative or fractional`(count: String) async throws {
        try buddyTokens(#"{"tokens-today": {"date": "\#(Self.day())", "tokens": \#(count)}}"#)
        #expect(try await desktop().report == nil)
    }

    @Test func `should show nothing for Claude Desktop when it isn't on this Mac`() async throws {
        #expect(try await desktop().report == nil)
    }

    @Test
    func `should count Claude Desktop tokens from the app data folder supplied to the factory`() async throws {
        defer { try? FileManager.default.removeItem(at: home) }
        let appData = home.appendingPathComponent("Controlled App Data")
        let file = appData.appendingPathComponent("Claude/buddy-tokens.json")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"tokens-today":{"date":"2026-10-13","tokens":74422}}"#.utf8).write(to: file)
        // The old Mac location contains a different total, so choosing it is observable.
        try buddyTokens(#"{"tokens-today":{"date":"2026-10-13","tokens":123}}"#)
        var platform = Platform.current
        platform.applicationData = { _, _ in appData }
        let definition = try #require(try ProviderFactory.builtIn("claude").usageHistory?.otherApps?.first).definition
        let calendar = DataSources.calendar()
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 13, hour: 12)))
        // Log discovery filters by modification date; the date-only record is parsed in the person's zone.
        for fixture in [file, home.appendingPathComponent("Library/Application Support/Claude/buddy-tokens.json")] {
            try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: fixture.path)
        }
        let log = DataSources.makeUsageLog(definition, platform: platform, environment: { _ in nil },
                                          homeDirectory: home, now: { now })

        let today = try #require(await log.days(last: 1).first)
        #expect(today.totalTokens == 74_422)
        #expect(today.totalCost == 0)
        #expect(!log.knowsCost)
    }

    #if os(Windows)
    @Test(arguments: [nil, "", "redirected"] as [String?])
    func `should count Claude Desktop tokens from Windows app data including redirected APPDATA`(_ appDataValue: String?) async throws {
        defer { try? FileManager.default.removeItem(at: home) }
        let appData = appDataValue == "redirected"
            ? home.appendingPathComponent("Redirected App Data")
            : home.appendingPathComponent("AppData/Roaming")
        let file = appData.appendingPathComponent("Claude/buddy-tokens.json")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"tokens-today":{"date":"2026-10-13","tokens":61210}}"#.utf8).write(to: file)
        try buddyTokens(#"{"tokens-today":{"date":"2026-10-13","tokens":123}}"#)
        let environment: @Sendable (String) -> String? = { name in
            guard name == "APPDATA" else { return nil }
            return appDataValue == "redirected" ? appData.path : appDataValue
        }
        let definition = try #require(try ProviderFactory.builtIn("claude").usageHistory?.otherApps?.first).definition
        let calendar = DataSources.calendar()
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 13, hour: 12)))
        for fixture in [file, home.appendingPathComponent("Library/Application Support/Claude/buddy-tokens.json")] {
            try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: fixture.path)
        }
        let log = DataSources.makeUsageLog(definition, platform: .current, environment: environment,
                                          homeDirectory: home, now: { now })

        let today = try #require(await log.days(last: 1).first)
        #expect(today.totalTokens == 61_210)
        #expect(today.totalCost == 0)
    }
    #endif
}
