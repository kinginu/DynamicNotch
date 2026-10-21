// About pane: app icon, version, licence line and the open-source components used.
import SwiftUI
import AppKit

private struct OSSLicense: Identifiable {
    let name: String
    let license: String
    let url: String
    var id: String { name }
}

private let ossLicenses: [OSSLicense] = [
    // The resolved checkout contains no LICENSE file.
    .init(name: "mediaremote-adapter", license: NSLocalizedString("See repository", comment: "About: license unknown"),
          url: "https://github.com/ejbills/mediaremote-adapter"),
]

private func sysctlString(_ name: String) -> String {
    var size = 0
    guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return "?" }
    var buf = [CChar](repeating: 0, count: size)
    guard sysctlbyname(name, &buf, &size, nil, 0) == 0 else { return "?" }
    return String(cString: buf)
}

struct AboutSettingsView: View {
    private let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    private let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
    private let model = sysctlString("hw.model")
    private let chip = sysctlString("machdep.cpu.brand_string")
    private let macOS = ProcessInfo.processInfo.operatingSystemVersionString
    private let helperInstalled: Bool = {
        let fm = FileManager.default
        return fm.fileExists(atPath: "/Library/LaunchDaemons/com.example.dynamicnotch.DynamicNotch.fanfi.plist")
            && fm.fileExists(atPath: "/Library/PrivilegedHelperTools/com.example.dynamicnotch.DynamicNotch.fanfi")
    }()
    @State private var copied = false

    private var helperText: String {
        helperInstalled
            ? NSLocalizedString("Installed (manual)", comment: "About: helper state")
            : NSLocalizedString("Not installed", comment: "About: helper state")
    }

    private var diagnostics: String {
        """
        DynamicNotch \(version) (\(build))
        Model: \(model)
        Chip: \(chip)
        macOS: \(macOS)
        Fan Control helper installed: \(helperInstalled ? "yes" : "no")
        """
    }

    var body: some View {
        SettingsForm {
            Section {
                HStack(spacing: 16) {
                    Image(nsImage: NSApp.applicationIconImage ?? NSImage())
                        .resizable().frame(width: 72, height: 72)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(verbatim: "DynamicNotch").font(.title.bold())
                        Text(String(format: NSLocalizedString("Version %@ (%@)", comment: "About"), version, build))
                            .foregroundStyle(.secondary)
                        Text("Open source under the MIT License.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
            }

            Section {
                row("Mac", model)
                row("Chip", chip)
                row("macOS", macOS)
                row(NSLocalizedString("Fan Control helper", comment: "About"), helperText)
                Button(copied ? NSLocalizedString("Copied", comment: "About") : NSLocalizedString("Copy Diagnostics", comment: "About")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(diagnostics, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
                }
            }

            Section {
                ForEach(ossLicenses) { dep in
                    LabeledContent {
                        HStack(spacing: 12) {
                            Text(verbatim: dep.license).foregroundStyle(.secondary)
                            if let u = URL(string: dep.url) {
                                Link(dep.url.replacingOccurrences(of: "https://", with: ""), destination: u)
                                    .lineLimit(1)
                            }
                        }
                    } label: {
                        Text(verbatim: dep.name)
                    }
                }
            } header: {
                Text("Open Source Licenses")
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        LabeledContent {
            Text(verbatim: value).textSelection(.enabled)
        } label: {
            Text(verbatim: label)
        }
    }
}
