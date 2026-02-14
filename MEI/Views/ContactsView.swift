import SwiftUI

struct ContactsView: View {
    @Bindable var appState: AppState
    @State private var searchText = ""
    @State private var showAddContact = false
    @State private var newContactID = ""
    @State private var newContactName = ""

    var filteredContacts: [ContactConfig] {
        if searchText.isEmpty {
            return appState.contacts
        }
        return appState.contacts.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchText) ||
            $0.contactID.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Contacts")
                    .font(.title2.bold())
                Spacer()
                Button {
                    showAddContact = true
                } label: {
                    Label("Add Contact", systemImage: "plus")
                }
            }
            .padding()

            Divider()

            if appState.contacts.isEmpty {
                ContentUnavailableView {
                    Label("No contacts configured", systemImage: "person.crop.circle.badge.plus")
                } description: {
                    Text("Add contacts to your whitelist to get started.")
                }
            } else {
                List {
                    ForEach(filteredContacts) { contact in
                        ContactRow(contact: contact, appState: appState)
                    }
                }
                .searchable(text: $searchText, prompt: "Search contacts...")
            }
        }
        .sheet(isPresented: $showAddContact) {
            addContactSheet
        }
    }

    private var addContactSheet: some View {
        VStack(spacing: 16) {
            Text("Add Contact")
                .font(.headline)

            TextField("Phone number (e.g. +11234567890)", text: $newContactID)
                .textFieldStyle(.roundedBorder)

            TextField("Display name", text: $newContactName)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Cancel") {
                    showAddContact = false
                    newContactID = ""
                    newContactName = ""
                }

                Spacer()

                Button("Add") {
                    let config = ContactConfig(
                        contactID: newContactID,
                        displayName: newContactName.isEmpty ? newContactID : newContactName,
                        mode: .shadowOnly,
                        customRules: []
                    )
                    appState.contacts.append(config)
                    showAddContact = false
                    newContactID = ""
                    newContactName = ""
                }
                .disabled(newContactID.isEmpty)
            }
        }
        .padding()
        .frame(width: 350)
    }
}

struct ContactRow: View {
    let contact: ContactConfig
    @Bindable var appState: AppState

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(contact.displayName)
                    .font(.headline)
                Text(contact.contactID)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Picker("", selection: Binding(
                get: { contact.mode },
                set: { newMode in
                    if let idx = appState.contacts.firstIndex(where: { $0.id == contact.id }) {
                        appState.contacts[idx].mode = newMode
                    }
                }
            )) {
                ForEach(ContactMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .frame(width: 140)
        }
        .padding(.vertical, 4)
    }
}
