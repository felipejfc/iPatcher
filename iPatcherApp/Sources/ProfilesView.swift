import SwiftUI
import UniformTypeIdentifiers

struct ProfilesView: View {
    @ObservedObject private var store = PatchStore.shared
    @State private var showImporter = false

    var body: some View {
        NavigationView {
            ZStack {
                IPTheme.background.ignoresSafeArea()

                if store.profiles.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(store.profiles) { profile in
                                ProfileRowView(
                                    profile: profile,
                                    store: store,
                                    onExport: { shareProfile(profile) },
                                    onDelete: { store.delete(profile) }
                                )
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 20)
                    }
                }
            }
            .navigationTitle("Profiles")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showImporter = true } label: {
                        Image(systemName: "square.and.arrow.down")
                            .foregroundColor(IPTheme.accent)
                    }
                }
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.json]
            ) { result in
                if case .success(let url) = result,
                   let data = try? Data(contentsOf: url) {
                   _ = store.importProfile(from: data)
                }
            }
            .onAppear {
                store.loadAll()
            }
        }
        .navigationViewStyle(.stack)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray")
                .font(.system(size: 48))
                .foregroundColor(IPTheme.textSecondary.opacity(0.25))
            Text("No Profiles")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(IPTheme.textSecondary)
            Text("Profiles appear here once you\ncreate patches for an app.")
                .font(.system(size: 14))
                .foregroundColor(IPTheme.textSecondary.opacity(0.6))
                .multilineTextAlignment(.center)
            Button("Import Profile") { showImporter = true }
                .buttonStyle(GlowButtonStyle())
        }
    }

    #if canImport(UIKit)
    private func shareProfile(_ profile: PatchProfile) {
        guard let data = store.exportProfile(profile) else { return }
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(profile.bundleID)_patches.json")
        try? data.write(to: tmp)

        guard let scene = UIApplication.shared.connectedScenes
                .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
              let root = scene.windows.first?.rootViewController
        else { return }

        let vc = UIActivityViewController(activityItems: [tmp], applicationActivities: nil)
        root.present(vc, animated: true)
    }
    #else
    private func shareProfile(_ profile: PatchProfile) {}
    #endif
}

// MARK: - Row

struct ProfileRowView: View {
    let profile: PatchProfile
    let store: PatchStore
    let onExport: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(profile.appName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(IPTheme.textPrimary)
                    Text(profile.bundleID)
                        .font(IPTheme.monoSmall)
                        .foregroundColor(IPTheme.textSecondary)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { profile.enabled },
                    set: { val in
                        var p = profile
                        p.enabled = val
                        store.save(p)
                    }
                ))
                .labelsHidden()
                .tint(IPTheme.success)
            }

            HStack {
                let n = profile.patches.count
                Label("\(n) patch\(n == 1 ? "" : "es")", systemImage: "wrench.and.screwdriver")
                    .font(.system(size: 12))
                    .foregroundColor(IPTheme.textSecondary)

                Spacer()

                Button(action: onExport) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 14))
                        .foregroundColor(IPTheme.accent)
                }

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 14))
                        .foregroundColor(IPTheme.danger.opacity(0.6))
                }
            }
        }
        .cardStyle()
    }
}
