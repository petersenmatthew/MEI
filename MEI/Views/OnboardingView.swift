import SwiftUI

struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var currentStep = 0
    @State private var apiKeyInput = ""

    var body: some View {
        VStack(spacing: 0) {
            // Progress
            HStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { step in
                    Capsule()
                        .fill(step <= currentStep ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(height: 4)
                }
            }
            .padding()

            Divider()

            // Content
            TabView(selection: $currentStep) {
                fullDiskAccessStep.tag(0)
                accessibilityStep.tag(1)
                apiKeyStep.tag(2)
            }
            .tabViewStyle(.automatic)

            Divider()

            // Navigation
            HStack {
                if currentStep > 0 {
                    Button("Back") {
                        currentStep -= 1
                    }
                }
                Spacer()
                if currentStep < 2 {
                    Button("Next") {
                        currentStep += 1
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Done") {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
        }
        .frame(width: 500, height: 400)
    }

    private var fullDiskAccessStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.open.fill")
                .font(.system(size: 48))
                .foregroundStyle(.blue)

            Text("Full Disk Access")
                .font(.title2.bold())

            Text("MEI needs Full Disk Access to read your iMessage history from chat.db.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Text("System Settings > Privacy & Security > Full Disk Access")
                .font(.caption)
                .padding()
                .background(.background.secondary)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            Button("Open System Settings") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
            }
        }
        .padding()
    }

    private var accessibilityStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)

            Text("Accessibility Access")
                .font(.title2.bold())

            Text("MEI needs Accessibility access to send iMessages via AppleScript automation.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Text("System Settings > Privacy & Security > Accessibility")
                .font(.caption)
                .padding()
                .background(.background.secondary)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            Button("Open System Settings") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            }
        }
        .padding()
    }

    private var apiKeyStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "key.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)

            Text("Gemini API Key")
                .font(.title2.bold())

            Text("Enter your Google Gemini API key. It will be stored securely in your Mac's Keychain.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            SecureField("Gemini API Key", text: $apiKeyInput)
                .textFieldStyle(.roundedBorder)
                .frame(width: 350)

            Button("Save to Keychain") {
                if !apiKeyInput.isEmpty {
                    try? KeychainManager.save(key: "gemini_api_key", value: apiKeyInput)
                    apiKeyInput = ""
                }
            }
            .disabled(apiKeyInput.isEmpty)

            Link("Get a Gemini API key", destination: URL(string: "https://aistudio.google.com/apikey")!)
                .font(.caption)
        }
        .padding()
    }
}
