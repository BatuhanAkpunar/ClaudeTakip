import SwiftUI

struct WelcomeView: View {
    let onSignIn: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            if let nsImage = NSImage(named: "ClaudeLogo") {
                Image(nsImage: nsImage)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 56, height: 56)
            }

            Spacer().frame(height: 14)

            Text("ClaudeTakip")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            Spacer().frame(height: 8)

            Text("Track your Claude AI usage limits in real time.", bundle: .app)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 56)

            Spacer()

            Button(action: onSignIn) {
                Text("Sign in with Claude", bundle: .app)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 11)
                    .background(Capsule().fill(DT.Colors.claudeAccent))
            }
            .buttonStyle(.plain)

            Spacer().frame(height: 12)

            Text("Opens claude.ai in a login window.", bundle: .app)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.tertiary)

            Spacer()
        }
        .overlay(alignment: .bottomTrailing) {
            Button(action: { NSApp.terminate(nil) }) {
                Image(systemName: "power")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary.opacity(0.5))
            }
            .buttonStyle(.plain)
            .padding(12)
        }
        .frame(width: DT.Size.popoverWidth, height: 300)
        .popoverBG()
    }
}
