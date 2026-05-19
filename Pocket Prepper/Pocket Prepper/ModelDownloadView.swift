import SwiftUI

/// Shown in HomeView when the device is AI-capable but model isn't downloaded yet
struct ModelDownloadBanner: View {
    @EnvironmentObject var llmService: LLMService

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "cpu")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.green)
                Text("ON-DEVICE AI AVAILABLE")
                    .font(.system(.caption2, design: .monospaced).weight(.bold))
                    .foregroundColor(.green)
            }

            Text("Your device supports on-device AI. Download the \(OnDeviceModel.displayName) model (~\(String(format: "%.1f", OnDeviceModel.approximateSizeGB)) GB) to enable full AI responses without internet.")
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(.gray)
                .fixedSize(horizontal: false, vertical: true)

            if llmService.isDownloadingModel {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: llmService.modelDownloadProgress)
                        .tint(.green)
                    HStack {
                        Text("DOWNLOADING MODEL")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(.gray)
                        Spacer()
                        Text("\(Int(llmService.modelDownloadProgress * 100))%")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(.green)
                    }
                }
            } else if let error = llmService.modelError {
                Text(error)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.red)

                downloadButton
            } else {
                downloadButton
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.05))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.green.opacity(0.2), lineWidth: 1)
        )
        .cornerRadius(8)
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    private var downloadButton: some View {
        Button {
            Task { await llmService.downloadModel() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 12))
                Text("DOWNLOAD MODEL")
                    .font(.system(.caption2, design: .monospaced).weight(.bold))
            }
            .foregroundColor(.black)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.green)
            .cornerRadius(6)
        }
    }
}
