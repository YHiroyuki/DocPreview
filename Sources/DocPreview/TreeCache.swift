import Foundation

/// ツリーのキャッシュ。走査は重いのでバックグラウンドで行い、UI スレッドは結果を読むだけにする。
final class TreeCache {
    private let workspace: Workspace
    private let queue = DispatchQueue(label: "docpreview.tree", qos: .userInitiated)
    private let lock = NSLock()
    private var tree: [String: Any]?
    private var signature = 0
    private var refreshing = false
    private var lastRefresh = Date.distantPast

    init(workspace: Workspace) { self.workspace = workspace }

    var cachedSignature: Int { lock.lock(); defer { lock.unlock() }; return signature }

    /// キャッシュがあれば即返し、なければ構築を待って返す（コールバックは任意のスレッド）。
    func tree(_ completion: @escaping ([String: Any]) -> Void) {
        lock.lock(); let cached = tree; lock.unlock()
        if let cached { return completion(cached) }
        refresh(force: true, completion: completion)
    }

    /// 前回から `minInterval` 秒以上経っていれば再走査する。多重実行はしない。
    func refresh(force: Bool = false, minInterval: TimeInterval = 3, completion: (([String: Any]) -> Void)? = nil) {
        lock.lock()
        if refreshing || (!force && Date().timeIntervalSince(lastRefresh) < minInterval) {
            lock.unlock()
            if refreshing, let completion { queue.async { self.lock.lock(); let t = self.tree; self.lock.unlock(); if let t { completion(t) } } }
            return
        }
        refreshing = true
        lock.unlock()
        queue.async { [workspace] in
            let t = workspace.tree()
            var h = Hasher()
            func walk(_ n: [String: Any]) {
                h.combine(n["path"] as? String ?? "")
                (n["children"] as? [[String: Any]])?.forEach(walk)
            }
            walk(t)
            self.lock.lock()
            self.tree = t; self.signature = h.finalize(); self.refreshing = false; self.lastRefresh = Date()
            self.lock.unlock()
            completion?(t)
        }
    }
}
