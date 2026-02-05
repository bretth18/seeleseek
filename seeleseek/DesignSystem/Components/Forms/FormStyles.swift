import SwiftUI

// MARK: - Text Field Style

/// Standard text field style for the Seele design system
struct SeeleTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<_Label>) -> some View {
        configuration
            .padding(.horizontal, SeeleSpacing.md)
            .padding(.vertical, SeeleSpacing.sm + 2)
            .background(SeeleColors.surfaceSecondary)
            .foregroundStyle(SeeleColors.textPrimary)
            .clipShape(RoundedRectangle(cornerRadius: SeeleSpacing.radiusMD, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: SeeleSpacing.radiusMD, style: .continuous)
                    .stroke(SeeleColors.border, lineWidth: SeeleSpacing.strokeThin)
            )
    }
}

// MARK: - Toggle Style

/// Standard toggle style matching macOS design with Seele theming
struct SeeleToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label

            Spacer()

            ZStack {
                RoundedRectangle(cornerRadius: SeeleSpacing.toggleCornerRadius)
                    .fill(configuration.isOn ? SeeleColors.accent : SeeleColors.surfaceElevated)
                    .frame(width: SeeleSpacing.toggleWidth, height: SeeleSpacing.toggleHeight)
                    .overlay(
                        RoundedRectangle(cornerRadius: SeeleSpacing.toggleCornerRadius)
                            .stroke(configuration.isOn ? SeeleColors.accent : SeeleColors.border, lineWidth: SeeleSpacing.strokeThin)
                    )

                Circle()
                    .fill(SeeleColors.textOnAccent)
                    .shadow(color: SeeleColors.shadowColor, radius: 2, x: 0, y: 1)
                    .frame(width: SeeleSpacing.toggleKnobSize, height: SeeleSpacing.toggleKnobSize)
                    .offset(x: configuration.isOn ? SeeleSpacing.toggleKnobOffset : -SeeleSpacing.toggleKnobOffset)
            }
            .onTapGesture {
                withAnimation(.easeInOut(duration: SeeleSpacing.animationFast)) {
                    configuration.isOn.toggle()
                }
            }
        }
    }
}

// MARK: - Form Section

/// Grouped form section with title and bordered content
struct SeeleFormSection<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SeeleSpacing.sm) {
            Text(title)
                .font(SeeleTypography.caption)
                .fontWeight(.medium)
                .foregroundStyle(SeeleColors.textTertiary)
                .textCase(.uppercase)
                .tracking(SeeleSpacing.trackingWide)

            VStack(spacing: 0) {
                content
            }
            .background(SeeleColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: SeeleSpacing.radiusMD, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: SeeleSpacing.radiusMD, style: .continuous)
                    .stroke(SeeleColors.border, lineWidth: SeeleSpacing.strokeThin)
            )
        }
    }
}

// MARK: - Form Row

/// Standard row within a form section with optional divider
struct SeeleFormRow<Content: View>: View {
    let content: Content
    let showDivider: Bool

    init(showDivider: Bool = true, @ViewBuilder content: () -> Content) {
        self.showDivider = showDivider
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            content
                .padding(.horizontal, SeeleSpacing.md)
                .padding(.vertical, SeeleSpacing.sm + 2)

            if showDivider {
                Divider()
                    .background(SeeleColors.border)
                    .padding(.leading, SeeleSpacing.md)
            }
        }
    }
}

// MARK: - Previews

#Preview("Text Field") {
    VStack(spacing: SeeleSpacing.lg) {
        TextField("Username", text: .constant(""))
            .textFieldStyle(SeeleTextFieldStyle())

        TextField("Email", text: .constant("user@example.com"))
            .textFieldStyle(SeeleTextFieldStyle())
    }
    .padding()
    .background(SeeleColors.background)
}

#Preview("Toggle") {
    VStack(spacing: SeeleSpacing.lg) {
        Toggle("Remember me", isOn: .constant(true))
            .toggleStyle(SeeleToggleStyle())

        Toggle("Auto-connect", isOn: .constant(false))
            .toggleStyle(SeeleToggleStyle())
    }
    .padding()
    .background(SeeleColors.background)
}

#Preview("Form Section") {
    SeeleFormSection("Account Settings") {
        SeeleFormRow {
            HStack {
                Text("Username")
                Spacer()
                Text("john_doe")
                    .foregroundStyle(SeeleColors.textSecondary)
            }
        }
        SeeleFormRow {
            HStack {
                Text("Email")
                Spacer()
                Text("john@example.com")
                    .foregroundStyle(SeeleColors.textSecondary)
            }
        }
        SeeleFormRow(showDivider: false) {
            HStack {
                Text("Notifications")
                Spacer()
                Toggle("", isOn: .constant(true))
                    .toggleStyle(SeeleToggleStyle())
            }
        }
    }
    .padding()
    .background(SeeleColors.background)
}
