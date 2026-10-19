import CommonCrypto
import Foundation

/// Desktop owns and refreshes these credentials. Vitals only reads an existing
/// account-bound bearer with user:profile scope; it never copies a refresh token.
struct ClaudeDesktopCredential {
    let accountID: String
    let organizationID: String
    let token: String
    let expiresAt: Date
    var id: String { "claude-desktop:\(accountID)|\(organizationID)" }
}

enum ClaudeDesktopCredentials {
    static let configURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Claude/config.json")

    static func read(now: Date) throws -> ClaudeDesktopCredential? {
        guard FileManager.default.fileExists(atPath: configURL.path) else { return nil }
        let data = try Data(contentsOf: configURL)
        guard data.count < 16 * 1024 * 1024,
              let config = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accountID = config["lastKnownAccountUuid"] as? String,
              UUID(uuidString: accountID) != nil else { return nil }
        let encrypted = ["oauth:tokenCacheV2", "oauth:tokenCache"].compactMap { config[$0] as? String }
        guard !encrypted.isEmpty else { return nil }
        guard let password = try ClaudeKeychainStore().read(service: "Claude Safe Storage", account: "Claude Key") else {
            throw ClaudeNativeError.keychainUnavailable("Claude Desktop sign-in is locked")
        }
        var candidates: [ClaudeDesktopCredential] = []
        for value in encrypted {
            guard let data = Data(base64Encoded: value),
                  let decoded = try? decrypt(data, password: password),
                  let entries = try? JSONSerialization.jsonObject(with: decoded) as? [String: Any] else { continue }
            if let selected = select(entries, accountID: accountID, now: now) { candidates.append(selected) }
        }
        // Two organizations for the same account must not be silently conflated.
        guard Set(candidates.map(\.organizationID)).count <= 1 else { return nil }
        return candidates.first
    }

    static func select(_ entries: [String: Any], accountID: String, now: Date) -> ClaudeDesktopCredential? {
        guard UUID(uuidString: accountID) != nil else { return nil }
        let prefix = "acct:\(accountID.lowercased())|"
        let candidates: [(ClaudeDesktopCredential, Int)] = entries.compactMap { name, value in
            guard name.lowercased().hasPrefix(prefix),
                  let range = name.range(of: ":https://api.anthropic.com:"),
                  let entry = value as? [String: Any],
                  let token = entry["token"] as? String, !token.isEmpty,
                  let expiry = entry["expiresAt"] as? Double, expiry.isFinite,
                  expiry > now.timeIntervalSince1970 * 1000 + 60_000 else { return nil }
            let identity = name[name.index(name.startIndex, offsetBy: prefix.count)..<range.lowerBound].split(separator: ":")
            guard identity.count == 2, UUID(uuidString: String(identity[0])) != nil,
                  UUID(uuidString: String(identity[1])) != nil else { return nil }
            let scopes = Set(name[range.upperBound...].split(separator: " ").map(String.init))
            guard scopes.contains("user:profile") else { return nil }
            return (ClaudeDesktopCredential(accountID: accountID.lowercased(), organizationID: String(identity[1]).lowercased(),
                token: token, expiresAt: Date(timeIntervalSince1970: expiry / 1000)), scopes.count)
        }
        guard Set(candidates.map { $0.0.organizationID }).count <= 1 else { return nil }
        return candidates.sorted {
            $0.1 == $1.1 ? $0.0.expiresAt > $1.0.expiresAt : $0.1 < $1.1
        }.first?.0
    }

    static func decrypt(_ encrypted: Data, password: String) throws -> Data {
        guard encrypted.count > 3, encrypted.count < 4 * 1024 * 1024,
              encrypted.prefix(3) == Data("v10".utf8) else { throw ClaudeNativeError.invalidCredentials }
        let passwordBytes = Array(password.utf8)
        let salt = Array("saltysalt".utf8)
        var key = [UInt8](repeating: 0, count: 16)
        defer { key = [UInt8](repeating: 0, count: key.count) }
        let result = passwordBytes.withUnsafeBytes { bytes in
            CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), bytes.baseAddress?.assumingMemoryBound(to: CChar.self),
                passwordBytes.count, salt, salt.count, CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1), 1003, &key, key.count)
        }
        guard result == kCCSuccess else { throw ClaudeNativeError.invalidCredentials }
        let ciphertext = encrypted.dropFirst(3)
        let iv = [UInt8](repeating: 32, count: 16)
        var plaintext = [UInt8](repeating: 0, count: ciphertext.count + 16)
        var count = 0
        let status = ciphertext.withUnsafeBytes { bytes in
            CCCrypt(CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding),
                key, key.count, iv, bytes.baseAddress, ciphertext.count, &plaintext, plaintext.count, &count)
        }
        guard status == kCCSuccess else { throw ClaudeNativeError.invalidCredentials }
        return Data(plaintext.prefix(count))
    }
}

