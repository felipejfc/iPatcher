import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 0
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView(selection: $selectedTab) {
            AppListView()
                .tabItem {
                    Image(systemName: "app.badge")
                    Text("Apps")
                }
                .tag(0)

            ProfilesView()
                .tabItem {
                    Image(systemName: "doc.text")
                    Text("Profiles")
                }
                .tag(1)

            LogsView()
                .tabItem {
                    Image(systemName: "text.page")
                    Text("Logs")
                }
                .tag(2)

            SettingsView()
                .tabItem {
                    Image(systemName: "gearshape")
                    Text("Settings")
                }
                .tag(3)
        }
        .tint(IPTheme.accent)
        .onAppear {
            PatchStore.shared.loadAll()
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                PatchStore.shared.loadAll()
            }
        }
    }
}
