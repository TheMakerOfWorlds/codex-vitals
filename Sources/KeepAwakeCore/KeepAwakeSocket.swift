import Darwin
import Foundation

/// Local, bounded messages only. The privileged helper never writes user-provided paths.
public enum KeepAwakeSocket {
    public enum SocketError: Error { case failed, invalidPath, disconnected, oversizedMessage }

    public static func make() throws -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw SocketError.failed }
        _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
        var one: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout.size(ofValue: one)))
        return fd
    }

    private static func address(_ path: String) throws -> sockaddr_un {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let bytes = Array(path.utf8CString)
        guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path), !path.utf8.contains(0) else {
            throw SocketError.invalidPath
        }
        withUnsafeMutableBytes(of: &address.sun_path) { target in
            bytes.withUnsafeBytes { target.copyBytes(from: $0) }
        }
        return address
    }

    public static func bind(_ fd: Int32, path: String) throws {
        var value = try address(path)
        let result = withUnsafePointer(to: &value) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0, chmod(path, 0o600) == 0, listen(fd, 1) == 0 else { throw SocketError.failed }
    }

    public static func connect(_ fd: Int32, path: String) throws {
        var value = try address(path)
        let result = withUnsafePointer(to: &value) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else { throw SocketError.failed }
    }

    public static func peerUID(_ fd: Int32) -> uid_t? {
        var uid: uid_t = 0
        var gid: gid_t = 0
        return getpeereid(fd, &uid, &gid) == 0 ? uid : nil
    }

    public static func readable(_ fd: Int32, milliseconds: Int32) -> Bool {
        var descriptor = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
        return poll(&descriptor, 1, milliseconds) > 0
    }

    @discardableResult
    public static func send(_ line: String, to fd: Int32) -> Bool {
        let data = Array((line + "\n").utf8)
        return data.withUnsafeBytes { buffer in
            Darwin.send(fd, buffer.baseAddress, buffer.count, 0) == buffer.count
        }
    }

    /// Call only after readable(). A partial message is bounded by a per-message deadline.
    public static func receive(_ fd: Int32) throws -> String {
        var bytes: [UInt8] = []
        let end = ProcessInfo.processInfo.systemUptime + 2
        while bytes.count < 256, ProcessInfo.processInfo.systemUptime < end {
            guard readable(fd, milliseconds: 100) else { continue }
            var byte: UInt8 = 0
            let count = recv(fd, &byte, 1, 0)
            guard count == 1 else { throw SocketError.disconnected }
            if byte == 10 { return String(decoding: bytes, as: UTF8.self) }
            bytes.append(byte)
        }
        throw SocketError.oversizedMessage
    }
}
