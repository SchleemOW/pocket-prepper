import SwiftUI

struct OnboardingView: View {
    @Binding var hasCompletedOnboarding: Bool
    @State private var currentPage = 0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                TabView(selection: $currentPage) {
                    OnboardingPage1().tag(0)
                    OnboardingPage2().tag(1)
                    OnboardingPage3().tag(2)
                    OnboardingPage4(hasCompletedOnboarding: $hasCompletedOnboarding).tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                HStack(spacing: 8) {
                    ForEach(0..<4) { i in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(i == currentPage ? Color.green : Color.gray.opacity(0.4))
                            .frame(width: i == currentPage ? 20 : 6, height: 4)
                            .animation(.easeInOut(duration: 0.2), value: currentPage)
                    }
                }
                .padding(.bottom, 20)

                if currentPage < 3 {
                    Button {
                        withAnimation { currentPage += 1 }
                    } label: {
                        Text("CONTINUE")
                            .font(.system(.callout, design: .monospaced).weight(.bold))
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.green)
                            .cornerRadius(6)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Page 1

struct OnboardingPage1: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Spacer()

            Text("POCKET\nPREPPER")
                .font(.system(size: 42, weight: .black, design: .monospaced))
                .foregroundColor(.green)
                .lineSpacing(4)

            Text("An offline AI survival assistant.\nNo internet. No cloud. No dependencies.")
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.white)
                .lineSpacing(6)

            Divider().background(Color.green.opacity(0.3))

            VStack(alignment: .leading, spacing: 14) {
                FeatureLine(text: "Works without internet or cell service")
                FeatureLine(text: "AI answers from military & medical manuals")
                FeatureLine(text: "18 specialized knowledge modules")
                FeatureLine(text: "From Day 1 survival to rebuilding civilization")
            }

            Spacer()
            Spacer()
        }
        .padding(.horizontal, 28)
    }
}

// MARK: - Page 2

struct OnboardingPage2: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Spacer()

            Text("KNOWLEDGE\nMODULES")
                .font(.system(size: 36, weight: .black, design: .monospaced))
                .foregroundColor(.green)
                .lineSpacing(4)

            Text("Download while you have WiFi. Works fully offline after that.")
                .font(.system(.callout, design: .monospaced))
                .foregroundColor(.white)
                .lineSpacing(5)

            Divider().background(Color.green.opacity(0.3))

            VStack(alignment: .leading, spacing: 16) {
                CategoryBlock(
                    title: "SURVIVE", subtitle: "Day 1-90",
                    items: "General, Fire & Shelter, Navigation, Desert, Cold Weather"
                )
                CategoryBlock(
                    title: "MEDICINE", subtitle: "Health & Safety",
                    items: "Trauma, Infection, Childbirth, Herbal Medicine"
                )
                CategoryBlock(
                    title: "STABILIZE", subtitle: "Month 1 - Year 5",
                    items: "Water, Foraging, Agriculture, Construction"
                )
                CategoryBlock(
                    title: "REBUILD", subtitle: "Year 5+",
                    items: "Energy, Materials, Chemistry, Electronics, Governance"
                )
            }

            Spacer()
        }
        .padding(.horizontal, 28)
    }
}

// MARK: - Page 3 (Offline Maps)

struct OnboardingPage3: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Spacer()

            Text("OFFLINE\nMAPS")
                .font(.system(size: 42, weight: .black, design: .monospaced))
                .foregroundColor(.green)
                .lineSpacing(4)

            Text("Download map areas before you need them. Navigate without cell service.")
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.white)
                .lineSpacing(6)

            Divider().background(Color.green.opacity(0.3))

            VStack(alignment: .leading, spacing: 14) {
                FeatureLine(text: "Pan to any area and tap Download")
                FeatureLine(text: "Name and save multiple regions")
                FeatureLine(text: "Street-level detail stored on device")
                FeatureLine(text: "No internet needed after download")
            }

            Spacer()

            // Visual hint
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("EXAMPLE REGIONS")
                        .font(.system(.caption2, design: .monospaced).weight(.bold))
                        .foregroundColor(.green.opacity(0.6))
                    VStack(alignment: .leading, spacing: 4) {
                        MapRegionHint(name: "Stockholm", size: "~45 MB")
                        MapRegionHint(name: "Cabin area — Dalarna", size: "~12 MB")
                        MapRegionHint(name: "E4 corridor", size: "~80 MB")
                    }
                }
                Spacer()
            }
            .padding(14)
            .background(Color.white.opacity(0.05))
            .cornerRadius(8)

            Spacer()
        }
        .padding(.horizontal, 28)
    }
}

struct MapRegionHint: View {
    let name: String
    let size: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 10))
                .foregroundColor(.green)
            Text(name)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.white)
            Spacer()
            Text(size)
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(.gray)
        }
    }
}

// MARK: - Page 4 (formerly Page 3 — Download Modules)

struct OnboardingPage4: View {
    @Binding var hasCompletedOnboarding: Bool
    @EnvironmentObject var moduleManager: ModuleManager

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("DOWNLOAD\nMODULES")
                .font(.system(size: 32, weight: .black, design: .monospaced))
                .foregroundColor(.green)
                .lineSpacing(4)
                .padding(.top, 20)

            Text("Select what you need offline. Add more anytime.")
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.white)

            ScrollView {
                VStack(spacing: 16) {
                    ForEach(Module.categories, id: \.self) { category in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(category.uppercased())
                                .font(.system(.caption2, design: .monospaced).weight(.bold))
                                .foregroundColor(.green.opacity(0.6))
                                .padding(.leading, 4)

                            ForEach(Module.modules(for: category)) { module in
                                OnboardingModuleRow(module: module)
                            }
                        }
                    }
                }
            }

            Button {
                hasCompletedOnboarding = true
            } label: {
                Text("GET STARTED")
                    .font(.system(.callout, design: .monospaced).weight(.bold))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.green)
                    .cornerRadius(6)
            }
            .padding(.bottom, 32)
        }
        .padding(.horizontal, 24)
    }
}

struct OnboardingModuleRow: View {
    @EnvironmentObject var moduleManager: ModuleManager
    let module: Module

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(module.name.uppercased())
                    .font(.system(.caption, design: .monospaced).weight(.bold))
                    .foregroundColor(.white)
                Text("\(String(format: "%.1f", module.sizeMB)) MB")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.gray)
            }

            Spacer()

            if module.isDownloaded {
                Image(systemName: "checkmark")
                    .font(.system(.caption, design: .monospaced).weight(.bold))
                    .foregroundColor(.green)
            } else if moduleManager.downloadingIDs.contains(module.id) {
                ProgressView(value: moduleManager.downloadProgress[module.id] ?? 0)
                    .tint(.green)
                    .frame(width: 50)
            } else {
                Button("GET") {
                    Task { await moduleManager.download(module) }
                }
                .font(.system(.caption2, design: .monospaced).weight(.bold))
                .foregroundColor(.black)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.green)
                .cornerRadius(4)
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.05))
        .cornerRadius(6)
    }
}

// MARK: - Helpers

struct FeatureLine: View {
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(">")
                .font(.system(.callout, design: .monospaced).weight(.bold))
                .foregroundColor(.green)
            Text(text)
                .font(.system(.callout, design: .monospaced))
                .foregroundColor(.gray)
        }
    }
}

struct CategoryBlock: View {
    let title: String
    let subtitle: String
    let items: String
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(.caption, design: .monospaced).weight(.bold))
                    .foregroundColor(.green)
                Text(subtitle)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.green.opacity(0.5))
            }
            Text(items)
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(.gray)
        }
    }
}
