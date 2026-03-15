import Foundation

/// Reads and writes patch profiles as JSON files in the shared directory.
/// The tweak reads these same files at app launch.
class PatchStore: ObservableObject {
    static let shared = PatchStore()

    @Published var profiles: [PatchProfile] = []

    private let patchesDir: String
    private let fm = FileManager.default

    init() {
        #if targetEnvironment(simulator)
        patchesDir = NSHomeDirectory() + "/Library/iPatcher/patches"
        #else
        patchesDir = "/var/jb/var/mobile/Library/iPatcher/patches"
        #endif

        try? fm.createDirectory(atPath: patchesDir,
                                withIntermediateDirectories: true)
        loadAll()
    }

    // MARK: - CRUD

    func loadAll() {
        guard let files = try? fm.contentsOfDirectory(atPath: patchesDir) else { return }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        profiles = files.compactMap { filename -> PatchProfile? in
            guard filename.hasSuffix(".json") else { return nil }
            let path = (patchesDir as NSString).appendingPathComponent(filename)
            guard let data = fm.contents(atPath: path) else { return nil }
            return try? decoder.decode(PatchProfile.self, from: data)
        }
        .sorted { $0.updatedAt > $1.updatedAt }
    }

    func save(_ profile: PatchProfile) {
        var p = profile
        p.updatedAt = Date()

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        guard let data = try? encoder.encode(p) else { return }
        let path = (patchesDir as NSString)
            .appendingPathComponent("\(p.bundleID).json")
        fm.createFile(atPath: path, contents: data)

        loadAll()
    }

    func delete(_ profile: PatchProfile) {
        let path = (patchesDir as NSString)
            .appendingPathComponent("\(profile.bundleID).json")
        try? fm.removeItem(atPath: path)
        loadAll()
    }

    func profile(for bundleID: String) -> PatchProfile? {
        profiles.first { $0.bundleID == bundleID }
    }

    // MARK: - Import / Export

    func exportProfile(_ profile: PatchProfile) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(profile)
    }

    func importProfile(from data: Data) -> PatchProfile? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let profile = try? decoder.decode(PatchProfile.self, from: data)
        else { return nil }
        save(profile)
        return profile
    }
}
