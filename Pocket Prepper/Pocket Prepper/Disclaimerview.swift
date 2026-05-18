import SwiftUI

struct DisclaimerView: View {
    var onAccept: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                Spacer()

                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.green)
                        Text("IMPORTANT DISCLAIMER")
                            .font(.system(.callout, design: .monospaced, weight: .bold))
                            .foregroundColor(.green)
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        DisclaimerLine(
                            text: "Pocket Prepper is an informational reference tool only. It is NOT a substitute for professional medical care, emergency services, or certified survival training."
                        )
                        DisclaimerLine(
                            text: "In any life-threatening situation, contact your local emergency services immediately. Do not rely on this app instead of calling for help."
                        )
                        DisclaimerLine(
                            text: "AI responses may be incomplete, inaccurate, or inappropriate for your specific situation. Always apply judgment and verify critical information."
                        )
                        DisclaimerLine(
                            text: "Medical information in this app is for general reference only and is not medical advice. Consult a qualified medical professional for diagnosis and treatment."
                        )
                    }

                    Divider()
                        .background(Color.green.opacity(0.3))

                    Text("By continuing, you acknowledge that you have read and understood this disclaimer.")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.gray)
                }
                .padding(24)
                .background(Color.white.opacity(0.04))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.green.opacity(0.2), lineWidth: 1)
                )
                .padding(.horizontal, 20)

                Spacer()

                Button(action: onAccept) {
                    Text("I UNDERSTAND — CONTINUE")
                        .font(.system(.callout, design: .monospaced, weight: .bold))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.green)
                        .cornerRadius(8)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
        .preferredColorScheme(.dark)
    }
}

private struct DisclaimerLine: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("›")
                .font(.system(.body, design: .monospaced, weight: .bold))
                .foregroundColor(.green)
                .frame(width: 14)
            Text(text)
                .font(.system(.footnote, design: .monospaced))
                .foregroundColor(.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Usage
// Present on first launch using @AppStorage:
//
// @AppStorage("hasAcceptedDisclaimer") var hasAcceptedDisclaimer = false
//
// .fullScreenCover(isPresented: .constant(!hasAcceptedDisclaimer)) {
//     DisclaimerView {
//         hasAcceptedDisclaimer = true
//     }
// }

#Preview {
    DisclaimerView(onAccept: {})
}
