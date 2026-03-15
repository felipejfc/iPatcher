import SwiftUI

struct AppDetailView: View {
    let app: InstalledApp
    @ObservedObject private var store = PatchStore.shared
    @State private var showAddPatch = false

    private var profile: PatchProfile? { store.profile(for: app.bundleID) }

    var body: some View {
        ZStack {
            IPTheme.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    appHeader
                    if profile != nil { masterToggle }
                    patchesSection
                }
                .padding(16)
                .padding(.bottom, 20)
            }
        }
        .navigationTitle(app.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAddPatch) {
            PatchEditorView(bundleID: app.bundleID, appName: app.name)
        }
        .onAppear {
            store.loadAll()
        }
    }

    // MARK: - Header

    private var appHeader: some View {
        HStack(spacing: 16) {
            AppIconView(path: app.iconPath)
                .frame(width: 64, height: 64)

            VStack(alignment: .leading, spacing: 4) {
                Text(app.name)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(IPTheme.textPrimary)
                Text(app.bundleID)
                    .font(IPTheme.monoSmall)
                    .foregroundColor(IPTheme.textSecondary)
                Text("v\(app.version)")
                    .font(.system(size: 12))
                    .foregroundColor(IPTheme.textSecondary)
            }
            Spacer()
        }
        .cardStyle()
    }

    // MARK: - Master toggle

    private var masterToggle: some View {
        HStack {
            Image(systemName: profile?.enabled == true ? "bolt.fill" : "bolt.slash")
                .foregroundColor(profile?.enabled == true ? IPTheme.success : IPTheme.textSecondary)
            Text("Patches Active")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(IPTheme.textPrimary)
            Spacer()
            Toggle("", isOn: Binding(
                get: { profile?.enabled ?? false },
                set: { val in
                    guard var p = profile else { return }
                    p.enabled = val
                    store.save(p)
                }
            ))
            .tint(IPTheme.accent)
            .labelsHidden()
        }
        .cardStyle()
    }

    // MARK: - Patches

    private var patchesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "PATCHES",
                trailing: AnyView(
                    Button { showAddPatch = true } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                            Text("Add")
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(IPTheme.accent)
                    }
                )
            )

            if let patches = profile?.patches, !patches.isEmpty {
                ForEach(patches) { patch in
                    PatchRowView(
                        patch: patch,
                        profile: profile!,
                        onUpdate: { updated in
                            var p = profile!
                            if let i = p.patches.firstIndex(where: { $0.id == updated.id }) {
                                p.patches[i] = updated
                                store.save(p)
                            }
                        },
                        onDelete: {
                            var p = profile!
                            p.patches.removeAll { $0.id == patch.id }
                            store.save(p)
                        }
                    )
                }
            } else {
                VStack(spacing: 14) {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 36))
                        .foregroundColor(IPTheme.textSecondary.opacity(0.3))
                    Text("No patches yet")
                        .font(.system(size: 15))
                        .foregroundColor(IPTheme.textSecondary)
                    Button("Create First Patch") { showAddPatch = true }
                        .buttonStyle(GlowButtonStyle())
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
                .cardStyle()
            }
        }
    }
}

// MARK: - Patch Row

struct PatchRowView: View {
    let patch: PatchEntry
    let profile: PatchProfile
    let onUpdate: (PatchEntry) -> Void
    let onDelete: () -> Void

    @State private var showEditor = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(patch.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(IPTheme.textPrimary)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { patch.enabled },
                    set: { val in
                        var u = patch
                        u.enabled = val
                        onUpdate(u)
                    }
                ))
                .tint(IPTheme.accent)
                .labelsHidden()
            }

            // Pattern / replacement preview
            VStack(alignment: .leading, spacing: 6) {
                hexRow(label: "FIND", hex: patch.pattern, color: IPTheme.accent)
                hexRow(label: "SET",  hex: patch.replacement, color: IPTheme.success)
                if patch.offset != 0 {
                    HStack(spacing: 6) {
                        Text("OFF")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(IPTheme.warning)
                            .tracking(0.8)
                        Text("+\(patch.offset)")
                            .font(IPTheme.monoSmall)
                            .foregroundColor(IPTheme.textSecondary)
                    }
                }
            }
            .padding(10)
            .background(IPTheme.background.opacity(0.6))
            .cornerRadius(8)

            // Actions
            HStack {
                Button { showEditor = true } label: {
                    Label("Edit", systemImage: "pencil")
                        .font(.system(size: 13))
                        .foregroundColor(IPTheme.accent)
                }
                Spacer()
                Button(action: onDelete) {
                    Label("Delete", systemImage: "trash")
                        .font(.system(size: 13))
                        .foregroundColor(IPTheme.danger.opacity(0.7))
                }
            }
        }
        .cardStyle()
        .sheet(isPresented: $showEditor) {
            PatchEditorView(
                bundleID: profile.bundleID,
                appName: profile.appName,
                existingPatch: patch
            )
        }
    }

    private func hexRow(label: String, hex: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(color)
                .tracking(0.8)
                .frame(width: 32, alignment: .leading)
            Text(hex)
                .font(IPTheme.monoSmall)
                .foregroundColor(IPTheme.textSecondary)
                .lineLimit(1)
        }
    }
}
