from pathlib import Path
import shutil,json,difflib,gzip
ROOT=Path(__file__).resolve().parent;src=ROOT/'build/Sources';baseline=json.loads((ROOT/'baseline.json').read_text())
# Source archive can be recovered again by stage.py; patch once on its exact copy.
def replace(name,a,b):
 p=src/name;s=p.read_text();assert s.count(a)==1,(name,a[:80],s.count(a));p.write_text(s.replace(a,b))
original={p.name:p.read_text() for p in src.glob('*.swift')}
shutil.copy2(ROOT/'AngelSkin.swift',src/'AngelSkin.swift')
replace('PetView.swift','    private var amuRanPoseEpoch =','''    private var angelEpoch = ProcessInfo.processInfo.systemUptime
    private var angelPreviewTime:Double?
    func setAngelTimeForPreview(_ time:Double){angelPreviewTime=time;needsDisplay=true}
    private var amuRanPoseEpoch =''')
replace('PetView.swift','            if skin == .hachupingping { spriteRestState=nil;', '            if skin == .angelWings { spriteRestState=nil }\n            if skin == .hachupingping { spriteRestState=nil;')
replace('PetView.swift','    private var allowsGaze: Bool {','''    private var allowsGaze: Bool {
        if skin == .angelWings,AngelSkin.available{return false}''')
replace('PetView.swift','    private var hasActiveGaze: Bool {','    private var hasActiveGaze: Bool { (skin != .angelWings || !AngelSkin.available) &&')
replace('PetView.swift','    private var currentAnimation: Animation? {','''    private var currentAnimation: Animation? {
        if skin == .angelWings,AngelSkin.available,dragRun==nil,let a=animationCatalog[visibleState]{return AngelSkin.animation(a)}''')
replace('PetView.swift','    private func restartAnimation() {','''    private func restartAnimation() {
        if skin == .angelWings,dragRun==nil{angelEpoch=ProcessInfo.processInfo.systemUptime}''')
replace('PetView.swift','let timer = Timer(timeInterval: skin == .hachupingping','let timer = Timer(timeInterval: skin == .angelWings && AngelSkin.available && dragRun == nil ? 0.05 : skin == .hachupingping')
replace('PetView.swift','        if skin == .hachupingping || skin == .howl || skin == .amuRan || skin == .jeanne { needsDisplay = true }','        if skin == .angelWings || skin == .hachupingping || skin == .howl || skin == .amuRan || skin == .jeanne { needsDisplay = true }')
replace('PetView.swift','        if skin == .hachupingping {\n            let p=HachupingSkin.position','''        if skin == .angelWings,AngelSkin.available,dragRun==nil {
            let p=AngelSkin.position(row:animation.row,time:ProcessInfo.processInfo.systemUptime-angelEpoch);frameIndex=p.frame;completedCycles=p.cycles
        } else if skin == .hachupingping {
            let p=HachupingSkin.position''')
replace('PetView.swift','        shadow.shadowColor = NSColor.black.withAlphaComponent(0.16)','        shadow.shadowColor = skin == .angelWings && AngelSkin.available && dragRun == nil ? NSColor.clear:NSColor.black.withAlphaComponent(0.16)')
replace('PetView.swift','        if skin == .hachupingping {\n            HachupingSkin.drawCharacter','''        if skin == .angelWings,AngelSkin.available,dragRun==nil {
            _ = AngelSkin.draw(row:row,time:angelPreviewTime ?? (ProcessInfo.processInfo.systemUptime-angelEpoch),in:petRect)
        } else if skin == .hachupingping {
            HachupingSkin.drawCharacter''')
replace('PetView.swift','if visibleState == .sleeping && skin != .hachupingping','if visibleState == .sleeping && skin != .angelWings && skin != .hachupingping')
replace('PetView.swift','                case .hachupingping: HachupingSkin.purge()','                case .angelWings: AngelSkin.cache.removeAllObjects()\n                case .hachupingping: HachupingSkin.purge()')
replace('AppDelegate.swift','        petLayout(scale: scale, chatScale: chatScale).windowSize','''        let size=petLayout(scale: scale, chatScale: chatScale).windowSize
        return skin == .angelWings && AngelSkin.available ? AngelSkin.windowSize(size,scale:scale):size''')
replace('AppDelegate.swift','let target = petLayout(scale: currentScale, expanded: expanded, chatScale: chatScale).windowSize','let originalTarget = petLayout(scale: currentScale, expanded: expanded, chatScale: chatScale).windowSize\n        let target = skin == .angelWings && AngelSkin.available ? AngelSkin.windowSize(originalTarget,scale:currentScale):originalTarget')
replace('AppDelegate.swift','let nextSize = petLayout(scale: nextScale, expanded: petView.isRibbonExpanded, chatScale: chatScale).windowSize','let originalSize = petLayout(scale: nextScale, expanded: petView.isRibbonExpanded, chatScale: chatScale).windowSize\n        let nextSize = skin == .angelWings && AngelSkin.available ? AngelSkin.windowSize(originalSize,scale:nextScale):originalSize')
replace('AppDelegate.swift','        petView.skin = next\n','''        petView.skin = next
        let newSize=scaledWindowSize(currentScale)
        let oldFrame=panel.frame
        panel.setFrame(NSRect(x:oldFrame.midX-newSize.width/2,y:oldFrame.minY,width:newSize.width,height:oldFrame.height),display:true)
''')
replace('main.swift','import Foundation','''import Foundation
if CommandLine.arguments.contains("--angel-self-test"){exit(AngelSkin.validate() ? 0:1)}
if let i=CommandLine.arguments.firstIndex(of:"--render-angel-preview"),i+1<CommandLine.arguments.count {
 let time=i+2<CommandLine.arguments.count ? Double(CommandLine.arguments[i+2]) ?? 0.9:0.9
 exit(renderAngelPreview(to:CommandLine.arguments[i+1],time:time))
}
''')
replace('PetView.swift','    private func playReaction() {',(ROOT/'AngelTransitions.txt').read_text()+'    private func playReaction() {')
replace('main.swift','import Foundation','''import Foundation
if CommandLine.arguments.contains("--angel-state-self-test") {
 let v=RettoView(frame:NSRect(x:0,y:0,width:400,height:500),spriteSheet:NSImage(size:NSSize(width:1792,height:3840)),skin:.angelWings,onOpenClaude:{_,_ in},onOpenAttention:{_ in})
 exit(v.validateAngelTransitions() ? 0:1)
}
''')
patch=''
for name,text in original.items():
 new=(src/name).read_text()
 if new!=text:patch+=''.join(difflib.unified_diff(text.splitlines(True),new.splitlines(True),fromfile='a/'+name,tofile='b/'+name))
(ROOT/'runtime.patch.gz').write_bytes(gzip.compress(patch.encode(),mtime=0));print('Angel-only runtime integration patched; original46 sources recovered, only3 touched plus new provider')
