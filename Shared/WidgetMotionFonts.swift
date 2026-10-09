import SwiftUI
import CoreText
import CryptoKit

struct WidgetMotionFonts: Codable, Equatable {
    var playful: [String] = []
    var sleepy: [String] = []

    func files(sleeping: Bool) -> [String] { sleeping ? sleepy : playful }
}

/// Artwork is prepared by the app once; the extension only registers existing fonts.
enum WidgetMotionFontStorage {
    private static let registrationLock = NSLock()
    private static var registered = Set<String>()
    static var directory: URL { SharedStorage.directory.appendingPathComponent("WidgetFonts", isDirectory: true) }

    @MainActor static func prepare(pet: FurPet) throws -> WidgetMotionFonts {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let templateURL = Bundle.main.url(forResource: "FurMotionTemplate", withExtension: "ttf") else {
            throw MotionFontError.missingTemplate
        }
        let template = try Data(contentsOf: templateURL)
        var result = WidgetMotionFonts()
        for sleeping in [false, true] {
            let artwork = sleeping ? pet.sleepingArtwork : pet.playfulArtwork
            guard pet.isSample || (artwork != nil && pet.animationFrames == 4) else { continue }
            let encoder = JSONEncoder()
            encoder.outputFormatting = .sortedKeys
            var identity = try encoder.encode(pet.recipe)
            identity.append(Data("bitmap-motion-v1-\(sleeping)".utf8))
            if let artwork {
                guard artwork == URL(fileURLWithPath: artwork).lastPathComponent else { throw MotionFontError.invalidFont }
                identity.append(try Data(contentsOf: SharedStorage.directory.appendingPathComponent(artwork)))
            }
            let digest = SHA256.hash(data: identity).prefix(12).map { String(format: "%02x", $0) }.joined()
            var files: [String] = []
            for frame in 0..<4 {
                let name = "FurMotion\(digest)F\(frame)"
                let file = name + ".ttf", url = directory.appendingPathComponent(file)
                if !FileManager.default.fileExists(atPath: url.path) {
                    // An opaque frame covers earlier layers, avoiding transparent-pet ghosting.
                    let renderer = ImageRenderer(content: PetArtworkView(pet: pet, sleeping: sleeping,
                        playful: !sleeping, phase: Double(frame) / 4)
                        .frame(width: 192, height: 192).background(FurTheme.lavender))
                    renderer.scale = 2
                    renderer.isOpaque = true
                    guard let png = renderer.uiImage?.pngData() else { throw MotionFontError.renderFailed }
                    try BitmapMotionFont.make(template: template, png: png, name: name, pixels: 384).write(to: url, options: .atomic)
                }
                files.append(file)
            }
            if sleeping { result.sleepy = files } else { result.playful = files }
        }
        return result
    }

    static func fontNames(files: [String]) -> [String]? {
        guard files.count == 4 else { return nil }
        registrationLock.lock()
        defer { registrationLock.unlock() }
        var names: [String] = []
        for file in files {
            guard file == URL(fileURLWithPath: file).lastPathComponent, file.hasPrefix("FurMotion"), file.hasSuffix(".ttf") else { return nil }
            let url = directory.appendingPathComponent(file), name = url.deletingPathExtension().lastPathComponent
            if !registered.contains(file) {
                guard CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil) else { return nil }
                registered.insert(file)
            }
            names.append(name)
        }
        return names
    }
}

enum MotionFontError: Error { case missingTemplate, renderFailed, invalidFont }

