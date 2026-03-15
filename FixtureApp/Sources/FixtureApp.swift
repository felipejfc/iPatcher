import Foundation
import SwiftUI

@_silgen_name("fixture_patch_target")
private func fixture_patch_target() -> Int32

private struct FixtureStatus: Codable {
    let bundleID: String
    let bundlePath: String
    let rawValue: Int32
    let isPatched: Bool
    let source: String
    let updatedAt: Date
}

@MainActor
final class FixtureState: ObservableObject {
    @Published var rawValue: Int32 = 0
    @Published var updatedAt = Date()

    private let fm = FileManager.default
    let statusPath = (NSHomeDirectory() as NSString)
        .appendingPathComponent("Documents/fixture-status.json")

    init() {
        refresh(source: "init")
    }

    var isPatched: Bool { rawValue != 0 }
    var statusText: String { isPatched ? "PATCHED" : "UNPATCHED" }
    var detailText: String {
        isPatched
            ? "fixture_patch_target() returned non-zero. The patch is active."
            : "fixture_patch_target() returned 0. The original code is still active."
    }

    func refresh(source: String) {
        rawValue = fixture_patch_target()
        updatedAt = Date()
        writeStatus(source: source)
    }

    private func writeStatus(source: String) {
        let status = FixtureStatus(
            bundleID: Bundle.main.bundleIdentifier ?? "unknown",
            bundlePath: Bundle.main.bundlePath,
            rawValue: rawValue,
            isPatched: isPatched,
            source: source,
            updatedAt: updatedAt
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        guard let data = try? encoder.encode(status) else { return }
        let dir = (statusPath as NSString).deletingLastPathComponent
        try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        fm.createFile(atPath: statusPath, contents: data)

        let defaults = UserDefaults.standard
        defaults.set(status.bundleID, forKey: "bundleID")
        defaults.set(status.bundlePath, forKey: "bundlePath")
        defaults.set(status.rawValue, forKey: "rawValue")
        defaults.set(status.isPatched, forKey: "isPatched")
        defaults.set(status.source, forKey: "source")
        defaults.set(status.updatedAt.ISO8601Format(), forKey: "updatedAt")
        defaults.set(statusPath, forKey: "statusPath")
        defaults.synchronize()
    }
}

struct ContentView: View {
    @StateObject private var state = FixtureState()
    private let ticker = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.05, blue: 0.08),
                    Color(red: 0.08, green: 0.12, blue: 0.18)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 18) {
                Text("iPatcher Fixture")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.white)

                Text(state.statusText)
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .foregroundColor(state.isPatched ? .green : .red)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 10)
                    .background(.white.opacity(0.08))
                    .clipShape(Capsule())

                Text(state.detailText)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 18)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Raw value: \(state.rawValue)")
                    Text("Bundle ID: \(Bundle.main.bundleIdentifier ?? "unknown")")
                    Text("Updated: \(state.updatedAt.formatted(date: .numeric, time: .standard))")
                    Text("Status file: \(state.statusPath)")
                }
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(.white.opacity(0.82))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 18))

                Button {
                    state.refresh(source: "manual")
                } label: {
                    Text("Refresh Now")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.cyan.opacity(0.75))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }
            .padding(24)
        }
        .onAppear {
            state.refresh(source: "appear")
        }
        .onReceive(ticker) { _ in
            state.refresh(source: "timer")
        }
    }
}

@main
struct iPatcherFixtureApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
    }
}
