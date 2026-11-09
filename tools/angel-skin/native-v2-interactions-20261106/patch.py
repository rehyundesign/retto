from pathlib import Path
import shutil
R=Path(__file__).resolve().parent;D=R/'build/Sources'
p=D/'PetView.swift';s=p.read_text()
def sub(a,b):
 global s
 assert s.count(a)==1,(a[:100],s.count(a));s=s.replace(a,b)
sub('case .angelWings: AngelSkin.cache.removeAllObjects()','case .angelWings: AngelSkin.cache.removeAllObjects(); AngelInteractions.cache.removeAllObjects()')
sub('    private var angelPreviewTime:Double?','    private var angelPreviewTime:Double?\n    private var angelIdleChoice=AngelInteractions.IdleChoice()\n    private var angelLastMouseLocation:NSPoint?\n    func setAngelIdleVariantForPreview(_ value:Int,time:Double){angelPreviewTime=time;angelIdleChoice.force(value,cycle:Int(floor(time/3.2)));needsDisplay=true}')
sub('if skin == .angelWings,AngelSkin.available{return false}','if skin == .angelWings,AngelSkin.available{return AngelInteractions.hasGaze && visibleState == .idle && dragRun == nil && !sleepPose && transientState == nil}')
sub('(skin != .angelWings || !AngelSkin.available) &&','(skin != .angelWings || allowsGaze) &&')
sub('if skin == .angelWings,AngelSkin.available,dragRun==nil,let a=animationCatalog[visibleState]{return AngelSkin.animation(a)}','''if skin == .angelWings,AngelSkin.available {
            if let d=dragRun,let a=dragRunAnimations[d]{return AngelInteractions.animation(a)}
            if let a=animationCatalog[visibleState]{return AngelSkin.animation(a)}
        }''')
sub('if skin == .angelWings,dragRun==nil{angelEpoch=ProcessInfo.processInfo.systemUptime}','if skin == .angelWings{angelEpoch=ProcessInfo.processInfo.systemUptime;angelIdleChoice.reset();angelLastMouseLocation=nil}')
sub('skin == .angelWings && AngelSkin.available && dragRun == nil ? 0.05','skin == .angelWings && AngelSkin.available ? 0.05')
sub('    private func advanceFrame() {','''    private func advanceFrame() {
        if skin == .angelWings {
            if visibleState == .idle && dragRun == nil && !hasActiveGaze {
                angelIdleChoice.choose(cycle:Int(floor(max(0,ProcessInfo.processInfo.systemUptime-angelEpoch)/3.2)))
            }
            if let window,window.isVisible {
                let cursor=NSEvent.mouseLocation
                if let previous=angelLastMouseLocation,hypot(cursor.x-previous.x,cursor.y-previous.y)>0.5 {
                    updateAngelGaze(at:convert(window.convertPoint(fromScreen:cursor),from:nil))
                }
                angelLastMouseLocation=cursor
            }
        }''')
sub('''if skin == .angelWings,AngelSkin.available,dragRun==nil {
            let p=AngelSkin.position(row:animation.row,time:ProcessInfo.processInfo.systemUptime-angelEpoch);frameIndex=p.frame;completedCycles=p.cycles''','''if skin == .angelWings,AngelSkin.available,dragRun == nil || AngelInteractions.hasFlight {
            let elapsed=ProcessInfo.processInfo.systemUptime-angelEpoch
            let p=dragRun == nil ? AngelSkin.position(row:animation.row,time:elapsed):AngelInteractions.position(row:animation.row,time:elapsed)
            frameIndex=p.frame;completedCycles=p.cycles''')
