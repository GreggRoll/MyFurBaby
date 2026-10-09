import SwiftUI
import WidgetKit

struct FurEntry: TimelineEntry { var date: Date; var snapshot: WidgetSnapshot }

struct FurProvider: TimelineProvider {
    func placeholder(in context: Context) -> FurEntry {
        FurEntry(date: Date(), snapshot: WidgetSnapshot(pet: .sample, isPro: true, proExpiresAt: Date().addingTimeInterval(3600)))
    }
    func getSnapshot(in context: Context, completion: @escaping (FurEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : FurEntry(date: Date(), snapshot: SharedStorage.load()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<FurEntry>) -> Void) {
        Task {
            var snapshot = SharedStorage.load()
            if snapshot.resolvedRightSide == .dailyQuote, snapshot.hasAccess() {
                let quote = await DailyQuoteService.shared.quote()
                // Re-read app settings after the request so a concurrent studio edit wins.
                snapshot = SharedStorage.load()
                snapshot.dailyQuote = quote
            }
            completion(timeline(snapshot: snapshot))
        }
    }
    private func timeline(snapshot: WidgetSnapshot) -> Timeline<FurEntry> {
        let now = Date()
        var dates = [now]
        // Mood updates and expiry handling, not frame-by-frame animation reloads.
        for hour in 1...6 { dates.append(now.addingTimeInterval(Double(hour) * 3600)) }
        if snapshot.resolvedRightSide == .clock, #unavailable(iOS 18) {
            // Clock entries update every minute without using animation timer masks.
            let minute = Calendar.current.dateInterval(of: .minute, for: now)?.start ?? now
            for offset in 1...360 { dates.append(minute.addingTimeInterval(Double(offset) * 60)) }
        }
        if let midnight = Calendar.current.dateInterval(of: .day, for: now)?.end,
           midnight <= now.addingTimeInterval(6 * 3600) { dates.append(midnight) }
        if let expiry = snapshot.proExpiresAt, expiry > now && expiry < dates.last! { dates.append(expiry) }
        if snapshot.resolvedRightSide == .dailyQuote {
            let refreshDate = snapshot.dailyQuote?.isCurrent(at: now) == true
                ? (Calendar.current.dateInterval(of: .day, for: now)?.end ?? now.addingTimeInterval(3600))
                : now.addingTimeInterval(30 * 60)
            // End at midnight to fetch the next day's quote, or retry an unavailable service.
            let end = min(now.addingTimeInterval(6 * 3600), refreshDate)
            dates = dates.filter { $0 < end } + [end]
        }
        let entries = Set(dates).sorted().map { FurEntry(date: $0, snapshot: snapshot) }
        return Timeline(entries: entries, policy: .atEnd)
    }
}

