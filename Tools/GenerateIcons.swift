import Foundation
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers

let root = URL(fileURLWithPath: CommandLine.arguments[1])
let ios = root.appendingPathComponent("platforms/ios/App/Assets.xcassets/AppIcon.appiconset")
let windows = root.appendingPathComponent("platforms/windows/Resources")
try FileManager.default.createDirectory(at: ios, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: windows, withIntermediateDirectories: true)

func icon(_ size: Int) -> Data {
    let context = CGContext(data: nil,width: size,height: size,bitsPerComponent: 8,bytesPerRow: size * 4,
                            space: CGColorSpaceCreateDeviceRGB(),bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    context.setFillColor(CGColor(red: 0.08,green: 0.23,blue: 0.45,alpha: 1))
    context.fill(CGRect(x: 0,y: 0,width: size,height: size))
    let font = CTFontCreateWithName("PingFangTC-Medium" as CFString,CGFloat(size) * 0.65,nil)
    let string = NSAttributedString(string: "ㄅ",attributes: [NSAttributedString.Key(kCTFontAttributeName as String):font,
        NSAttributedString.Key(kCTForegroundColorAttributeName as String):CGColor(gray: 1,alpha: 1)])
    let line = CTLineCreateWithAttributedString(string)
    let bounds = CTLineGetBoundsWithOptions(line,.useGlyphPathBounds)
    context.textPosition = CGPoint(x: (CGFloat(size) - bounds.width) / 2 - bounds.minX,y: (CGFloat(size) - bounds.height) / 2 - bounds.minY)
    CTLineDraw(line,context)
    let data = NSMutableData()
    let destination = CGImageDestinationCreateWithData(data,UTType.png.identifier as CFString,1,nil)!
    CGImageDestinationAddImage(destination,context.makeImage()!,nil)
    precondition(CGImageDestinationFinalize(destination))
    return data as Data
}
try icon(1024).write(to: ios.appendingPathComponent("AppIcon.png"))
let contents = """
{"images":[{"filename":"AppIcon.png","idiom":"universal","platform":"ios","size":"1024x1024"}],"info":{"author":"xcode","version":1}}
"""
try Data(contents.utf8).write(to: ios.appendingPathComponent("Contents.json"))
func little<T: FixedWidthInteger>(_ value: T) -> Data { withUnsafeBytes(of: value.littleEndian) { Data($0) } }
let sizes = [16,32,48,256]
let images = sizes.map(icon)
var data = little(UInt16(0)) + little(UInt16(1)) + little(UInt16(sizes.count))
var offset = UInt32(6 + sizes.count * 16)
for (index,size) in sizes.enumerated() {
    data += Data([UInt8(size == 256 ? 0 : size),UInt8(size == 256 ? 0 : size),0,0])
    data += little(UInt16(1)) + little(UInt16(32)) + little(UInt32(images[index].count)) + little(offset)
    offset += UInt32(images[index].count)
}
for image in images { data += image }
try data.write(to: windows.appendingPathComponent("Jianfan.ico"))
