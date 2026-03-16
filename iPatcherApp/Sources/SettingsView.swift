import SwiftUI

struct SettingsView: View {
    @AppStorage("ip_logEnabled")    private var logEnabled = true
    @AppStorage("ip_showSysApps")   private var showSystemApps = false
    @ObservedObject private var store = PatchStore.shared
    @StateObject private var installer = TweakInstaller.shared
    @State private var toastMessage: String?
    @State private var activeAlert: SettingsAlert?
    private let logger = AppLogger.shared

    private var installContext: String {
        let bundlePath = Bundle.main.bundlePath
        if bundlePath.hasPrefix("/var/jb/Applications/") {
            return "Rootless package"
        }
        if bundlePath.hasPrefix("/private/var/containers/Bundle/Application/") {
            return "Containerized app"
        }
        return "Custom path"
    }

    enum SettingsAlert: String, Identifiable {
        case deleteAll, uninstall, respring
        var id: String { rawValue }
    }

    private var alertTitle: String {
        switch activeAlert {
        case .deleteAll: return "Delete All Profiles?"
        case .uninstall: return "Uninstall Tweak?"
        case .respring:  return "Respring Required"
        case .none:      return ""
        }
    }

    var body: some View {
        NavigationView {
            ZStack {
                IPTheme.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        // Tweak installation
                        tweakSection

                        section("GENERAL") {
                            toggle(icon: "eye", title: "Show System Apps", binding: $showSystemApps)
                        }

                        section("TWEAK ENGINE") {
                            toggle(icon: "text.alignleft", title: "Enable Logging", binding: $logEnabled)
                        }

                        section("ABOUT") {
                            info(icon: "info.circle",            title: "Version",  value: "1.0.0")
                            info(icon: "cpu",                    title: "Engine",   value: "NEON SIMD")
                            info(icon: "shield.lefthalf.filled", title: "Platform", value: "Rootless")
                            info(icon: "shippingbox",            title: "Install",  value: installContext)
                            info(icon: "app.badge",              title: "Profiles", value: "\(store.profiles.count)")
                        }

                        section("ACTIONS") {
                            Button { activeAlert = .respring } label: {
                                HStack {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                        .foregroundColor(IPTheme.accent)
                                        .frame(width: 24)
                                    Text("Respring")
                                        .font(.system(size: 15))
                                        .foregroundColor(IPTheme.textPrimary)
                                    Spacer()
                                }
                                .padding(.vertical, 4)
                            }
                        }

                        section("DATA") {
                            Button { activeAlert = .deleteAll } label: {
                                HStack {
                                    Image(systemName: "trash")
                                        .foregroundColor(IPTheme.danger)
                                        .frame(width: 24)
                                    Text("Delete All Profiles")
                                        .font(.system(size: 15))
                                        .foregroundColor(IPTheme.danger)
                                    Spacer()
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                    .padding(16)
                    .padding(.bottom, 20)
                }

                // Toast overlay
                if let msg = toastMessage {
                    VStack {
                        Spacer()
                        Text(msg)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(Capsule().fill(IPTheme.surface))
                            .shadow(color: .black.opacity(0.3), radius: 8)
                            .padding(.bottom, 32)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    .animation(.spring(response: 0.35), value: toastMessage)
                }
            }
            .navigationTitle("Settings")
            .onAppear {
                installer.checkStatus()
            }
            .alert(item: $activeAlert) { alert in
                switch alert {
                case .deleteAll:
                    return Alert(
                        title: Text("Delete All Profiles?"),
                        message: Text("This removes all saved patches. Apps will no longer be patched on launch."),
                        primaryButton: .destructive(Text("Delete")) {
                            logger.log("UI confirmed delete all profiles")
                            store.profiles.forEach { store.delete($0) }
                        },
                        secondaryButton: .cancel()
                    )
                case .uninstall:
                    return Alert(
                        title: Text("Uninstall Tweak?"),
                        message: Text("The tweak dylib will be removed. A respring is needed for changes to take effect."),
                        primaryButton: .destructive(Text("Uninstall")) {
                            logger.log("UI confirmed uninstall")
                            if installer.uninstall() {
                                toast("Tweak uninstalled")
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    activeAlert = .respring
                                }
                            } else {
                                toast("Uninstall failed")
                            }
                        },
                        secondaryButton: .cancel()
                    )
                case .respring:
                    return Alert(
                        title: Text("Respring Required"),
                        message: Text("A respring is needed for the tweak changes to take effect."),
                        primaryButton: .destructive(Text("Respring Now")) {
                            logger.log("UI confirmed respring")
                            if installer.respring() {
                                toast("Respring signal sent")
                            } else {
                                toast("Respring failed")
                            }
                        },
                        secondaryButton: .cancel(Text("Later")) {
                            installer.needsRespring = false
                        }
                    )
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    // MARK: - Tweak Section

    private var tweakSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("TWEAK STATUS")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(IPTheme.textSecondary)
                .tracking(1.0)

            VStack(spacing: 14) {
                // Status indicator
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(installer.isInstalled
                                  ? IPTheme.success.opacity(0.15)
                                  : IPTheme.danger.opacity(0.15))
                            .frame(width: 40, height: 40)
                        Image(systemName: installer.isInstalled
                              ? "checkmark.shield.fill"
                              : "shield.slash")
                            .font(.system(size: 18))
                            .foregroundColor(installer.isInstalled
                                             ? IPTheme.success : IPTheme.danger)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(installer.isInstalled ? "Tweak Installed" : "Tweak Not Installed")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(IPTheme.textPrimary)
                        Text(installer.isInstalled
                             ? "Active in all UIKit apps"
                             : "Install to enable runtime patching")
                            .font(.system(size: 13))
                            .foregroundColor(IPTheme.textSecondary)
                    }
                    Spacer()
                }

                // Helper status
                if !installer.helperInstalled {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "terminal")
                                .foregroundColor(IPTheme.accent)
                            Text("Root helper not ready")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(IPTheme.accent)
                        }
                        if let helperIssue = installer.helperIssue {
                            Text(helperIssue)
                                .font(IPTheme.monoSmall)
                                .foregroundColor(IPTheme.textSecondary)
                        }
                        Text("Run once via SSH as root:")
                            .font(.system(size: 12))
                            .foregroundColor(IPTheme.textSecondary)
                        Text(installer.setupCommand())
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(IPTheme.textPrimary)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(IPTheme.background)
                            .cornerRadius(6)
                        Button {
                            #if canImport(UIKit)
                            UIPasteboard.general.string = installer.setupCommand()
                            toast("Copied to clipboard")
                            #endif
                        } label: {
                            Label("Copy Command", systemImage: "doc.on.doc")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(GlowButtonStyle())

                        Button {
                            installer.checkStatus()
                        } label: {
                            Label("Check Again", systemImage: "arrow.clockwise")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(GlowButtonStyle(color: IPTheme.textSecondary))
                    }
                    .padding(10)
                    .background(IPTheme.accent.opacity(0.07))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(IPTheme.accent.opacity(0.15), lineWidth: 1)
                    )
                }

                // Error display
                if let err = installer.lastError {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundColor(IPTheme.warning)
                        Text(err)
                            .font(.system(size: 12))
                            .foregroundColor(IPTheme.warning)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(IPTheme.warning.opacity(0.08))
                    .cornerRadius(8)
                }

                // Action buttons
                if installer.isInstalled {
                    HStack(spacing: 12) {
                        Button {
                            if installer.update() {
                                toast("Tweak updated")
                                activeAlert = .respring
                            }
                        } label: {
                            Label("Update", systemImage: "arrow.clockwise")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(GlowButtonStyle())

                        Button {
                            logger.log("UI requested uninstall confirmation")
                            toast("Uninstall confirmation opened")
                            activeAlert = .uninstall
                        } label: {
                            Label("Uninstall", systemImage: "trash")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(GlowButtonStyle(color: IPTheme.danger))
                    }
                } else {
                    Button {
                        if installer.install() {
                            toast("Tweak installed")
                            activeAlert = .respring
                        }
                    } label: {
                        Label("Install Tweak", systemImage: "arrow.down.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(GlowButtonStyle(color: IPTheme.success))
                }

                // Respring button (shown when needed)
                if installer.needsRespring {
                    Button {
                        logger.log("UI requested respring confirmation")
                        toast("Respring confirmation opened")
                        activeAlert = .respring
                    } label: {
                        Label("Respring Required", systemImage: "arrow.triangle.2.circlepath")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(GlowButtonStyle(color: IPTheme.warning))
                }
            }
            .cardStyle()
        }
    }

    // MARK: - Builders

    private func section<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(IPTheme.textSecondary)
                .tracking(1.0)
            VStack(spacing: 0) { content() }
                .cardStyle()
        }
    }

    private func toggle(icon: String, title: String, binding: Binding<Bool>) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(IPTheme.accent)
                .frame(width: 24)
            Text(title)
                .font(.system(size: 15))
                .foregroundColor(IPTheme.textPrimary)
            Spacer()
            Toggle("", isOn: binding)
                .tint(IPTheme.accent)
                .labelsHidden()
        }
        .padding(.vertical, 4)
    }

    private func info(icon: String, title: String, value: String) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(IPTheme.accent)
                .frame(width: 24)
            Text(title)
                .font(.system(size: 15))
                .foregroundColor(IPTheme.textPrimary)
            Spacer()
            Text(value)
                .font(IPTheme.monoSmall)
                .foregroundColor(IPTheme.textSecondary)
        }
        .padding(.vertical, 4)
    }

    private func toast(_ msg: String) {
        withAnimation { toastMessage = msg }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation { toastMessage = nil }
        }
    }
}
