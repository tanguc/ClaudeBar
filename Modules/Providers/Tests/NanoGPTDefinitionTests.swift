import DataSources
import Foundation
import Mockable
import Providers
import Quotas
import Testing

/// NanoGPT as data: the subscription's weekly input tokens and daily images
/// from its usage endpoint, the balance from check-balance, and tokens from
/// the gateway's usage file.
@MainActor @Suite
struct NanoGPTDefinitionTests {
    static let usage = #"{"active":true,"state":"active","limits":{"weeklyInputTokens":60000000,"dailyInputTokens":null,"dailyImages":100},"dailyInputTokens":null,"weeklyInputTokens":{"used":2029,"remaining":59997971,"percentUsed":0.25,"resetAt":1795996800000},"dailyImages":{"used":10,"remaining":90,"percentUsed":0.1,"resetAt":1795996800000},"period":{"currentPeriodEnd":"2026-12-27T07:02:56.632Z"},"routing":{"recommendedMode":"subscription","reason":"included_quota_available","subscriptionQuotaAvailable":true}}"#
    static let balance = #"{"usd_balance":"12.95","usd_pending_usage":"0","usd_spendable_balance":"12.90"}"#

    private func make(usage: String = usage, usageStatus: Int = 200, balance: String = balance, balanceStatus: Int = 200,
                      vault: MemoryVault = MemoryVault(["nanogpt.apiKey": "key"])) throws -> Provider {
        let definition = try ProviderFactory.builtIn("nanogpt")
        let network = MockNetworkClient()
        given(network).request(.any).willProduce { @Sendable request in
            switch (request.httpMethod, request.url?.absoluteString) {
            case ("GET", "https://api.nano-gpt.com/api/subscription/v1/usage"):
                guard request.value(forHTTPHeaderField: "Authorization") == "Bearer key" else { return (Data(), StubbedProvider.response(401)) }
                return (Data(usage.utf8), StubbedProvider.response(usageStatus))
            case ("POST", "https://api.nano-gpt.com/api/check-balance"):
                guard request.value(forHTTPHeaderField: "x-api-key") == "key" else { return (Data(), StubbedProvider.response(401)) }
                return (Data(balance.utf8), StubbedProvider.response(balanceStatus))
            default:
                return (Data(), StubbedProvider.response(400))
            }
        }
        let settings = InMemoryProviderSettings()
        return Provider(definition: definition, settings: settings, accounts: [],
                        makeDataSource: { source, login in
            DataSources.make(source, providerId: definition.id, cliExecutor: MockCLIExecutor(), network: network,
                             makeTransport: { _, _, _, _ in MockRPCTransport() }, scripts: ProviderFactory.builtInScripts,
                             secrets: vault.scoped(to: login), environment: { _ in nil },
                             homeDirectory: FileManager.default.temporaryDirectory, now: { Date() })
        }, vault: vault)
    }

    @Test func `should show NanoGPT with its usage dashboard, off until turned on`() throws {
        let provider = try make()
        #expect(provider.id == "nanogpt")
        #expect(provider.name == "NanoGPT")
        #expect(!provider.plainIsInLineup)
        #expect(provider.definition.profile.links.dashboard == URL(string: "https://nano-gpt.com/usage"))
    }

    @Test func `should show the weekly input tokens left with their reset and counts`() async throws {
        let weekly = try #require(try await make().refreshPlain().quotas.first { $0.quotaType == .weekly })
        #expect(weekly.percentLeft == 75)
        #expect(weekly.resetsAt == Date(timeIntervalSince1970: 1_795_996_800))
        #expect(weekly.resetText == "2K of 60M input tokens")
    }

    @Test func `should show today's images and leave out a daily token quota NanoGPT does not set`() async throws {
        let quotas = try await make().refreshPlain().quotas
        #expect(quotas.first { $0.quotaType == .modelSpecific("Images") }?.percentLeft == 90)
        #expect(quotas.contains { $0.quotaType == .modelSpecific("Daily tokens") } == false)
    }

    @Test func `should show the spendable balance in dollars`() async throws {
        let money = try #require(try await make().refreshPlain().quotas.first { $0.quotaType == .modelSpecific("Balance") })
        #expect(money.left == .money(Money(Decimal(string: "12.90")!, currency: "USD"), of: nil))
    }

    @Test func `should still show the quotas when the balance cannot be read`() async throws {
        let quotas = try await make(balanceStatus: 500).refreshPlain().quotas
        #expect(quotas.contains { $0.quotaType == .weekly })
        #expect(quotas.contains { $0.quotaType == .modelSpecific("Balance") } == false)
    }

    @Test func `should say requests spend the balance once the subscription is used up`() async throws {
        let spent = Self.usage.replacingOccurrences(of: #""recommendedMode":"subscription""#, with: #""recommendedMode":"paygo""#)
            .replacingOccurrences(of: #""percentUsed":0.25"#, with: #""percentUsed":1.02"#)
        let weekly = try #require(try await make(usage: spent).refreshPlain().quotas.first { $0.quotaType == .weekly })
        #expect(weekly.percentLeft == 0)
        #expect(weekly.resetText?.hasSuffix("Subscription used up: requests now spend the balance") == true)
    }

    @Test func `should show an unknown counter as nothing left, never a full allowance`() async throws {
        let degraded = Self.usage.replacingOccurrences(of: #"{"used":2029,"remaining":59997971,"percentUsed":0.25,"resetAt":1795996800000}"#,
                                                       with: #"{"used":null,"remaining":null,"percentUsed":null,"resetAt":null}"#)
        let weekly = try #require(try await make(usage: degraded).refreshPlain().quotas.first { $0.quotaType == .weekly })
        #expect(weekly.percentLeft == 0)
        #expect(weekly.resetText == "Usage unknown right now")
    }

    @Test func `should ask for the key again when NanoGPT refuses it`() async throws {
        await #expect(throws: UsageError.authenticationRequired) { try await make(usageStatus: 401).refreshPlain() }
    }

    @Test func `should read the gateway usage file for its own gateway account only`() throws {
        let definition = try ProviderFactory.builtIn("nanogpt")
        #expect(definition.defaultAccountHistory == nil)
        let history = try #require(definition.defaultAccountHistory(gatewayAuth: "claude:apikey:51e84b2e15b2"))
        // sha-256 of the gateway's auth id, as the usage file's auth_ref
        #expect(history.records.shapes.first?.where == Match(path: "$.auth_ref", equals: .string("44371921b5175e84f349d1df87d077150eace2d7354de265fa14bc50c09b90de")))
        #expect(!UsageHistory(log: DataSources.makeUsageLog(history, environment: { _ in nil })).knowsCost)
    }
}
