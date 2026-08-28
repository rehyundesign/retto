// 레토 스프라이트 아틀라스의 셀 단위 크기를 재고, 특정 행의 크기 드리프트를 교정한다.
//
//   swift apps/retto-pet/tools/sprite-scale.swift measure <atlas>
//   swift apps/retto-pet/tools/sprite-scale.swift apply <in> <out.png> <row>=<factor> ...
//
// 크기 비교 지표는 알파 면적의 제곱근이다. 실루엣 넓이는 포즈에 따라 변하지만,
// 같은 포즈 묶음(행) 안에서 중앙값을 비교하면 "같은 고양이를 얼마나 확대해 그렸는지"가 남는다.
// 확대는 콘텐츠 바닥 중앙을 고정점으로 한다. 발이 같은 선에 남아야 시선이 움직일 때 뜨지 않는다.

import AppKit
import CoreGraphics
import Foundation

let cellWidth = 192
let cellHeight = 208
let columns = 8
let rows = 11

struct CellMetrics {
    let row: Int
    let column: Int
    let minX: Int, minY: Int, maxX: Int, maxY: Int
    let area: Int
    var width: Int { maxX - minX + 1 }
    var height: Int { maxY - minY + 1 }
    var scaleProxy: Double { Double(area).squareRoot() }
    var centerX: Double { Double(minX + maxX + 1) / 2 }
    var bottom: Int { maxY + 1 }
}

func loadImage(_ path: String) -> CGImage {
    guard let image = NSImage(contentsOfFile: path),
          let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        FileHandle.standardError.write("cannot read \(path)\n".data(using: .utf8)!)
        exit(1)
    }
    return cgImage
}

