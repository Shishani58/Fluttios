import Darwin
import Foundation

/// One newline-delimited request per connection. Socket I/O never runs on the UI actor.
@MainActor public final class LocalControlServer {
    nonisolated public static var defaultSocketURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Fluttios/mcp/control.sock")
    }

    private let worker: LocalControlSocket

    public init(
        socketURL: URL = LocalControlServer.defaultSocketURL,
        handler: @escaping @MainActor (Data) async -> Data
    ) {
        worker = LocalControlSocket(url: socketURL, handler: handler)
    }

    public func start() throws { try worker.start() }
    public func stop() { worker.stop() }
    deinit { worker.stop() }
}

// All mutable transport state is confined to queue; MainActor owns request semantics.
private final class LocalControlSocket: @unchecked Sendable {
    private let queue = DispatchQueue(label: "Fluttios.local-control")
    private let url: URL
    private let handler: @MainActor (Data) async -> Data
    private var listener: DispatchSourceRead?
    private var listenerFD: Int32 = -1
    private var lockFD: Int32 = -1
    private var identity: (dev_t, ino_t)?
    private var clients: [Int32: Client] = [:]
    private static let requestLimit = 65_536
    private static let responseLimit = 4 * 1_024 * 1_024

    // Passed through MainActor only as an opaque identity; all mutable fields stay on queue.
    private final class Client: @unchecked Sendable {
        let fd: Int32
        var request = Data()
        var response = Data()
        var offset = 0
        var readSource: DispatchSourceRead?
        var writeSource: DispatchSourceWrite?
        var timeout: DispatchWorkItem?
        var task: Task<Void, Never>?
        var closed = false
        var readSuspended = false
        var pendingCancellations = 0
        init(fd: Int32) { self.fd = fd }
    }

    init(url: URL, handler: @escaping @MainActor (Data) async -> Data) {
        self.url = url
        self.handler = handler
    }

