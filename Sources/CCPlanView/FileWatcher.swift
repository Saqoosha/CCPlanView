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
    private var needsRewatch = false

    init(fileURL: URL, onChange: @escaping () -> Void) {
        self.fileURL = fileURL
        self.onChange = onChange
        self.lastModificationDate = getModificationDate()
        startWatching()
    }

    private func getModificationDate() -> Date? {
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            return attrs[.modificationDate] as? Date
        } catch {
            logger.debug(
                "Cannot read modification date: \(self.fileURL.path, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
    }

    private func startWatching() {
        let fd = open(fileURL.path, O_EVTONLY)
        guard fd >= 0 else {
            logger.error("Failed to open file for watching: \(self.fileURL.path, privacy: .public)")
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .attrib, .delete, .rename],
            queue: .main
        )

        source.setEventHandler { [weak self] in
            guard let self else { return }
            let flags = self.source?.data ?? []
            if flags.contains(.delete) || flags.contains(.rename) {
                self.needsRewatch = true
            }
            self.debounceWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                guard let self, self.source != nil else { return }
                self.checkForChanges()
                if self.needsRewatch {
                    self.needsRewatch = false
                    self.restartWatching()
                }
            }
            self.debounceWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: workItem)
        }

        source.setCancelHandler {
            close(fd)
        }

        source.resume()
        self.source = source
    }

    private func restartWatching(retryCount: Int = 0) {
        source?.cancel()
        source = nil

        let fd = open(fileURL.path, O_EVTONLY)
        if fd < 0 {
            if retryCount < 5 {
                logger.warning(
                    "File not yet available, retry \(retryCount + 1)/5: \(self.fileURL.path, privacy: .public)"
                )
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                    self?.restartWatching(retryCount: retryCount + 1)
                }
            } else {
                logger.error(
                    "Failed to restart watching after 5 retries: \(self.fileURL.path, privacy: .public)"
                )
            }
            return
        }
        close(fd)
        startWatching()
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
