import Foundation
import AppKit
import SwiftUI
import Combine
import Observation

// A stack: files dropped together (Tray.addFilesFromURLs gives them one stackID).
//   Fanned icons + "N files" name; dragging drags every file of the stack; double-click unstacks;
//   right-click → context menu (Unstack, Show in Finder, AirDrop, Remove from tray …).
//   Popovers from the notch window are unreliable, so the stack unstacks in place instead of
//   listing its files in a popover.
struct TrayStackView: View {
    var stackID: UUID
    var files: [TrayFile]
    var name: String
    var tray: Tray
    @StoredSetting(.traySettings) private var settings
    @State private var isHovering = false

    private var isSelected: Bool {
        !files.isEmpty && files.allSatisfy { f in tray.selectedFiles.contains { $0 === f } }
    }

    var body: some View {
        FileDraggableView(
            urls: files.map(\.url),
            onDropCompleted: { success in
                // not when they were dropped on the AirDrop zone (still being sent)
                if success && settings.removeAfterDraggingOut
                    && !AirDropZoneDrops.consume(files.map(\.url)) { tray.remove(files) }
            },
            onClick: { event in
                if event.clickCount >= 2 {
                    tray.unstack(stackID)
                } else {
                    tray.selectedFiles = files
                }
            },
            menu: { tray.contextMenu(for: files, stackID: stackID) },
            preview: { AnyView(TrayFilesGridPreviewView(files: files, size: 48)) }
        ) {
            // restyle (2026-10-20): same Finder-style tile as TrayFileView.
            VStack(spacing: 3) {
                TrayFilesGridPreviewView(files: files, size: 42)
                    .frame(width: 54, height: 54)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(isSelected ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.quinary.opacity(isHovering ? 1 : 0)))
                    )
                if settings.showLabels {
                    Text(name)
                        .font(.caption2)
                        .foregroundStyle(isSelected ? AnyShapeStyle(Color.white) : AnyShapeStyle(.primary))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Color.accentColor.opacity(isSelected ? 1 : 0))
                        )
                        .frame(height: 28, alignment: .top)
                }
            }
            .frame(width: 68)
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: name))
        }
        .foregroundStyle(.primary)
        .padding(2)
        .overlay(alignment: .topTrailing) {
            if isHovering {
                Button {
                    tray.remove(files)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(Color.black, Color.white.opacity(0.85))
                }
                .buttonStyle(ShrinkOnClick())
                .help(Text("Remove from tray"))
                .offset(x: 2, y: -2)
                .transition(.scale)
            }
        }
        .onHover { hovering in
            if isHovering != hovering { isHovering = hovering }
        }
        .animation(.snappy(duration: 0.15), value: isHovering)
        .transition(.scaleAndBlur)
    }
}
