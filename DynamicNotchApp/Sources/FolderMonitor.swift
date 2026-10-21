// FolderMonitor — calls back (on the main actor) when the contents of a folder change: a vnode
// dispatch source on the folder's descriptor, delivered on the main queue. Used by Tray to prune
// items whose file disappeared.
import Foundation

final class FolderMonitor {
    private let monitoredPath: String
    private var source: DispatchSourceFileSystemObject?

    init(path: String, callback: @escaping @MainActor @Sendable () -> Void) {
        self.monitoredPath = path
        startMonitoring(callback)
    }

    deinit {
        stopMonitoring()
    }

    private func startMonitoring(_ callback: @escaping @MainActor @Sendable () -> Void) {
        let fileDescriptor = open(monitoredPath, O_EVTONLY)
        guard fileDescriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fileDescriptor,
                                                               eventMask: [.write, .delete, .rename, .extend],
                                                               queue: .main)
        source.setEventHandler {
            MainActor.assumeIsolated { callback() }
        }
        source.setCancelHandler {
            close(fileDescriptor)
        }
        source.resume()
        self.source = source
    }

    func stopMonitoring() {
        source?.cancel()
        source = nil
    }
}
