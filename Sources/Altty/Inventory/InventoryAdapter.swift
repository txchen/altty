import Foundation

typealias WindowID = UInt32
typealias ProcessID = Int32
typealias InventoryGeneration = UInt64

struct WindowIdentity: Equatable, Hashable, Sendable {
    let wid: WindowID
    let pid: ProcessID
    let generation: InventoryGeneration
}

struct FocusedWindow: Equatable, Sendable {
    let wid: WindowID
    let pid: ProcessID
}

struct WindowServerWindow: Equatable, Sendable {
    let wid: WindowID
    let pid: ProcessID
    let frontToBackOrder: Int
}

struct WindowServerSnapshot: Equatable, Sendable {
    let activeSpaceIDs: [UInt64]
    let windows: [WindowServerWindow]
}

enum FieldUpdate<Value: Equatable & Sendable>: Equatable, Sendable {
    case unchanged
    case value(Value)
    case unavailable
    case stale
}

enum WindowQualification {
    private static let transientSubroles: Set<String> = [
        "AXMenu", "AXPopover", "AXSheet", "AXSystemFloatingWindow",
    ]

    static func isTransient(role: String?, subrole: String?) -> Bool {
        (role.map { $0 != "AXWindow" } ?? true)
            || subrole.map(transientSubroles.contains) == true
    }
}

struct WindowSemanticPatch: Equatable, Sendable {
    var title: FieldUpdate<String> = .unchanged
    var role: FieldUpdate<String> = .unchanged
    var subrole: FieldUpdate<String> = .unchanged
    var isMinimized: FieldUpdate<Bool> = .unchanged
    var isFullscreen: FieldUpdate<Bool> = .unchanged
    var isTransient: FieldUpdate<Bool> = .unchanged
}

struct WorkspaceApplicationFacts: Equatable, Sendable {
    let pid: ProcessID
    let bundleIdentifier: String?
    var applicationName: String? = nil
    var bundlePath: String? = nil
    let isHidden: Bool
    let isFrontmost: Bool
}

enum WorkspaceApplicationEvent: Equatable, Sendable {
    case snapshot([WorkspaceApplicationFacts])
    case launched(WorkspaceApplicationFacts)
    case hidden(pid: ProcessID, isHidden: Bool)
    case activated(pid: ProcessID)
    case terminated(pid: ProcessID)
}

enum InventoryEvent: Equatable, Sendable {
    case replaceActiveSpace(WindowServerSnapshot)
    case reconcileActiveSpace(WindowServerSnapshot)
    case created(WindowServerWindow, generation: InventoryGeneration)
    case destroyed(WindowIdentity)
    case focused(WindowIdentity)
    case semanticsInvalidated(WindowIdentity)
    case semanticsChanged(WindowIdentity, WindowSemanticPatch)
    case workspaceChanged(WorkspaceApplicationEvent)
    case clear
}

struct SwitchableWindow: Equatable, Sendable {
    let wid: WindowID
    let pid: ProcessID
    let generation: InventoryGeneration
    let title: String?
    let titleIsStale: Bool
    let isMinimized: Bool
    let isFullscreen: Bool
    let applicationIsHidden: Bool
    let applicationIsFrontmost: Bool
    let bundleIdentifier: String?
    var applicationName: String? = nil
    var applicationBundlePath: String? = nil

    var identity: WindowIdentity {
        WindowIdentity(wid: wid, pid: pid, generation: generation)
    }
}

struct WindowInventorySnapshot: Equatable, Sendable {
    let generation: InventoryGeneration
    let activeSpaceIDs: [UInt64]
    let windows: [SwitchableWindow]
    // Authoritative existence is independent of transient AX qualification.
    let liveIdentities: Set<WindowIdentity>
    let focusedWindow: WindowIdentity?
    let frontmostApplicationPID: ProcessID?
    let exceptionForegroundContext: ExceptionForegroundContext

    static let empty = WindowInventorySnapshot(
        generation: 0,
        activeSpaceIDs: [],
        windows: [],
        liveIdentities: [],
        focusedWindow: nil,
        frontmostApplicationPID: nil,
        exceptionForegroundContext: .unknown
    )
}

protocol InventoryAdapter: Sendable {
    func apply(_ event: InventoryEvent) async -> [WindowIdentity]
    func snapshot() async -> WindowInventorySnapshot
}

private struct SemanticField<Value: Equatable & Sendable>: Equatable, Sendable {
    var value: Value?
    var isStale = false

