import Foundation

final class FileWatcher: Sendable {
    private let url: URL
    private let onChange: @Sendable () -> Void
    private let queue: DispatchQueue
    private let queueKey = DispatchSpecificKey<Bool>()

    private var isOnQueue: Bool {
        DispatchQueue.getSpecific(key: queueKey) == true
    }

    // nonisolated(unsafe) because DispatchSource is managed entirely on our serial queue
    nonisolated(unsafe) private var source: DispatchSourceFileSystemObject?
    nonisolated(unsafe) private var fileDescriptor: Int32 = -1
    nonisolated(unsafe) private var debounceWorkItem: DispatchWorkItem?
    nonisolated(unsafe) private var isRunning = false

    init(url: URL, onChange: @escaping @Sendable () -> Void) {
        self.url = url
        self.onChange = onChange
        self.queue = DispatchQueue(label: "sh.saqoo.ccplanview.filewatcher")
        queue.setSpecific(key: queueKey, value: true)
    }

    deinit {
        // Clean up synchronously, checking if we're already on the queue to avoid deadlock.
        // This can happen if the last reference is released from within an event handler.
        if isOnQueue {
            isRunning = false
            stopWatching()
        } else {
            queue.sync {
                isRunning = false
                stopWatching()
            }
        }
    }

    func start() {
        queue.async { [self] in
            guard !isRunning else { return }
            isRunning = true
            startWatching()
        }
    }

    func stop() {
        if isOnQueue {
            isRunning = false
            stopWatching()
        } else {
            queue.sync {
                isRunning = false
                stopWatching()
            }
        }
    }

    private func startWatching() {
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }
        fileDescriptor = fd

        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete],
            queue: queue
        )

        src.setEventHandler { [self] in
            let flags = src.data
            if flags.contains(.delete) || flags.contains(.rename) {
                // Editor replaced the file (vim, TextMate pattern)
                stopWatching()
                // Wait briefly for the new file to appear, then restart
                queue.asyncAfter(deadline: .now() + .milliseconds(100)) { [self] in
                    guard isRunning else { return }
                    startWatching()
                    debouncedOnChange()
                }
            } else if flags.contains(.write) {
                debouncedOnChange()
            }
        }

        src.setCancelHandler {
            close(fd)
        }

        source = src
        src.resume()
    }

    private func stopWatching() {
        source?.cancel()
        source = nil
        fileDescriptor = -1
    }

    private func debouncedOnChange() {
        debounceWorkItem?.cancel()
        let work = DispatchWorkItem { [onChange] in
            onChange()
        }
        debounceWorkItem = work
        queue.asyncAfter(deadline: .now() + .milliseconds(100), execute: work)
    }
}
