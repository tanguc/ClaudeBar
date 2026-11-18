import Foundation
import Leaderboard

/// fork: the leaderboard never reaches a server, every call fails as unreachable
struct OfflineLeaderboardAPI: LeaderboardAPI {
    func join(username: String, publicKey: String, label: String) async throws { throw LeaderboardError.unreachable }
    func upload(_ days: [DailyTokens], as credentials: MemberCredentials) async throws -> [RefusedDay] { throw LeaderboardError.unreachable }
    func me(period: BoardPeriod, provider: String?, as credentials: MemberCredentials) async throws -> MemberSummary { throw LeaderboardError.unreachable }
    func export(as credentials: MemberCredentials) async throws -> Data { throw LeaderboardError.unreachable }
    func update(_ change: MemberChange, as credentials: MemberCredentials) async throws { throw LeaderboardError.unreachable }
    func leave(as credentials: MemberCredentials) async throws { throw LeaderboardError.unreachable }
    func board(period: BoardPeriod, provider: String?) async throws -> [Board.Member] { throw LeaderboardError.unreachable }
    func globe(period: BoardPeriod) async throws -> GlobeSummary { throw LeaderboardError.unreachable }
    func requestDevice(publicKey: String, label: String) async throws -> DeviceAuthorization { throw LeaderboardError.unreachable }
    func approval(of key: SigningKey) async throws -> DeviceApproval { throw LeaderboardError.unreachable }
    func pendingDevice(code: DeviceCode, as credentials: MemberCredentials) async throws -> PendingDevice { throw LeaderboardError.unreachable }
    func approveDevice(code: DeviceCode, as credentials: MemberCredentials) async throws -> Device { throw LeaderboardError.unreachable }
    func removeDevice(_ publicKey: String, as credentials: MemberCredentials) async throws { throw LeaderboardError.unreachable }
    func deleteDays(of publicKey: String, provider: String?, day: String?, as credentials: MemberCredentials) async throws { throw LeaderboardError.unreachable }
}
