#if os(macOS)
import Foundation

extension Platform {
    /// The Mac: the key in the app's UserDefaults (fork: never the Keychain,
    /// whose prompts come back with every local rebuild); the machine through
    /// the I/O Registry.
    static let current = Platform(
        deviceName: "Mac",
        signingKeyStore: DefaultsSigningKeyStore(),
        machineIdentity: IOKitMachineIdentity()
    )
}
#endif