    mutating func apply(_ update: FieldUpdate<Value>) {
        switch update {
        case .unchanged:
            break
        case let .value(value):
            self.value = value
            isStale = false
        case .unavailable:
            value = nil
            isStale = false
        case .stale:
            isStale = true
        }
    }
}

private struct ApplicationState: Equatable, Sendable {
    var bundleIdentifier: String?
    var applicationName: String?
    var bundlePath: String?
    var isHidden = false
    var isFrontmost = false
}

private struct WindowRecord: Equatable, Sendable {
    let identity: WindowIdentity
    var title = SemanticField<String>()
    var role = SemanticField<String>()
    var subrole = SemanticField<String>()
    var isMinimized = SemanticField<Bool>()
    var isFullscreen = SemanticField<Bool>()
    var isTransient = SemanticField<Bool>()
    var hasReceivedSemantics = false

    mutating func apply(_ patch: WindowSemanticPatch) {
        title.apply(patch.title)
        role.apply(patch.role)
        subrole.apply(patch.subrole)
        isMinimized.apply(patch.isMinimized)
        isFullscreen.apply(patch.isFullscreen)
        isTransient.apply(patch.isTransient)
        hasReceivedSemantics = true
    }

    var isSwitchable: Bool {
        guard role.value == "AXWindow", !role.isStale,
              isTransient.value == false, !isTransient.isStale else { return false }
        return true
    }
}

