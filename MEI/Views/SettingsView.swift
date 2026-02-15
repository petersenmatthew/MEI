import SwiftUI

struct SettingsView: View {
    @Bindable var appState: AppState
    @State private var apiKeyInput = ""
    @State private var showAPIKey = false
    @State private var hasAPIKey = false
    @State private var newTopic = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Settings")
                    .font(.title2.bold())

                // General
                GroupBox("General") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Agent mode")
                            Spacer()
                            Picker("", selection: $appState.mode) {
                                ForEach(AgentMode.allCases, id: \.self) { mode in
                                    Text(mode.rawValue).tag(mode)
                                }
                            }
                            .frame(width: 160)
                        }

                        HStack {
                            Text("Confidence threshold")
                            Spacer()
                            Slider(value: $appState.confidenceThreshold, in: 0.5...1.0, step: 0.05) {
                                Text("Threshold")
                            }
                            .frame(width: 200)
                            Text(String(format: "%.2f", appState.confidenceThreshold))
                                .monospacedDigit()
                                .frame(width: 40)
                        }

                        HStack {
                            Text("Send delay")
                            Spacer()
                            Toggle("", isOn: $appState.sendDelayEnabled)
                            if appState.sendDelayEnabled {
                                Text("\(appState.sendDelaySeconds)s")
                                    .foregroundStyle(.secondary)
                                Stepper("", value: $appState.sendDelaySeconds, in: 10...120, step: 10)
                                    .frame(width: 100)
                            }
                        }

                        HStack {
                            Text("Kill word")
                            Spacer()
                            TextField("Text this to stop agent", text: $appState.killWord)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 200)
                        }
                    }
                    .padding(.vertical, 4)
                }

                // Active Hours
                GroupBox("Active Hours") {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Limit active hours", isOn: $appState.activeHoursEnabled)

                        if appState.activeHoursEnabled {
                            HStack {
                                Text("Respond between")
                                Spacer()
                                Picker("", selection: $appState.activeHoursStart) {
                                    ForEach(0..<24, id: \.self) { hour in
                                        Text(formatHour(hour)).tag(hour)
                                    }
                                }
                                .frame(width: 100)
                                Text("and")
                                Picker("", selection: $appState.activeHoursEnd) {
                                    ForEach(0..<24, id: \.self) { hour in
                                        Text(formatHour(hour)).tag(hour)
                                    }
                                }
                                .frame(width: 100)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                // API
                GroupBox("API") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Gemini API key")
                            Spacer()
                            if hasAPIKey {
                                Text("Configured")
                                    .foregroundStyle(.green)
                                    .font(.caption)
                                Button("Remove") {
                                    KeychainManager.delete(key: "gemini_api_key")
                                    hasAPIKey = false
                                }
                                .font(.caption)
                            } else {
                                SecureField("Enter API key", text: $apiKeyInput)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 200)
                                Button("Save") {
                                    if !apiKeyInput.isEmpty {
                                        try? KeychainManager.save(key: "gemini_api_key", value: apiKeyInput)
                                        hasAPIKey = true
                                        apiKeyInput = ""
                                    }
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                // Topic Boundaries
                GroupBox("Topic Boundaries") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Never respond about:")
                            .font(.subheadline)

                        ForEach(Array(appState.restrictedTopics).sorted(), id: \.self) { topic in
                            HStack {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.red)
                                    .onTapGesture {
                                        appState.restrictedTopics.remove(topic)
                                    }
                                Text(topic)
                            }
                        }

                        HStack {
                            TextField("Add topic...", text: $newTopic)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit {
                                    addTopic()
                                }
                            Button("Add") {
                                addTopic()
                            }
                            .disabled(newTopic.isEmpty)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding()
        }
        .onAppear {
            hasAPIKey = KeychainManager.load(key: "gemini_api_key") != nil
        }
    }

    private func addTopic() {
        let topic = newTopic.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !topic.isEmpty else { return }
        appState.restrictedTopics.insert(topic)
        newTopic = ""
    }

    private func formatHour(_ hour: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        var components = DateComponents()
        components.hour = hour
        let date = Calendar.current.date(from: components) ?? Date()
        return formatter.string(from: date)
    }
}
