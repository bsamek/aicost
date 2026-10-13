import CryptoKit
import Foundation

// Public-key-only verification: the release must match the key embedded in the app.
let arguments = CommandLine.arguments
guard arguments.count == 4,
    let publicData = Data(base64Encoded: arguments[2]),
    let signature = Data(base64Encoded: arguments[3])
else { fatalError("Usage: verify-update.swift ARCHIVE PUBLIC_KEY SIGNATURE") }
let key = try Curve25519.Signing.PublicKey(rawRepresentation: publicData)
let archive = try Data(contentsOf: URL(fileURLWithPath: arguments[1]))
guard key.isValidSignature(signature, for: archive) else {
    FileHandle.standardError.write(
        Data("Update signature does not match the app's public key.\n".utf8))
    exit(1)
}
