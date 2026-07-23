import SwiftUI

struct RegisterView: View {
    @EnvironmentObject private var appState: AppState

    @State private var name = ""
    @State private var email = ""
    @State private var phone = ""
    @State private var gender: Gender = .preferNotToSay
    @State private var personType: PersonType = .homeless
    @State private var staffCode = ""

    private var canSubmit: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        (!personType.isStaff || !staffCode.trimmingCharacters(in: .whitespaces).isEmpty) &&
        !appState.isLoading
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Ground to Growth Connect")
                            .font(.title2.bold())
                        Text("A path to healing, a journey to home")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("A program of Ground to Growth Initiative · Savannah, GA")
                            .font(.footnote)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 4)
                }

                Section("Your details") {
                    TextField("Full name", text: $name)
                        .textContentType(.name)
                    TextField("Email (optional)", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Phone (optional)", text: $phone)
                        .textContentType(.telephoneNumber)
                        .keyboardType(.phonePad)
                    Picker("Gender", selection: $gender) {
                        ForEach(Gender.allCases) { g in
                            Text(g.label).tag(g)
                        }
                    }
                }

                Section("Account type") {
                    Picker("I am a", selection: $personType) {
                        ForEach(PersonType.allCases) { t in
                            Text(t.label).tag(t)
                        }
                    }
                    if personType.isStaff {
                        SecureField("Staff invite code", text: $staffCode)
                        Text("Staff accounts can view participant locations and require a code from Ground to Growth.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Button {
                        submit()
                    } label: {
                        if appState.isLoading {
                            ProgressView().frame(maxWidth: .infinity)
                        } else {
                            Text("Create account").frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(!canSubmit)
                } footer: {
                    Text("Your details are encrypted and stored securely. Your access token is kept only in this device's Keychain.")
                }

                if let disclosure = appState.disclosure {
                    Section("Disclosure · v\(disclosure.version)") {
                        Text(disclosure.text)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Welcome")
            .alert("Error", isPresented: .constant(appState.errorMessage != nil)) {
                Button("OK") { appState.errorMessage = nil }
            } message: {
                Text(appState.errorMessage ?? "")
            }
        }
    }

    private func submit() {
        let trimmedEmail = email.trimmingCharacters(in: .whitespaces)
        let trimmedPhone = phone.trimmingCharacters(in: .whitespaces)
        let payload = RegisterRequest(
            name: name.trimmingCharacters(in: .whitespaces),
            email: trimmedEmail.isEmpty ? nil : trimmedEmail,
            gender: gender.rawValue,
            phone: trimmedPhone.isEmpty ? nil : trimmedPhone,
            personType: personType.rawValue,
            staffCode: personType.isStaff ? staffCode.trimmingCharacters(in: .whitespaces) : nil
        )
        Task { await appState.register(payload) }
    }
}
