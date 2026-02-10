import SwiftUI
import AppKit

// MARK: - Private Chat Content View

struct PrivateChatContentView: View {
    let chat: PrivateChat
    @Bindable var chatState: ChatState
    var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Circle()
                    .fill(chat.isOnline ? SeeleColors.success : SeeleColors.textTertiary)
                    .frame(width: SeeleSpacing.statusDot, height: SeeleSpacing.statusDot)

                Text(chat.username)
                    .font(SeeleTypography.headline)
                    .foregroundStyle(SeeleColors.textPrimary)

                Spacer()

                Button {
                    chatState.closePrivateChat(chat.username)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: SeeleSpacing.iconSizeXS))
                        .foregroundStyle(SeeleColors.textSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(SeeleSpacing.md)
            .background(SeeleColors.surface)

            Divider().background(SeeleColors.surfaceSecondary)

            ScrollView {
                LazyVStack(spacing: SeeleSpacing.sm) {
                    ForEach(chat.messages) { message in
                        MessageBubble(message: message, chatState: chatState, appState: appState)
                    }
                }
                .padding(SeeleSpacing.md)
            }

            Divider().background(SeeleColors.surfaceSecondary)

            MessageInput(text: $chatState.messageInput) {
                chatState.sendMessage()
            }
        }
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: ChatMessage
    var chatState: ChatState
    var appState: AppState

    var body: some View {
        HStack(alignment: .top, spacing: SeeleSpacing.sm) {
            if message.isOwn {
                Spacer()
            }

            VStack(alignment: message.isOwn ? .trailing : .leading, spacing: SeeleSpacing.xxs) {
                if !message.isOwn && !message.isSystem {
                    Text(message.username)
                        .font(SeeleTypography.caption)
                        .foregroundStyle(SeeleColors.accent)
                }

                Text(message.content)
                    .font(SeeleTypography.body)
                    .foregroundStyle(message.isSystem ? SeeleColors.textTertiary : SeeleColors.textPrimary)
                    .padding(.horizontal, SeeleSpacing.md)
                    .padding(.vertical, SeeleSpacing.sm)
                    .background(
                        message.isOwn ? SeeleColors.accent.opacity(0.2) :
                        message.isSystem ? .clear : SeeleColors.surface
                    )
                    .clipShape(RoundedRectangle(cornerRadius: SeeleSpacing.radiusMD, style: .continuous))
                    .contextMenu {
                        if !message.isSystem {
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(message.content, forType: .string)
                            } label: {
                                Label("Copy Message", systemImage: "doc.on.doc")
                            }

                            if !message.isOwn {
                                Button {
                                    chatState.messageInput = "@\(message.username) "
                                } label: {
                                    Label("Reply", systemImage: "arrowshape.turn.up.left")
                                }

                                Divider()

                                Button {
                                    Task { await appState.socialState.loadProfile(for: message.username) }
                                } label: {
                                    Label("View Profile", systemImage: "person.crop.circle")
                                }

                                Button {
                                    chatState.selectPrivateChat(message.username)
                                } label: {
                                    Label("Send Message", systemImage: "envelope")
                                }

                                Button {
                                    appState.browseState.browseUser(message.username)
                                } label: {
                                    Label("Browse Files", systemImage: "folder")
                                }
                            }
                        }
                    }

                Text(message.formattedTime)
                    .font(SeeleTypography.caption2)
                    .foregroundStyle(SeeleColors.textTertiary)
            }

            if !message.isOwn {
                Spacer()
            }
        }
    }
}

// MARK: - Message Input

struct MessageInput: View {
    @Binding var text: String
    let onSend: () -> Void

    private static let maxLength = 2000

    var body: some View {
        VStack(spacing: 0) {
            if text.count > 1500 {
                HStack {
                    Spacer()
                    Text("\(text.count)/\(Self.maxLength)")
                        .font(SeeleTypography.caption2)
                        .foregroundStyle(text.count > 1900 ? SeeleColors.error : SeeleColors.warning)
                }
                .padding(.horizontal, SeeleSpacing.md)
                .padding(.top, SeeleSpacing.xs)
            }

            HStack(spacing: SeeleSpacing.sm) {
                TextField("Type a message...", text: $text)
                    .textFieldStyle(.plain)
                    .font(SeeleTypography.body)
                    .foregroundStyle(SeeleColors.textPrimary)
                    .onSubmit {
                        if !text.trimmingCharacters(in: .whitespaces).isEmpty {
                            onSend()
                        }
                    }

                Button(action: onSend) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: SeeleSpacing.iconSizeLarge))
                        .foregroundStyle(
                            text.trimmingCharacters(in: .whitespaces).isEmpty ?
                            SeeleColors.textTertiary : SeeleColors.accent
                        )
                }
                .buttonStyle(.plain)
                .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(SeeleSpacing.md)
        }
        .background(SeeleColors.surface)
    }
}
