import Dispatch
import Foundation
import os

@MainActor
final class FileWatcher {
    private var source: DispatchSourceFileSystemObject?
    private var debounceWorkItem: DispatchWorkItem?
    private let fileURL: URL
    private let onChange: () -> Void
    private let logger = Logger(subsystem: "sh.saqoo.ccplanview", category: "FileWatcher")
    private var lastModificationDate: Date?

    init(fileURL: URL, onChange: @escaping () -> Void) {
        self.fileURL = fileURL
        self.onChange = onChange
        self.lastModificationDate = getModificationDate()
        startWatching()
    }

    private func getModificationDate() -> Date? {
        try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.modificationDate] as? Date
    }

    private func startWatching() {
        let fd = open(fileURL.path, O_EVTONLY)
        guard fd >= 0 else {
            logger.error("Failed to open file for watching: \(self.fileURL.path, privacy: .public)")
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .attrib],
            queue: .main
        )

        source.setEventHandler { [weak self] in
            guard let self else { return }
            debounceWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                self?.checkForChanges()
            }
            debounceWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: workItem)
        }

        source.setCancelHandler {
            close(fd)
        }

        source.resume()
        self.source = source
    }

    private func checkForChanges() {
        let currentModDate = getModificationDate()
        if currentModDate != lastModificationDate {
            lastModificationDate = currentModDate
            onChange()
        }
    }

    func stop() {
        source?.cancel()
        source = nil
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
    }

    deinit {
        source?.cancel()
    }
}
