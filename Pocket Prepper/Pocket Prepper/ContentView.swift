import SwiftUI

struct ContentView: View {
    @StateObject private var moduleManager = ModuleManager.shared
    @StateObject private var llmService = LLMService.shared
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("hasAcceptedDisclaimer") private var hasAcceptedDisclaimer = false

    var body: some View {
        if !hasCompletedOnboarding {
            OnboardingView(hasCompletedOnboarding: $hasCompletedOnboarding)
                .environmentObject(moduleManager)
                .environmentObject(llmService)
        } else if !hasAcceptedDisclaimer {
            DisclaimerView {
                hasAcceptedDisclaimer = true
            }
        } else {
            MainTabView()
                .environmentObject(moduleManager)
                .environmentObject(llmService)
        }
    }
}

// MARK: - Tab Bar

struct MainTabView: View {
    @EnvironmentObject var moduleManager: ModuleManager
    @EnvironmentObject var llmService: LLMService
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .environmentObject(moduleManager)
                .environmentObject(llmService)
                .tabItem {
                    Label("Modules", systemImage: "square.grid.2x2")
                }
                .tag(0)

            MapsRootView()
                .tabItem {
                    Label("Maps", systemImage: "map")
                }
                .tag(1)
        }
        .tint(.green)
        .preferredColorScheme(.dark)
        // Style the tab bar to match the black theme
        .onAppear {
            let appearance = UITabBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = UIColor.black
            appearance.stackedLayoutAppearance.normal.iconColor = UIColor.gray
            appearance.stackedLayoutAppearance.normal.titleTextAttributes = [
                .foregroundColor: UIColor.gray,
                .font: UIFont.monospacedSystemFont(ofSize: 10, weight: .regular)
            ]
            appearance.stackedLayoutAppearance.selected.iconColor = UIColor.systemGreen
            appearance.stackedLayoutAppearance.selected.titleTextAttributes = [
                .foregroundColor: UIColor.systemGreen,
                .font: UIFont.monospacedSystemFont(ofSize: 10, weight: .bold)
            ]
            UITabBar.appearance().standardAppearance = appearance
            UITabBar.appearance().scrollEdgeAppearance = appearance
        }
    }
}

// MARK: - Home (unchanged from before)

struct HomeView: View {
    @EnvironmentObject var moduleManager: ModuleManager
    @EnvironmentObject var llmService: LLMService

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Header
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("POCKET PREPPER")
                                .font(.system(.caption, design: .monospaced).weight(.bold))
                                .foregroundColor(.green)
                            Text("Offline survival intelligence")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundColor(.gray)
                        }
                        Spacer()
                        HStack(spacing: 6) {
                            Circle()
                                .fill(llmService.isLoaded ? Color.green : Color.orange)
                                .frame(width: 7, height: 7)
                            Text(llmService.isLoaded ? "READY" : llmService.isLoading ? "LOADING" : "OFFLINE")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundColor(llmService.isLoaded ? .green : .orange)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 12)

                    Divider().background(Color.green.opacity(0.3))

                    if llmService.isLoading {
                        VStack(spacing: 8) {
                            Text("Loading AI model...")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.gray)
                            ProgressView(value: llmService.loadingProgress)
                                .tint(.green)
                                .padding(.horizontal)
                        }
                        .padding()
                    }
                    
                    // Show model download prompt on capable devices
                    if llmService.isAICapable && !llmService.isLoaded && !llmService.isLoading {
                        ModelDownloadBanner()
                            .environmentObject(llmService)
                    }

                    if moduleManager.downloadedModules.isEmpty {
                        Spacer()
                        VStack(spacing: 12) {
                            Text("NO MODULES ENABLED")
                                .font(.system(.caption, design: .monospaced).weight(.bold))
                                .foregroundColor(.gray)
                            Text("Tap + to add knowledge modules")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundColor(.gray.opacity(0.6))
                        }
                        Spacer()
                    } else {
                        List {
                            ForEach(Module.categories, id: \.self) { category in
                                let modules = moduleManager.downloadedModules.filter { $0.category == category }
                                if !modules.isEmpty {
                                    Section {
                                        ForEach(modules) { module in
                                            NavigationLink(destination: ChatView(module: module)) {
                                                ModuleRow(module: module)
                                            }
                                            .listRowBackground(Color.black)
                                        }
                                    } header: {
                                        Text(category.uppercased())
                                            .font(.system(.caption2, design: .monospaced).weight(.bold))
                                            .foregroundColor(.green.opacity(0.6))
                                    }
                                    .listRowSeparatorTint(Color.green.opacity(0.15))
                                }
                            }
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(destination: ModuleStoreView()) {
                        Image(systemName: "plus")
                            .foregroundColor(.green)
                    }
                }
            }
            .toolbarBackground(Color.black, for: .navigationBar)
        }
        .task {
            await llmService.loadModel()
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Module Row

struct ModuleRow: View {
    let module: Module

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(module.name.uppercased())
                .font(.system(.caption, design: .monospaced).weight(.bold))
                .foregroundColor(.green)
            Text(module.description)
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(.gray)
                .lineLimit(2)
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Module Store

struct ModuleStoreView: View {
    @EnvironmentObject var moduleManager: ModuleManager

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            List {
                ForEach(Module.categories, id: \.self) { category in
                    Section {
                        ForEach(Module.modules(for: category)) { module in
                            ModuleStoreRow(module: module)
                                .listRowBackground(Color.black)
                        }
                    } header: {
                        CategoryHeader(category: category)
                    }
                    .listRowSeparatorTint(Color.green.opacity(0.15))
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("MODULES")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.black, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .preferredColorScheme(.dark)
    }
}

struct CategoryHeader: View {
    let category: String

    var categoryDescription: String {
        switch category {
        case "Prepare": return "BEFORE IT HAPPENS"
        case "Survive": return "DAY 1-90"
        case "Medicine": return "HEALTH & SAFETY"
        case "Stabilize": return "MONTH 1 - YEAR 5"
        case "Rebuild": return "YEAR 5+"
        default: return ""
        }
    }

    var body: some View {
        HStack {
            Text(category.uppercased())
                .font(.system(.caption, design: .monospaced).weight(.bold))
                .foregroundColor(.green)
            Text(categoryDescription)
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(.green.opacity(0.5))
        }
    }
}

struct ModuleStoreRow: View {
    @EnvironmentObject var moduleManager: ModuleManager
    let module: Module

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(module.name.uppercased())
                    .font(.system(.caption, design: .monospaced).weight(.bold))
                    .foregroundColor(.green)
                Text(module.description)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.gray)
                    .lineLimit(2)
                Text("\(String(format: "%.1f", module.sizeMB)) MB")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.gray.opacity(0.5))
            }

            Spacer()

            if module.isDownloaded {
                Text("INSTALLED")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.green)
            } else if moduleManager.downloadingIDs.contains(module.id) {
                VStack(spacing: 4) {
                    ProgressView(value: moduleManager.downloadProgress[module.id] ?? 0)
                        .tint(.green)
                        .frame(width: 60)
                    Text("\(Int((moduleManager.downloadProgress[module.id] ?? 0) * 100))%")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(.gray)
                }
            } else {
                Button("GET") {
                    Task { await moduleManager.download(module) }
                }
                .font(.system(.caption, design: .monospaced).weight(.bold))
                .foregroundColor(.black)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.green)
                .cornerRadius(4)
            }
        }
        .padding(.vertical, 6)
    }
}