    func start() throws {
        try queue.sync {
            guard listener == nil else { return }
            do {
                try prepareDirectory()
                let lockPath = url.path + ".lock"
                lockFD = Darwin.open(lockPath, O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
                guard lockFD >= 0 else { throw failure("Open control lock") }
                var lockInfo = stat()
                guard fstat(lockFD, &lockInfo) == 0, lockInfo.st_uid == geteuid(),
                    lockInfo.st_mode & S_IFMT == S_IFREG, lockInfo.st_mode & 0o077 == 0
                else { throw failure("Unsafe control lock", code: EACCES) }
                guard flock(lockFD, LOCK_EX | LOCK_NB) == 0 else {
                    throw failure("Fluttios control server is already running", code: EADDRINUSE)
                }
                let address = try socketAddress()
                var existing = stat()
                if lstat(url.path, &existing) == 0 {
                    guard existing.st_uid == geteuid(), existing.st_mode & S_IFMT == S_IFSOCK else {
                        throw failure("Unsafe control socket", code: EACCES)
                    }
                    let probe = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
                    guard probe >= 0 else { throw failure("Probe control socket") }
                    defer { Darwin.close(probe) }
                    _ = fcntl(probe, F_SETFL, O_NONBLOCK)
                    let connected = withAddress(address) { Darwin.connect(probe, $0, $1) }
                    guard connected == -1 && errno == ECONNREFUSED else {
                        throw failure("Control socket is already in use", code: EADDRINUSE)
                    }
                    guard unlink(url.path) == 0 else { throw failure("Remove stale control socket") }
                } else if errno != ENOENT {
                    throw failure("Inspect control socket")
                }
                listenerFD = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
                guard listenerFD >= 0 else { throw failure("Create control socket") }
                guard fcntl(listenerFD, F_SETFL, O_NONBLOCK) == 0,
                    fcntl(listenerFD, F_SETFD, FD_CLOEXEC) == 0
                else { throw failure("Configure control socket") }
                guard withAddress(address, { Darwin.bind(listenerFD, $0, $1) }) == 0 else {
                    throw failure("Bind control socket")
                }
                var bound = stat()
                guard lstat(url.path, &bound) == 0 else { throw failure("Inspect bound control socket") }
                identity = (bound.st_dev, bound.st_ino)
                guard chmod(url.path, 0o600) == 0, Darwin.listen(listenerFD, 16) == 0 else {
                    throw failure("Listen on control socket")
                }
                let source = DispatchSource.makeReadSource(fileDescriptor: listenerFD, queue: queue)
                source.setEventHandler { [weak self] in self?.acceptClients() }
                listener = source
                source.resume()
            } catch {
                cleanup()
                throw error
            }
        }
    }

    func stop() { queue.sync { cleanup() } }

    private func cleanup() {
        if let listener {
            let fd = listenerFD
            listener.setCancelHandler { Darwin.close(fd) }
            listener.cancel()
        } else if listenerFD >= 0 {
            Darwin.close(listenerFD)
        }
        listener = nil
        listenerFD = -1
        for client in Array(clients.values) { close(client) }
        if let identity {
            var current = stat()
            if lstat(url.path, &current) == 0, current.st_dev == identity.0, current.st_ino == identity.1 {
                unlink(url.path)
            }
        }
        identity = nil
        if lockFD >= 0 {
            Darwin.close(lockFD)
            lockFD = -1
        }
    }

    private func prepareDirectory() throws {
        guard url.isFileURL, url.path.hasPrefix("/"), !url.path.utf8.contains(0) else {
            throw failure("Control socket requires an absolute file URL", code: EINVAL)
        }
        // Preserve the actual spelling: URL parent operations can turn /private/var
        // back into the /var symlink on macOS, invalidating a securely resolved path.
        let directory = (url.path as NSString).deletingLastPathComponent
        var ancestor = directory
        // Reject symlink traversal and writable ancestors before creating any path.
        while ancestor != "/" {
            var info = stat()
            if lstat(ancestor, &info) == 0 {
                let stickySystemDirectory = info.st_uid == 0 && info.st_mode & S_ISVTX != 0
                guard info.st_mode & S_IFMT == S_IFDIR,
                    info.st_uid == 0 || info.st_uid == geteuid(),
                    info.st_mode & 0o022 == 0 || stickySystemDirectory
                else { throw failure("Unsafe control directory: \(ancestor)", code: EACCES) }
            } else if errno != ENOENT {
                throw failure("Inspect control directory")
            }
            ancestor = (ancestor as NSString).deletingLastPathComponent
        }
        try FileManager.default.createDirectory(
            atPath: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var info = stat()
        guard lstat(directory, &info) == 0, info.st_mode & S_IFMT == S_IFDIR,
            info.st_uid == geteuid(), info.st_mode & 0o077 == 0
        else { throw failure("Control directory must be owned by the current user with mode 0700", code: EACCES) }
    }

    private func acceptClients() {
        for _ in 0..<32 {
            guard listenerFD >= 0 else { return }
            let fd = Darwin.accept(listenerFD, nil, nil)
            guard fd >= 0 else { return }
            var uid: uid_t = 0
            var gid: gid_t = 0
            guard clients.count < 32, getpeereid(fd, &uid, &gid) == 0, uid == geteuid(),
                fcntl(fd, F_SETFL, O_NONBLOCK) == 0, fcntl(fd, F_SETFD, FD_CLOEXEC) == 0
            else {
                Darwin.close(fd)
                continue
            }
            var noSignal: Int32 = 1
            guard
                setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout.size(ofValue: noSignal)))
                    == 0
            else {
                Darwin.close(fd)
                continue
            }
            let client = Client(fd: fd)
            clients[fd] = client
            let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
            source.setEventHandler { [weak self, weak client] in
                if let client { self?.read(client) }
            }
            client.readSource = source
            source.resume()
            deadline(client, seconds: 10)
        }
    }

