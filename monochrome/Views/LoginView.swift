import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var authService: AuthService
    @Environment(\.dismiss) private var dismiss
    @State private var mode: AuthMode = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var resetSent = false

    enum AuthMode {
        case signIn, signUp, resetPassword
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Spacer(minLength: 60)

                // Logo
                VStack(spacing: 12) {
                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 64))
                        .foregroundColor(Theme.foreground)

                    Text("Monochrome")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(Theme.foreground)

                    Text(modeSubtitle)
                        .font(.system(size: 14))
                        .foregroundColor(Theme.mutedForeground)
                }
                .padding(.bottom, 40)

                // Error message
                if let error = authService.errorMessage {
                    Text(error)
                        .font(.system(size: 13))
                        .foregroundColor(.red.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 12)
                }

                // Google sign-in (only in signIn mode)
                if mode == .signIn {
                    Button {
                        Task { await googleSignIn() }
                    } label: {
                        HStack(spacing: 10) {
                            if authService.isLoading {
                                ProgressView()
                                    .tint(Theme.foreground)
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "globe")
                                    .font(.system(size: 18))
                            }
                            Text("Sign in with Google")
                                .font(.system(size: 16, weight: .medium))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .foregroundColor(Theme.foreground)
                        .background(Theme.secondary)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusLg))
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.radiusLg)
                                .stroke(Theme.border, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(authService.isLoading)
                    .padding(.horizontal, 24)

                    // Divider
                    HStack {
                        Rectangle().fill(Theme.border).frame(height: 1)
                        Text("or")
                            .font(.system(size: 12))
                            .foregroundColor(Theme.mutedForeground)
                            .textCase(.uppercase)
                        Rectangle().fill(Theme.border).frame(height: 1)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 20)
                }

                // Email form
                VStack(spacing: 14) {
                    if mode != .resetPassword || !resetSent {
                        AuthTextField(
                            icon: "envelope.fill",
                            placeholder: "Email",
                            text: $email,
                            keyboardType: .emailAddress
                        )
                    }

                    if mode != .resetPassword {
                        AuthTextField(
                            icon: "lock.fill",
                            placeholder: "Password",
                            text: $password,
                            isSecure: true
                        )
                    }

                    if mode == .signUp {
                        AuthTextField(
                            icon: "lock.fill",
                            placeholder: "Confirm password",
                            text: $confirmPassword,
                            isSecure: true
                        )
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 8)

                // Reset sent confirmation
                if mode == .resetPassword && resetSent {
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.green)
                        Text("Reset email sent to \(email)")
                            .font(.system(size: 14))
                            .foregroundColor(Theme.mutedForeground)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.vertical, 20)
                    .padding(.horizontal, 24)
                }

                // Action button
                if !(mode == .resetPassword && resetSent) {
                    Button {
                        Task { await performAction() }
                    } label: {
                        HStack(spacing: 8) {
                            if authService.isLoading {
                                ProgressView()
                                    .tint(Theme.primaryForeground)
                                    .scaleEffect(0.8)
                            }
                            Text(actionTitle)
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .foregroundColor(Theme.primaryForeground)
                        .background(isFormValid ? Theme.primary : Theme.primary.opacity(0.4))
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusLg))
                    }
                    .buttonStyle(.plain)
                    .disabled(!isFormValid || authService.isLoading)
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                }

                // Forgot password (sign in mode)
                if mode == .signIn {
                    Button {
                        withAnimation { mode = .resetPassword }
                        resetSent = false
                    } label: {
                        Text("Forgot password?")
                            .font(.system(size: 14))
                            .foregroundColor(Theme.mutedForeground)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 16)
                }

                // Switch mode
                HStack(spacing: 4) {
                    Text(switchPrompt)
                        .foregroundColor(Theme.mutedForeground)
                    Button {
                        withAnimation {
                            switch mode {
                            case .signIn: mode = .signUp
                            case .signUp, .resetPassword: mode = .signIn
                            }
                            authService.errorMessage = nil
                            resetSent = false
                        }
                    } label: {
                        Text(switchAction)
                            .fontWeight(.semibold)
                            .foregroundColor(Theme.foreground)
                    }
                    .buttonStyle(.plain)
                }
                .font(.system(size: 14))
                .padding(.top, 24)

                Spacer(minLength: 40)
            }
        }
        .background(Theme.background)
        .compatScrollDismissesKeyboard(.interactively)
    }

    // MARK: - Computed

    private var modeSubtitle: String {
        switch mode {
        case .signIn: return "Sign in to sync your library"
        case .signUp: return "Create an account"
        case .resetPassword: return "Reset your password"
        }
    }

    private var actionTitle: String {
        switch mode {
        case .signIn: return "Sign In"
        case .signUp: return "Create Account"
        case .resetPassword: return "Send Reset Email"
        }
    }

    private var switchPrompt: String {
        switch mode {
        case .signIn: return "Don't have an account?"
        case .signUp, .resetPassword: return "Already have an account?"
        }
    }

    private var switchAction: String {
        switch mode {
        case .signIn: return "Sign Up"
        case .signUp, .resetPassword: return "Sign In"
        }
    }

    private var isFormValid: Bool {
        let emailValid = email.contains("@") && email.contains(".")
        switch mode {
        case .signIn:
            return emailValid && password.count >= 6
        case .signUp:
            return emailValid && password.count >= 6 && password == confirmPassword
        case .resetPassword:
            return emailValid
        }
    }

    // MARK: - Actions

    private func googleSignIn() async {
        do {
            try await authService.signInWithGoogle()
            dismiss()
        } catch AuthError.cancelled {
            // User cancelled, do nothing
        } catch let error as AuthError {
            authService.errorMessage = error.errorDescription
        } catch {
            authService.errorMessage = error.localizedDescription
        }
    }

    private func performAction() async {
        do {
            switch mode {
            case .signIn:
                try await authService.signIn(email: email.trimmingCharacters(in: .whitespaces), password: password)
                dismiss()
            case .signUp:
                try await authService.signUp(email: email.trimmingCharacters(in: .whitespaces), password: password)
                dismiss()
            case .resetPassword:
                try await authService.sendPasswordReset(email: email.trimmingCharacters(in: .whitespaces))
                resetSent = true
            }
        } catch let error as AuthError {
            authService.errorMessage = error.errorDescription
        } catch {
            authService.errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Auth Text Field

private struct AuthTextField: View {
    let icon: String
    let placeholder: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default
    var isSecure: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(Theme.mutedForeground)
                .frame(width: 20)

            if isSecure {
                SecureField(placeholder, text: $text)
                    .font(.system(size: 16))
                    .foregroundColor(Theme.foreground)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            } else {
                TextField(placeholder, text: $text)
                    .font(.system(size: 16))
                    .foregroundColor(Theme.foreground)
                    .keyboardType(keyboardType)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(Theme.secondary)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusLg))
    }
}

#Preview {
    LoginView()
        .environmentObject(AuthService.shared)
}
