import MindMapPersistence
import SwiftUI

extension CloudSyncState {
    /// A few words, for the status line and the Settings row.
    var title: String {
        switch self {
        case .upToDate: String(localized: "Up to Date")
        case .syncing: String(localized: "Syncing…")
        case .waitingForNetwork: String(localized: "Waiting for Network")
        case .notSignedIn: String(localized: "Not Using iCloud")
        case .restricted: String(localized: "iCloud Is Restricted")
        case .accountNeedsAttention: String(localized: "iCloud Needs Attention")
        case .off: String(localized: "Off")
        case .unavailable: String(localized: "Not Available")
        case .error(.quotaExceeded): String(localized: "iCloud Storage Is Full")
        case .error: String(localized: "Couldn’t Sync")
        }
    }

    /// What it means and what to do, if anything. Every state that is not
    /// syncing says the maps are still on this device: nothing is lost.
    var detail: String {
        switch self {
        case .upToDate, .syncing:
            String(localized: "Your maps are on this device and in your private iCloud, and follow you to your other devices.")
        case .waitingForNetwork:
            String(localized: "Changes stay on this device and sync when you’re back online.")
        case .notSignedIn:
            #if os(macOS)
            String(localized: "Sign in to iCloud in System Settings to sync your maps between your devices. Your maps stay on this device.")
            #else
            String(localized: "Sign in to iCloud, or turn on iCloud for MindMap AI, in Settings to sync your maps between your devices. Your maps stay on this device.")
            #endif
        case .restricted:
            String(localized: "Screen Time or device management keeps MindMap AI out of iCloud. Your maps stay on this device.")
        case .accountNeedsAttention:
            #if os(macOS)
            String(localized: "Open your Apple Account in System Settings to continue syncing. Your maps stay on this device.")
            #else
            String(localized: "Open your Apple Account in Settings to continue syncing. Your maps stay on this device.")
            #endif
        case .off:
            String(localized: "Your maps stay on this device only.")
        case .unavailable:
            String(localized: "This build of MindMap AI can’t use iCloud. Your maps stay on this device.")
        case .error(.quotaExceeded):
            String(localized: "Free up iCloud storage or choose a larger plan. Your maps stay on this device until there’s room.")
        case .error:
            String(localized: "Your maps stay on this device. MindMap AI tries again later.")
        }
    }

    var systemImage: String {
        switch self {
        case .upToDate: "checkmark.icloud"
        case .syncing: "arrow.clockwise.icloud"
        case .waitingForNetwork: "icloud.slash"
        case .error: "exclamationmark.icloud"
        case .off, .unavailable, .notSignedIn, .restricted, .accountNeedsAttention: "icloud.slash"
        }
    }
}

/// iCloud in Settings (FR-SET-04, FR-SYN-03, FR-SYN-06). On the Mac, which
/// has no per-app iCloud switch for CloudKit apps, a switch; on iPad and
/// iPhone the system's per-app iCloud switch is the one place to turn it off
/// (HIG Settings: no copies of system settings), so the status only.
struct CloudSyncSettingsSection: View {
    @Environment(CloudSyncMonitor.self) private var sync

    var body: some View {
        Section {
            #if os(macOS)
            Toggle("iCloud Sync", isOn: Binding(get: { sync.isEnabled }, set: { sync.setEnabled($0) }))
                .disabled(!CloudSyncMonitor.isBuildEntitled)
                .accessibilityIdentifier(AccessibilityID.Settings.iCloudSync)
            #endif
            LabeledContent("Status") {
                Label(sync.state.title, systemImage: sync.state.systemImage)
            }
            .accessibilityIdentifier(AccessibilityID.Settings.iCloudStatus)
        } header: {
            Text("iCloud")
        } footer: {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(sync.state.detail)
                if sync.needsRelaunch {
                    Text("Quit and reopen MindMap AI to apply this change.")
                }
            }
        }
    }
}

/// One small line under the library while something is happening: syncing,
/// waiting for the network, or a failure. Up to date says nothing (FR-SYN-03).
struct CloudSyncStatusLine: View {
    @Environment(CloudSyncMonitor.self) private var sync

    var body: some View {
        let state = sync.state
        if state.isWorthShowing {
            Label(state.title, systemImage: state.systemImage)
                .font(Typography.statusLine)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.sm)
                .help(state.detail)
                .accessibilityElement(children: .combine)
                .accessibilityHint(state.detail)
                .accessibilityIdentifier(AccessibilityID.Sidebar.syncStatus)
        }
    }
}
