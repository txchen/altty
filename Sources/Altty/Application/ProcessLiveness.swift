import Darwin
import Foundation

enum ProcessLiveness {
    /// Kernel state, not NSRunningApplication's asynchronously refreshed cache.
    static func isRunning(_ pid: ProcessID) -> Bool {
        guard pid > 0 else { return false }
        var info = proc_bsdinfo()
        let size = MemoryLayout<proc_bsdinfo>.stride
        let count = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(size))
        if count == size { return info.pbi_status != UInt32(SZOMB) }
        return kill(pid, 0) == 0 || errno == EPERM
    }
}

/// Stable notification-source identity disambiguates an old object's termination
/// from a newly admitted application that happens to reuse the same PID.
struct WorkspaceIdentityRegistry<Key: Hashable> {
    private var byKey: [Key: ProcessID] = [:]
    private var byPID: [ProcessID: Key] = [:]

    mutating func admit(_ key: Key, pid: ProcessID) {
        guard pid > 0 else { return }
        if let oldPID = byKey[key], oldPID != pid { byPID[oldPID] = nil }
        if let old = byPID[pid], old != key { byKey[old] = nil }
        byKey[key] = pid
        byPID[pid] = key
    }

    func pid(for key: Key) -> ProcessID? { byKey[key] }

    mutating func terminate(_ key: Key) -> ProcessID? {
        guard let pid = byKey.removeValue(forKey: key), byPID[pid] == key else { return nil }
        byPID[pid] = nil
        return pid
    }
}
