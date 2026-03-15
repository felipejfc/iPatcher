import SwiftUI

struct AppListView: View {
    @StateObject private var discovery = AppDiscovery()
    @ObservedObject private var store = PatchStore.shared
    @AppStorage("ip_showSysApps") private var showSystemApps = false
    @State private var searchText = ""

    private var filteredApps: [InstalledApp] {
        guard !searchText.isEmpty else { return discovery.apps }
        return discovery.apps.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
                || $0.bundleID.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationView {
            ZStack {
                IPTheme.background.ignoresSafeArea()

                if discovery.isLoading {
                    ProgressView()
                        .tint(IPTheme.accent)
                        .scaleEffect(1.5)
                } else if filteredApps.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(filteredApps) { app in
                                NavigationLink(destination: AppDetailView(app: app)) {
                                    AppRowView(app: app)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 20)
                    }
                }
            }
            .navigationTitle("iPatcher")
            .searchable(text: $searchText, prompt: "Search apps...")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        store.loadAll()
                        discovery.refresh(includeSystemApps: showSystemApps)
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .foregroundColor(IPTheme.accent)
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
        .onAppear {
            store.loadAll()
            discovery.refresh(includeSystemApps: showSystemApps)
        }
        .onChange(of: showSystemApps) { _ in
            store.loadAll()
            discovery.refresh(includeSystemApps: showSystemApps)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 40))
                .foregroundColor(IPTheme.textSecondary.opacity(0.3))
            Text(searchText.isEmpty ? "No apps found" : "No results")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(IPTheme.textSecondary)
        }
    }
}

// MARK: - Row

struct AppRowView: View {
    let app: InstalledApp

    var body: some View {
        HStack(spacing: 14) {
            AppIconView(path: app.iconPath)
                .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 3) {
                Text(app.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(IPTheme.textPrimary)
                    .lineLimit(1)
                Text(app.bundleID)
                    .font(IPTheme.monoSmall)
                    .foregroundColor(IPTheme.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            if app.patchCount > 0 {
                Text("\(app.patchCount)")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 26, height: 26)
                    .background(IPTheme.accent.opacity(0.8))
                    .clipShape(Circle())
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(IPTheme.textSecondary.opacity(0.4))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(IPTheme.surface)
        .cornerRadius(14)
    }
}

// MARK: - Icon

struct AppIconView: View {
    let path: String?

    var body: some View {
        Group {
            #if canImport(UIKit)
            if let path, let img = UIImage(contentsOfFile: path) {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .clipShape(RoundedRectangle(cornerRadius: 11))
            } else {
                placeholder
            }
            #else
            placeholder
            #endif
        }
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 11)
            .fill(IPTheme.surfaceLight)
            .overlay(
                Image(systemName: "app.fill")
                    .foregroundColor(IPTheme.textSecondary)
            )
    }
}