/// Adapted from Bryce Bostwick's MIT-licensed WidgetAnimation (see THIRD_PARTY_NOTICES.md).
/// Ordinary images hold the artwork, with bundled timer masks sequencing the frames.
/// This depends on undocumented timer rendering behavior and remains a beta experiment.
struct TimerMotionExperiment: View {
    let pet: FurPet
    let sleeping: Bool
    let frames: WidgetMotionFrames?
    let referenceDate: Date
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isLuminanceReduced) private var dimmed
    var body: some View {
        if reduceMotion || dimmed || (frames?.timing(sleeping: sleeping).usesElapsedSeconds == true && !supportsElapsedSeconds) { PetArtworkView(pet: pet, sleeping: sleeping) }
        else if let images = frames?.images(sleeping: sleeping) {
            let timing = frames?.timing(sleeping: sleeping) ?? .legacy
            GeometryReader { geometry in
                let side = min(geometry.size.width, geometry.size.height)
                // Give adjacent poses one refresh to hand off, avoiding a blank
                // pet when the system updates the two timer masks separately.
                ZStack {
                    ForEach(0..<timing.slotCount, id: \.self) { index in
                        artworkFrame(index: index, images: images, side: side)
                            .mask { blink(index: index, timing: timing, side: side) }
                            .mask { blink(index: index, timing: timing, side: side, closing: true) }
                    }
                    if timing.idle != nil {
                        ForEach(0..<timing.idleFrameCount, id: \.self) { index in
                            artworkFrame(index: timing.slotCount + index, images: images, side: side)
                                .mask { idleBlink(index: index, timing: timing, side: side) }
                                .mask { idleBlink(index: index, timing: timing, side: side, closing: true) }
                        }
                    }
                    if timing.hasHold {
                        artworkFrame(index: images.count - 1, images: images, side: side)
                            .mask {
                                MotionTimerGlyph(date: cycleReferenceDate(timing), fontName: timing.holdFontName,
                                    side: side, elapsedSeconds: true)
                            }
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(pet.name.isEmpty ? "Your Fur Baby" : pet.name), \(sleeping ? "sleeping" : "playful")")
        } else { PetArtworkView(pet: pet, sleeping: sleeping) }
    }

    private var supportsElapsedSeconds: Bool {
        if #available(iOS 18, *) { return true }
        return false
    }

    private func artworkFrame(index: Int, images: [UIImage], side: CGFloat) -> some View {
        Image(uiImage: images[index % images.count]).resizable().scaledToFit()
            .frame(width: side, height: side)
    }

    private func blink(index: Int, timing: WidgetMotionTiming, side: CGFloat, closing: Bool = false) -> some View {
        MotionTimerGlyph(date: cycleReferenceDate(timing).addingTimeInterval(
            closing ? timing.closingMaskOffset(index: index) : Double(index) / Double(timing.fps)),
            fontName: timing.fontName, side: side, elapsedSeconds: timing.usesElapsedSeconds)
    }

    private func idleBlink(index: Int, timing: WidgetMotionTiming, side: CGFloat, closing: Bool = false) -> some View {
        // Each idle pose appears five times within the ten-second interval.
        MotionTimerGlyph(date: cycleReferenceDate(timing).addingTimeInterval(Double(timing.period) +
            (closing ? timing.closingMaskOffset(index: index) : Double(index) / Double(timing.fps))),
            fontName: timing.idleFontName, side: side, elapsedSeconds: true)
    }

    private func cycleReferenceDate(_ timing: WidgetMotionTiming) -> Date {
        timing.referenceDate(at: referenceDate)
    }
}

private struct MotionTimerGlyph: View {
    let date: Date
    let fontName: String
    let side: CGFloat
    var elapsedSeconds = false
    var body: some View {
        if elapsedSeconds, #available(iOS 18, *) {
            Text(.currentDate, format: .offset(to: date, allowedFields: [.second], maxFieldCount: 1, sign: .never)
                .locale(Locale(identifier: "en_US_POSIX")))
                .font(.custom(fontName, fixedSize: side))
                .foregroundStyle(.white)
                .lineLimit(1)
                .frame(width: side * 9, height: side, alignment: .leading)
                .frame(width: side, height: side, alignment: .leading)
                .clipped().accessibilityHidden(true)
        } else {
            Text(date, style: .timer)
                .font(.custom(fontName, fixedSize: side))
                .foregroundStyle(.white)
                .multilineTextAlignment(.trailing)
                .frame(width: side * 9, height: side)
                .offset(x: -side * 4)
                .frame(width: side, height: side)
                .clipped().accessibilityHidden(true)
        }
    }
}

struct FurWidgetView: View {
    let entry: FurEntry
    @Environment(\.widgetFamily) private var family
    var body: some View {
        if entry.snapshot.hasAccess(at: entry.date), let pet = entry.snapshot.pet {
            let sleeping = entry.snapshot.behavior.isSleeping(at: entry.date)
            let background = entry.snapshot.resolvedBackground
            HStack(spacing: 7) {
                VStack(spacing: 0) {
                    TimerMotionExperiment(pet: pet, sleeping: sleeping, frames: entry.snapshot.motionFrames,
                        referenceDate: entry.date)
                    if family == .systemSmall { Text(pet.name.isEmpty ? "Your Fur Baby" : pet.name).font(.system(size: 12, weight: .heavy, design: .rounded)).lineLimit(1).padding(.horizontal, 8).padding(.vertical, 4).background(background.labelFill, in: Capsule()) }
                }.frame(maxWidth: .infinity)
                if family == .systemMedium {
                    WidgetRightSideView(selection: entry.snapshot.resolvedRightSide, pet: pet,
                        sleeping: sleeping, date: entry.date, background: background, liveClock: true,
                        dailyQuote: entry.snapshot.dailyQuote)
                }
            }.foregroundStyle(background.foreground)
                .widgetURL(URL(string: family == .systemMedium && entry.snapshot.resolvedRightSide == .dailyQuote ? "myfurbaby://widgets" : "myfurbaby://pet"))
        } else {
            VStack(spacing: 9) { FurBrandIcon(size: 40); Text("Your little friend\nbelongs here.").font(.system(size: 15, weight: .bold, design: .rounded)).multilineTextAlignment(.center); Text("Create a pet & unlock Pro").font(.system(size: 10)).foregroundStyle(.secondary) }.widgetURL(URL(string: "myfurbaby://widgets"))
        }
    }
}

@main struct FurBabyWidget: Widget {
    let kind = "MyFurBabyWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FurProvider()) { entry in
            FurWidgetView(entry: entry).containerBackground(for: .widget) {
                WidgetBackgroundView(background: entry.snapshot.hasAccess(at: entry.date) ? entry.snapshot.resolvedBackground : WidgetBackground())
            }
        }
        .configurationDisplayName("My Fur Baby")
        .description("A little home for your very own pet.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
