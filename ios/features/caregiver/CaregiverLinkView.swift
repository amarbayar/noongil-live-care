import SwiftUI

/// UI for managing caregiver links. Members can send email invitations
/// and see/revoke linked caregivers.
struct CaregiverLinkView: View {
    @EnvironmentObject var theme: ThemeService
    @EnvironmentObject var storageService: StorageService

    @StateObject private var caregiverService: CaregiverService
    @State private var selectedPermissions: Set<CaregiverPermission> = Set(CaregiverPermission.allCases)
    @State private var caregiverEmail = ""
    @State private var shareURL: URL?
    @State private var showingShareSheet = false
    @State private var isSendingInvite = false
    @State private var inviteError: String?
    @State private var inviteSuccessMessage: String?

    init(userId: String, storageService: StorageService? = nil) {
        _caregiverService = StateObject(wrappedValue: CaregiverService(
            userId: userId,
            storageService: storageService
        ))
    }

    var body: some View {
        NavigationView {
            ZStack {
                ScrollView {
                    VStack(spacing: 24) {
                        inviteSection
                        pendingInvitationsSection
                        linkedCaregiversSection
                        membersICareForSection
                    }
                    .padding(20)
                }
            }
            .screenBackground()
            .navigationTitle("Caregivers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .task {
            await caregiverService.fetchRelationships()
            await caregiverService.fetchInvitations()
            await caregiverService.fetchMembersICareFor()
        }
        .sheet(isPresented: $showingShareSheet) {
            if let url = shareURL {
                ShareSheet(items: [url])
            }
        }
    }

    // MARK: - Invite Section

    private var inviteSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "person.badge.plus")
                    .foregroundColor(theme.primary)
                Text("Invite a caregiver")
                    .font(.headline)
                    .foregroundColor(theme.text)
            }

            Text("Enter your caregiver's Google/Firebase sign-in email. They'll receive a link to view the data you choose to share.")
                .font(.subheadline)
                .foregroundColor(theme.textSecondary)

            // Email input
            TextField("Caregiver's email", text: $caregiverEmail)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .font(.body)
                .foregroundColor(theme.text)
                .padding(14)
                .background(theme.surface)
                .cornerRadius(12)
                .frame(minHeight: 60)
                .accessibilityLabel("Caregiver email address")

            // Permission toggles
            VStack(alignment: .leading, spacing: 10) {
                Text("Data to share")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(theme.text)

                ForEach(CaregiverPermission.allCases, id: \.self) { perm in
                    HStack(spacing: 12) {
                        Image(systemName: selectedPermissions.contains(perm) ? "checkmark.square.fill" : "square")
                            .font(.title3)
                            .foregroundColor(selectedPermissions.contains(perm) ? theme.primary : theme.textSecondary)

                        Text(perm.displayName)
                            .font(.body)
                            .foregroundColor(theme.text)

                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if selectedPermissions.contains(perm) {
                            selectedPermissions.remove(perm)
                        } else {
                            selectedPermissions.insert(perm)
                        }
                    }
                    .frame(minHeight: 48)
                    .accessibilityLabel("\(perm.displayName) — \(selectedPermissions.contains(perm) ? "shared" : "not shared")")
                }
            }

            // Disclosure summary
            if !selectedPermissions.isEmpty {
                Text("You are sharing: \(selectedPermissions.sorted(by: { $0.rawValue < $1.rawValue }).map(\.displayName).joined(separator: ", "))")
                    .font(.caption)
                    .foregroundColor(theme.textSecondary)
                    .padding(.vertical, 4)
            }

            // Error feedback
            if let inviteError {
                Text(inviteError)
                    .font(.caption)
                    .foregroundColor(theme.error)
                    .padding(.vertical, 2)
            }

            if let inviteSuccessMessage {
                Text(inviteSuccessMessage)
                    .font(.caption)
                    .foregroundColor(theme.success)
                    .padding(.vertical, 2)
            }

            // Send button
            Button {
                Task { await sendInvitation() }
            } label: {
                HStack(spacing: 8) {
                    if isSendingInvite {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "paperplane")
                    }
                    Text(isSendingInvite ? "Sending..." : "Send Invite")
                        .font(.body.weight(.semibold))
                }
                .foregroundColor(.white)
                .frame(height: 60)
                .frame(maxWidth: .infinity)
                .background(canSend && !isSendingInvite ? theme.primary : .white.opacity(0.15))
                .cornerRadius(30)
            }
            .disabled(!canSend || isSendingInvite)
            .opacity(canSend && !isSendingInvite ? 1.0 : 0.5)
            .accessibilityLabel("Send invitation to \(caregiverEmail)")
        }
        .glassCard()
    }

    private var canSend: Bool {
        !caregiverEmail.isEmpty && caregiverEmail.contains("@") && !selectedPermissions.isEmpty
    }

    private func sendInvitation() async {
        inviteError = nil
        inviteSuccessMessage = nil
        isSendingInvite = true
        defer { isSendingInvite = false }

        let result = await caregiverService.createInvitation(
            caregiverEmail: caregiverEmail,
            permissions: Array(selectedPermissions)
        )

        switch result {
        case .success(let invitation):
            let inviteURLString = invitation.inviteURL ?? "\(Config.publicDashboardURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")))/dashboard?invite=\(invitation.token)"
            if invitation.emailDeliveryStatus == "sent" {
                inviteSuccessMessage = "Invitation emailed to \(invitation.caregiverEmail)."
            } else {
                shareURL = URL(string: inviteURLString)
                showingShareSheet = true
                inviteSuccessMessage = "Email delivery was unavailable, so a share link is ready."
            }
            caregiverEmail = ""
        case .failure(let message):
            inviteError = message
        }
    }

    // MARK: - Pending Invitations

    @ViewBuilder
    private var pendingInvitationsSection: some View {
        let pending = caregiverService.invitations.filter { $0.status == .pending }
        if !pending.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    Image(systemName: "clock")
                        .foregroundColor(theme.primary)
                    Text("Pending invitations")
                        .font(.headline)
                        .foregroundColor(theme.text)
                }

                ForEach(pending) { invitation in
                    HStack(spacing: 12) {
                        Image(systemName: "envelope.circle.fill")
                            .font(.title2)
                            .foregroundColor(theme.accent)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(invitation.caregiverEmail)
                                .font(.body.weight(.medium))
                                .foregroundColor(theme.text)

                            Text(invitation.permissions.map(\.displayName).joined(separator: ", "))
                                .font(.caption)
                                .foregroundColor(theme.textSecondary)
                        }

                        Spacer()

                        Button {
                            if let id = invitation.id {
                                Task { await caregiverService.revokeInvitation(id: id) }
                            }
                        } label: {
                            Text("Revoke")
                                .font(.caption.weight(.medium))
                                .foregroundColor(theme.error)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(theme.error.opacity(0.1))
                                .cornerRadius(8)
                        }
                        .accessibilityLabel("Revoke invitation to \(invitation.caregiverEmail)")
                    }
                    .padding(.vertical, 4)
                    .frame(minHeight: 60)
                }
            }
            .glassCard()
        }
    }

    // MARK: - Linked Caregivers

    private var linkedCaregiversSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "person.2")
                    .foregroundColor(theme.primary)
                Text("Linked caregivers")
                    .font(.headline)
                    .foregroundColor(theme.text)
            }

            let active = caregiverService.activeRelationships

            if active.isEmpty {
                Text("No caregivers linked yet. Send an invitation above to get started.")
                    .font(.subheadline)
                    .foregroundColor(theme.textSecondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(active) { relationship in
                    caregiverRow(relationship)
                }
            }
        }
        .glassCard()
    }

    private func caregiverRow(_ relationship: CaregiverRelationship) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "person.circle.fill")
                .font(.title2)
                .foregroundColor(theme.primary)

            VStack(alignment: .leading, spacing: 2) {
                Text(relationship.caregiverName ?? "Caregiver")
                    .font(.body.weight(.medium))
                    .foregroundColor(theme.text)

                Text(relationship.role == .primary ? "Primary" : "Secondary")
                    .font(.caption)
                    .foregroundColor(theme.textSecondary)
            }

            Spacer()

            Button {
                if let id = relationship.id {
                    Task { await caregiverService.revokeRelationship(id: id) }
                }
            } label: {
                Text("Remove")
                    .font(.caption.weight(.medium))
                    .foregroundColor(theme.error)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(theme.error.opacity(0.1))
                    .cornerRadius(8)
            }
            .accessibilityLabel("Remove \(relationship.caregiverName ?? "caregiver")")
        }
        .padding(.vertical, 4)
        .frame(minHeight: 60)
        .accessibilityElement(children: .combine)
    }

    // MARK: - People I Care For

    @ViewBuilder
    private var membersICareForSection: some View {
        let members = caregiverService.membersICareFor
        if !members.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    Image(systemName: "heart.circle")
                        .foregroundColor(theme.primary)
                    Text("People I care for")
                        .font(.headline)
                        .foregroundColor(theme.text)
                }

                ForEach(members) { member in
                    NavigationLink {
                        CaregiverMemberView(member: member, caregiverService: caregiverService)
                            .environmentObject(theme)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "person.circle.fill")
                                .font(.title2)
                                .foregroundColor(theme.accent)

                            Text(member.memberName ?? "Member")
                                .font(.body.weight(.medium))
                                .foregroundColor(theme.text)

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(theme.textSecondary)
                        }
                        .padding(.vertical, 4)
                        .frame(minHeight: 60)
                    }
                    .accessibilityLabel(member.memberName ?? "Member")
                }
            }
            .glassCard()
        }
    }
}

// ShareSheet is defined in ReportView.swift and shared across features
