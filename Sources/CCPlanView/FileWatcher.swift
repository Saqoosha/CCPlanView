import Dispatch
import Foundation
import os

@MainActor
final class FileWatcher {
    private var source: DispatchSourceFileSystemObject?
    private var debounceWorkItem: DispatchWorkItem?
    private var pollTimer: DispatchSourceTimer?
    private let fileURL: URL
    private let onChange: () -> Void
    private let logger = Logger(subsystem: "sh.saqoo.ccplanview", category: "FileWatcher")
    private var lastModificationDate: Date?
    private var lastFileSize: Int64?
    private var needsRewatch = false

    init(fileURL: URL, onChange: @escaping () -> Void) {
        self.fileURL = fileURL
        self.onChange = onChange
        let attrs = getFileAttributes()
        self.lastModificationDate = attrs.modDate
        self.lastFileSize = attrs.size
        startWatching()
        startPolling()
    }

    private func getFileAttributes() -> (modDate: Date?, size: Int64?) {
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            let modDate = attrs[.modificationDate] as? Date
            let size = (attrs[.size] as? NSNumber)?.int64Value
            return (modDate, size)
        } catch {
            // .info so the failure shows up in `log stream` at default level;
            // a file we're actively watching becoming unreadable is a real
            // signal, not debug noise.
            logger.info(
                "Cannot read file attributes: \(self.fileURL.path, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            return (nil, nil)
        }
    }

    private func startWatching() {
        let fd = open(fileURL.path, O_EVTONLY)
        guard fd >= 0 else {
            let errnoMessage = String(cString: strerror(errno))
            // The 2s poll timer is still running so changes are still detectable,
            // just at poll latency instead of kqueue latency. Call that out so a
            // future maintainer reading logs doesn't conclude the watcher is dead.
            logger.error(
                "kqueue unavailable for \(self.fileURL.path, privacy: .public) (errno \(errno): \(errnoMessage, privacy: .public)) — continuing with 2s poll fallback only."
            )
            return
        }
        setupSource(fd: fd)
    }

    private func setupSource(fd: Int32) {
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
                let errnoMessage = String(cString: strerror(errno))
                logger.error(
                    "kqueue rewatch failed after 5 retries for \(self.fileURL.path, privacy: .public) (errno \(errno): \(errnoMessage, privacy: .public)) — continuing with 2s poll fallback only."
                )
            }
            return
        }
        // Use this fd directly instead of closing and reopening — the file can
        // disappear between the two opens during atomic saves, leaving the
        // watcher unset.
        setupSource(fd: fd)
        // Catch any change that landed between the cancel and the new fd —
        // kqueue cannot deliver events during that window.
        checkForChanges()
    }

    private func checkForChanges() {
        let attrs = getFileAttributes()
        // Compare both modification date and file size. Mod date alone misses
        // tools that preserve mtime while changing content (touch -t, scripted
        // restores) — size catches those.
        if attrs.modDate != lastModificationDate || attrs.size != lastFileSize {
            lastModificationDate = attrs.modDate
            lastFileSize = attrs.size
            onChange()
        }
    }

    // Polling fallback for kqueue events that get dropped or coalesced — e.g.
    // changes landing while restartWatching is between fds, or multiple writes
    // within the kqueue debounce window that share an mtime. 2-second cadence
    // balances responsiveness against wakeups.
    //
    // The timer MUST stay on .main because the event handler uses
    // MainActor.assumeIsolated to call checkForChanges() without an actor hop.
    private func startPolling() {
        pollTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 2, repeating: 2)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            MainActor.assumeIsolated {
                self.checkForChanges()
            }
        }
        timer.resume()
        pollTimer = timer
    }

    func stop() {
        source?.cancel()
        source = nil
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
        pollTimer?.cancel()
        pollTimer = nil
    }

    deinit {
        source?.cancel()
        pollTimer?.cancel()
    }
}
