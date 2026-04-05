import SwiftUI

struct LoginView: View {
    let onLogin: (String) -> Void
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            if let error = errorMessage {
                Text(error)
                    .font(DT.Typography.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, DT.Spacing.popoverPadding)
                    .padding(.vertical, 8)
            }

            LoginWebView { sessionKey in
                isLoading = true
                onLogin(sessionKey)
            }
        }
        .frame(width: DT.Size.popoverWidth, height: 400)
    }
}
