import Foundation
import AppKit
import SwiftUI
import Combine
import Observation

// The open tray: header (file count, Quick Look / AirDrop / Show in Finder /
//   Clear) above a horizontal strip of tiles (files and stacks, in tray order). Clicking the
//   empty area clears the selection.
//   2026-10-20: TrayView puts this in the left column next to the AirDrop zone, which replaces the
//   header's AirDrop button (`showsAirDropButton` is false while the zone is shown).
struct TrayFilesScrollView: View {
    var tray: Tray
    var showsAirDropButton: Bool = true

    private var targets: [TrayFile] { tray.selectedFiles.isEmpty ? tray.files : tray.selectedFiles }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // restyle (2026-10-20): secondary caption title + count, round glass
            //   action buttons (NookRoundIconButton), Finder-style tiles below.
            HStack(spacing: 6) {
                Text("Files Tray")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityAddTraits(.isHeader)
                TrayFilesCountView(count: tray.files.count)
                    .foregroundStyle(.tertiary)
                Spacer()
                headerButton("eye", help: "Quick Look") {
                    TrayQuickLookSource.shared.show(targets.map(\.url))
                }
                if showsAirDropButton {
                    headerButton("antenna.radiowaves.left.and.right", help: "Send via AirDrop") {
                        tray.airDrop(targets)
                    }
                }
                headerButton("folder", help: "Show in Finder") {
                    tray.revealInFinder(targets)
                }
                headerButton("trash", help: "Clear Tray") {
                    tray.removeAll()
                }
            }
            .padding(.horizontal, 4)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 6) {
                    ForEach(tray.trayItems) { item in
                        switch item {
                        case .file(let file):
                            TrayFileView(file: file, tray: tray)
                        case .stack(let id, let files, let name):
                            TrayStackView(stackID: id, files: files, name: name, tray: tray)
                        }
                    }
                }
                .padding(.horizontal, 2)
                .padding(.top, 2)
            }
            .background(
                Color.black.opacity(0.001)
                    .onTapGesture { tray.selectFile(nil) }
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.top, 2)
    }

    private func headerButton(_ systemImage: String, help: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        NookRoundIconButton(systemImage: systemImage, label: Text(help), diameter: 24, action: action)
    }
}
