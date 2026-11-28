import DataSources
import Foundation
import Mockable
import Providers
import Quotas
import Testing
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Claude API credits as data: the monthly credit of a Max/Ultra/Team plan,
/// against the organization's spend since the plan renewed, from the Admin
/// API's cost report, read by `claude-api-credits.js`.
@MainActor @Suite
struct ClaudeAPICreditsDefinitionTests {
    /// 2026-11-28 12:00:00 UTC; 30 days before its midnight is 2026-10-29.
    private nonisolated static let now = Date(timeIntervalSince1970: 1_795_867_200)
    private static let costURL = "https://api.anthropic.com/v1/organizations/cost_report?starting_at=2026-10-29T00:00:00Z&bucket_width=1d&limit=31&group_by%5B%5D=description"

    /// amounts are cents: 50 + 1234.5 + 300 + 1000 + 50 from the 14th, 5000 before it
    static let report = #"""
    {"data":[
     {"starting_at":"2026-11-13T00:00:00Z","ending_at":"2026-11-14T00:00:00Z","results":[
      {"amount":"5000","currency":"USD","cost_type":"tokens","model":"claude-opus-5-5","description":"Claude Opus 5.5 Usage - Output Tokens"}]},
     {"starting_at":"2026-11-14T00:00:00Z","ending_at":"2026-11-15T00:00:00Z","results":[
      {"amount":"1234.5","currency":"USD","cost_type":"tokens","model":"claude-opus-5-5","description":"Claude Opus 5.5 Usage - Input Tokens"},
      {"amount":"300","currency":"USD","cost_type":"tokens","model":"claude-sonnet-5-5","description":"Claude Sonnet 5.5 Usage - Input Tokens"}]},
     {"starting_at":"2026-11-20T00:00:00Z","ending_at":"2026-11-21T00:00:00Z","results":[
      {"amount":"1000","currency":"USD","cost_type":"tokens","model":"claude-opus-5-5","description":"Claude Opus 5.5 Usage - Output Tokens"},
      {"amount":"50","currency":"USD","cost_type":"web_search","model":null,"description":"Web Search Usage"},
      {"amount":null,"currency":"USD","cost_type":null,"model":null,"description":null}]},
     {"starting_at":"2026-11-28T00:00:00Z","ending_at":"2026-11-29T00:00:00Z","results":[]}],
     "has_more":false,"next_page":null}
    """#

    final class Seen: @unchecked Sendable {
        private let lock = NSLock()
        private var request: URLRequest?
        func record(_ request: URLRequest) { lock.lock(); self.request = request; lock.unlock() }
        var last: URLRequest? { lock.lock(); defer { lock.unlock() }; return request }
    }

    private func make(body: String = Self.report, status: Int = 200,
                      environment: [String: String] = ["ANTHROPIC_ADMIN_KEY": "sk-ant-admin-test"],
                      values: [String: String] = [:],
                      vault: MemoryVault = MemoryVault(), seen: Seen = Seen()) throws -> Provider {
        let definition = try ProviderFactory.builtIn("claude-api")
        let network = MockNetworkClient()
        given(network).request(.any).willProduce { @Sendable request in
            seen.record(request)
            return (Data(body.utf8), StubbedProvider.response(status))
        }
        let settings = InMemoryProviderSettings()
        for (key, value) in values { settings.setValue(value, key, forProvider: "claude-api") }
        return Provider(definition: definition, settings: settings, makeDataSource: { source, login in
            DataSources.make(source, providerId: definition.id, cliExecutor: MockCLIExecutor(), network: network,
                             makeTransport: { _, _, _, _ in MockRPCTransport() }, scripts: ProviderFactory.builtInScripts,
                             secrets: vault.scoped(to: login), environment: { environment[$0] },
                             homeDirectory: FileManager.default.temporaryDirectory, now: { Self.now })
        }, vault: vault)
    }

    /// local midnight of a day, in the zone the script's `Date` uses
    private func localMidnight(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(timeZone: DataSources.timeZone(), year: year, month: month, day: day))!
    }

    @Test
    func `should be Claude API credits, off until turned on, with the Console billing page`() throws {
        let credits = try make()
        #expect(credits.id == "claude-api")
        #expect(credits.name == "Claude API credits")
        #expect(credits.plainIsInLineup == false)
        #expect(credits.definition.profile.links.dashboard == URL(string: "https://platform.claude.com/settings/billing"))
    }

    @Test
    func `should ask the cost report for the last 30 days, with the Admin key`() async throws {
        let seen = Seen()
        _ = try await make(seen: seen).refreshPlain()
        #expect(seen.last?.url?.absoluteString == Self.costURL)
        #expect(seen.last?.value(forHTTPHeaderField: "x-api-key") == "sk-ant-admin-test")
        #expect(seen.last?.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
    }

    @Test
    func `should count only the spend since the plan renewed, against the monthly credit`() async throws {
        let usage = try await make(values: ["billingDay": "14"]).refreshPlain()
        let quota = try #require(usage.quotas.first)
        #expect(quota.left == .money(Money(Decimal(string: "174.155")!, currency: "USD"), of: Money(200, currency: "USD")))
        #expect(quota.resetText == "Spent $25.85 of $200.00")
        #expect(quota.resetsAt == localMidnight(2026, 12, 14))
        let cost = try #require(usage.costUsage)
        #expect(cost.totalCost == Decimal(string: "25.845"))
        #expect(cost.budget == 200)
        #expect(cost.resetText == "Since 2026-11-14")
        #expect(cost.lines.map(\.label) == ["claude-opus-5-5", "claude-sonnet-5-5", "Web search"])
        #expect(cost.lines.map(\.amount) == [Decimal(string: "22.345"), 3, Decimal(string: "0.5")])
    }

    @Test
    func `should start the cycle on the 1st when no renewal day is set`() async throws {
        let usage = try await make().refreshPlain()
        #expect(usage.costUsage?.totalCost == Decimal(string: "75.845"))
        #expect(usage.costUsage?.resetText == "Since 2026-11-01")
        #expect(usage.quotas.first?.resetsAt == localMidnight(2026, 12, 1))
    }

    @Test
    func `should renew on the month's last day when the renewal day is past it`() async throws {
        let usage = try await make(values: ["billingDay": "31"]).refreshPlain()
        #expect(usage.costUsage?.resetText == "Since 2026-10-31")
        #expect(usage.quotas.first?.resetsAt == localMidnight(2026, 11, 30))
    }

    @Test
    func `should use the credit the person set and show nothing left once it is spent`() async throws {
        let usage = try await make(values: ["monthlyCredit": "50"]).refreshPlain()
        #expect(usage.quotas.first?.left == .money(Money(0, currency: "USD"), of: Money(50, currency: "USD")))
        #expect(usage.costUsage?.budget == 50)
    }

    @Test
    func `should use a pasted Admin key when there is no environment key`() async throws {
        let seen = Seen()
        _ = try await make(environment: [:], vault: MemoryVault(["claude-api.apiKey": "sk-ant-admin-pasted"]), seen: seen).refreshPlain()
        #expect(seen.last?.value(forHTTPHeaderField: "x-api-key") == "sk-ant-admin-pasted")
    }

    @Test
    func `should ask for a key when there is none`() async throws {
        let credits = try make(environment: [:])
        let account = credits.defaultAccount
        await #expect(throws: UsageError.authenticationRequired) { try await credits.refresh(account) }
        #expect(account.lastFailedStep == .lookup)
    }

    @Test(arguments: [401, 403])
    func `should ask for an Admin key when Anthropic refuses the key`(_ status: Int) async throws {
        let credits = try make(status: status)
        await #expect(throws: UsageError.sessionExpired(hint: "Use an Admin API key (sk-ant-admin...); a normal API key can't read spend.")) {
            try await credits.refresh(credits.defaultAccount)
        }
    }

    @Test(arguments: ["not json", #"{"has_more":false}"#])
    func `should fail reading the spend when the answer has no buckets`(_ body: String) async throws {
        let credits = try make(body: body)
        let account = credits.defaultAccount
        await #expect(throws: UsageError.self) { try await credits.refresh(account) }
        #expect(account.lastFailedStep == .mapping)
    }
}
