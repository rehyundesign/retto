// 자는 행(행 11)을 아틀라스에 새로 만든다.
//
// 아틀라스에는 자는 그림이 없었다. 대신 대기 행(행 0)의 세 번째 프레임에서 레토가 눈을 감고
// 있다 — 눈 깜빡임 프레임이다. 그 한 장을 재료로 삼아, 숨쉬기와 고개 기울임을 코드로 넣어
// 여섯 프레임을 만든다. 앉은 채로 졸았다는 뜻이므로 발은 같은 선에 남긴다.
//
//   swift tools/sprite-sleep.swift assets/spritesheet.webp out.png
//   cwebp -lossless out.png -o assets/spritesheet.webp
//
// 새로 그린 자는 그림이 있으면 그것을 행 11 에 얹는다. 스트립은 가로로 이어 붙인
// 1344×240 PNG(224×240 여섯 칸, 투명 배경)여야 한다.
//
//   swift tools/sprite-sleep.swift assets/spritesheet.webp out.png --strip sleeping.png
//   cwebp -lossless out.png -o assets/spritesheet.webp
import AppKit

let cellWidth: CGFloat = 224
let cellHeight: CGFloat = 240
let columns = 8
let sourceRow = 0        // 대기
let sourceColumn = 2     // 눈을 감은 프레임
let sleepFrames = 6

guard CommandLine.arguments.count >= 3 else {
    print("사용법: sprite-sleep.swift <입력 아틀라스> <출력 PNG>")
    exit(1)
}
let inputPath = CommandLine.arguments[1]
let outputPath = CommandLine.arguments[2]
/// 새로 그린 스트립을 그대로 얹을 때 쓴다. 없으면 대기 프레임으로 만든다.
let stripPath: String? = {
    guard let index = CommandLine.arguments.firstIndex(of: "--strip"),
          index + 1 < CommandLine.arguments.count else { return nil }
    return CommandLine.arguments[index + 1]
}()

guard let sheet = NSImage(contentsOfFile: inputPath),
      let sheetCG = sheet.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    print("아틀라스를 읽지 못했습니다: \(inputPath)")
    exit(1)
}
let oldWidth = CGFloat(sheetCG.width)
let oldHeight = CGFloat(sheetCG.height)
let rows = Int((oldHeight / cellHeight).rounded())
let newHeight = oldHeight + cellHeight
print("입력 \(Int(oldWidth))×\(Int(oldHeight)) (\(columns)×\(rows)) → 출력 \(Int(oldWidth))×\(Int(newHeight)) (\(columns)×\(rows + 1))")

/// 숨 한 번. 0~1 을 넣으면 들이쉬고 내쉬는 한 주기가 나온다.
func breath(_ t: CGFloat) -> CGFloat { (1 - cos(t * 2 * .pi)) / 2 }

guard let context = CGContext(
    data: nil,
    width: Int(oldWidth),
    height: Int(newHeight),
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    print("그릴 자리를 못 잡았습니다")
    exit(1)
}
context.interpolationQuality = .high

// 원본을 위쪽에 그대로 둔다. 새 행은 아래에 붙는다(아틀라스는 위에서 아래로 행 0..n).
context.draw(sheetCG, in: CGRect(x: 0, y: cellHeight, width: oldWidth, height: oldHeight))

// 눈 감은 프레임 한 칸을 떼어낸다.
// CGImage 자르기는 위쪽이 0 이다. 앱이 쓰는 아래쪽 0 규칙과 반대라 여기서 헷갈리기 쉽다.
let srcRect = CGRect(
    x: CGFloat(sourceColumn) * cellWidth,
    y: CGFloat(sourceRow) * cellHeight,
    width: cellWidth,
    height: cellHeight
)
guard let cell = sheetCG.cropping(to: srcRect) else {
    print("프레임을 떼어내지 못했습니다")
    exit(1)
}

if let stripPath {
    // 새로 그린 스트립을 그대로 얹는다. 규격만 확인하고 손대지 않는다.
    guard let strip = NSImage(contentsOfFile: stripPath),
          let stripCG = strip.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        print("스트립을 읽지 못했습니다: \(stripPath)")
        exit(1)
    }
    let expectedWidth = Int(cellWidth) * sleepFrames
    guard stripCG.width == expectedWidth, stripCG.height == Int(cellHeight) else {
        print("스트립 규격이 다릅니다. \(expectedWidth)×\(Int(cellHeight)) 이어야 하는데 \(stripCG.width)×\(stripCG.height) 입니다")
        exit(1)
    }
    context.draw(stripCG, in: CGRect(x: 0, y: 0, width: CGFloat(expectedWidth), height: cellHeight))
    print("스트립을 행 \(rows) 에 얹었습니다: \(stripPath)")
    guard let output = context.makeImage(),
          let png = NSBitmapImageRep(cgImage: output).representation(using: .png, properties: [:]) else {
        print("이미지를 만들지 못했습니다")
        exit(1)
    }
    do { try png.write(to: URL(fileURLWithPath: outputPath)); print("· \(outputPath)") } catch {
        print("쓰지 못했습니다: \(error)"); exit(1)
    }
    exit(0)
}

for frame in 0..<sleepFrames {
    let phase = CGFloat(frame) / CGFloat(sleepFrames)
    let rise = breath(phase)
    // 숨: 세로로 아주 조금 자란다. 발이 뜨지 않게 바닥을 고정점으로 둔다.
    let lift = 1 + 0.014 * rise
    // 고개: 졸다가 기우는 느낌으로 살짝 눕는다. 몸 전체를 발 앞쪽 기준으로 돌린다.
    let tilt = (2.6 * rise) * .pi / 180

    let originX = CGFloat(frame) * cellWidth
    context.saveGState()
    context.translateBy(x: originX, y: 0)
    // 발밑 중앙을 원점으로 삼는다. 콘텐츠 바닥은 칸 아래에서 약 8px 위다.
    let footY: CGFloat = 8
    context.translateBy(x: cellWidth / 2, y: footY)
    context.rotate(by: tilt)
    context.scaleBy(x: 1 - 0.004 * rise, y: lift)
    context.translateBy(x: -cellWidth / 2, y: -footY)
    context.draw(cell, in: CGRect(x: 0, y: 0, width: cellWidth, height: cellHeight))
    context.restoreGState()
}

guard let output = context.makeImage() else { print("이미지를 만들지 못했습니다"); exit(1) }
let rep = NSBitmapImageRep(cgImage: output)
guard let png = rep.representation(using: .png, properties: [:]) else { print("PNG 로 바꾸지 못했습니다"); exit(1) }
do {
    try png.write(to: URL(fileURLWithPath: outputPath))
    print("새 행 \(rows) 을 만들었습니다 · \(outputPath)")
} catch {
    print("쓰지 못했습니다: \(error)")
    exit(1)
}
