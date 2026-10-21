import Foundation
import AppKit
import SwiftUI
import Combine
import Observation

// One tray file tile: icon (QuickLook thumbnail) + name, selection highlight,
//   hover remove button. The AppKit drag source in front of the tile drags the file (or the whole
//   selection when the file is selected) to other apps, and handles clicks: click = select
//   (⌘/⇧ extend, Tray.selectFile), double-click = open, right-click = context menu. Rename edits
//   the name in place (Return commits, Esc cancels).
struct TrayFileView: View {
    var file: TrayFile
    var tray: Tray
    @StoredSetting(.traySettings) private var settings
    @State private var isHovering = false
    @FocusState private var nameFocused: Bool

    private var isSelected: Bool { tray.selectedFiles.contains { $0 === file } }
    private var isEditing: Bool { tray.editingFile?.file === file }
    private var dragTargets: [TrayFile] { tray.actionTargets(for: file) }

    var body: some View {
        VStack(spacing: 4) {
            FileDraggableView(
                urls: dragTargets.map(\.url),
                onDropCompleted: { success in
                    // not when they were dropped on the AirDrop zone (still being sent)
                    if success && settings.removeAfterDraggingOut
                        && !AirDropZoneDrops.consume(dragTargets.map(\.url)) { tray.remove(dragTargets) }
                },
                onClick: { event in
                    if event.clickCount >= 2 {
                        tray.open(tray.actionTargets(for: file))
                    } else {
                        tray.selectFile(file)
                    }
                },
                menu: { tray.contextMenu(for: tray.actionTargets(for: file)) },
                preview: { AnyView(TrayFileDragPreviewView(file: file, count: tray.actionTargets(for: file).count)) }
            ) {
                // restyle (2026-10-20): Finder-style tile — 48 pt icon on a
                //   quaternary rounded backing when selected, name in caption2 on an accent capsule
                //   when selected (white text), secondary otherwise.
                VStack(spacing: 3) {
                    TrayFileIconView(file: file)
                        .frame(width: 48, height: 48)
                        .padding(3)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(isSelected ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.quinary.opacity(isHovering ? 1 : 0)))
                        )
                    if settings.showLabels && !isEditing {
                        Text(file.nameTruncated)
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
                .accessibilityLabel(Text(verbatim: file.name))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
            if isEditing {
                TextField("", text: Binding(
                    get: { tray.editingFile?.newName ?? file.name },
                    set: { tray.editingFile = (file: file, newName: $0) }))
                    .textFieldStyle(.plain)
                    .font(.system(size: 10, weight: .medium))
                    .multilineTextAlignment(.center)
                    .frame(width: 68)
                    .background(RoundedRectangle(cornerRadius: 3).fill(Color.black.opacity(0.6)))
                    .focused($nameFocused)
                    .onSubmit { tray.rename() }
                    .onExitCommand { tray.editingFile = nil }
                    .onAppear {
                        NSApp.activate(ignoringOtherApps: true)
                        nameFocused = true
                    }
            }
        }
        .foregroundStyle(.primary)
        .padding(2)
        .overlay(alignment: .topTrailing) {
            if isHovering && !isEditing {
                Button {
                    tray.removeFile(file)
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

    var selectedFiles: [TrayFile] { tray.selectedFiles }
}
