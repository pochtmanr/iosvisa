import Foundation
import CryptoKit

/// Nonce helpers for Sign in with Apple: a random raw nonce is generated, its
/// SHA-256 is sent in the Apple request, and the **raw** nonce is handed to
/// Supabase to bind the id-token. Pure + headless-safe (unit-tested).
enum Nonce {
    /// A cryptographically-random nonce string of `length` URL-safe characters.
    static func random(length: Int = 32) -> String {
        precondition(length > 0)
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        var bytes = [UInt8](repeating: 0, count: length)
        if SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) != errSecSuccess {
            for index in bytes.indices { bytes[index] = UInt8.random(in: 0...255) }
        }
        return String(bytes.map { charset[Int($0) % charset.count] })
    }

    /// Lowercase hex SHA-256 of the input string (the value sent to Apple).
    static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
