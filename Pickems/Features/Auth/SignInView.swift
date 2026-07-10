import SwiftUI
import AuthenticationServices

struct SignInView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.themePalette) private var theme
    @State private var mode: AuthMode = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var displayName = ""
    @State private var confirmPassword = ""
    @State private var showForgotPassword = false
    #if DEBUG
    @State private var showAdminLogin = false
    #endif

    private enum AuthMode: String, CaseIterable {
        case signIn = "Sign In"
        case createAccount = "Create Account"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                brandHeader

                Picker("Mode", selection: $mode) {
                    ForEach(AuthMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .accessibilityLabel("Sign in or create account")

                emailPasswordForm

                PrimaryButton(
                    title: mode == .signIn ? "Sign In" : "Create Account",
                    isLoading: appState.authService.isLoading
                ) {
                    Task { await submitEmailPassword() }
                }
                .padding(.horizontal)
                .disabled(!canSubmit)

                if mode == .signIn {
                    Button("Forgot password?") {
                        showForgotPassword = true
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(PickemsColors.textSecondary)
                }

                divider

                Text("Or continue with Apple")
                    .font(.caption)
                    .foregroundStyle(PickemsColors.textSecondary)

                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.fullName, .email]
                    request.nonce = appState.authService.prepareAppleSignIn()
                } onCompletion: { result in
                    Task {
                        switch result {
                        case .success(let authorization):
                            do {
                                try await appState.authService.signInWithApple(authorization: authorization)
                                await appState.onAuthStateReady()
                            } catch {
                                appState.authService.errorMessage = error.localizedDescription
                            }
                        case .failure(let error):
                            appState.authService.errorMessage = error.localizedDescription
                            AppEvents.failure(.authAppleFailed, error: error, metadata: [
                                "phase": "authorization_sheet",
                            ])
                        }
                    }
                }
                .signInWithAppleButtonStyle(.white)
                .frame(height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)
                .disabled(appState.authService.isLoading)

                if let error = appState.authService.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(PickemsColors.warning)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                #if DEBUG
                Button("Admin") {
                    showAdminLogin = true
                }
                .font(.caption2)
                .foregroundStyle(PickemsColors.textSecondary.opacity(0.5))
                .padding(.top, 8)
                #endif
            }
            .padding()
            .padding(.bottom, 24)
        }
        .background(PickemsColors.background)
        .onChange(of: mode) { _, _ in
            appState.authService.errorMessage = nil
            password = ""
            confirmPassword = ""
        }
        .sheet(isPresented: $showForgotPassword) {
            ForgotPasswordSheet(prefilledEmail: email)
        }
        #if DEBUG
        .sheet(isPresented: $showAdminLogin) {
            AdminLoginSheet()
        }
        #endif
    }

    private var brandHeader: some View {
        VStack(spacing: 8) {
            Image(systemName: "football.fill")
                .font(.system(size: 64))
                .foregroundStyle(theme.accent)
            Text("Pickems")
                .font(.largeTitle.bold())
                .foregroundStyle(PickemsColors.textPrimary)
            Text("College football picks with your crew")
                .font(.subheadline)
                .foregroundStyle(PickemsColors.textSecondary)
        }
        .padding(.top, 40)
    }

    private var emailPasswordForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            if mode == .createAccount {
                fieldLabel("Display name")
                TextField("How you'll show up in leagues", text: $displayName)
                    .textFieldStyle(.pickems)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
            }

            fieldLabel("Email")
            TextField("you@example.com", text: $email)
                .textFieldStyle(.pickems)
                .textInputAutocapitalization(.never)
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .autocorrectionDisabled()

            fieldLabel("Password")
            SecureField(mode == .createAccount ? "At least 6 characters" : "Password", text: $password)
                .textFieldStyle(.pickems)
                .textInputAutocapitalization(.never)
                .textContentType(mode == .createAccount ? .newPassword : .password)
                .autocorrectionDisabled()

            if mode == .createAccount {
                fieldLabel("Confirm password")
                SecureField("Re-enter password", text: $confirmPassword)
                    .textFieldStyle(.pickems)
                    .textInputAutocapitalization(.never)
                    .textContentType(.newPassword)
                    .autocorrectionDisabled()
            }
        }
        .padding(.horizontal)
    }

    private var divider: some View {
        HStack {
            Rectangle()
                .fill(PickemsColors.textSecondary.opacity(0.25))
                .frame(height: 1)
            Text("or")
                .font(.caption)
                .foregroundStyle(PickemsColors.textSecondary)
            Rectangle()
                .fill(PickemsColors.textSecondary.opacity(0.25))
                .frame(height: 1)
        }
        .padding(.horizontal)
    }

    private func fieldLabel(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(PickemsColors.textSecondary)
    }

    private var canSubmit: Bool {
        guard !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !password.isEmpty,
              !appState.authService.isLoading else {
            return false
        }
        if mode == .createAccount {
            return !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && password == confirmPassword
                && password.count >= 6
        }
        return true
    }

    private func submitEmailPassword() async {
        appState.authService.errorMessage = nil

        if mode == .createAccount, password != confirmPassword {
            appState.authService.errorMessage = "Passwords do not match."
            return
        }

        do {
            switch mode {
            case .signIn:
                try await appState.authService.signIn(email: email, password: password)
            case .createAccount:
                try await appState.authService.signUp(
                    email: email,
                    password: password,
                    displayName: displayName
                )
            }
            await appState.onAuthStateReady()
        } catch {
            if appState.authService.errorMessage == nil {
                appState.authService.errorMessage = error.localizedDescription
            }
        }
    }
}
