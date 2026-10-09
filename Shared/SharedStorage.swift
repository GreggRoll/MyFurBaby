import Foundation
import UIKit
import ImageIO

enum SharedStorage {
    static func saveWidgetBackgroundImage(_ data: Data, named filename: String) throws {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 640,
                kCGImageSourceCreateThumbnailWithTransform: true
              ] as CFDictionary), let bounded = UIImage(cgImage: image).pngData() else {
            throw CocoaError(.fileReadCorruptFile)
        }
        try saveImage(bounded, named: filename)
    }
    static func saveAdventureImages(_ data: Data, artwork: String, thumbnail: String) throws {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let preview = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 480,
                kCGImageSourceCreateThumbnailWithTransform: true
              ] as CFDictionary),
              let thumbnailData = UIImage(cgImage: preview).jpegData(compressionQuality: 0.85) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        try saveImage(data, named: artwork)
        try saveImage(thumbnailData, named: thumbnail)
    }
    static func saveAnimation(_ payload: AnimationPayload, petID: String) throws -> PetAnimation {
        let kind = payload.kind == "lick" ? "playful" : payload.kind
        let files = payload.framesBase64.indices.map { "\(petID)-\(kind)-frame_\(String(format: "%04d", $0 + 1)).png" }
        let sequence = PetAnimation(kind: kind, fps: payload.fps, width: payload.width, height: payload.height, files: files)
        guard sequence.isValid, payload.frameCount == files.count,
              payload.duration.isFinite, abs(payload.duration - sequence.duration) < 0.001 else {
            throw CocoaError(.fileReadCorruptFile)
        }
        // Validate every frame before publishing metadata; keep its complete fixed canvas.
        let frames = try payload.framesBase64.map { encoded -> Data in
            guard let data = Data(base64Encoded: encoded), let image = UIImage(data: data)?.cgImage,
                  image.width == sequence.width, image.height == sequence.height,
                  [.first, .last, .premultipliedFirst, .premultipliedLast].contains(image.alphaInfo) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            return data
        }
        for (index, data) in frames.enumerated() { try saveImage(data, named: files[index]) }
        return sequence
    }
    static let group = "group.com.gregadams.myfurbaby.shared"
    static var defaults: UserDefaults { UserDefaults(suiteName: group) ?? .standard }
    static var directory: URL {
        let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent("PetArtwork", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    static func save(snapshot: WidgetSnapshot) {
        if let data = try? JSONEncoder().encode(snapshot) { defaults.set(data, forKey: "widgetSnapshot") }
    }
    static func load() -> WidgetSnapshot {
        guard let data = defaults.data(forKey: "widgetSnapshot"), let value = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) else { return WidgetSnapshot() }
        return value
    }
    static func saveImage(_ data: Data, named filename: String) throws {
        guard filename == URL(fileURLWithPath: filename).lastPathComponent, UIImage(data: data) != nil else { throw CocoaError(.fileWriteInapplicableStringEncoding) }
        try data.write(to: directory.appendingPathComponent(filename), options: .atomic)
        cache.removeObject(forKey: filename as NSString)
        cache.removeObject(forKey: "\(filename)#display" as NSString)
        for frame in 0..<4 { cache.removeObject(forKey: "\(filename)#\(frame)" as NSString) }
    }
    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = 32 * 1024 * 1024
        return cache
    }()

    /// Pin a complete, decoded sequence for the preview, so playback never reads
    /// files or evicts its own next frame. Loading and PNG decoding run off-main.
    static func playbackImages(for sequence: PetAnimation?) async -> [UIImage]? {
        guard let sequence, sequence.isValid else { return nil }
        let loading = Task.detached(priority: .userInitiated) { () -> [UIImage]? in
            let directory = Self.directory
            var images: [UIImage] = []
            for file in sequence.files {
                guard !Task.isCancelled else { return nil }
                let key = "\(file)#display" as NSString
                if let cached = cache.object(forKey: key) { images.append(cached); continue }
                guard let source = CGImageSourceCreateWithURL(directory.appendingPathComponent(file) as CFURL, nil),
                      let bitmap = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceThumbnailMaxPixelSize: 384,
                        kCGImageSourceCreateThumbnailWithTransform: true,
                        kCGImageSourceShouldCacheImmediately: true
                      ] as CFDictionary) else { return nil }
                let image = UIImage(cgImage: bitmap)
                cache.setObject(image, forKey: key, cost: bitmap.bytesPerRow * bitmap.height)
                images.append(image)
            }
            return images
        }
        return await withTaskCancellationHandler {
            await loading.value
        } onCancel: {
            loading.cancel()
        }
    }
    static func image(_ filename: String?, frame: Int? = nil) -> UIImage? {
        guard let filename, filename == URL(fileURLWithPath: filename).lastPathComponent else { return nil }
        let key = filename + (frame.map { "#\($0)" } ?? "")
        if let found = cache.object(forKey: key as NSString) { return found }
        guard let value = UIImage(contentsOfFile: directory.appendingPathComponent(filename).path) else { return nil }
        let result: UIImage
        if let frame, let source = value.cgImage {
            let cell = CGSize(width: CGFloat(source.width / 2), height: CGFloat(source.height / 2))
            guard let crop = source.cropping(to: CGRect(x: CGFloat(frame % 2) * cell.width, y: CGFloat(frame / 2) * cell.height, width: cell.width, height: cell.height)) else { return nil }
            result = UIImage(cgImage: crop)
        } else { result = value }
        let cost = result.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
        cache.setObject(result, forKey: key as NSString, cost: cost)
        return result
    }
}
