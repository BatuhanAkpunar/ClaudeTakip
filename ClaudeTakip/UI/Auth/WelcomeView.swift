import SwiftUI

struct WelcomeView: View {
    let onSignIn: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Image("ClaudeLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 52, height: 52)

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
                    .background(DT.Colors.claudeAccent, in: Capsule())
            }
            .buttonStyle(.plain)

            Spacer().frame(height: 12)

            Text("Opens claude.ai in a login window.", bundle: .app)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.tertiary)

            Spacer()
        }
        .frame(width: DT.Size.popoverWidth, height: 300)
    }
}
