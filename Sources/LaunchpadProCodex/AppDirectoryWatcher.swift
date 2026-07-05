import Foundation

final class AppDirectoryWatcher {
    private struct Watch {
        let source: DispatchSourceFileSystemObject
    }

    private let queue = DispatchQueue(label: "com.leo.launchpadpro.app-directory-watcher")
    private let onChange: @MainActor () -> Void
    private var watches: [Watch] = []
    private var debounceWorkItem: DispatchWorkItem?

    init(onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
    }

    deinit {
        stop()
    }

    func start(watching urls: [URL]) {
        stop()

        for url in urls where isDirectory(url) {
            let descriptor = open(url.path, O_EVTONLY)
            guard descriptor >= 0 else { continue }

            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor,
                eventMask: [.write, .rename, .delete, .attrib],
                queue: queue
            )

            source.setEventHandler { [weak self] in
                self?.scheduleReload()
            }
            source.setCancelHandler {
                close(descriptor)
            }
            source.resume()
            watches.append(Watch(source: source))
        }
    }

    func stop() {
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
        watches.forEach { $0.source.cancel() }
        watches.removeAll()
    }

    private func scheduleReload() {
        debounceWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                self.onChange()
            }
        }
        debounceWorkItem = workItem
        queue.asyncAfter(deadline: .now() + 0.8, execute: workItem)
    }

    private func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}