    private func read(_ client: Client) {
        guard !client.closed, client.task == nil else { return }
        var bytes = [UInt8](repeating: 0, count: 8192)
        while true {
            let count = Darwin.read(client.fd, &bytes, bytes.count)
            if count < 0 && errno == EINTR { continue }
            if count < 0 && (errno == EAGAIN || errno == EWOULDBLOCK) { return }
            guard count > 0 else {
                close(client)
                return
            }
            client.request.append(contentsOf: bytes.prefix(count))
            guard client.request.count <= Self.requestLimit else {
                close(client)
                return
            }
            guard let newline = client.request.firstIndex(of: 10) else { continue }
            let request = Data(client.request[..<newline])
            client.request.removeAll()
            client.readSource?.suspend()
            client.readSuspended = true
            deadline(client, seconds: 120)
            let handler = handler
            client.task = Task { @MainActor [weak self, weak client] in
                guard !Task.isCancelled else { return }
                let result = await handler(request)
                guard !Task.isCancelled, let self, let client else { return }
                self.queue.async { self.respond(result, to: client) }
            }
            return
        }
    }

    private func respond(_ data: Data, to client: Client) {
        guard !client.closed else { return }
        client.task = nil
        guard data.count < Self.responseLimit else {
            close(client)
            return
        }
        client.response = data
        client.response.append(10)
        deadline(client, seconds: 10)
        let source = DispatchSource.makeWriteSource(fileDescriptor: client.fd, queue: queue)
        source.setEventHandler { [weak self, weak client] in
            if let client { self?.write(client) }
        }
        client.writeSource = source
        source.resume()
    }

    private func write(_ client: Client) {
        guard !client.closed else { return }
        while client.offset < client.response.count {
            let count = client.response.withUnsafeBytes { buffer in
                Darwin.write(client.fd, buffer.baseAddress!.advanced(by: client.offset), buffer.count - client.offset)
            }
            if count < 0 && errno == EINTR { continue }
            if count < 0 && (errno == EAGAIN || errno == EWOULDBLOCK) { return }
            guard count > 0 else {
                close(client)
                return
            }
            client.offset += count
        }
        close(client)
    }

    private func deadline(_ client: Client, seconds: Double) {
        client.timeout?.cancel()
        let timeout = DispatchWorkItem { [weak self, weak client] in
            if let client { self?.close(client) }
        }
        client.timeout = timeout
        queue.asyncAfter(deadline: .now() + seconds, execute: timeout)
    }

    private func close(_ client: Client) {
        guard !client.closed else { return }
        client.closed = true
        client.timeout?.cancel()
        client.task?.cancel()
        // Wait for every dispatch registration to release the descriptor before closing it.
        // Closing earlier can race with descriptor reuse in another accepted connection.
        if client.readSuspended {
            client.readSource?.resume()
            client.readSuspended = false
        }
        var sources: [any DispatchSourceProtocol] = []
        if let source = client.readSource { sources.append(source) }
        if let source = client.writeSource { sources.append(source) }
        client.pendingCancellations = sources.count
        for source in sources {
            source.setCancelHandler {
                client.pendingCancellations -= 1
                if client.pendingCancellations == 0 { Darwin.close(client.fd) }
            }
            source.cancel()
        }
        if sources.isEmpty { Darwin.close(client.fd) }
        client.readSource = nil
        client.writeSource = nil
        clients.removeValue(forKey: client.fd)
    }

    private func socketAddress() throws -> sockaddr_un {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let path = Array(url.path.utf8) + [0]
        guard path.count <= MemoryLayout.size(ofValue: address.sun_path) else {
            throw failure("Control socket path is too long", code: ENAMETOOLONG)
        }
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: path) }
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        return address
    }

    private func withAddress<T>(_ address: sockaddr_un, _ body: (UnsafePointer<sockaddr>, socklen_t) -> T) -> T {
        var address = address
        return withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                body($0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
    }

    private func failure(_ message: String, code: Int32 = errno) -> NSError {
        NSError(domain: NSPOSIXErrorDomain, code: Int(code), userInfo: [NSLocalizedDescriptionKey: message])
    }
}
