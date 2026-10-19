import Foundation
import XCTest
@testable import CodexVitals

final class ClaudeDesktopUsageTests: XCTestCase {
    private let accountID = "11111111-1111-1111-1111-111111111111"
    private let orgID = "22222222-2222-2222-2222-222222222222"
    private let clientID = "33333333-3333-3333-3333-333333333333"
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func entry(account: String? = nil, org: String? = nil, host: String = "https://api.anthropic.com",
                       scopes: String = "user:profile", expiry: Double? = nil, token: String = "synthetic") -> (String, Any) {
        ("acct:\(account ?? accountID)|\(clientID):\(org ?? orgID):\(host):\(scopes)",
         ["token": token, "expiresAt": expiry ?? now.addingTimeInterval(3600).timeIntervalSince1970 * 1000])
    }

    func testSelectsOnlyCurrentAccountAndLeastPrivilegeScope() {
        let entries = Dictionary(uniqueKeysWithValues: [
            entry(scopes: "user:profile user:inference", token: "broad"),
            entry(token: "profile-only"),
            entry(account: UUID().uuidString, token: "other-account"),
            entry(host: "https://example.com", token: "other-host")
        ])
        let result = ClaudeDesktopCredentials.select(entries, accountID: accountID.uppercased(), now: now)
        XCTAssertEqual(result?.token, "profile-only")
        XCTAssertEqual(result?.organizationID, orgID)
    }

    func testRejectsAmbiguousOrganizations() {
        let entries = Dictionary(uniqueKeysWithValues: [entry(), entry(org: UUID().uuidString)])
        XCTAssertNil(ClaudeDesktopCredentials.select(entries, accountID: accountID, now: now))
    }

    func testRejectsExpiredUnscopedAndMalformedCredentials() {
        for item in [entry(expiry: now.timeIntervalSince1970 * 1000), entry(scopes: "user:inference"),
                     entry(org: "not-a-uuid"), entry(token: "")] {
            XCTAssertNil(ClaudeDesktopCredentials.select([item.0: item.1], accountID: accountID, now: now))
        }
        XCTAssertNil(ClaudeDesktopCredentials.select(["unbound": ["token": "synthetic"]], accountID: accountID, now: now))
    }

    func testDecryptsSyntheticDesktopFixtureAndRejectsUnsupportedFormat() throws {
        let encrypted = try XCTUnwrap(Data(base64Encoded: "djEw/exGEJSJCDxdBwHDmUNY9KxhtB6O+u4UjUD0iG5e3i4="))
        let result = try ClaudeDesktopCredentials.decrypt(encrypted, password: "test-only-password")
        XCTAssertEqual(String(data: result, encoding: .utf8), #"{"synthetic":"fixture"}"#)
        XCTAssertThrowsError(try ClaudeDesktopCredentials.decrypt(Data("v11unsupported".utf8), password: "test"))
        // CBC padding alone does not authenticate a password; the reader also requires valid JSON.
        XCTAssertThrowsError(try JSONSerialization.jsonObject(with:
            ClaudeDesktopCredentials.decrypt(encrypted, password: "wrong-password")))
    }

    private var credential: ClaudeDesktopCredential {
        ClaudeDesktopCredential(accountID: accountID, organizationID: orgID, token: "synthetic",
                                expiresAt: now.addingTimeInterval(3600))
    }

    private func session(profileAccount: String? = nil, status: Int = 200, onRequest: (() -> Void)? = nil) -> URLSession {
        let profile = """
        {"account":{"uuid":"\(profileAccount ?? accountID)","email":"test@example.com"},
         "organization":{"uuid":"\(orgID)","organization_type":"claude_max","rate_limit_tier":"default_claude_max_20x"}}
        """
        let reset = ISO8601DateFormatter().string(from: now.addingTimeInterval(1800))
        let usage = """
        {"five_hour":{"utilization":25,"resets_at":"\(reset)"},
         "seven_day":{"utilization":10,"resets_at":"\(reset)"}}
        """
        DesktopUsageURLProtocol.handler = { request in
            onRequest?()
            XCTAssertEqual(request.url?.host, "api.anthropic.com")
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer synthetic")
            return (status, Data((request.url?.lastPathComponent == "profile" ? profile : usage).utf8))
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DesktopUsageURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    func testReadsUsageCachesAndKeepsResetCountdownAccurate() async throws {
        var requests = 0
        let value = credential
        let service = ClaudeDesktopUsageService(readCredential: { _ in value }, session: session { requests += 1 })
        let first = await service.load(now: now)
        XCTAssertEqual(first?.plan, "Max 20x")
        XCTAssertEqual(first?.sessionFree, 75)
        XCTAssertEqual(first?.weeklyFree, 90)
        XCTAssertEqual(first?.workspace, "Claude Desktop")
        XCTAssertEqual(first?.canSwitchProviderAccount, false)
        XCTAssertNil(first?.providerProfileID)
        let second = await service.load(now: now.addingTimeInterval(120))
        XCTAssertEqual(requests, 2)
        XCTAssertEqual(second?.providerStatus, "cached")
        XCTAssertEqual(second?.sessionResetSeconds, 1680)
        XCTAssertEqual(second?.quotaWindows?.first?.resetAfterSeconds, 1680)
        _ = await service.load(now: now.addingTimeInterval(901))
        XCTAssertEqual(requests, 4)
    }

    func testProfileMismatchNeverPublishesUsageOrBypassesBackoff() async {
        var requests = 0
        let value = credential
        let service = ClaudeDesktopUsageService(readCredential: { _ in value },
            session: session(profileAccount: UUID().uuidString, onRequest: { requests += 1 }))
        let first = await service.load(now: now)
        let retry = await service.load(now: now.addingTimeInterval(5))
        XCTAssertNil(first)
        XCTAssertNil(retry)
        XCTAssertEqual(requests, 1)
    }

    func testAuthenticationFailureDoesNotHammerEndpoint() async {
        var requests = 0
        let value = credential
        let service = ClaudeDesktopUsageService(readCredential: { _ in value },
            session: session(status: 401, onRequest: { requests += 1 }))
        let first = await service.load(now: now)
        let retry = await service.load(now: now.addingTimeInterval(60))
        XCTAssertNil(first)
        XCTAssertNil(retry)
        XCTAssertEqual(requests, 1)
    }

    func testSignOutDiscardsCachedUsage() async {
        var value: ClaudeDesktopCredential? = credential
        let service = ClaudeDesktopUsageService(readCredential: { _ in value }, session: session())
        let first = await service.load(now: now)
        XCTAssertNotNil(first)
        value = nil
        let signedOut = await service.load(now: now.addingTimeInterval(30))
        XCTAssertNil(signedOut)
    }

    func testAccountChangeDuringRequestDiscardsResponse() async {
        var value: ClaudeDesktopCredential? = credential
        let service = ClaudeDesktopUsageService(readCredential: { _ in value }, session: session(onRequest: { value = nil }))
        let result = await service.load(now: now)
        XCTAssertNil(result)
    }
}

private final class DesktopUsageURLProtocol: URLProtocol {
    static var handler: ((URLRequest) -> (Int, Data))!
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (status, data) = Self.handler(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
