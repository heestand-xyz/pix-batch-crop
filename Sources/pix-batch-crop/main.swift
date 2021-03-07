import AppKit
import RenderKit
import PixelKit

frameLoopRenderThread = .background
PixelKit.main.render.engine.renderMode = .manual

let args = CommandLine.arguments
let fm = FileManager.default

let callURL: URL = URL(fileURLWithPath: args[0])

func getURL(_ path: String) -> URL {
    if path.starts(with: "/") {
        return URL(fileURLWithPath: path)
    }
    if path.starts(with: "~/") {
        let docsURL: URL = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docsURL.deletingLastPathComponent().appendingPathComponent(path.replacingOccurrences(of: "~/", with: ""))
    }
    return callURL.appendingPathComponent(path)
}

let argCount: Int = 4
guard args.count == argCount + 1 else {
    print("pix-batch-crop <threshold> <resolution> <input-folder> <output-folder>")
    exit(EXIT_FAILURE)
}

let threshArg: String = args[1]
guard let threshVal: Double = Double(threshArg) else {
    print("threshold format: \"0.5\"")
    exit(EXIT_FAILURE)
}
let threshold: CGFloat = CGFloat(threshVal)

let resArg: String = args[2]
let resolution: Resolution?
if resArg == "auto" {
    resolution = nil
} else {
    let resParts: [String] = resArg.components(separatedBy: "x")
    guard resParts.count == 2,
          let resWidth: Int = Int(resParts[0]),
          let resHeight: Int = Int(resParts[1]) else {
        print("resolution format: \"1000x1000\" or \"auto\"")
        exit(EXIT_FAILURE)
    }
    resolution = .custom(w: resWidth, h: resHeight)
}
let autoResolution: Bool = resolution == nil

let inputFolderURL: URL = getURL(args[3])
var inputFolderIsDir: ObjCBool = false
let inputFolderExists: Bool = fm.fileExists(atPath: inputFolderURL.path, isDirectory: &inputFolderIsDir)
guard inputFolderExists && inputFolderIsDir.boolValue else {
    print("input needs to be a folder")
    print(inputFolderURL.path)
    exit(EXIT_FAILURE)
}

let outputFolderURL: URL = getURL(args[4])
var outputFolderIsDir: ObjCBool = false
let outputFolderExists: Bool = fm.fileExists(atPath: outputFolderURL.path, isDirectory: &outputFolderIsDir)
if outputFolderExists {
    guard outputFolderIsDir.boolValue else {
        print("output needs to be a folder")
        print(outputFolderURL.path)
        exit(EXIT_FAILURE)
    }
} else {
    try! fm.createDirectory(at: outputFolderURL, withIntermediateDirectories: true, attributes: nil)
}

// MARK: - PIXs

let imagePix = ImagePIX()

let backgroundPix = ColorPIX(at: resolution ?? ._128)
backgroundPix.backgroundColor = .black

let horizontalReducePix = ReducePIX()
horizontalReducePix.method = .max
horizontalReducePix.input = imagePix

let verticalReducePix = ReducePIX()
verticalReducePix.method = .max
verticalReducePix.input = imagePix._flopRight()

let cropPix = CropPIX()
cropPix.input = imagePix

let finalPix: PIX & NODEOut = backgroundPix & cropPix

// MARK: - Images

