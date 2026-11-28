import Foundation
import Providers
import Quotas
import Testing

/// `"companion": true` — a data source that runs beside whichever one answers
/// a refresh and adds its quotas to that login's usage: a plan's API credit
/// on the Claude login it belongs to. It is never the answer, never picked,
/// and its failure leaves the login's usage and health as they were.
@MainActor
@Suite
struct CompanionTests {
    private let folder = FileManager.default.temporaryDirectory.appendingPathComponent("companion-\(UUID().uuidString)", isDirectory: true)

    private func write(_ name: String, _ json: String) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(json.utf8).write(to: folder.appendingPathComponent(name))
    }

    private func provider(settings: InMemoryProviderSettings = InMemoryProviderSettings()) throws -> Provider {
        let json = """
        {"profile":{"id":"ext-acme","name":"Acme","links":{}},
         "dataSources":[
          {"kind":"plan","fetch":{"file":{"path":"\(folder.path)/plan.json"}},"mapping":{"usage":{}}},
          {"kind":"credit","companion":true,"fetch":{"file":{"path":"\(folder.path)/credit.json"}},"mapping":{"usage":{}}}],
         "defaultDataSource":"plan"}
        """
        let definition = try ProviderDefinition.parse(Data(json.utf8), origin: .extension)
        return ProviderFactory.make(definition, settings: settings)
    }

    @Test
    func `should add the companion's quotas after the answer's own`() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        try write("plan.json", #"{"quotas":[{"type":"weekly","percentRemaining":62}]}"#)
        try write("credit.json", #"{"quotas":[{"type":"credit","percentRemaining":90}]}"#)
        let acme = try provider()

        let usage = try await acme.refreshPlain()

        #expect(usage.quotas.map(\.quotaType) == [.weekly, .timeLimit("credit")])
        #expect(acme.defaultAccount.answeredBy == "plan")
    }

    @Test
    func `should keep the answer and its health when the companion fails`() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        try write("plan.json", #"{"quotas":[{"type":"weekly","percentRemaining":62}]}"#)
        let acme = try provider()

        let usage = try await acme.refreshPlain()

        #expect(usage.quotas.map(\.quotaType) == [.weekly])
        #expect(acme.defaultAccount.lastError == nil)
    }

    @Test
    func `should never answer a refresh with the companion, even when it is the saved data source`() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        try write("plan.json", #"{"quotas":[{"type":"weekly","percentRemaining":62}]}"#)
        try write("credit.json", #"{"quotas":[{"type":"credit","percentRemaining":90}]}"#)
        let acme = try provider(settings: InMemoryProviderSettings(dataSourceKinds: ["ext-acme": "credit"]))

        _ = try await acme.refreshPlain()

        #expect(acme.configuration.activeKind == "plan")
        #expect(acme.configuration.use("credit") == false)
        #expect(acme.defaultAccount.answeredBy == "plan")
    }

    @Test
    func `should give each Claude login its plan's API credit, from its own admin key, beside its limits`() throws {
        let claude = try ProviderFactory.builtIn("claude")

        let credits = try #require(claude.dataSource("apiCredits"))

        #expect(credits.companion)
        #expect(credits.credential == .setting("adminKey"))
        #expect(claude.settings.filter { $0.scope == .account }.map(\.id) == ["adminKey", "billingDay", "monthlyCredit"])
        #expect(claude.defaultDataSource == "cli")
    }

    @Test
    func `should keep the companion out of the data sources a person picks, and keep it after a save`() throws {
        let definition = try provider().definition

        let again = try ProviderDefinition.parse(try JSONEncoder().encode(definition), origin: .extension)

        #expect(definition.dataSources.last?.hidden == true)
        #expect(again.dataSources.last?.companion == true)
    }
}
