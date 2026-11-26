import DataSources
import Providers

/// A built-in definition as its default account runs it — signed in on this
/// Mac, `{{account.folder}}` where the vendor keeps the default login.
extension ProviderDefinition {
    func asDefaultAccount(_ kind: String) throws -> DataSourceDefinition? {
        try dataSources(forDefaultAccount: defaultAccountValues).first { $0.kind == kind }
    }

    var defaultAccountHistory: UsageLog.Definition? {
        usageHistory(forDefaultAccount: defaultAccountValues)
    }

    /// The plain login's history with its gateway account set, as the person saves it.
    func defaultAccountHistory(gatewayAuth: String) -> UsageLog.Definition? {
        usageHistory(forDefaultAccount: defaultAccountValues.merging(["gatewayAuth": gatewayAuth]) { _, set in set })
    }
}