/// 픽셀을 top-left 원점 RGBA8(premultiplied)로 정규화해 읽는다.
func rasterize(_ image: CGImage) -> (pixels: [UInt8], width: Int, height: Int) {
    let width = image.width, height = image.height
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    pixels.withUnsafeMutableBytes { raw in
        let context = CGContext(
            data: raw.baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    }
    return (pixels, width, height)
}

func metrics(_ pixels: [UInt8], _ sheetWidth: Int, row: Int, column: Int, areaThreshold: UInt8 = 64) -> CellMetrics? {
    var minX = cellWidth, minY = cellHeight, maxX = -1, maxY = -1, area = 0
    for y in 0..<cellHeight {
        let sheetY = row * cellHeight + y
        for x in 0..<cellWidth {
            let sheetX = column * cellWidth + x
            let alpha = pixels[(sheetY * sheetWidth + sheetX) * 4 + 3]
            guard alpha > 0 else { continue }
            if x < minX { minX = x }
            if x > maxX { maxX = x }
            if y < minY { minY = y }
            if y > maxY { maxY = y }
            if alpha > areaThreshold { area += 1 }
        }
    }
    guard maxX >= 0 else { return nil }
    return CellMetrics(row: row, column: column, minX: minX, minY: minY, maxX: maxX, maxY: maxY, area: area)
}

func median(_ values: [Double]) -> Double {
    let sorted = values.sorted()
    guard !sorted.isEmpty else { return 0 }
    return sorted.count % 2 == 1 ? sorted[sorted.count / 2] : (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
}

func measure(_ path: String) {
    let (pixels, sheetWidth, sheetHeight) = rasterize(loadImage(path))
    print("atlas \(sheetWidth)x\(sheetHeight)")
    for row in 0..<rows {
        let cells = (0..<columns).compactMap { metrics(pixels, sheetWidth, row: row, column: $0) }
        guard !cells.isEmpty else { continue }
        let proxy = median(cells.map(\.scaleProxy))
        print(String(format: "row %2d  cells=%d  medianScaleProxy=%6.1f  medianHeight=%3.0f", row, cells.count, proxy, median(cells.map { Double($0.height) })))
        for cell in cells {
            print(String(format: "    c%d  %3dx%3d @%3d,%3d  proxy=%6.1f  bottomGap=%2d", cell.column, cell.width, cell.height, cell.minX, cell.minY, cell.scaleProxy, cellHeight - cell.bottom))
        }
    }
}

func apply(_ inputPath: String, _ outputPath: String, factors: [Int: CGFloat]) {
    let image = loadImage(inputPath)
    let (pixels, sheetWidth, sheetHeight) = rasterize(image)
    guard sheetWidth == cellWidth * columns, sheetHeight == cellHeight * rows else {
        FileHandle.standardError.write("unexpected atlas size \(sheetWidth)x\(sheetHeight)\n".data(using: .utf8)!)
        exit(1)
    }

    let context = CGContext(
        data: nil,
        width: sheetWidth,
        height: sheetHeight,
        bitsPerComponent: 8,
        bytesPerRow: sheetWidth * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.interpolationQuality = .high
    // CGContext 는 bottom-left 원점이므로 행 번호를 뒤집어 계산한다.
    func cellRect(row: Int, column: Int) -> CGRect {
        CGRect(x: CGFloat(column * cellWidth), y: CGFloat(sheetHeight - (row + 1) * cellHeight), width: CGFloat(cellWidth), height: CGFloat(cellHeight))
    }

    context.draw(image, in: CGRect(x: 0, y: 0, width: sheetWidth, height: sheetHeight))

    for (row, factor) in factors.sorted(by: { $0.key < $1.key }) {
        for column in 0..<columns {
            guard let cell = metrics(pixels, sheetWidth, row: row, column: column) else { continue }
            let rect = cellRect(row: row, column: column)

            // 고정점: 콘텐츠 바닥 중앙 (셀 좌표 → 컨텍스트 좌표)
            let anchorX = rect.minX + CGFloat(cell.centerX)
            let anchorY = rect.minY + CGFloat(cellHeight - cell.bottom)

            let scaledMinX = anchorX + (rect.minX + CGFloat(cell.minX) - anchorX) * factor
            let scaledMaxX = anchorX + (rect.minX + CGFloat(cell.maxX + 1) - anchorX) * factor
            let scaledMaxY = anchorY + CGFloat(cell.height) * factor
            guard scaledMinX >= rect.minX, scaledMaxX <= rect.maxX, scaledMaxY <= rect.maxY else {
                FileHandle.standardError.write("row \(row) c\(column): factor \(factor) overflows the cell\n".data(using: .utf8)!)
                exit(1)
            }

            context.saveGState()
            context.clear(rect)
            context.clip(to: rect)
            let destination = CGRect(
                x: anchorX + (rect.minX - anchorX) * factor,
                y: anchorY + (rect.minY - anchorY) * factor,
                width: rect.width * factor,
                height: rect.height * factor
            )
            context.draw(image.cropping(to: CGRect(
                x: CGFloat(column * cellWidth),
                y: CGFloat(row * cellHeight),
                width: CGFloat(cellWidth),
                height: CGFloat(cellHeight)
            ))!, in: destination)
            context.restoreGState()
            print(String(format: "row %d c%d  x%.4f  %3dx%3d -> %3.0fx%3.0f", row, column, factor, cell.width, cell.height, CGFloat(cell.width) * factor, CGFloat(cell.height) * factor))
        }
    }

    guard let output = context.makeImage() else { exit(1) }
    let rep = NSBitmapImageRep(cgImage: output)
    rep.size = NSSize(width: sheetWidth, height: sheetHeight)
    guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
    try! png.write(to: URL(fileURLWithPath: outputPath))
    print("wrote \(outputPath)")
}

let arguments = Array(CommandLine.arguments.dropFirst())
switch arguments.first {
case "measure" where arguments.count == 2:
    measure(arguments[1])
case "apply" where arguments.count >= 4:
    var factors: [Int: CGFloat] = [:]
    for spec in arguments.dropFirst(3) {
        let parts = spec.split(separator: "=")
        guard parts.count == 2, let row = Int(parts[0]), let factor = Double(parts[1]) else {
            FileHandle.standardError.write("bad spec \(spec), expected <row>=<factor>\n".data(using: .utf8)!)
            exit(1)
        }
        factors[row] = CGFloat(factor)
    }
    apply(arguments[1], arguments[2], factors: factors)
default:
    print("usage: sprite-scale.swift measure <atlas>")
    print("       sprite-scale.swift apply <in> <out.png> <row>=<factor> ...")
    exit(2)
}
