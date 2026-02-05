import SwiftUI

/// Reusable download status icon that shows the current state of a file transfer.
/// Used consistently across Search, Browse, and Transfers views.
struct DownloadStatusIcon: View {
    let status: Transfer.TransferStatus?
    var size: CGFloat = SeeleSpacing.iconSizeMedium
    var isHovered: Bool = false

    var body: some View {
        switch status {
        case .transferring:
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: size))
                .foregroundStyle(SeeleColors.accent)
                .symbolEffect(.pulse)
        case .queued, .waiting, .connecting:
            Image(systemName: "clock.fill")
                .font(.system(size: size))
                .foregroundStyle(SeeleColors.warning)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: size))
                .foregroundStyle(SeeleColors.success)
        case .failed, .cancelled, nil:
            Image(systemName: "arrow.down.circle")
                .font(.system(size: size))
                .foregroundStyle(isHovered ? SeeleColors.accent : SeeleColors.textSecondary)
        }
    }

    /// Returns appropriate help text for the current status
    var helpText: String {
        switch status {
        case .transferring:
            return "Downloading..."
        case .queued, .waiting:
            return "Queued for download"
        case .connecting:
            return "Connecting..."
        case .completed:
            return "Download complete"
        case .failed:
            return "Download failed - click to retry"
        case .cancelled:
            return "Download cancelled - click to retry"
        case nil:
            return "Download file"
        }
    }

    /// Whether the download is currently in progress (queued, connecting, or transferring)
    var isInProgress: Bool {
        switch status {
        case .transferring, .queued, .waiting, .connecting:
            return true
        default:
            return false
        }
    }
}

#Preview {
    VStack(spacing: SeeleSpacing.lg) {
        HStack(spacing: SeeleSpacing.xl) {
            VStack {
                DownloadStatusIcon(status: nil)
                Text("nil").font(SeeleTypography.caption)
            }
            VStack {
                DownloadStatusIcon(status: .queued)
                Text("queued").font(SeeleTypography.caption)
            }
            VStack {
                DownloadStatusIcon(status: .connecting)
                Text("connecting").font(SeeleTypography.caption)
            }
            VStack {
                DownloadStatusIcon(status: .transferring)
                Text("transferring").font(SeeleTypography.caption)
            }
            VStack {
                DownloadStatusIcon(status: .completed)
                Text("completed").font(SeeleTypography.caption)
            }
            VStack {
                DownloadStatusIcon(status: .failed)
                Text("failed").font(SeeleTypography.caption)
            }
        }
        .foregroundStyle(SeeleColors.textSecondary)
    }
    .padding()
    .background(SeeleColors.background)
}
