import Foundation

// MARK: - Patch Profile (persisted as JSON, read by tweak)

struct PatchProfile: Codable, Identifiable {
    var id: UUID
    var name: String
    var bundleID: String
    var appName: String
    var enabled: Bool
    var patches: [PatchEntry]
    var createdAt: Date
    var updatedAt: Date
}

struct PatchEntry: Codable, Identifiable {
    var id: UUID
    var name: String
    var enabled: Bool
    var pattern: String       // hex with ?? wildcards, e.g. "f4 4f ?? a9"
    var replacement: String   // hex bytes to write
    var offset: Int           // byte offset from match start

    var isValid: Bool {
        !pattern.isEmpty && !replacement.isEmpty
            && validateHex(pattern) && validateHex(replacement)
    }

    private func validateHex(_ hex: String) -> Bool {
        let tokens = hex.split(separator: " ")
        guard !tokens.isEmpty else { return false }
        for token in tokens {
            if token == "??" { continue }
            guard token.count == 2, UInt8(token, radix: 16) != nil else { return false }
        }
        return true
    }
}

// MARK: - Installed App (runtime only)

struct InstalledApp: Identifiable {
    var id: String { bundleID }
    var name: String
    var bundleID: String
    var version: String
    var iconPath: String?
    var patchCount: Int = 0
}
