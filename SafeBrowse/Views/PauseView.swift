import SwiftUI

struct PauseView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var password = ""
    @State private var selectedDuration: AppState.PauseDuration = .thirtyMin
    @State private var errorMessage = ""

    private let pm = PasswordManager()

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.shield")
                .font(.system(size: 40))
                .foregroundStyle(.blue)

            if !state.isBlocking {
                // Resume flow
                Text("Resume Protection?")
                    .font(.title2.bold())
                Button("Resume Now") {
                    state.enableBlocking()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                Button("Cancel", role: .cancel) { dismiss() }

            } else if !pm.isPasswordSet {
                // No password set — direct user to Settings
                Text("No Password Set")
                    .font(.title2.bold())
                Text("Set a protection password in Settings before using Pause.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Dismiss") { dismiss() }

            } else {
                // Pause flow
                Text("Pause Protection")
                    .font(.title2.bold())

                Picker("Duration", selection: $selectedDuration) {
                    ForEach(AppState.PauseDuration.allCases) { d in
                        Text(d.rawValue).tag(d)
                    }
                }
                .pickerStyle(.segmented)

                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)

                if !errorMessage.isEmpty {
                    Text(errorMessage).foregroundStyle(.red).font(.caption)
                }

                HStack {
                    Button("Cancel") { dismiss() }
                    Spacer()
                    Button("Pause") {
                        guard pm.verifyPassword(password) else {
                            errorMessage = "Incorrect password."
                            password = ""
                            return
                        }
                        state.pauseBlocking(for: selectedDuration)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                }
            }
        }
        .padding(24)
        .frame(width: 360)
    }
}
