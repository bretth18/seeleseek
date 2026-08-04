import SwiftUI
import SeeleseekCore

struct RoomManagementSheet: View {
    let room: ChatRoom
    @Bindable var chatState: ChatState
    @Binding var isPresented: Bool

    @State private var tickerText: String = ""
    @State private var newMemberName: String = ""
    @State private var newOperatorName: String = ""
    @State private var showGiveUpConfirm: Bool = false

    private var isOwner: Bool {
        chatState.isOwner(of: room.name)
    }

    private var isOperator: Bool {
        chatState.isOperator(of: room.name)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Room Settings")
                    .font(SeeleTypography.title2)
                    .foregroundStyle(SeeleColors.textPrimary)

                Spacer()

                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: SeeleSpacing.iconSizeMedium))
                        .foregroundStyle(SeeleColors.textSecondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("Close")
            }
            .padding(SeeleSpacing.lg)

            ScrollView {
                VStack(spacing: SeeleSpacing.lg) {
                    // Info section
                    infoSection

                    // Ticker section
                    tickerSection

                    // Members section (owner/operator)
                    if isOwner || isOperator {
                        membersSection
                    }

                    // Operators section (owner only)
                    if isOwner {
                        operatorsSection
                    }

                    // Danger zone (owner only)
                    if isOwner {
                        dangerSection
                    }
                }
                .padding(SeeleSpacing.lg)
            }
        }
        .frame(width: 400, height: 500)
        .background(SeeleColors.background)
        // Seed the field with the ticker already on the server so the sheet
        // shows the current value rather than an empty box, and so "Set" can
        // stay hidden until the text actually differs.
        .onAppear { tickerText = myTicker }
        .onChange(of: myTicker) { _, new in tickerText = new }
        .alert("Give Up Ownership", isPresented: $showGiveUpConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Give Up", role: .destructive) {
                chatState.giveUpOwnership(room: room.name)
                isPresented = false
            }
        } message: {
            Text("Are you sure you want to give up ownership of '\(room.name)'? This cannot be undone.")
        }
    }

    // MARK: - Info Section

    private var infoSection: some View {
        SeeleFormSection("INFO") {
            SeeleFormRow(showDivider: true) {
                HStack {
                    Text("Room")
                        .font(SeeleTypography.body)
                        .foregroundStyle(SeeleColors.textSecondary)
                    Spacer()
                    Text(room.name)
                        .font(SeeleTypography.body)
                        .foregroundStyle(SeeleColors.textPrimary)
                }
                .accessibilityElement(children: .combine)
            }

            SeeleFormRow(showDivider: true) {
                HStack {
                    Text("Type")
                        .font(SeeleTypography.body)
                        .foregroundStyle(SeeleColors.textSecondary)
                    Spacer()
                    Text(room.isPrivate ? "Private" : "Public")
                        .font(SeeleTypography.caption)
                        .foregroundStyle(SeeleColors.textOnAccent)
                        .padding(.horizontal, SeeleSpacing.xs)
                        .padding(.vertical, SeeleSpacing.xxs)
                        .background(room.isPrivate ? SeeleColors.accent.opacity(0.8) : SeeleColors.success.opacity(0.8))
                        .clipShape(Capsule())
                }
                .accessibilityElement(children: .combine)
            }

            if let owner = room.owner {
                SeeleFormRow(showDivider: true) {
                    HStack {
                        Text("Owner")
                            .font(SeeleTypography.body)
                            .foregroundStyle(SeeleColors.textSecondary)
                        Spacer()
                        HStack(spacing: SeeleSpacing.xs) {
                            // The "Owner" row title already speaks the role.
                            Image(systemName: "crown.fill")
                                .font(.system(size: SeeleSpacing.iconSizeXS))
                                .foregroundStyle(SeeleColors.warning)
                                .accessibilityHidden(true)
                            Text(owner)
                                .font(SeeleTypography.body)
                                .foregroundStyle(SeeleColors.textPrimary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }

            SeeleFormRow(showDivider: false) {
                HStack {
                    Text("Online")
                        .font(SeeleTypography.body)
                        .foregroundStyle(SeeleColors.textSecondary)
                    Spacer()
                    Text("\(room.userCount)")
                        .font(SeeleTypography.mono)
                        .foregroundStyle(SeeleColors.textPrimary)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    // MARK: - Ticker Section

    private var myTicker: String {
        chatState.myTicker(in: room.name)
    }

    private var tickerSection: some View {
        SeeleFormSection("TICKER") {
            SeeleFormRow(showDivider: !room.tickers.isEmpty) {
                HStack(spacing: SeeleSpacing.sm) {
                    TextField("Set your ticker...", text: $tickerText)
                        .textFieldStyle(.plain)
                        .font(SeeleTypography.body)
                        .foregroundStyle(SeeleColors.textPrimary)
                        .accessibilityLabel("Set your ticker")
                        .onSubmit(commitTicker)

                    // Compare trimmed, or trailing whitespace alone surfaces a
                    // "Set" button that commitTicker would no-op on.
                    if tickerText.trimmingCharacters(in: .whitespaces) != myTicker {
                        Button(action: commitTicker) {
                            Text("Set")
                                .font(SeeleTypography.caption)
                                .foregroundStyle(SeeleColors.accent)
                        }
                        .buttonStyle(.plain)
                    }

                    // Only reachable once a ticker exists on the server, so
                    // "Clear" never offers to remove something that isn't there.
                    if !myTicker.isEmpty {
                        Button {
                            chatState.clearTicker(room: room.name)
                            tickerText = ""
                        } label: {
                            Text("Clear")
                                .font(SeeleTypography.caption)
                                .foregroundStyle(SeeleColors.error)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Sorted: `tickers` is a Dictionary, so an unsorted ForEach
            // reshuffles the rows on every render. Matches the ordering the
            // ticker strip in ChatRoomContentView already uses.
            ForEach(room.tickers.sorted(by: { $0.key < $1.key }), id: \.key) { username, ticker in
                SeeleFormRow {
                    HStack {
                        Text(username)
                            .font(SeeleTypography.caption)
                            .foregroundStyle(SeeleColors.accent)
                        Text(ticker)
                            .font(SeeleTypography.caption)
                            .foregroundStyle(SeeleColors.textSecondary)
                            .lineLimit(1)
                        Spacer()
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Ticker from \(username): \(ticker)")
                    .accessibilityAddTraits(.isStaticText)
                }
            }
        }
    }

    private func commitTicker() {
        let text = tickerText.trimmingCharacters(in: .whitespaces)
        guard text != myTicker else { return }
        if text.isEmpty {
            chatState.clearTicker(room: room.name)
        } else {
            chatState.setTicker(room: room.name, text: text)
        }
    }

    // MARK: - Members Section

    private var membersSection: some View {
        SeeleFormSection("MEMBERS (\(room.members.count))") {
            // Add member field
            SeeleFormRow(showDivider: true) {
                HStack(spacing: SeeleSpacing.sm) {
                    TextField("Add member...", text: $newMemberName)
                        .textFieldStyle(.plain)
                        .font(SeeleTypography.body)
                        .foregroundStyle(SeeleColors.textPrimary)
                        .onSubmit {
                            addMember()
                        }
                        .accessibilityLabel("Add member")

                    if !newMemberName.isEmpty {
                        Button {
                            addMember()
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: SeeleSpacing.iconSizeSmall))
                                .foregroundStyle(SeeleColors.accent)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Add \(newMemberName) as member")
                    }
                }
            }

            ForEach(room.members.sorted(), id: \.self) { member in
                SeeleFormRow {
                    HStack {
                        Text(member)
                            .font(SeeleTypography.body)
                            .foregroundStyle(SeeleColors.textPrimary)

                        Spacer()

                        Button {
                            chatState.removeMember(room: room.name, username: member)
                        } label: {
                            Image(systemName: "minus.circle")
                                .font(.system(size: SeeleSpacing.iconSizeSmall))
                                .foregroundStyle(SeeleColors.error)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove member \(member)")
                    }
                }
            }
        }
    }

    // MARK: - Operators Section

    private var operatorsSection: some View {
        SeeleFormSection("OPERATORS (\(room.operators.count))") {
            // Add operator field
            SeeleFormRow(showDivider: true) {
                HStack(spacing: SeeleSpacing.sm) {
                    TextField("Add operator...", text: $newOperatorName)
                        .textFieldStyle(.plain)
                        .font(SeeleTypography.body)
                        .foregroundStyle(SeeleColors.textPrimary)
                        .onSubmit {
                            addOp()
                        }
                        .accessibilityLabel("Add operator")

                    if !newOperatorName.isEmpty {
                        Button {
                            addOp()
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: SeeleSpacing.iconSizeSmall))
                                .foregroundStyle(SeeleColors.accent)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Add \(newOperatorName) as operator")
                    }
                }
            }

            ForEach(room.operators.sorted(), id: \.self) { op in
                SeeleFormRow {
                    HStack {
                        HStack(spacing: SeeleSpacing.xs) {
                            // The section title already speaks the role.
                            Image(systemName: "wrench.fill")
                                .font(.system(size: SeeleSpacing.iconSizeXS))
                                .foregroundStyle(SeeleColors.textTertiary)
                                .accessibilityHidden(true)
                            Text(op)
                                .font(SeeleTypography.body)
                                .foregroundStyle(SeeleColors.textPrimary)
                        }

                        Spacer()

                        Button {
                            chatState.removeOperator(room: room.name, username: op)
                        } label: {
                            Image(systemName: "minus.circle")
                                .font(.system(size: SeeleSpacing.iconSizeSmall))
                                .foregroundStyle(SeeleColors.error)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove operator \(op)")
                    }
                }
            }
        }
    }

    // MARK: - Danger Section

    private var dangerSection: some View {
        SeeleFormSection("DANGER ZONE") {
            SeeleFormRow(showDivider: false) {
                Button {
                    showGiveUpConfirm = true
                } label: {
                    HStack {
                        Text("Give Up Ownership")
                            .font(SeeleTypography.body)
                            .foregroundStyle(SeeleColors.error)
                        Spacer()
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: SeeleSpacing.iconSizeSmall))
                            .foregroundStyle(SeeleColors.error)
                            .accessibilityHidden(true)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Helpers

    private func addMember() {
        let name = newMemberName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        chatState.addMember(room: room.name, username: name)
        newMemberName = ""
    }

    private func addOp() {
        let name = newOperatorName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        chatState.addOperator(room: room.name, username: name)
        newOperatorName = ""
    }
}
