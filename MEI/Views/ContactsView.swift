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
    @State private var phoneContacts: [PhoneContact] = []
    @State private var accessDenied = false
    @State private var loading = true

    var filteredPhoneContacts: [PhoneContact] {
        if searchText.isEmpty { return phoneContacts }
        return phoneContacts.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.phoneNumbers.contains { $0.formatted.localizedCaseInsensitiveContains(searchText) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Add from Contacts")
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
            } else if phoneContacts.isEmpty {
                ContentUnavailableView {
                    Label("No Contacts", systemImage: "person.crop.circle")
                } description: {
                    Text("No contacts with phone numbers found.")
                }
            } else {
                TextField("Search contacts...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal)
                    .padding(.vertical, 8)

                List(filteredPhoneContacts) { contact in
                    ContactPickerRow(contact: contact) { selectedNumber in
                        addContact(name: contact.name, phoneNumber: selectedNumber)
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
            CNContactThumbnailImageDataKey as CNKeyDescriptor,
        ]

        let results = await Task.detached(priority: .userInitiated) {
            var contacts: [PhoneContact] = []
            let request = CNContactFetchRequest(keysToFetch: keysToFetch)
            request.sortOrder = .givenName

            do {
                try store.enumerateContacts(with: request) { cnContact, _ in
                    let phones = cnContact.phoneNumbers.compactMap { labeled -> PhoneNumber? in
                        let normalized = Self.normalizePhoneNumber(labeled.value.stringValue)
                        guard !normalized.isEmpty, !existingIDs.contains(normalized) else { return nil }
                        let label = CNLabeledValue<NSString>.localizedString(forLabel: labeled.label ?? "")
                        return PhoneNumber(normalized: normalized   , formatted: labeled.value.stringValue, label: label)
                    }
                    guard !phones.isEmpty else { return }

                    let name = [cnContact.givenName, cnContact.familyName]
                        .filter { !$0.isEmpty }
                        .joined(separator: " ")

                    contacts.append(PhoneContact(
                        name: name.isEmpty ? "Unknown" : name,
                        phoneNumbers: phones,
                        thumbnailData: cnContact.thumbnailImageData
                    ))
                }
            } catch {
                // Fetch failed — return empty results
            }

            return contacts
        }.value

        phoneContacts = results
        loading = false
    }

    private func addContact(name: String, phoneNumber: String) {
        let config = ContactConfig(
            contactID: phoneNumber,
            displayName: name,
            mode: .active,
            customRules: []
        )
        appState.contacts.append(config)

        // Remove the number from the picker list so it can't be added again
        for i in phoneContacts.indices {
            phoneContacts[i].phoneNumbers.removeAll { $0.normalized == phoneNumber }
        }
        phoneContacts.removeAll { $0.phoneNumbers.isEmpty }
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
    let contact: PhoneContact
    let onSelect: (String) -> Void

    var body: some View {
        if contact.phoneNumbers.count == 1, let phone = contact.phoneNumbers.first {
            Button {
                onSelect(phone.normalized)
            } label: {
                HStack(spacing: 10) {
                    contactAvatar
                    VStack(alignment: .leading, spacing: 2) {
                        Text(contact.name).font(.headline)
                        Text(phone.formatted)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "plus.circle")
                        .foregroundStyle(.blue)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            DisclosureGroup {
                ForEach(contact.phoneNumbers) { phone in
                    Button {
                        onSelect(phone.normalized)
                    } label: {
                        HStack {
                            Text(phone.label)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 60, alignment: .leading)
                            Text(phone.formatted)
                                .font(.body)
                            Spacer()
                            Image(systemName: "plus.circle")
                                .foregroundStyle(.blue)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            } label: {
                HStack(spacing: 10) {
                    contactAvatar
                    Text(contact.name).font(.headline)
                }
            }
        }
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

struct PhoneContact: Identifiable {
    let id = UUID()
    let name: String
    var phoneNumbers: [PhoneNumber]
    let thumbnailData: Data?
}

struct PhoneNumber: Identifiable {
    let id = UUID()
    let normalized: String
    let formatted: String
    let label: String
}

// MARK: - Contact Row (existing)

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
