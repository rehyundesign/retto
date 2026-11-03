from pathlib import Path
import json,shutil
p=Path(__file__).parent;res=p/'Retto.app/Contents/Resources/JeanneFrames';m=json.loads((res/'manifest.json').read_text());old=p.parent/'native-v31/Retto.app/Contents/Resources/JeanneFrames'
for s in m['states']:
 if s['id'] not in ['running','failed']:continue
 original=s['row'];s['row']=7 if s['id']=='running' else 5
 for i in range(len(s['files'])):
  name=f"character-{s['row']}-{i}.png";shutil.copy2(old/f'character-{original}-{i}.png',res/name);s['files'][i]=name
(res/'manifest.json').write_text(json.dumps(m,indent=2))
f=p/'Sources/JeanneSkin.swift';s=f.read_text();s=s.replace('cycleLimit: a.cycleLimit, kicker:', 'cycleLimit: a.row == animationCatalog[.waving]!.row ? nil : a.cycleLimit, kicker:',1)
a=s.index('        for s in m.states {',s.index('static func validate()'))
s=s[:a]+'''        let expectedRows = Dictionary(uniqueKeysWithValues: animationCatalog.map { ($0.key.rawValue,$0.value.row) } + dragRunAnimations.map { ($0.key == .right ? "drag-right" : "drag-left",$0.value.row) })
        guard Set(m.states.map { $0.id }) == Set(expectedRows.keys) else { return false }
        for state in m.states { guard expectedRows[state.id] == state.row else { print("State row mismatch: \\(state.id)"); return false } }
        guard animation(animationCatalog[.waving]!).cycleLimit == nil else { return false }
'''+s[a:];f.write_text(s)
f=p/'Sources/PetView.swift';s=f.read_text();idx=s.index('    private func advanceFrame()')
method='''    func validateJeanneStateTransitions() -> Bool {
        for state in PetState.allCases {
            guard let data = "{\\"state\\":\\"\\(state.rawValue)\\",\\"sessionId\\":\\"jeanne-state-fixture\\"}".data(using:.utf8),
                  let payload = try? JSONDecoder().decode(StatePayload.self,from:data) else { return false }
            apply(payload,state:state,sessionCount:1,attentionCount:0,isPinned:false)
            guard currentAnimation?.row == animationCatalog[state]?.row else { return false }
            let duration = JeanneSkin.state(row: animationCatalog[state]!.row)!.cycle
            jeanneEpoch = ProcessInfo.processInfo.systemUptime - duration * 3 - 0.01
            advanceFrame()
            guard visibleState == state, currentAnimation?.row == animationCatalog[state]?.row else { print("State changed unexpectedly: \\(state)"); return false }
        }
        for direction in [DragRun.right,.left] {
            dragRun = direction; restartAnimation()
            guard let a = currentAnimation, a.row == dragRunAnimations[direction]?.row, a.frames == 8 else { return false }
            jeanneEpoch = ProcessInfo.processInfo.systemUptime - 2.1
            advanceFrame()
            guard frameIndex < 8 else { return false }
        }
        dragRun = nil
        for direction in 0..<16 { setGazeDirectionForPreview(direction); guard lookDirection == direction else { return false } }
        clearGaze()
        return lookDirection == nil
    }

'''
s=s[:idx]+method+s[idx:];f.write_text(s)
f=p/'Sources/main.swift';s=f.read_text();idx=s.index('if CommandLine.arguments.contains("--discovery-cache-self-test")');s=s[:idx]+'''if CommandLine.arguments.contains("--jeanne-state-self-test") {
    let v = RettoView(frame:NSRect(x:0,y:0,width:224,height:320),spriteSheet:JeanneSkin.placeholder,skin:.jeanne,onOpenClaude:{ _,_ in },onOpenAttention:{ _ in })
    let ok = v.validateJeanneStateTransitions()
    print("Jeanne state/loop/drag/gaze transitions: \\(ok)")
    exit(ok ? 0 : 1)
}

'''+s[idx:];f.write_text(s)