let fileNames: [String] = try! fm.contentsOfDirectory(atPath: inputFolderURL.path).sorted()
let count: Int = fileNames.count
for (i, fileName) in fileNames.enumerated() {

    guard fileName != ".DS_Store" else { continue }
    let fileURL: URL = inputFolderURL.appendingPathComponent(fileName)
    let name: String = fileURL.deletingPathExtension().lastPathComponent
    let saveURL: URL = outputFolderURL.appendingPathComponent("\(name).jpg")
    let fileExtension: String = fileURL.pathExtension.lowercased()
    guard ["png", "jpg", "tiff"].contains(fileExtension) else {
        print("\(i + 1)/\(count) non image \"\(fileName)\"")
        continue
    }
    let saveFileExists: Bool = fm.fileExists(atPath: saveURL.path)
    if saveFileExists {
        print("\(i + 1)/\(count) skip \"\(fileName)\"")
        continue
    }
    
    guard let image: NSImage = NSImage(contentsOf: fileURL) else {
        print("error \"\(fileName)\"")
        continue
    }
    print("\(i + 1)/\(count) image \"\(fileName)\" \(Int(image.size.width))x\(Int(image.size.height))")
    
    imagePix.image = image

    let imageResolution: Resolution = imagePix.renderResolution
    
    // Horizontal
    
    print("\(i + 1)/\(count) will render horizontal")
    var horizontalPixels: [UInt8]!
    let group1 = DispatchGroup()
    group1.enter()
    try! PixelKit.main.render.engine.manuallyRender {
        horizontalPixels = horizontalReducePix.renderedRaw8!
        group1.leave()
    }
    group1.wait()
    print("\(i + 1)/\(count) did render horizontal")
    
    var horizontalBools: [Bool] = []
    for (i, px) in horizontalPixels.enumerated() {
        guard i % 4 == 0 else { continue }
        let pxb: Bool = px > Int(threshold * 255.0)
        horizontalBools.append(pxb)
    }
    var horizontalIndex: Int? = nil
    var horizontalRanges: [Range<Int>] = []
    for (i, b) in horizontalBools.enumerated() {
        if b {
            if horizontalIndex == nil {
                horizontalIndex = i
            }
        } else {
            if let index: Int = horizontalIndex {
                horizontalRanges.append(index..<i)
                horizontalIndex = nil
            }
        }
    }
    guard let horizontalRange: Range<Int> = horizontalRanges.sorted(by: { rangeA, rangeB in
        rangeA.count > rangeB.count
    }).first else {
        print("fail \"\(fileName)\"")
        continue
    }
    let horizontalLow: CGFloat = CGFloat(horizontalRange.lowerBound) / CGFloat(imageResolution.h - 1)
    let horizontalHigh: CGFloat = CGFloat(horizontalRange.upperBound) / CGFloat(imageResolution.h - 1)
    let horizontalCenter: CGFloat = (horizontalLow + horizontalHigh) / 2.0
    let horizontalScale: CGFloat = horizontalHigh - horizontalLow
    
    // Vertical
    
    print("\(i + 1)/\(count) will render vertical")
    var verticalPixels: [UInt8]!
    let group2 = DispatchGroup()
    group2.enter()
    try! PixelKit.main.render.engine.manuallyRender {
        verticalPixels = verticalReducePix.renderedRaw8!
        group2.leave()
    }
    group2.wait()
    print("\(i + 1)/\(count) did render vertical")
    
    var verticalBools: [Bool] = []
    for (i, px) in verticalPixels.enumerated() {
        guard i % 4 == 0 else { continue }
        let pxb: Bool = px > Int(threshold * 255.0)
        verticalBools.append(pxb)
    }
    var verticalIndex: Int? = nil
    var verticalRanges: [Range<Int>] = []
    for (i, b) in verticalBools.enumerated() {
        if b {
            if verticalIndex == nil {
                verticalIndex = i
            }
        } else {
            if let index: Int = verticalIndex {
                verticalRanges.append(index..<i)
                verticalIndex = nil
            }
        }
    }
    guard let verticalRange: Range<Int> = verticalRanges.sorted(by: { rangeA, rangeB in
        rangeA.count > rangeB.count
    }).first else {
        print("fail \"\(fileName)\"")
        continue
    }
    let verticalLow: CGFloat = CGFloat(verticalRange.lowerBound) / CGFloat(imageResolution.w - 1)
    let verticalHigh: CGFloat = CGFloat(verticalRange.upperBound) / CGFloat(imageResolution.w - 1)
    let verticalCenter: CGFloat = (verticalLow + verticalHigh) / 2.0
    let verticalScale: CGFloat = verticalHigh - verticalLow
    
    // Render
    
    let cropResolution: Resolution = resolution ?? .cgSize(CGSize(width: verticalScale * imageResolution.width.cg,
                                                                  height: horizontalScale * imageResolution.height.cg))
    
    backgroundPix.resolution = cropResolution
    
    let cropFactor: CGVector = CGVector(dx: CGFloat(cropResolution.w) / CGFloat(imageResolution.w),
                                        dy: CGFloat(cropResolution.h) / CGFloat(imageResolution.h))

    let uvCenter: CGVector = CGVector(dx: verticalCenter, dy: 1.0 - horizontalCenter)

    let cropLeft: CGFloat = uvCenter.dx - cropFactor.dx / 2.0
    let cropRight: CGFloat = uvCenter.dx + cropFactor.dx / 2.0
    let cropBottom: CGFloat = uvCenter.dy - cropFactor.dy / 2.0
    let cropTop: CGFloat = uvCenter.dy + cropFactor.dy / 2.0
    
//    if !autoResolution {
//
//        func roundBy10(_ value: CGFloat) -> CGFloat {
//            round(value * 10) / 10
//        }
//
//        while roundBy10((cropRight - cropLeft) * imageResolution.width.cg) != roundBy10(cropResolution.width.cg) {
//            let fraction: CGFloat = 0.1 * (1.0 / roundBy10(cropResolution.width.cg))
//            if roundBy10((cropRight - cropLeft) * imageResolution.width.cg) < roundBy10(cropResolution.width.cg) {
//                cropLeft -= fraction
//                cropRight += fraction
//                print("nudge +")
//            } else {
//                cropLeft += fraction
//                cropRight -= fraction
//                print("nudge -")
//            }
//        }
//
//        while roundBy10((cropTop - cropBottom) * imageResolution.height.cg) != roundBy10(cropResolution.height.cg) {
//            let fraction: CGFloat = 0.1 * (1.0 / roundBy10(cropResolution.height.cg))
//            if roundBy10((cropTop - cropBottom) * imageResolution.height.cg) < roundBy10(cropResolution.height.cg) {
//                cropBottom -= fraction
//                cropTop += fraction
//                print("nudge +")
//            } else {
//                cropBottom += fraction
//                cropTop -= fraction
//                print("nudge -")
//            }
//        }
//
//    }

    cropPix.cropLeft = cropLeft
    cropPix.cropRight = cropRight
    cropPix.cropBottom = cropBottom
    cropPix.cropTop = cropTop
    
    print("\(i + 1)/\(count) will render")
    var outImg: NSImage!
    let group = DispatchGroup()
    group.enter()
    try! PixelKit.main.render.engine.manuallyRender {
        guard let img: NSImage = finalPix.renderedImage else {
            print("\(i + 1)/\(count) render failed")
            exit(EXIT_FAILURE)
        }
        if !autoResolution {
            guard img.size == cropResolution.size.cg else {
                fatalError("bad resolution: \(img.size)")
            }
        }
        outImg = img
        group.leave()
    }
    group.wait()
    print("\(i + 1)/\(count) did render")

    let bitmap = NSBitmapImageRep(data: outImg.tiffRepresentation!)!
    let data: Data = bitmap.representation(using: .jpeg, properties: [.compressionFactor:0.8])!
    try data.write(to: saveURL)
}

print("done!")