sub('        if skin == .hana { updateHanaGaze(at: point); return }','        if skin == .angelWings { updateAngelGaze(at:point);return }\n        if skin == .hana { updateHanaGaze(at: point); return }')
sub('    private func updateHanaGaze(at point: NSPoint) {','''    private func updateAngelGaze(at point:NSPoint) {
        guard allowsGaze else{return}
        let pivot=AngelInteractions.point([255,215],in:AngelSkin.rect(row:0,in:layout.petRect))
        let dx=point.x-pivot.x,dy=point.y-pivot.y
        guard hypot(dx,dy)>18*petScale else{return}
        updateGaze(toward:gazeDirection(dx:dx,dy:dy,previous:gazeTargetDirection ?? lookDirection))
        scheduleGazeReset();needsDisplay=true
    }
    private func updateHanaGaze(at point: NSPoint) {''')
sub('guard ((skin == .hachupingping || skin == .christmas','guard (skin == .angelWings && AngelInteractions.hasGaze) || ((skin == .hachupingping || skin == .christmas')
# Above adds one condition to a guard's first comma expression; no grouping changes to existing expression.
sub('        if skin == .classic && ClassicGrown.available { restartAnimation() }','        if skin == .angelWings { restartAnimation() }\n        if skin == .classic && ClassicGrown.available { restartAnimation() }')
sub('        drawGroundShadow(petRect: skin == .amuRan ? petRect.offsetBy(dx:0,dy:AmuApproved.shadowOffset(row:row,in:petRect,workingKey:amuChoice.working,completionKey:amuChoice.completion)):petRect, scale: uiScale)','        if !(skin == .angelWings && dragRun != nil && AngelInteractions.hasFlight) {\n            drawGroundShadow(petRect: skin == .amuRan ? petRect.offsetBy(dx:0,dy:AmuApproved.shadowOffset(row:row,in:petRect,workingKey:amuChoice.working,completionKey:amuChoice.completion)):petRect, scale: uiScale)\n        }')
sub('shadow.shadowColor = skin == .angelWings && AngelSkin.available && dragRun == nil ?','shadow.shadowColor = skin == .angelWings && AngelSkin.available ?')
sub('''if skin == .angelWings,AngelSkin.available,dragRun==nil {
            _ = AngelSkin.draw(row:row,time:angelPreviewTime ?? (ProcessInfo.processInfo.systemUptime-angelEpoch),in:petRect)''','''if skin == .angelWings,AngelSkin.available,dragRun == nil || AngelInteractions.hasFlight {
            let t=angelPreviewTime ?? (ProcessInfo.processInfo.systemUptime-angelEpoch)
            if hasActiveGaze,let d=lookDirection {
                _=AngelInteractions.drawGaze(direction:d,time:t,in:petRect)
            }else if dragRun != nil,let key=AngelInteractions.flightKey(row) {
                _=AngelInteractions.draw(key:key,time:t,in:petRect)
            }else {
                if visibleState == .idle {angelIdleChoice.choose(cycle:Int(floor(max(0,t)/3.2)))}
                if visibleState == .idle && angelIdleChoice.variant==1 && AngelInteractions.hasIdle {
                    _=AngelInteractions.draw(key:"idle-look",time:t,in:petRect)
                }else{_=AngelSkin.draw(row:row,time:t,in:petRect)}
            }''')
sub('abs(a.interval*16-m.cycle)<0.000001,!allowsGaze','abs(a.interval*16-m.cycle)<0.000001,allowsGaze == (s == .idle && AngelInteractions.hasGaze)')
sub('setGazeDirectionForPreview(3);guard !hasActiveGaze else{return false};clearGaze()','setGazeDirectionForPreview(3);guard hasActiveGaze == allowsGaze else{return false};clearGaze()')
p.write_text(s)
shutil.copy2(R/'AngelInteractions.swift',D/'AngelInteractions.swift')
p=D/'main.swift';s=p.read_text();s=s.replace('if CommandLine.arguments.contains("--angel-state-self-test") {','''if CommandLine.arguments.contains("--angel-interactions-self-test"){exit(AngelInteractions.validate() ? 0:1)}
if CommandLine.arguments.contains("--angel-state-self-test") {''',1);p.write_text(s)
print('Patched only Angel branches in current installed source snapshot')
