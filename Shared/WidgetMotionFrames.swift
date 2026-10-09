import SwiftUI
import CryptoKit

struct WidgetMotionTiming: Codable, Equatable {
    var fps: Int
    var period: Int
    var hold: Int? = nil
    var idle: Int? = nil
    static let legacy = WidgetMotionTiming(fps: 4, period: 2)
    var isValid: Bool { (1...15).contains(fps) && (2...4).contains(period) && (hold == nil || hold == 20) && (idle == nil || idle == 10) && !(hold != nil && idle != nil) }
    var slotCount: Int { fps * period }
    var idleFrameCount: Int { idle == nil ? 0 : fps * 2 }
    var imageCount: Int { slotCount + idleFrameCount }
    var idleFontName: String { "FurIdle\(cyclePeriod)-Regular" }
    var hasHold: Bool { hold == 20 }
    var cyclePeriod: Int { period + (hold ?? 0) + (idle ?? 0) }
    var usesElapsedSeconds: Bool { hasHold || idle != nil }
    // Allow one display refresh of overlap: independently rendered timers can
    // switch on different refreshes even when their mathematical boundaries match.
    var handoffOverlap: Double { min(1.0 / 60, 0.25 / Double(fps)) }
    func closingMaskOffset(index: Int) -> Double {
        Double(index + 1 - fps) / Double(fps) + handoffOverlap
    }
    func referenceDate(at date: Date) -> Date {
        let cycle = Double(cyclePeriod)
        // Entry reloads preserve the same phase instead of restarting mid-pose.
        let aligned = floor(date.timeIntervalSinceReferenceDate / cycle) * cycle
        return Date(timeIntervalSinceReferenceDate: aligned - cycle * 3)
    }
    var fontName: String { usesElapsedSeconds ? "FurLoop\(cyclePeriod)-Regular" : period == 2 ? "Custom-Regular" : "FurCycle\(period)-Regular" }
    var holdFontName: String { "FurRest\(cyclePeriod)-Regular" }
}

struct WidgetMotionFrames: Codable, Equatable {
    var playful: [String] = []
    var sleepy: [String] = []
    var running: [String]?
    var playfulTiming: WidgetMotionTiming?
    var sleepyTiming: WidgetMotionTiming?
    var runningTiming: WidgetMotionTiming?

    func timing(sleeping: Bool, isRunning: Bool = false) -> WidgetMotionTiming {
        (sleeping ? sleepyTiming : isRunning ? runningTiming : playfulTiming) ?? .legacy
    }

    func images(sleeping: Bool, isRunning: Bool = false) -> [UIImage]? {
        let files = sleeping ? sleepy : isRunning ? running ?? [] : playful
        let timing = timing(sleeping: sleeping, isRunning: isRunning)
        guard timing.isValid, files.count == timing.imageCount || (timing == .legacy && files.count == 4) else { return nil }
        let images = files.compactMap { SharedStorage.image($0) }
        return images.count == files.count ? images : nil
    }
}

/// Images are embedded in the widget's view archive. Only the bundled timer mask is a font.
enum WidgetMotionFrameStorage {
    @MainActor static func prepare(pet: FurPet) throws -> WidgetMotionFrames {
        var result = WidgetMotionFrames()
        for kind in ["playful", "sleep"] {
            let sleeping = kind == "sleep"
            let sequence = sleeping ? pet.sleepingAnimation : pet.playfulAnimation
            let artwork = sleeping ? pet.sleepingArtwork : pet.playfulArtwork
            guard sequence?.isValid == true || pet.isSample || (artwork != nil && pet.animationFrames == 4) else { continue }
            let timing: WidgetMotionTiming
            let frameCount: Int
            if let sequence, sequence.isValid {
                timing = WidgetMotionTiming(fps: min(15, sequence.fps), period: min(4, max(2, Int(sequence.duration.rounded(.up)))), idle: sleeping ? nil : 10)
                frameCount = timing.fps * timing.period
            } else if pet.isSample {
                timing = WidgetMotionTiming(fps: 15, period: 4, idle: sleeping ? nil : 10)
                frameCount = timing.fps * timing.period
            } else {
                timing = WidgetMotionTiming(fps: 1, period: 4, idle: sleeping ? nil : 10)
                frameCount = 4
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = .sortedKeys
            var identity = try encoder.encode(pet.recipe)
            identity.append(Data("widget-png-v8-playful-192-\(kind)".utf8))
            identity.append(try encoder.encode(timing))
            if let sequence {
                identity.append(try encoder.encode(sequence))
                for file in sequence.files {
                    identity.append(try Data(contentsOf: SharedStorage.directory.appendingPathComponent(file)))
                }
            } else if let artwork {
                guard artwork == URL(fileURLWithPath: artwork).lastPathComponent else { throw MotionFontError.invalidFont }
                identity.append(try Data(contentsOf: SharedStorage.directory.appendingPathComponent(artwork)))
            }
            let idleSequence = sleeping ? nil : pet.idleAnimation.flatMap { $0.isValid ? $0 : nil }
            if let idleSequence {
                identity.append(try encoder.encode(idleSequence))
                for file in idleSequence.files {
                    identity.append(try Data(contentsOf: SharedStorage.directory.appendingPathComponent(file)))
                }
            }
            let digest = SHA256.hash(data: identity).prefix(12).map { String(format: "%02x", $0) }.joined()
            var files: [String] = []
            for frame in 0..<frameCount {
                let file = "WidgetMotion\(digest)F\(frame).png"
                if SharedStorage.image(file) == nil {
                    let renderer = ImageRenderer(content: PetArtworkView(pet: pet, sleeping: sleeping,
                        playful: !sleeping, phase: Double(frame) / Double(frameCount),
                        animationFrame: sequence.map { frame * $0.files.count / frameCount })
                        .frame(width: 192, height: 192))
                    // Keep the complete timeline archive below WidgetKit's size limit.
                    renderer.scale = 1
                    renderer.isOpaque = false
                    guard let png = renderer.uiImage?.pngData() else { throw MotionFontError.renderFailed }
                    try SharedStorage.saveImage(png, named: file)
                }
                files.append(file)
            }
            if timing.idle != nil {
                var idleFiles: [String] = []
                if idleSequence != nil || pet.isSample {
                    // Fit the two-second idle loop to 30 slots. Store each image once.
                    let idleCount = timing.fps * 2
                    for frame in 0..<idleCount {
                        let file = "WidgetMotion\(digest)IdleF\(frame).png"
                        if SharedStorage.image(file) == nil {
                            let renderer = ImageRenderer(content: PetArtworkView(pet: pet, idling: true,
                                phase: Double(frame) / Double(idleCount),
                                animationFrame: idleSequence.map { frame * $0.files.count / idleCount })
                                .frame(width: 192, height: 192))
                            renderer.scale = 1
                            renderer.isOpaque = false
                            guard let png = renderer.uiImage?.pngData() else { throw MotionFontError.renderFailed }
                            try SharedStorage.saveImage(png, named: file)
                        }
                        idleFiles.append(file)
                    }
                } else {
                    // Existing pets keep moving until their new idle clip is generated.
                    idleFiles = (0..<timing.idleFrameCount).map { files[$0 * files.count / timing.idleFrameCount] }
                }
                files += idleFiles
            }
            if sleeping { result.sleepy = files; result.sleepyTiming = timing }
            else { result.playful = files; result.playfulTiming = timing }
        }
        return result
    }
}
