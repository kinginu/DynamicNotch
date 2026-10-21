import Foundation
import AppKit
import SwiftUI
import Combine
import Observation

// Row for one file of a stack (icon, name, remove button; draggable). Kept for
//   API completeness; the stack tile unstacks instead of listing rows in a popover.
struct TrayStackFileRowView: View {
    var file: TrayFile
    var onRemove: () -> Void
    @State private var isHovering: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            FileDraggableView(urls: [file.url]) {
                TrayFileIconView(file: file)
                    .frame(width: 32, height: 32)
            }
            Text(file.name)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(ShrinkOnClick())
            .help(Text("Remove from tray"))
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.nonShockingWhite.opacity(isHovering ? 0.085 : 0.0))
        )
        .onHover { isHovering = $0 }
    }
}
