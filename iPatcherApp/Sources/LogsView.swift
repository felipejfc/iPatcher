import SwiftUI

struct LogsView: View {
    @StateObject private var logger = AppLogger.shared

    var body: some View {
        NavigationView {
            ZStack {
                IPTheme.background.ignoresSafeArea()

                if logger.entries.isEmpty {
                    VStack(spacing: 14) {
                        Image(systemName: "text.page")
                            .font(.system(size: 40))
                            .foregroundColor(IPTheme.textSecondary.opacity(0.3))
                        Text("No logs yet")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(IPTheme.textSecondary)
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(logger.entries) { entry in
                                LogEntryRow(entry: entry)
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .navigationTitle("Logs")
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button {
                        logger.load()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .foregroundColor(IPTheme.accent)
                    }

                    Button {
                        logger.clear()
                    } label: {
                        Image(systemName: "trash")
                            .foregroundColor(IPTheme.danger)
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}

private struct LogEntryRow: View {
    let entry: LogEntry

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(entry.source.rawValue)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(tagColor.opacity(0.85))
                .cornerRadius(4)

            Text(entry.text)
                .font(IPTheme.monoSmall)
                .foregroundColor(IPTheme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(IPTheme.surface)
        .cornerRadius(12)
    }

    private var tagColor: Color {
        switch entry.source {
        case .app:     return IPTheme.accent
        case .patcher: return IPTheme.accentAlt
        case .loader:  return IPTheme.warning
        }
    }
}
