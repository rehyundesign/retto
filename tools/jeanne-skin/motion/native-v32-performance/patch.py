from pathlib import Path
p=Path(__file__).parent/'Sources/PetView.swift';s=p.read_text()
s=s.replace('        if skin == .jeanne {\n            if dragRun == nil && lookDirection != nil { needsDisplay = true; return }','        let previousFrame = frameIndex\n        if skin == .jeanne {\n            if dragRun == nil && lookDirection != nil { return }',1)
s=s.replace('frameIndex = p.frame; completedCycles = p.cycles; needsDisplay = true','frameIndex = p.frame; completedCycles = p.cycles',1)
a=s.index('    private func advanceFrame()');b=s.index('    private func playReaction()',a)
part=s[a:b];assert part.count('        needsDisplay = true\n')==1
part=part.replace('        needsDisplay = true\n','        if skin != .jeanne || frameIndex != previousFrame { needsDisplay = true }\n')
s=s[:a]+part+s[b:]
a=s.index('    private func fittedBody(');b=s.index('\n    ///',a)
old=s[a:b]
new='''    private struct JeanneBodyFit {
        let input: NSAttributedString
        let width: CGFloat
        let maxHeight: CGFloat
        let result: NSString
    }
    private var jeanneBodyFits: [JeanneBodyFit] = []

    private func fittedBody(_ text: String, in rect: NSRect, attributes: [NSAttributedString.Key: Any], maxHeight: CGFloat) -> NSString {
        let input = NSAttributedString(string: text, attributes: attributes)
        if skin == .jeanne, let cached = jeanneBodyFits.first(where: {
            $0.width == rect.width && $0.maxHeight == maxHeight && $0.input.isEqual(to: input)
        }) { return cached.result }
        let result = uncachedFittedBody(text, in: rect, attributes: attributes, maxHeight: maxHeight)
        if skin == .jeanne {
            if jeanneBodyFits.count >= 8 { jeanneBodyFits.removeFirst() }
            jeanneBodyFits.append(JeanneBodyFit(input: input, width: rect.width, maxHeight: maxHeight, result: result))
        }
        return result
    }
'''+old.replace('private func fittedBody(', 'private func uncachedFittedBody(',1)
s=s[:a]+new+s[b:];p.write_text(s)
