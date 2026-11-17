import CryptoKit
import Foundation

// Usage: swift verify-ed25519.swift <base64 public key> <file> <base64 signature>
guard CommandLine.arguments.count == 4,
      let keyBytes = Data(base64Encoded: CommandLine.arguments[1]),
      let signature = Data(base64Encoded: CommandLine.arguments[3]) else {
    exit(2)
}
let key = try Curve25519.Signing.PublicKey(rawRepresentation: keyBytes)
let file = URL(fileURLWithPath: CommandLine.arguments[2])
let contents = try Data(contentsOf: file, options: .mappedIfSafe)
guard key.isValidSignature(signature, for: contents) else {
    FileHandle.standardError.write(Data("Invalid EdDSA signature for \(file.lastPathComponent)\n".utf8))
    exit(1)
}
