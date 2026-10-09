import AppKit
import Foundation

// Reinstall the approved artwork; never redraw the old placeholder paw icon.
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let catalog = root.appendingPathComponent("Resources/Assets.xcassets")
let source = root.appendingPathComponent("Resources/Branding/my-fur-baby-icon.png")
let data = try Data(contentsOf: source)
guard let image = NSBitmapImageRep(data: data),
      image.pixelsWide == 1024, image.pixelsHigh == 1024, !image.hasAlpha else {
    fatalError("The approved app icon must be an opaque 1024 × 1024 PNG.")
}

func writeContents(_ value: [String: Any], to directory: URL) throws {
    try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
        .write(to: directory.appendingPathComponent("Contents.json"))
}

let info: [String: Any] = ["author": "xcode", "version": 1]
let iconSet = catalog.appendingPathComponent("AppIcon.appiconset")
try FileManager.default.createDirectory(at: iconSet, withIntermediateDirectories: true)
try data.write(to: iconSet.appendingPathComponent("AppIcon.png"))
try writeContents([
    "images": [["filename": "AppIcon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"]],
    "info": info
], to: iconSet)

// Compact renditions keep the same art inexpensive in app headers and widgets.
let brandSet = catalog.appendingPathComponent("FurBrandIcon.imageset")
try FileManager.default.createDirectory(at: brandSet, withIntermediateDirectories: true)
var images: [[String: String]] = []
for scale in 1...3 {
    let filename = "FurBrandIcon@\(scale)x.png"
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
    process.arguments = ["-z", "\(128 * scale)", "\(128 * scale)", source.path, "--out", brandSet.appendingPathComponent(filename).path]
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { fatalError("Could not resize the brand icon.") }
    images.append(["filename": filename, "idiom": "universal", "scale": "\(scale)x"])
}
try writeContents(["images": images, "info": info], to: brandSet)
try writeContents(["info": info], to: catalog)
