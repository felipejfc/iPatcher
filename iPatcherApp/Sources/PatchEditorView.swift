import SwiftUI

struct PatchEditorView: View {
    let bundleID: String
    let appName: String
    var existingPatch: PatchEntry?

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = PatchStore.shared

    @State private var name = ""
    @State private var pattern = ""
    @State private var replacement = ""
    @State private var offset = "0"
    @State private var showError = false
    @State private var errorMessage = ""

    private var isEditing: Bool { existingPatch != nil }

    var body: some View {
        NavigationView {
            ZStack {
                IPTheme.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        field("PATCH NAME") {
                            TextField("e.g. Bypass License Check", text: $name)
                                .textFieldStyle(.plain)
                                .font(.system(size: 15))
                                .foregroundColor(IPTheme.textPrimary)
                                .padding(14)
                                .background(IPTheme.surface)
                                .cornerRadius(12)
                        }

                        field("HEX PATTERN (FIND)") {
                            HexInputField(
                                text: $pattern,
                                placeholder: "f4 4f be a9 fd 7b ?? ?? 01 a9"
                            )
                        }

                        field("REPLACEMENT BYTES") {
                            HexInputField(
                                text: $replacement,
                                placeholder: "00 00 80 d2 c0 03 5f d6"
                            )
                        }

                        field("OFFSET FROM MATCH START") {
                            TextField("0", text: $offset)
                                .textFieldStyle(.plain)
                                .font(IPTheme.monoMedium)
                                .foregroundColor(IPTheme.textPrimary)
                                .keyboardType(.numberPad)
                                .padding(14)
                                .background(IPTheme.surface)
                                .cornerRadius(12)
                        }

                        syntaxInfo

                        Button(action: save) {
                            HStack {
                                Image(systemName: isEditing ? "checkmark.circle" : "plus.circle")
                                Text(isEditing ? "Update Patch" : "Create Patch")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(GlowButtonStyle())
                        .padding(.top, 8)
                    }
                    .padding(16)
                    .padding(.bottom, 20)
                }
            }
            .navigationTitle(isEditing ? "Edit Patch" : "New Patch")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(IPTheme.textSecondary)
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK") {}
            } message: {
                Text(errorMessage)
            }
            .onAppear {
                if let p = existingPatch {
                    name = p.name
                    pattern = p.pattern
                    replacement = p.replacement
                    offset = "\(p.offset)"
                }
            }
        }
    }

    // MARK: - Helpers

    private func field<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(IPTheme.textSecondary)
                .tracking(1.0)
            content()
        }
    }

    private var syntaxInfo: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .foregroundColor(IPTheme.accent)
                Text("Pattern Syntax")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(IPTheme.accent)
            }
            Text("Space-separated hex bytes. Use ?? for wildcard bytes that match anything. Replacement is written at match start + offset.")
                .font(.system(size: 13))
                .foregroundColor(IPTheme.textSecondary)
                .lineSpacing(3)
        }
        .padding(14)
        .background(IPTheme.accent.opacity(0.07))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(IPTheme.accent.opacity(0.12), lineWidth: 1)
        )
    }

    // MARK: - Save

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else {
            errorMessage = "Enter a patch name."
            showError = true; return
        }
        guard !pattern.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorMessage = "Enter a hex pattern."
            showError = true; return
        }
        guard !replacement.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorMessage = "Enter replacement bytes."
            showError = true; return
        }
        guard let off = Int(offset) else {
            errorMessage = "Offset must be a number."
            showError = true; return
        }

        let entry = PatchEntry(
            id: existingPatch?.id ?? UUID(),
            name: trimmedName,
            enabled: existingPatch?.enabled ?? true,
            pattern: normalizeHex(pattern),
            replacement: normalizeHex(replacement),
            offset: off
        )

        guard entry.isValid else {
            errorMessage = "Invalid hex. Use space-separated bytes like f4 4f ?? a9."
            showError = true; return
        }

        var profile = store.profile(for: bundleID) ?? PatchProfile(
            id: UUID(), name: appName, bundleID: bundleID, appName: appName,
            enabled: true, patches: [],
            createdAt: Date(), updatedAt: Date()
        )

        if let i = profile.patches.firstIndex(where: { $0.id == entry.id }) {
            profile.patches[i] = entry
        } else {
            profile.patches.append(entry)
        }

        store.save(profile)
        dismiss()
    }

    private func normalizeHex(_ s: String) -> String {
        s.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