/// Builds a TrueType font with one PNG digit and sbix duplicate glyphs for the other digits.
/// All ten digits show the same pose; offset timers select the four poses in the widget.
enum BitmapMotionFont {
    static func make(template: Data, png: Data, name: String, pixels: UInt16) throws -> Data {
        guard template.count >= 12, png.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]),
              !name.isEmpty, name.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) }) else {
            throw MotionFontError.invalidFont
        }
        let count = Int(template.uint16(at: 4))
        guard count > 0, template.count >= 12 + count * 16 else { throw MotionFontError.invalidFont }
        var tables: [String: Data] = [:]
        for index in 0..<count {
            let base = 12 + index * 16
            guard let tag = String(data: template.subdata(in: base..<base + 4), encoding: .ascii) else { throw MotionFontError.invalidFont }
            let offset = Int(template.uint32(at: base + 8)), length = Int(template.uint32(at: base + 12))
            guard offset <= template.count, length <= template.count - offset else { throw MotionFontError.invalidFont }
            tables[tag] = template.subdata(in: offset..<offset + length)
        }
        // The bundled template has .notdef, space, colon, then digits 0 through 9.
        guard var head = tables["head"], head.count >= 54,
              let maxp = tables["maxp"], maxp.count >= 6, maxp.uint16(at: 4) == 13 else { throw MotionFontError.invalidFont }
        head.replaceSubrange(8..<12, with: [0, 0, 0, 0])
        tables["head"] = head
        tables["name"] = nameTable(name)
        tables["sbix"] = bitmapTable(png: png, pixels: pixels)
        let tags = tables.keys.sorted(), tableCount = tags.count
        let power = Int(pow(2, floor(log2(Double(tableCount)))))
        var output = Data()
        output.append32(0x00010000); output.append16(UInt16(tableCount))
        output.append16(UInt16(power * 16)); output.append16(UInt16(log2(Double(power))))
        output.append16(UInt16(tableCount * 16 - power * 16))
        var payload = Data(), headOffset = 0
        for tag in tags {
            let data = tables[tag]!, offset = 12 + tableCount * 16 + payload.count
            output.append(Data(tag.utf8)); output.append32(checksum(data))
            output.append32(UInt32(offset)); output.append32(UInt32(data.count))
            if tag == "head" { headOffset = offset }
            payload.append(data)
            while payload.count % 4 != 0 { payload.append(0) }
        }
        output.append(payload)
        var adjustment = Data(); adjustment.append32(0xB1B0AFBA &- checksum(output))
        output.replaceSubrange(headOffset + 8..<headOffset + 12, with: adjustment)
        return output
    }

    private static func nameTable(_ name: String) -> Data {
        let values: [(UInt16, String)] = [(1, name), (2, "Regular"), (3, name), (4, name), (5, "Version 1.0"), (6, name)]
        var table = Data(), strings = Data()
        table.append16(0); table.append16(UInt16(values.count)); table.append16(UInt16(6 + values.count * 12))
        for (id, text) in values {
            let encoded = text.data(using: .utf16BigEndian)!
            table.append16(3); table.append16(1); table.append16(0x0409); table.append16(id)
            table.append16(UInt16(encoded.count)); table.append16(UInt16(strings.count)); strings.append(encoded)
        }
        table.append(strings); return table
    }

    private static func bitmapTable(png: Data, pixels: UInt16) -> Data {
        var glyphs = Data(), offsets: [UInt32] = []
        let headerSize = 4 + 14 * 4
        for glyph in 0..<13 {
            offsets.append(UInt32(headerSize + glyphs.count))
            if glyph >= 3 {
                glyphs.append16(0); glyphs.append16(0)
                glyphs.append(Data((glyph == 3 ? "png " : "dupe").utf8))
                if glyph == 3 { glyphs.append(png) } else { glyphs.append16(3) }
            }
        }
        offsets.append(UInt32(headerSize + glyphs.count))
        var table = Data()
        table.append16(1); table.append16(1); table.append32(1); table.append32(12)
        table.append16(pixels); table.append16(72)
        offsets.forEach { table.append32($0) }; table.append(glyphs)
        return table
    }

    static func checksum(_ data: Data) -> UInt32 {
        var padded = data
        while padded.count % 4 != 0 { padded.append(0) }
        return stride(from: 0, to: padded.count, by: 4).reduce(0) { $0 &+ padded.uint32(at: $1) }
    }
}

private extension Data {
    func uint16(at offset: Int) -> UInt16 { UInt16(self[offset]) << 8 | UInt16(self[offset + 1]) }
    func uint32(at offset: Int) -> UInt32 { UInt32(uint16(at: offset)) << 16 | UInt32(uint16(at: offset + 2)) }
    mutating func append16(_ value: UInt16) { append(UInt8(value >> 8)); append(UInt8(value & 255)) }
    mutating func append32(_ value: UInt32) { append16(UInt16(value >> 16)); append16(UInt16(value & 65535)) }
}
