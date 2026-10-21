// NookModelContainer — the SwiftData container of the Notes widget (`Note`; to-dos live in Apple
// Reminders), and the `.nookModelContainer()` view modifier that attaches it.
import Foundation
import SwiftData
import SwiftUI
import os

private let logger = Logger(subsystem: "com.example.dynamicnotch.DynamicNotch", category: "notes")

/// `NSAttributedStringTransformer` must be registered before the schema is built (`Note.richText`
/// is `.transformable(by:)`); without a container the widgets' `@Query` traps. Falls back to an
/// in-memory store, then to nil (views without data).
enum NookModelContainer {
    /// `~/Library/Application Support/<bundle id>/Nook.store`. SwiftData's default
    /// (`Application Support/default.store`) is shared by every app — and every development
    /// instance (…DynamicNotch.dev-*) — that uses the default name.
    static var storeURL: URL {
        let fileManager = FileManager.default
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        let base = support.appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.example.dynamicnotch.DynamicNotch",
                                                  isDirectory: true)
        do {
            try fileManager.createDirectory(at: base, withIntermediateDirectories: true)
        } catch {
            logger.error("could not create \(base.path, privacy: .public): \(String(describing: error), privacy: .public)")
        }
        return base.appendingPathComponent("Nook.store")
    }

    static let shared: ModelContainer? = {
        ValueTransformer.setValueTransformer(NSAttributedStringTransformer(),
                                             forName: NSAttributedStringTransformer.name)
        let schema = Schema([Note.self])
        do {
            return try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: storeURL))
        } catch {
            logger.error("ModelContainer (on disk) failed, using an in-memory store: \(String(describing: error), privacy: .public)")
        }
        do {
            return try ModelContainer(for: schema,
                                      configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        } catch {
            logger.fault("ModelContainer (in memory) failed, notes are unavailable: \(String(describing: error), privacy: .public)")
            return nil
        }
    }()
}

extension View {
    /// Attaches `NookModelContainer.shared` when it could be created.
    @ViewBuilder func nookModelContainer() -> some View {
        if let container = NookModelContainer.shared {
            self.modelContainer(container)
        } else {
            self
        }
    }
}