actor ClaudeDesktopUsageService {
    private var cached: (Profile, ClaudeUsageResponse)?
    private var observedID: String?
    private var nextRefresh = Date.distantPast
    private let readCredential: (Date) throws -> ClaudeDesktopCredential?
    private let session: URLSession

    init(readCredential: @escaping (Date) throws -> ClaudeDesktopCredential? = { try ClaudeDesktopCredentials.read(now: $0) },
         session: URLSession = URLSession(configuration: .ephemeral)) {
        self.readCredential = readCredential
        self.session = session
    }

    func load(now: Date = Date()) async -> Account? {
        do {
            guard let credential = try readCredential(now) else {
                cached = nil; observedID = nil; nextRefresh = .distantPast
                return nil
            }
            if observedID != credential.id {
                cached = nil; observedID = credential.id; nextRefresh = .distantPast
            }
            if now < nextRefresh { return adjustedCache(now: now) }
            nextRefresh = now.addingTimeInterval(ClaudeAccountService.minimumUsageRefreshInterval)
            let profileData = try await request("profile", token: credential.token)
            let profile = try JSONDecoder().decode(Profile.self, from: profileData)
            guard profile.account.uuid.lowercased() == credential.accountID,
                  profile.organization.uuid.lowercased() == credential.organizationID else {
                cached = nil
                return nil
            }
            let data = try await request("usage", token: credential.token)
            let usage = try JSONDecoder().decode(ClaudeUsageResponse.self, from: data)
            let result = Self.account(profile: profile, usage: usage, id: credential.id, now: now)
            // Discard responses if Desktop switched accounts while requests were in flight.
            guard try readCredential(now)?.id == credential.id else { cached = nil; return nil }
            cached = (profile, usage)
            return result
        } catch {
            cached = nil
            return nil // Never publish another identity or zero usage after an auth failure.
        }
    }

    private func request(_ endpoint: String, token: String) async throws -> Data {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/\(endpoint)")!, timeoutInterval: 15)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        let (data, response) = try await session.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code == 429 {
            nextRefresh = max(nextRefresh, Date().addingTimeInterval(ClaudeUsageClient.retryAfterSeconds(from: response as? HTTPURLResponse) ?? 900))
        }
        guard code == 200 else { throw ClaudeNativeError.serviceUnavailable(code) }
        return data
    }

    private func adjustedCache(now: Date) -> Account? {
        guard let (profile, usage) = cached, let id = observedID else { return nil }
        var result = Self.account(profile: profile, usage: usage, id: id, now: now)
        result.providerStatus = "cached"
        return result
    }

    struct Profile: Decodable {
        struct Identity: Decodable { let uuid: String; let email: String }
        struct Organization: Decodable {
            let uuid: String
            let name: String?
            let organization_type: String?
            let rate_limit_tier: String?
        }
        let account: Identity
        let organization: Organization
    }

    static func account(profile: Profile, usage: ClaudeUsageResponse, id: String, now: Date) -> Account {
        func window(_ value: ClaudeUsageResponse.Window?, duration: Double) -> QuotaWindow? {
            guard let value else { return nil }
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let date = value.resetsAt.flatMap { formatter.date(from: $0) } ?? {
                formatter.formatOptions = [.withInternetDateTime]
                return value.resetsAt.flatMap { formatter.date(from: $0) }
            }()
            return QuotaWindow(limitSeconds: duration, remainingPercent: max(0, min(100, 100 - value.utilization)),
                               resetAfterSeconds: max(0, date?.timeIntervalSince(now) ?? 0))
        }
        let five = window(usage.fiveHour, duration: QuotaWindow.fiveHourSeconds)
        let week = window(usage.sevenDay, duration: QuotaWindow.weeklySeconds)
        let windows = [five, week].compactMap { $0 }
        let metadata = ["organizationType": profile.organization.organization_type ?? "",
                        "organizationRateLimitTier": profile.organization.rate_limit_tier ?? ""]
        return Account(id: id, profileKey: nil, email: profile.account.email,
            workspace: "Claude Desktop", plan: ClaudePlanFormatter.displayName(from: metadata) ?? "Claude",
            sessionFree: five?.remainingPercent ?? 0, weeklyFree: week?.remainingPercent ?? 0,
            sessionResetSeconds: five?.resetAfterSeconds ?? 0, weeklyResetSeconds: week?.resetAfterSeconds ?? 0,
            quotaWindows: windows, fableQuotaWindow: window(usage.fable, duration: QuotaWindow.weeklySeconds),
            hasError: windows.isEmpty, errorMessage: windows.isEmpty ? "Claude usage unavailable." : nil,
            provider: .claude, providerIsActive: true, providerStatus: windows.isEmpty ? "unavailable" : "ok")
    }
}