actor WindowInventory: InventoryAdapter {
    private var generation: InventoryGeneration = 0
    private var activeSpaceIDs: [UInt64] = []
    private var records: [WindowID: WindowRecord] = [:]
    private var applications: [ProcessID: ApplicationState] = [:]
    private var mostRecentFirst: [WindowIdentity] = []
    private var focusedWindow: WindowIdentity?
    private var frontmostApplicationPID: ProcessID?
    private var hasLoadedActiveSpaceInventory = false
    private var pendingEnrichment: Set<WindowIdentity> = []
    private var invalidatedWhileEnriching: Set<WindowIdentity> = []
    private var coldStartFrontToBack: [WindowIdentity: Int] = [:]
    private var hasObservedFocus = false

    func apply(_ event: InventoryEvent) -> [WindowIdentity] {
        switch event {
        case let .replaceActiveSpace(snapshot):
            return replace(with: snapshot)
        case let .reconcileActiveSpace(snapshot):
            return reconcile(with: snapshot)
        case let .created(window, eventGeneration):
            guard eventGeneration == generation else { return [] }
            return addOrReplace(window, authoritativeCreation: true)
        case let .destroyed(identity):
            remove(identity)
            return []
        case let .focused(identity):
            guard records[identity.wid]?.identity == identity else { return [] }
            hasObservedFocus = true
            focusedWindow = identity
            setFrontmostApplication(identity.pid)
            mostRecentFirst.removeAll { $0 == identity }
            mostRecentFirst.insert(identity, at: 0)
            return []
        case let .semanticsInvalidated(identity):
            guard var record = records[identity.wid], record.identity == identity else { return [] }
            record.apply(staleSemanticPatch)
            record.hasReceivedSemantics = false
            records[identity.wid] = record
            guard !pendingEnrichment.contains(identity) else {
                invalidatedWhileEnriching.insert(identity)
                return []
            }
            return requestEnrichment(for: [identity])
        case let .semanticsChanged(identity, patch):
            guard var record = records[identity.wid], record.identity == identity else { return [] }
            record.apply(patch)
            pendingEnrichment.remove(identity)
            if invalidatedWhileEnriching.remove(identity) != nil {
                record.apply(staleSemanticPatch)
                record.hasReceivedSemantics = false
                records[identity.wid] = record
                return requestEnrichment(for: [identity])
            }
            records[identity.wid] = record
            reorderColdStartIfNeeded()
            return []
        case let .workspaceChanged(event):
            apply(event)
            reorderColdStartIfNeeded()
            return []
        case .clear:
            generation &+= 1
            activeSpaceIDs = []
            records.removeAll()
            mostRecentFirst.removeAll()
            focusedWindow = nil
            frontmostApplicationPID = nil
            hasLoadedActiveSpaceInventory = false
            pendingEnrichment.removeAll()
            invalidatedWhileEnriching.removeAll()
            coldStartFrontToBack.removeAll()
            hasObservedFocus = false
            return []
        }
    }

    func snapshot() -> WindowInventorySnapshot {
        let windows = mostRecentFirst.compactMap { identity -> SwitchableWindow? in
            guard let record = records[identity.wid], record.identity == identity,
                  record.isSwitchable else { return nil }
            let application = applications[identity.pid] ?? ApplicationState()
            return SwitchableWindow(
                wid: identity.wid,
                pid: identity.pid,
                generation: identity.generation,
                title: record.title.value,
                titleIsStale: record.title.isStale,
                isMinimized: record.isMinimized.value ?? false,
                isFullscreen: record.isFullscreen.value ?? false,
                applicationIsHidden: application.isHidden,
                applicationIsFrontmost: application.isFrontmost,
                bundleIdentifier: application.bundleIdentifier,
                applicationName: application.applicationName,
                applicationBundlePath: application.bundlePath
            )
        }
        let frontmostApplication = frontmostApplicationPID.flatMap { applications[$0] }
        let frontmostWindowIsFullscreen: Bool?
        if !hasLoadedActiveSpaceInventory {
            frontmostWindowIsFullscreen = nil
        } else if let focusedWindow {
            if focusedWindow.pid != frontmostApplicationPID {
                frontmostWindowIsFullscreen = nil
            } else if let fullscreen = records[focusedWindow.wid]?.isFullscreen,
                      !fullscreen.isStale {
                frontmostWindowIsFullscreen = fullscreen.value
            } else {
                frontmostWindowIsFullscreen = nil
            }
        } else {
            frontmostWindowIsFullscreen = false
        }
        return WindowInventorySnapshot(
            generation: generation,
            activeSpaceIDs: activeSpaceIDs,
            windows: windows,
            liveIdentities: Set(records.values.map(\.identity)),
            focusedWindow: focusedWindow,
            frontmostApplicationPID: frontmostApplicationPID,
            exceptionForegroundContext: ExceptionForegroundContext(
                bundleIdentifier: frontmostApplication?.bundleIdentifier,
                windowIsFullscreen: frontmostWindowIsFullscreen
            )
        )
    }

    private func replace(with snapshot: WindowServerSnapshot) -> [WindowIdentity] {
        generation &+= 1
        hasLoadedActiveSpaceInventory = true
        activeSpaceIDs = Array(Set(snapshot.activeSpaceIDs)).sorted()
        records.removeAll(keepingCapacity: true)
        mostRecentFirst.removeAll(keepingCapacity: true)
        pendingEnrichment.removeAll(keepingCapacity: true)
        invalidatedWhileEnriching.removeAll(keepingCapacity: true)
        coldStartFrontToBack.removeAll(keepingCapacity: true)
        hasObservedFocus = false

        let ordered = orderedUniqueWindows(snapshot.windows)
        for window in ordered where window.wid != 0 && window.pid > 0 {
            let identity = WindowIdentity(wid: window.wid, pid: window.pid, generation: generation)
            records[window.wid] = WindowRecord(identity: identity)
            mostRecentFirst.append(identity)
            coldStartFrontToBack[identity] = window.frontToBackOrder
        }
        focusedWindow = mostRecentFirst.first
        return requestEnrichment(for: mostRecentFirst)
    }

    private func reconcile(with snapshot: WindowServerSnapshot) -> [WindowIdentity] {
        let spaceIDs = Array(Set(snapshot.activeSpaceIDs)).sorted()
        guard spaceIDs == activeSpaceIDs else { return replace(with: snapshot) }

        let authoritative = Dictionary(
            orderedUniqueWindows(snapshot.windows).map { ($0.wid, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let recordsToValidate = Array(records.values)
        for record in recordsToValidate {
            guard let current = authoritative[record.identity.wid],
                  current.pid == record.identity.pid else {
                remove(record.identity)
                continue
            }
        }

        var enrichment: [WindowIdentity] = []
        for window in orderedUniqueWindows(snapshot.windows) where window.wid != 0 && window.pid > 0 {
            if records[window.wid] == nil {
                enrichment.append(contentsOf: addOrReplace(window))
            }
        }
        return enrichment
    }

    private func addOrReplace(
        _ window: WindowServerWindow,
        authoritativeCreation: Bool = false
    ) -> [WindowIdentity] {
        let identity = WindowIdentity(wid: window.wid, pid: window.pid, generation: generation)
        if let existing = records[window.wid] {
            if existing.identity == identity {
                if pendingEnrichment.contains(identity) || !authoritativeCreation { return [] }
                remove(existing.identity)
            } else {
                remove(existing.identity)
            }
        }
        records[window.wid] = WindowRecord(identity: identity)
        mostRecentFirst.append(identity)
        coldStartFrontToBack[identity] = window.frontToBackOrder
        return requestEnrichment(for: [identity])
    }

    private func remove(_ identity: WindowIdentity) {
        guard records[identity.wid]?.identity == identity else { return }
        records.removeValue(forKey: identity.wid)
        mostRecentFirst.removeAll { $0 == identity }
        if focusedWindow == identity { focusedWindow = nil }
        pendingEnrichment.remove(identity)
        invalidatedWhileEnriching.remove(identity)
        coldStartFrontToBack.removeValue(forKey: identity)
    }

    private func requestEnrichment(for identities: [WindowIdentity]) -> [WindowIdentity] {
        identities.filter { identity in
            guard !pendingEnrichment.contains(identity) else { return false }
            pendingEnrichment.insert(identity)
            return true
        }
    }

    private var staleSemanticPatch: WindowSemanticPatch {
        WindowSemanticPatch(
            title: .stale,
            role: .stale,
            subrole: .stale,
            isMinimized: .stale,
            isFullscreen: .stale,
            isTransient: .stale
        )
    }

    private func orderedUniqueWindows(_ windows: [WindowServerWindow]) -> [WindowServerWindow] {
        var seen: Set<WindowID> = []
        return windows
            .sorted {
                if $0.frontToBackOrder != $1.frontToBackOrder {
                    return $0.frontToBackOrder < $1.frontToBackOrder
                }
                return $0.wid < $1.wid
            }
            .filter { seen.insert($0.wid).inserted }
    }

    private func reorderColdStartIfNeeded() {
        guard !hasObservedFocus else { return }
        mostRecentFirst.sort { left, right in
            let leftApplication = applications[left.pid] ?? ApplicationState()
            let rightApplication = applications[right.pid] ?? ApplicationState()
            let leftIsDeferred = records[left.wid]?.isMinimized.value == true
                || leftApplication.isHidden
            let rightIsDeferred = records[right.wid]?.isMinimized.value == true
                || rightApplication.isHidden
            if leftIsDeferred != rightIsDeferred { return !leftIsDeferred }
            if leftIsDeferred {
                return left.wid < right.wid
            }
            let leftOrder = coldStartFrontToBack[left] ?? .max
            let rightOrder = coldStartFrontToBack[right] ?? .max
            return leftOrder == rightOrder ? left.wid < right.wid : leftOrder < rightOrder
        }
    }

    private func apply(_ event: WorkspaceApplicationEvent) {
        switch event {
        case let .snapshot(facts):
            frontmostApplicationPID = facts.first(where: \.isFrontmost)?.pid
            applications = Dictionary(uniqueKeysWithValues: facts.map { fact in
                (fact.pid, ApplicationState(
                    bundleIdentifier: fact.bundleIdentifier,
                    applicationName: fact.applicationName,
                    bundlePath: fact.bundlePath,
                    isHidden: fact.isHidden,
                    isFrontmost: fact.isFrontmost
                ))
            })
        case let .launched(fact):
            applications[fact.pid] = ApplicationState(
                bundleIdentifier: fact.bundleIdentifier,
                applicationName: fact.applicationName,
                bundlePath: fact.bundlePath,
                isHidden: fact.isHidden,
                isFrontmost: fact.isFrontmost
            )
            if fact.isFrontmost { setFrontmostApplication(fact.pid) }
        case let .hidden(pid, isHidden):
            var application = applications[pid] ?? ApplicationState()
            application.isHidden = isHidden
            applications[pid] = application
        case let .activated(pid):
            setFrontmostApplication(pid)
        case let .terminated(pid):
            if frontmostApplicationPID == pid { frontmostApplicationPID = nil }
            applications.removeValue(forKey: pid)
            for record in Array(records.values) where record.identity.pid == pid {
                remove(record.identity)
            }
        }
    }

    private func setFrontmostApplication(_ pid: ProcessID) {
        frontmostApplicationPID = pid
        for key in Array(applications.keys) {
            applications[key]?.isFrontmost = key == pid
        }
        if applications[pid] == nil {
            applications[pid] = ApplicationState(isFrontmost: true)
        }
    }
}
