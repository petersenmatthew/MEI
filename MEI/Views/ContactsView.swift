import SwiftUI
import Contacts

struct ContactsView: View {
    @Bindable var appState: AppState
    @State private var searchText = ""
    @State private var showAddContact = false

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
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            ContactPickerSheet(appState: appState, isPresented: $showAddContact)
        }
    }
}

// MARK: - Contact Picker Sheet

struct ContactPickerSheet: View {
    @Bindable var appState: AppState
    @Binding var isPresented: Bool
    @State private var searchText = ""
    @State private var pickerContacts: [PickerContact] = []
    @State private var accessDenied = false
    @State private var loading = true

    var filteredContacts: [PickerContact] {
        if searchText.isEmpty { return pickerContacts }
        return pickerContacts.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.identifiers.contains { $0.formatted.localizedCaseInsensitiveContains(searchText) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Add Contact")
                    .font(.headline)
                Spacer()
                Button("Done") { isPresented = false }
            }
            .padding()

            Divider()

            if accessDenied {
                ContentUnavailableView {
                    Label("No Access", systemImage: "person.crop.circle.badge.xmark")
                } description: {
                    Text("Grant Contacts access in System Settings > Privacy & Security > Contacts.")
                }
            } else if loading {
                Spacer()
                ProgressView("Loading contacts...")
                Spacer()
            } else if pickerContacts.isEmpty {
                ContentUnavailableView {
                    Label("No Contacts", systemImage: "person.crop.circle")
                } description: {
                    Text("No contacts found.")
                }
            } else {
                TextField("Search contacts...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal)
                    .padding(.vertical, 8)

                List(filteredContacts) { contact in
                    ContactPickerRow(contact: contact) {
                        addAllIdentifiers(for: contact)
                    }
                }
            }
        }
        .frame(width: 400, height: 500)
        .task {
            await loadContacts()
        }
    }

    private func loadContacts() async {
        let store = CNContactStore()

        do {
            let granted = try await store.requestAccess(for: .contacts)
            guard granted else {
                accessDenied = true
                loading = false
                return
            }
        } catch {
            accessDenied = true
            loading = false
            return
        }

        let existingIDs = Set(appState.contacts.map { $0.contactID })

        let keysToFetch: [CNKeyDescriptor] = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
            CNContactThumbnailImageDataKey as CNKeyDescriptor,
        ]

        let results = await Task.detached(priority: .userInitiated) {
            var contacts: [PickerContact] = []
            let request = CNContactFetchRequest(keysToFetch: keysToFetch)
            request.sortOrder = .givenName

            do {
                try store.enumerateContacts(with: request) { cnContact, _ in
                    var identifiers: [ContactIdentifier] = []

                    // Phone numbers
                    for labeled in cnContact.phoneNumbers {
                        let normalized = Self.normalizePhoneNumber(labeled.value.stringValue)
                        guard !normalized.isEmpty, !existingIDs.contains(normalized) else { continue }
                        let label = CNLabeledValue<NSString>.localizedString(forLabel: labeled.label ?? "")
                        identifiers.append(ContactIdentifier(normalized: normalized, formatted: labeled.value.stringValue, label: label))
                    }

                    // Email addresses
                    for labeled in cnContact.emailAddresses {
                        let email = (labeled.value as String).lowercased()
                        guard !email.isEmpty, !existingIDs.contains(email) else { continue }
                        let label = CNLabeledValue<NSString>.localizedString(forLabel: labeled.label ?? "")
                        identifiers.append(ContactIdentifier(normalized: email, formatted: email, label: label.isEmpty ? "email" : label))
                    }

                    guard !identifiers.isEmpty else { return }

                    let name = [cnContact.givenName, cnContact.familyName]
                        .filter { !$0.isEmpty }
                        .joined(separator: " ")

                    contacts.append(PickerContact(
                        name: name.isEmpty ? "Unknown" : name,
                        identifiers: identifiers,
                        thumbnailData: cnContact.thumbnailImageData
                    ))
                }
            } catch {
                // Fetch failed — return empty results
            }

            return contacts
        }.value

        pickerContacts = results
        loading = false
    }

    private func addAllIdentifiers(for contact: PickerContact) {
        for identifier in contact.identifiers {
            let config = ContactConfig(
                contactID: identifier.normalized,
                displayName: contact.name,
                mode: .active,
                customRules: [],
                thumbnailData: contact.thumbnailData
            )
            appState.contacts.append(config)
        }

        // Remove the contact from the picker list
        pickerContacts.removeAll { $0.id == contact.id }
    }

    static func normalizePhoneNumber(_ raw: String) -> String {
        let digits = raw.filter { $0.isNumber || $0 == "+" }
        if digits.hasPrefix("+") { return digits }
        // Assume US number if 10 digits with no country code
        if digits.count == 10 { return "+1" + digits }
        if digits.count == 11 && digits.hasPrefix("1") { return "+" + digits }
        return digits.isEmpty ? "" : "+" + digits
    }
}

// MARK: - Contact Picker Row

struct ContactPickerRow: View {
    let contact: PickerContact
    let onSelect: () -> Void

    var body: some View {
        Button {
            onSelect()
        } label: {
            HStack(spacing: 10) {
                contactAvatar
                VStack(alignment: .leading, spacing: 2) {
                    Text(contact.name).font(.headline)
                    Text(contact.identifiers.map(\.formatted).joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "plus.circle")
                    .foregroundStyle(.blue)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var contactAvatar: some View {
        if let data = contact.thumbnailData, let nsImage = NSImage(data: data) {
            Image(nsImage: nsImage)
                .resizable()
                .frame(width: 32, height: 32)
                .clipShape(Circle())
        } else {
            Image(systemName: "person.circle.fill")
                .resizable()
                .frame(width: 32, height: 32)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Models

struct PickerContact: Identifiable {
    let id = UUID()
    let name: String
    var identifiers: [ContactIdentifier]
    let thumbnailData: Data?
}

struct ContactIdentifier: Identifiable {
    let id = UUID()
    let normalized: String
    let formatted: String
    let label: String
}

// MARK: - Contact Row (existing)

struct ContactRow: View {
    let contact: ContactConfig
    @Bindable var appState: AppState
    @State private var showDeleteConfirmation = false

    var body: some View {
        HStack(spacing: 10) {
            if let data = contact.thumbnailData, let nsImage = NSImage(data: data) {
                Image(nsImage: nsImage)
                    .resizable()
                    .frame(width: 32, height: 32)
                    .clipShape(Circle())
            } else {
                Image(systemName: "person.circle.fill")
                    .resizable()
                    .frame(width: 32, height: 32)
                    .foregroundStyle(.secondary)
            }

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

            Button {
                showDeleteConfirmation = true
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .help("Remove contact")
        }
        .padding(.vertical, 4)
        .alert("Remove Contact", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) {
                appState.contacts.removeAll { $0.id == contact.id }
            }
        } message: {
            Text("Are you sure you want to remove \(contact.displayName) from your contacts list?")
        }
    }
}
