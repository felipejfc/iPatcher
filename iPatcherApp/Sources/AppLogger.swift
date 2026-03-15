import Foundation

enum LogSource: String {
    case app = "APP"
    case patcher = "PATCHER"
    case loader = "LOADER"
}

struct LogEntry: Identifiable {
    let id = UUID()
    let source: LogSource
    let text: String
}

final class AppLogger: ObservableObject {
    static let shared = AppLogger()

    @Published private(set) var entries: [LogEntry] = []

    private let fm = FileManager.default
    private let logPath = "/var/jb/var/mobile/Library/iPatcher/app.log"
    private let taggedPaths: [(String, LogSource)] = [
        ("/var/jb/var/mobile/Library/iPatcher/app.log", .app),
        ("/var/jb/var/mobile/Library/iPatcher/tweak.log", .patcher),
        ("/var/jb/var/mobile/Library/iPatcher/tweakloader.log", .loader),
    ]
    private let maxEntries = 400
    private let queue = DispatchQueue(label: "com.ipatcher.applogger", qos: .utility)

    private init() {
        load()
    }

    func load() {
        queue.async { [weak self] in
            guard let self else { return }
            var all: [(sort: String, entry: LogEntry)] = []
            for (path, source) in self.taggedPaths {
                guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
                for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
                    let s = String(line)
                    all.append((sort: s, entry: LogEntry(source: source, text: s)))
                }
            }
            all.sort { $0.sort < $1.sort }
            let result = Array(all.suffix(self.maxEntries).map(\.entry))
            DispatchQueue.main.async {
                self.entries = result
            }
        }
    }

    func clear() {
        queue.async { [weak self] in
            guard let self else { return }
            for (path, _) in self.taggedPaths {
                try? self.fm.removeItem(atPath: path)
            }
            DispatchQueue.main.async {
                self.entries = []
            }
        }
    }

    func log(_ message: String, level: String = "INFO") {
        guard UserDefaults.standard.object(forKey: "ip_logEnabled") as? Bool ?? true else {
            return
        }

        let line = "\(Self.timestamp()) [\(level)] \(message)"
        queue.async { [weak self] in
            guard let self else { return }

            let dir = (self.logPath as NSString).deletingLastPathComponent
            try? self.fm.createDirectory(atPath: dir, withIntermediateDirectories: true)

            let existing = (try? String(contentsOfFile: self.logPath, encoding: .utf8)) ?? ""
            let combined = existing.isEmpty ? "\(line)\n" : "\(existing)\(line)\n"
            let trimmed = combined
                .split(separator: "\n", omittingEmptySubsequences: true)
                .suffix(self.maxEntries)
                .joined(separator: "\n")
            try? "\(trimmed)\n".write(toFile: self.logPath, atomically: true, encoding: .utf8)

            let entry = LogEntry(source: .app, text: line)
            DispatchQueue.main.async {
                self.entries = Array((self.entries + [entry]).suffix(self.maxEntries))
            }
        }
    }

    private static func timestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }
}
