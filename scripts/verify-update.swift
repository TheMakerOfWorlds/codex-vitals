import CryptoKit
import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

final class Feed: NSObject, XMLParserDelegate {
    var enclosures: [[String: String]] = []
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        if elementName == "enclosure" { enclosures.append(attributes) }
    }
}
func require(_ condition: Bool, _ message: String) throws {
    if !condition { throw NSError(domain: "CodexVitals.Release", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}
do {
    try require(CommandLine.arguments.count == 4, "Usage: verify-update.swift feed archive Info.plist")
    let arguments = CommandLine.arguments
    let parser = XMLParser(data: try Data(contentsOf: URL(fileURLWithPath: arguments[1])))
    let feed = Feed()
    parser.delegate = feed
    try require(parser.parse() && feed.enclosures.count == 1, "Expected exactly one valid update enclosure")
    let enclosure = feed.enclosures[0]
    let archive = URL(fileURLWithPath: arguments[2])
    let data = try Data(contentsOf: archive, options: .mappedIfSafe)
    let url = URL(string: enclosure["url"] ?? "")
    try require(url?.scheme == "https" && url?.host == "github.com" &&
        url?.path.hasPrefix("/TheMakerOfWorlds/codex-vitals/releases/download/v") == true &&
        url?.lastPathComponent == archive.lastPathComponent,
        "The update must download from TheMakerOfWorlds/codex-vitals")
    try require(Int(enclosure["length"] ?? "") == data.count, "Archive length does not match the feed")
    let plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: URL(fileURLWithPath: arguments[3])), format: nil) as? [String: Any]
    guard let publicKey = (plist?["SUPublicEDKey"] as? String).flatMap({ Data(base64Encoded: $0) }),
          let signature = enclosure["sparkle:edSignature"].flatMap({ Data(base64Encoded: $0) }) else {
        throw NSError(domain: "CodexVitals.Release", code: 2, userInfo: [NSLocalizedDescriptionKey: "Missing signing key or signature"])
    }
    let key = try Curve25519.Signing.PublicKey(rawRepresentation: publicKey)
    try require(key.isValidSignature(signature, for: data), "Invalid update signature")
    print("Verified repository URL, archive length, and Ed25519 signature.")
} catch {
    fputs("\(error.localizedDescription)\n", stderr)
    exit(1)
}
