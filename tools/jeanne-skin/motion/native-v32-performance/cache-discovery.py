from pathlib import Path
p=Path(__file__).parent/'Sources/Sessions.swift';s=p.read_text();anchor='    private(set) var diagnostic = ""\n'
pos=s.index(anchor,s.index('final class CodexRolloutDiscovery'));s=s[:pos]+s[pos:].replace(anchor,anchor+'''    private struct CachedTask {
        let size: UInt64
        let modified: Date
        let payload: StatePayload
    }
    private var taskCache: [String: CachedTask] = [:]
''',1)
a=s.index('    private func task(at url:',s.index('final class CodexRolloutDiscovery'));b=s.index('\n}\n',a);t=s[a:b]
anchor='        guard let handle = FileHandle(forReadingAtPath: url.path) else { return nil }'
t=t.replace(anchor,'''        let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.uint64Value ?? 0
        if let cached = taskCache[url.path], cached.size == fileSize, cached.modified == modifiedAt,
           let id = cached.payload.rawSessionId, cached.payload.sessionTitle == titles[id] {
            return cached.payload
        }
'''+anchor,1)
old='        let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.uint64Value ?? 0'
# Keep the first new declaration, remove the old second declaration.
idx=t.index(old,t.index(old)+len(old));t=t[:idx]+t[idx+len(old)+1:]
t=t.replace('        return StatePayload(','        let result = StatePayload(',1)
t=t.replace('''        )
    }''','''        )
        if taskCache.count >= 512 { taskCache.removeAll(keepingCapacity: true) }
        taskCache[url.path] = CachedTask(size: fileSize, modified: modifiedAt, payload: result)
        return result
    }''',1)
s=s[:a]+t+s[b:];p.write_text(s)
