import XCTest
import SwiftUI
import CoreText
@testable import MyFurBaby

final class WidgetMotionTests: XCTestCase {
    func testSavedActionMigratesWithoutLosingFramesAndEncodesCurrentKeys() throws {
        var pet = FurPet.sample
        pet.playfulArtwork = "old-sheet.png"
        pet.playfulAnimation = PetAnimation(kind: "playful", fps: 15, width: 64, height: 64,
            files: ["old-lick-frame_0001.png", "old-lick-frame_0002.png"])
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(pet)) as? [String: Any])
        json["lickingArtwork"] = json.removeValue(forKey: "playfulArtwork")
        var animation = try XCTUnwrap(json.removeValue(forKey: "playfulAnimation") as? [String: Any])
        animation["kind"] = "lick"
        json["lickingAnimation"] = animation
        let restored = try JSONDecoder().decode(FurPet.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(restored.playfulArtwork, pet.playfulArtwork)
        XCTAssertEqual(restored.playfulAnimation, pet.playfulAnimation)
        XCTAssertTrue(try XCTUnwrap(restored.playfulAnimation).isValid)
        XCTAssertEqual(restored.animation(kind: "playful"), pet.playfulAnimation)
        let current = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(restored)) as? [String: Any])
        XCTAssertNotNil(current["playfulAnimation"])
        XCTAssertNil(current["lickingAnimation"])
        XCTAssertNil(current["lickingArtwork"])
    }

    func testWidgetEntryRefreshKeepsPlaybackPhaseAcrossClockBoundaries() {
        for timing in [WidgetMotionTiming(fps: 15, period: 3, idle: 10),
                       WidgetMotionTiming(fps: 15, period: 4)] {
            let before = Date(timeIntervalSinceReferenceDate: 3599.9)
            let after = before.addingTimeInterval(0.2)
            let renderDate = after.addingTimeInterval(0.7)
            let cycle = Double(timing.cyclePeriod)
            let oldPhase = renderDate.timeIntervalSince(timing.referenceDate(at: before)).truncatingRemainder(dividingBy: cycle)
            let newPhase = renderDate.timeIntervalSince(timing.referenceDate(at: after)).truncatingRemainder(dividingBy: cycle)
            XCTAssertEqual(oldPhase, newPhase, accuracy: 0.000001)
        }
    }

    @MainActor func testPreviewPreloadsBoundedDecodedFramesAndRejectsIncompleteSequence() async throws {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = false
        let data = UIGraphicsImageRenderer(size: CGSize(width: 512, height: 512), format: format).image { context in
            UIColor.red.setFill(); context.fill(CGRect(x: 100, y: 100, width: 200, height: 200))
        }.pngData()!
        let animation = try SharedStorage.saveAnimation(AnimationPayload(kind: "lick", fps: 15,
            width: 512, height: 512, frameCount: 2, duration: 2.0 / 15,
            framesBase64: [data.base64EncodedString(), data.base64EncodedString()]), petID: UUID().uuidString)
        defer { for file in animation.files { try? FileManager.default.removeItem(at: SharedStorage.directory.appendingPathComponent(file)) } }
        XCTAssertEqual(animation.kind, "playful")
        let loaded = await SharedStorage.playbackImages(for: animation)
        let images = try XCTUnwrap(loaded)
        XCTAssertEqual(images.count, 2)
        for image in images {
            let bitmap = try XCTUnwrap(image.cgImage)
            XCTAssertEqual(bitmap.width, 384)
            XCTAssertEqual(bitmap.height, 384)
            XCTAssertTrue([.first, .last, .premultipliedFirst, .premultipliedLast].contains(bitmap.alphaInfo))
        }
        var missing = animation; missing.files[1] = UUID().uuidString + ".png"
        let incomplete = await SharedStorage.playbackImages(for: missing)
        XCTAssertNil(incomplete)
    }

    @MainActor func testRunningIsUnavailableAndSavedRunningMoodUsesPlayful() throws {
        XCTAssertEqual(PetBehavior.widgetCases, [.auto, .playful, .sleepy])
        XCTAssertEqual(try JSONDecoder().decode(PetBehavior.self, from: Data(#""running""#.utf8)).widgetBehavior, .playful)
        let suite = "widget-running-migration-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("running", forKey: "behavior")
        let store = FurStore(defaults: defaults, sessionReader: { _ in nil })
        XCTAssertEqual(store.behavior, .playful)
        store.setBehavior(.running)
        XCTAssertEqual(store.behavior, .playful)
        XCTAssertEqual(defaults.string(forKey: "behavior"), "playful")
    }
    @MainActor func testThreeSecondVideoRetainsEveryDistinctPose() throws {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = false
        let data = (0..<45).map { index in
            UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64), format: format).image { context in
                UIColor.red.setFill(); context.fill(CGRect(x: index + 2, y: 20, width: 8, height: 8))
            }.pngData()!
        }
        let sequence = try SharedStorage.saveAnimation(AnimationPayload(kind: "playful", fps: 15,
            width: 64, height: 64, frameCount: 45, duration: 3,
            framesBase64: data.map { $0.base64EncodedString() }), petID: UUID().uuidString)
        var pet = FurPet.sample; pet.isSample = false; pet.playfulAnimation = sequence
        let frames = try WidgetMotionFrameStorage.prepare(pet: pet)
        defer { for file in sequence.files + frames.playful {
            try? FileManager.default.removeItem(at: SharedStorage.directory.appendingPathComponent(file))
        } }
        XCTAssertEqual(frames.playfulTiming, WidgetMotionTiming(fps: 15, period: 3, idle: 10))
        XCTAssertEqual(frames.playful.count, 75)
        let poses = try frames.playful.map { try Data(contentsOf: SharedStorage.directory.appendingPathComponent($0)) }
        XCTAssertEqual(Set(poses).count, 45, "Floating-point timestamp rounding must not duplicate or skip source poses")
    }
    @MainActor func testRGBASequencePreservesCanvasAndWidgetSamplesWithoutCropping() throws {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = false
        let images = (0..<60).map { index in
            UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64), format: format).image { context in
                UIColor.red.setFill(); context.fill(CGRect(x: 4 + index % 40, y: 20, width: 12, height: 12))
            }.pngData()!
        }
        let id = UUID().uuidString
        let payload = AnimationPayload(kind: "run", fps: 15, width: 64, height: 64,
            frameCount: 60, duration: 4, framesBase64: images.map { $0.base64EncodedString() })
        let sequence = try SharedStorage.saveAnimation(payload, petID: id)
        var pet = FurPet(id: id, name: "Test", recipe: .sample, createdAt: Date(), isSample: false)
        pet.runningAnimation = sequence
        pet.playfulAnimation = sequence
        let frames = try WidgetMotionFrameStorage.prepare(pet: pet)
        defer {
            for file in sequence.files + frames.playful {
                try? FileManager.default.removeItem(at: SharedStorage.directory.appendingPathComponent(file))
            }
        }
        XCTAssertEqual(sequence.frameIndex(at: 0), 0)
        XCTAssertEqual(sequence.frameIndex(at: 0.1), 1)
        XCTAssertEqual(sequence.frameIndex(at: sequence.duration), 0)
        XCTAssertEqual(sequence.frameIndex(at: sequence.duration + 20), 0)
        XCTAssertEqual(sequence.frameIndex(at: .infinity), 0)
        XCTAssertNil(frames.running)
        XCTAssertNil(frames.runningTiming)
        XCTAssertEqual(frames.images(sleeping: false)?.count, 90)
        XCTAssertEqual(frames.playfulTiming, WidgetMotionTiming(fps: 15, period: 4, idle: 10))
        for image in try XCTUnwrap(frames.images(sleeping: false)) {
            let source = try XCTUnwrap(image.cgImage)
            XCTAssertEqual(source.width, 192)
            XCTAssertEqual(source.height, 192)
            var pixels = [UInt8](repeating: 0, count: source.width * source.height * 4)
            try pixels.withUnsafeMutableBytes { buffer in
                let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: source.width,
                    height: source.height, bitsPerComponent: 8, bytesPerRow: source.width * 4,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
                context.draw(source, in: CGRect(x: 0, y: 0, width: source.width, height: source.height))
            }
            // No colored square may cover the room, but the moving pet must remain visible.
            XCTAssertEqual(pixels[3], 0)
            XCTAssertEqual(pixels[pixels.count - 1], 0)
            XCTAssertTrue(stride(from: 3, to: pixels.count, by: 4).contains { pixels[$0] > 0 })
        }
        let restored = try JSONDecoder().decode(FurPet.self, from: JSONEncoder().encode(pet))
        XCTAssertEqual(restored.runningAnimation, sequence)
        for (index, file) in sequence.files.enumerated() {
            XCTAssertEqual(try Data(contentsOf: SharedStorage.directory.appendingPathComponent(file)), images[index])
            XCTAssertEqual(SharedStorage.image(file)?.cgImage?.width, 64)
        }
        var invalid = payload; invalid.width = 65
        XCTAssertThrowsError(try SharedStorage.saveAnimation(invalid, petID: UUID().uuidString))
    }
    @MainActor func testImageFramesAreDistinctCachedAndDecodeWithoutFonts() throws {
        var pet = FurPet.sample
        pet.recipe.personality = UUID().uuidString
        let frames = try WidgetMotionFrameStorage.prepare(pet: pet)
        let files = frames.playful + frames.sleepy
        defer { for file in files { try? FileManager.default.removeItem(at: SharedStorage.directory.appendingPathComponent(file)) } }
        XCTAssertEqual(frames.images(sleeping: false)?.count, 90)
        XCTAssertEqual(frames.images(sleeping: true)?.count, 60)
        let before = try files.map { try Data(contentsOf: SharedStorage.directory.appendingPathComponent($0)) }
        // The sample's sinusoidal loop returns to its starting pose midway through.
        XCTAssertGreaterThan(Set(before.prefix(4)).count, 1)
        XCTAssertGreaterThan(Set(before.suffix(4)).count, 1)
        XCTAssertEqual(try WidgetMotionFrameStorage.prepare(pet: pet), frames)
        let after = try files.map { try Data(contentsOf: SharedStorage.directory.appendingPathComponent($0)) }
        XCTAssertEqual(before, after)
        let snapshot = WidgetSnapshot(pet: pet, experimentalMotion: true, motionFrames: frames)
        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: JSONEncoder().encode(snapshot))
        XCTAssertEqual(decoded.motionFrames, frames)
        XCTAssertNil(decoded.motionFonts)
    }

    @MainActor func testMissingOrInvalidImageFramesUseStaticFallback() throws {
        var pet = FurPet.sample; pet.isSample = false
        let frames = try WidgetMotionFrameStorage.prepare(pet: pet)
        XCTAssertNil(frames.images(sleeping: false))
        XCTAssertNil(frames.images(sleeping: true))
        XCTAssertNil(WidgetMotionFrames(playful: Array(repeating: "../outside.png", count: 4)).images(sleeping: false))
        XCTAssertNil(WidgetMotionFrames(playful: Array(repeating: UUID().uuidString + ".png", count: 4)).images(sleeping: false))
    }

    func testOriginalMaskShapesSecondsAsAlternatingLigatures() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "FurTimerMask", withExtension: "otf"))
        XCTAssertTrue(CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil))
        defer { CTFontManagerUnregisterFontsForURL(url as CFURL, .process, nil) }
        let font = CTFontCreateWithName("Custom-Regular" as CFString, 16, nil)
        func glyph(for seconds: String) throws -> CGGlyph {
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: seconds,
                attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font]))
            let run = try XCTUnwrap((CTLineGetGlyphRuns(line) as? [CTRun])?.first)
            XCTAssertEqual(CTRunGetGlyphCount(run), 1)
            var glyph: CGGlyph = 0; CTRunGetGlyphs(run, CFRange(location: 0, length: 1), &glyph)
            return glyph
        }
        XCTAssertEqual(try glyph(for: "00"), try glyph(for: "58"))
        XCTAssertEqual(try glyph(for: "01"), try glyph(for: "59"))
        XCTAssertNotEqual(try glyph(for: "00"), try glyph(for: "01"))
        let visible = try glyph(for: "00")
        // The transparent renderer uses two masks to isolate one pose at a time.
        // Exercise all eight slots, including wraparound, using the actual bundled font.
        for tick in 0..<80 {
            let elapsed = 60 + (Double(tick) + 0.5) / 40
            var active: [Int] = []
            for index in 0..<8 {
                let first = Int(floor(elapsed - Double(index) / 4)) % 60
                let second = Int(floor(elapsed - Double(index + 5) / 4)) % 60
                if try glyph(for: String(format: "%02d", first)) == visible,
                   try glyph(for: String(format: "%02d", second)) == visible { active.append(index) }
            }
            XCTAssertEqual(active, [tick / 10])
        }
    }

    func testBundledVideoMasksExposeOneFrameAt15FPSIncludingMinuteWrap() throws {
        for period in [3, 4] {
            let url = try XCTUnwrap(Bundle.main.url(forResource: "FurCycle\(period)-Regular", withExtension: "ttf"))
            XCTAssertTrue(CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil))
            defer { CTFontManagerUnregisterFontsForURL(url as CFURL, .process, nil) }
            let font = CTFontCreateWithName("FurCycle\(period)-Regular" as CFString, 16, nil)
            func isVisible(_ seconds: Int) throws -> Bool {
                let line = CTLineCreateWithAttributedString(NSAttributedString(string: String(format: "%02d", seconds % 60),
                    attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font]))
                let run = try XCTUnwrap((CTLineGetGlyphRuns(line) as? [CTRun])?.first)
                XCTAssertEqual(CTRunGetGlyphCount(run), 1)
                var glyph: CGGlyph = 0; CTRunGetGlyphs(run, CFRange(location: 0, length: 1), &glyph)
                return !(CTFontCreatePathForGlyph(font, glyph, nil)?.isEmpty ?? true)
            }
            for seconds in 0..<60 { XCTAssertEqual(try isVisible(seconds), seconds % period == 0) }
            for tick in 0..<(period * 15 * 2) {
                let elapsed = 120 + (Double(tick) + 0.5) / 15
                var active: [Int] = []
                for index in 0..<(period * 15) {
                    let first = Int(floor(elapsed - Double(index) / 15))
                    let second = Int(floor(elapsed - Double(index + 1 - 15) / 15))
                    if try isVisible(first), try isVisible(second) { active.append(index) }
                }
                XCTAssertEqual(active, [tick % (period * 15)])
            }
        }
    }

    func testActionAndTenSecondIdleCycleHasNoStillHold() {
        for duration in [3.0, 4.0] {
            for cycle in 0..<3 {
                let start = Double(cycle) * (duration + 10)
                XCTAssertFalse(PetPlayback.isIdle(at: start, duration: duration))
                XCTAssertFalse(PetPlayback.isIdle(at: start + duration - 0.01, duration: duration))
                XCTAssertTrue(PetPlayback.isIdle(at: start + duration, duration: duration))
                XCTAssertTrue(PetPlayback.isIdle(at: start + duration + 9.99, duration: duration))
                XCTAssertFalse(PetPlayback.isIdle(at: start + duration + 10, duration: duration))
                XCTAssertEqual(PetPlayback.time(at: start + 1, duration: duration), 1)
            }
        }
        let idle = PetAnimation(kind: "idle", fps: 15, width: 64, height: 64,
            files: (0..<30).map { "idle\($0).png" })
        XCTAssertTrue(idle.isValid)
        for loop in 0..<5 {
            XCTAssertEqual(idle.frameIndex(at: Double(loop) * 2), 0)
            XCTAssertEqual(idle.frameIndex(at: Double(loop) * 2 + 1), 15)
        }
        XCTAssertEqual(PetPlayback.phase(at: .infinity, duration: 4), 0)
    }

    @MainActor func testIdleFramesRepeatFiveTimesWithoutDuplicatingImageStorage() throws {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = false
        func sequence(kind: String, count: Int, color: UIColor) throws -> PetAnimation {
            let frames = (0..<count).map { index in
                UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64), format: format).image { context in
                    color.setFill(); context.fill(CGRect(x: index + 2, y: 20, width: 8, height: 8))
                }.pngData()!
            }
            return try SharedStorage.saveAnimation(AnimationPayload(kind: kind, fps: 15,
                width: 64, height: 64, frameCount: count, duration: Double(count) / 15,
                framesBase64: frames.map { $0.base64EncodedString() }), petID: UUID().uuidString)
        }
        let action = try sequence(kind: "playful", count: 45, color: .red)
        let idle = try sequence(kind: "idle", count: 30, color: .blue)
        var pet = FurPet.sample; pet.isSample = false
        pet.playfulAnimation = action; pet.idleAnimation = idle
        let frames = try WidgetMotionFrameStorage.prepare(pet: pet)
        defer { for file in Set(action.files + idle.files + frames.playful) {
            try? FileManager.default.removeItem(at: SharedStorage.directory.appendingPathComponent(file))
        } }
        XCTAssertEqual(frames.playful.count, 75)
        XCTAssertEqual(Set(frames.playful).count, 75, "Ten seconds of idle reuses thirty image files")
        let firstIdle = Array(frames.playful[45..<75])
        XCTAssertEqual(firstIdle.count, 30)
        let images = try XCTUnwrap(frames.images(sleeping: false))
        XCTAssertEqual(images.count, 75, "Five loops keep thirty idle image layers")
        XCTAssertEqual(frames.playfulTiming?.cyclePeriod, 13)
        XCTAssertFalse(frames.playfulTiming?.hasHold ?? true)
    }

    func testIdleMasksCoverHandoffsAcrossActionIdleAndClockBoundaries() throws {
        for period in [2, 3, 4] {
            let timing = WidgetMotionTiming(fps: 15, period: period, idle: 10)
            let names = [timing.fontName, timing.idleFontName]
            var fonts: [CTFont] = []
            for name in names {
                let url = try XCTUnwrap(Bundle.main.url(forResource: name, withExtension: "ttf"))
                XCTAssertTrue(CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil))
                fonts.append(CTFontCreateWithName(name as CFString, 16, nil))
            }
            defer { for name in names {
                if let url = Bundle.main.url(forResource: name, withExtension: "ttf") {
                    CTFontManagerUnregisterFontsForURL(url as CFURL, .process, nil)
                }
            } }
            var visibility: [String: Bool] = [:]
            func visible(_ seconds: Int, idle: Bool) throws -> Bool {
                let key = "\(seconds)-\(idle)"
                if let result = visibility[key] { return result }
                let line = CTLineCreateWithAttributedString(NSAttributedString(string: String(seconds),
                    attributes: [NSAttributedString.Key(kCTFontAttributeName as String): fonts[idle ? 1 : 0]]))
                let run = try XCTUnwrap((CTLineGetGlyphRuns(line) as? [CTRun])?.first)
                XCTAssertEqual(CTRunGetGlyphCount(run), 1)
                var glyph: CGGlyph = 0; CTRunGetGlyphs(run, CFRange(location: 0, length: 1), &glyph)
                let result = !(CTFontCreatePathForGlyph(fonts[idle ? 1 : 0], glyph, nil)?.isEmpty ?? true)
                visibility[key] = result
                return result
            }
            for seconds in Array(0..<180) + Array(3595..<3610) + [36_000, 86_399, 99_999] {
                let phase = seconds % timing.cyclePeriod
                XCTAssertEqual(try visible(seconds, idle: false), phase == 0)
                XCTAssertEqual(try visible(seconds, idle: true), phase < 10 && phase % 2 == 0)
            }
            for start in [120, 3580] {
                for tick in 0..<(timing.cyclePeriod * timing.fps * 2 * 8) {
                    let elapsed = Double(start) + (Double(tick) + 0.5) / Double(timing.fps * 8)
                    var active: [Int] = []
                    for index in 0..<timing.imageCount {
                        let idle = index >= timing.slotCount
                        let localIndex = idle ? index - timing.slotCount : index
                        let offset = idle ? Double(period) : 0
                        let first = Int(floor(elapsed - offset - Double(localIndex) / Double(timing.fps)))
                        let second = Int(floor(elapsed - offset - timing.closingMaskOffset(index: localIndex)))
                        if try visible(first, idle: idle), try visible(second, idle: idle) { active.append(index) }
                    }
                    let phase = elapsed.truncatingRemainder(dividingBy: Double(timing.cyclePeriod))
                    let expected = phase < Double(period) ? Int(phase * 15)
                        : timing.slotCount + Int((phase - Double(period)).truncatingRemainder(dividingBy: 2) * 15)
                    XCTAssertTrue(active.contains(expected), "The current pose must be visible at \(elapsed)")
                    XCTAssertTrue((1...2).contains(active.count), "No blank frames or unrelated overlapping poses at \(elapsed)")
                    if phase.truncatingRemainder(dividingBy: 1.0 / 15) > timing.handoffOverlap + 0.00001 {
                        XCTAssertEqual(active, [expected])
                    }
                }
            }
        }
    }

    func testHoldMasksKeepExactlyOnePoseAcrossLoopMinuteAndHourBoundaries() throws {
        for period in [2, 3, 4] {
            let timing = WidgetMotionTiming(fps: period == 2 ? 4 : 15, period: period, hold: 20)
            let names = [timing.fontName, timing.holdFontName]
            var fonts: [CTFont] = []
            for name in names {
                let url = try XCTUnwrap(Bundle.main.url(forResource: name, withExtension: "ttf"))
                XCTAssertTrue(CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil))
                fonts.append(CTFontCreateWithName(name as CFString, 16, nil))
            }
            defer { for name in names {
                if let url = Bundle.main.url(forResource: name, withExtension: "ttf") {
                    CTFontManagerUnregisterFontsForURL(url as CFURL, .process, nil)
                }
            } }
            var visibility: [String: Bool] = [:]
            func visible(_ seconds: Int, holding: Bool) throws -> Bool {
                let key = "\(seconds)-\(holding)"
                if let result = visibility[key] { return result }
                let value = max(0, seconds)
                let text = String(value)
                let font = fonts[holding ? 1 : 0]
                let line = CTLineCreateWithAttributedString(NSAttributedString(string: text,
                    attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font]))
                let run = try XCTUnwrap((CTLineGetGlyphRuns(line) as? [CTRun])?.first)
                XCTAssertEqual(CTRunGetGlyphCount(run), 1, text)
                var glyph: CGGlyph = 0; CTRunGetGlyphs(run, CFRange(location: 0, length: 1), &glyph)
                let result = !(CTFontCreatePathForGlyph(font, glyph, nil)?.isEmpty ?? true)
                visibility[key] = result
                return result
            }
            for seconds in Array(0..<180) + Array(3595..<3610) + [36_000, 86_399, 99_999] {
                XCTAssertEqual(try visible(seconds, holding: false), seconds % timing.cyclePeriod == 0)
                XCTAssertEqual(try visible(seconds, holding: true), seconds % timing.cyclePeriod >= period)
            }
            for start in [120, 3580] {
                for tick in 0..<(timing.cyclePeriod * timing.fps * 2) {
                    let elapsed = Double(start) + (Double(tick) + 0.5) / Double(timing.fps)
                    var active: [Int] = []
                    for index in 0..<timing.slotCount {
                        let first = Int(floor(elapsed - Double(index) / Double(timing.fps)))
                        let second = Int(floor(elapsed - Double(index + 1 - timing.fps) / Double(timing.fps)))
                        if try visible(first, holding: false), try visible(second, holding: false) { active.append(index) }
                    }
                    if try visible(Int(floor(elapsed)), holding: true) { active.append(timing.slotCount - 1) }
                    let phase = elapsed.truncatingRemainder(dividingBy: Double(timing.cyclePeriod))
                    let expected = min(timing.slotCount - 1, Int(phase * Double(timing.fps)))
                    XCTAssertEqual(active, [expected], "period \(period), elapsed \(elapsed)")
                }
            }
        }
    }

    func testLegacyFrameMetadataKeepsItsCadenceAndRejectsInvalidTiming() throws {
        let old = Data(#"{"playful":[],"sleepy":[],"running":[]}"#.utf8)
        var frames = try JSONDecoder().decode(WidgetMotionFrames.self, from: old)
        XCTAssertEqual(frames.timing(sleeping: false), .legacy)
        let oldTiming = try JSONDecoder().decode(WidgetMotionTiming.self, from: Data(#"{"fps":15,"period":3}"#.utf8))
        XCTAssertFalse(oldTiming.hasHold)
        XCTAssertEqual(oldTiming.fontName, "FurCycle3-Regular")
        XCTAssertFalse(WidgetMotionTiming(fps: 15, period: 3, hold: -20).isValid)
        frames.playfulTiming = WidgetMotionTiming(fps: 0, period: 4)
        XCTAssertNil(frames.images(sleeping: false))
        frames.playfulTiming = WidgetMotionTiming(fps: 15, period: 5)
        XCTAssertNil(frames.images(sleeping: false))
    }

    @MainActor func testBitmapFontRendersAllTimerDigitsAndLeavesSeparatorsEmpty() throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16)).image { context in
            UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
        }
        let templateURL = try XCTUnwrap(Bundle.main.url(forResource: "FurMotionTemplate", withExtension: "ttf"))
        let name = "FurMotionTest" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let data = try BitmapMotionFont.make(template: Data(contentsOf: templateURL), png: XCTUnwrap(image.pngData()), name: name, pixels: 16)
        XCTAssertEqual(BitmapMotionFont.checksum(data), 0xB1B0AFBA)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name + ".ttf")
        try data.write(to: url)
        defer { CTFontManagerUnregisterFontsForURL(url as CFURL, .process, nil); try? FileManager.default.removeItem(at: url) }
        XCTAssertTrue(CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil))
        let font = CTFontCreateWithName(name as CFString, 16, nil)
        XCTAssertEqual(CTFontCopyPostScriptName(font) as String, name)
        func render(_ char: UniChar) throws -> Data {
            var character = char, glyph: CGGlyph = 0
            XCTAssertTrue(CTFontGetGlyphsForCharacters(font, &character, &glyph, 1))
            let rendered = UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16)).image { context in
                context.cgContext.translateBy(x: 0, y: 16); context.cgContext.scaleBy(x: 1, y: -1)
                var point = CGPoint.zero
                CTFontDrawGlyphs(font, &glyph, &point, 1, context.cgContext)
            }
            return try XCTUnwrap(rendered.pngData())
        }
        let zero = try render(48), blank = try render(58)
        XCTAssertNotEqual(zero, blank, "The bitmap glyph must contain visible artwork")
        for character: UniChar in 49...57 { XCTAssertEqual(try render(character), zero, "Every timer digit must render the same pose") }
        XCTAssertEqual(try render(32), blank)
    }

    @MainActor func testSamplePreparesBothMoodsAndReusesSavedFonts() throws {
        var pet = FurPet.sample
        pet.recipe.personality = UUID().uuidString
        let fonts = try WidgetMotionFontStorage.prepare(pet: pet)
        let files = fonts.playful + fonts.sleepy
        defer { for file in files { try? FileManager.default.removeItem(at: WidgetMotionFontStorage.directory.appendingPathComponent(file)) } }
        XCTAssertEqual(fonts.playful.count, 4); XCTAssertEqual(fonts.sleepy.count, 4)
        XCTAssertEqual(Set(files).count, 8)
        let before = try files.map { try Data(contentsOf: WidgetMotionFontStorage.directory.appendingPathComponent($0)) }
        XCTAssertEqual(Set(before).count, 8, "Each playful and sleeping pose must be distinct")
        XCTAssertEqual(try WidgetMotionFontStorage.prepare(pet: pet), fonts)
        let after = try files.map { try Data(contentsOf: WidgetMotionFontStorage.directory.appendingPathComponent($0)) }
        XCTAssertEqual(before, after)
    }

    @MainActor func testPetWithoutAnimationSheetsUsesStaticFallback() throws {
        var pet = FurPet.sample; pet.isSample = false
        let fonts = try WidgetMotionFontStorage.prepare(pet: pet)
        XCTAssertTrue(fonts.playful.isEmpty); XCTAssertTrue(fonts.sleepy.isEmpty)
        XCTAssertNil(WidgetMotionFontStorage.fontNames(files: fonts.playful))
        XCTAssertNil(WidgetMotionFontStorage.fontNames(files: Array(repeating: "../outside.ttf", count: 4)))
    }

    func testInvalidFontInputsAreRejected() {
        XCTAssertThrowsError(try BitmapMotionFont.make(template: Data(), png: Data(), name: "Unsafe/Name", pixels: 16))
    }

    func testLegacyWidgetSnapshotDecodesWithoutFonts() throws {
        let snapshot = WidgetSnapshot(pet: .sample)
        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: JSONEncoder().encode(snapshot))
        XCTAssertNil(decoded.motionFonts)
        XCTAssertNil(decoded.motionFrames)
    }
}
