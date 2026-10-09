import SwiftUI

/// The app's approved puppy artwork, shared with the widget extension.
struct FurBrandIcon: View {
    var size: CGFloat = 32

    var body: some View {
        Image("FurBrandIcon")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous))
            .accessibilityHidden(true)
    }
}

enum FurTheme {
    static let ink = Color(red: 0.19, green: 0.15, blue: 0.23)
    static let cream = Color(red: 0.99, green: 0.97, blue: 0.93)
    static let pink = Color(red: 0.92, green: 0.36, blue: 0.52)
    static let lavender = Color(red: 0.86, green: 0.82, blue: 0.97)
    static let lime = Color(red: 0.88, green: 0.94, blue: 0.62)
}

extension WidgetBackground {
    var color: Color { Color(red: red, green: green, blue: blue) }
    // Clear uses the system widget surface, which can be light or dark.
    var foreground: Color { kind == .clear ? .primary : usesLightText ? .white : FurTheme.ink }
    var labelFill: Color {
        kind.assetName == nil && kind != .custom ? .clear : (usesLightText ? Color.black.opacity(0.55) : Color.white.opacity(0.75))
    }
}

struct WidgetBackgroundView: View {
    let background: WidgetBackground
    var body: some View {
        if let image = artwork {
            // Resolve the image in the app/extension and embed it in the widget archive.
            // The overlay fills the proposed bounds without a geometry-dependent background.
            Color.clear.overlay {
                Image(uiImage: image).resizable().scaledToFill()
            }.clipped().accessibilityHidden(true)
        } else if background.kind == .solidColor {
            background.color
        } else {
            Color.clear
        }
    }
    private var artwork: UIImage? {
        if background.kind == .custom { return SharedStorage.image(background.imageFilename) }
        return background.kind.assetName.flatMap { WidgetBackgroundArtwork.image(named: $0) }
    }
}

/// Shared by the studio preview and the Home Screen widget so selections match.
struct WidgetRightSideView: View {
    let selection: WidgetRightSide
    let pet: FurPet
    let sleeping: Bool
    let date: Date
    let background: WidgetBackground
    var liveClock = false
    var dailyQuote: DailyQuote?

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            switch selection {
            case .petInfo:
                Image(systemName: sleeping ? "moon.zzz.fill" : "heart.fill")
                    .foregroundStyle(background.usesLightText ? .white : FurTheme.pink)
                Text(pet.name.isEmpty ? "Your Fur Baby" : pet.name)
                    .font(.system(size: 23, weight: .heavy, design: .rounded)).lineLimit(1).minimumScaleFactor(0.65)
                Text(sleeping ? "Dreaming of you." : "A little love, always.")
                    .font(.system(size: 12)).foregroundStyle(background.foreground.opacity(0.8))
            case .clock:
                Label("Time for a cuddle", systemImage: "clock").font(.system(size: 10, weight: .bold))
                clockText
                    .font(.system(size: 29, weight: .heavy, design: .rounded)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.65)
                Text(date, format: .dateTime.weekday(.wide).month(.abbreviated).day())
                    .font(.system(size: 11)).lineLimit(1).minimumScaleFactor(0.7)
            case .dailyQuote:
                Label("Daily quote", systemImage: "quote.opening").font(.system(size: 10, weight: .bold))
                if let dailyQuote {
                    Text(dailyQuote.content)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .lineLimit(5).minimumScaleFactor(0.75)
                    Text("— \(dailyQuote.author)").font(.system(size: 10))
                        .lineLimit(1).minimumScaleFactor(0.7).foregroundStyle(background.foreground.opacity(0.8))
                    Link("Quotes by ZenQuotes", destination: DailyQuote.sourceURL)
                        .font(.system(size: 8)).foregroundStyle(background.foreground.opacity(0.8))
                } else {
                    Text("Your daily quote will appear when ZenQuotes is available.")
                        .font(.system(size: 12)).foregroundStyle(background.foreground.opacity(0.8))
                }
            case .calendar:
                WidgetMonthView(date: date, foreground: background.foreground)
            }
        }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(background.foreground)
            .background(background.labelFill, in: RoundedRectangle(cornerRadius: 17))
    }
    @ViewBuilder private var clockText: some View {
        if liveClock, #available(iOS 18, *) {
            Text(.currentDate, format: .dateTime.hour().minute())
        } else {
            Text(date, style: .time)
        }
    }
}

private struct WidgetMonthView: View {
    let date: Date
    let foreground: Color
    private var calendar: Calendar { .current }
    private var firstDay: Date { calendar.dateInterval(of: .month, for: date)?.start ?? date }
    private var leadingDays: Int { (calendar.component(.weekday, from: firstDay) - calendar.firstWeekday + 7) % 7 }
    private var dayCount: Int { calendar.range(of: .day, in: .month, for: date)?.count ?? 30 }
    private var today: Int { calendar.component(.day, from: date) }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(date, format: .dateTime.month(.wide).year()).font(.system(size: 11, weight: .bold))
                .lineLimit(1).minimumScaleFactor(0.7)
            Grid(horizontalSpacing: 1, verticalSpacing: 2) {
                GridRow {
                    ForEach(0..<7, id: \.self) { index in
                        Text(calendar.veryShortStandaloneWeekdaySymbols[(calendar.firstWeekday - 1 + index) % 7])
                            .font(.system(size: 8, weight: .bold)).opacity(0.65).frame(maxWidth: .infinity)
                    }
                }
                ForEach(0..<((leadingDays + dayCount + 6) / 7), id: \.self) { row in
                    GridRow {
                        ForEach(0..<7, id: \.self) { column in
                            let day = row * 7 + column - leadingDays + 1
                            Text((1...dayCount).contains(day) ? "\(day)" : " ")
                                .font(.system(size: 9, weight: day == today ? .heavy : .medium)).monospacedDigit()
                                .frame(maxWidth: .infinity).frame(height: 14)
                                .background(day == today ? foreground.opacity(0.22) : .clear, in: Circle())
                        }
                    }
                }
            }
        }.accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(date, format: .dateTime.weekday(.wide).month(.wide).day().year()))
    }
}

enum WidgetBackgroundArtwork {
    // WidgetKit rejects oversized image archives, including offscreen background pixels.
    // Cache a bounded rendition shared by both widget sizes and the in-app previews.
    private static let images: [String: UIImage] = Dictionary(uniqueKeysWithValues:
        WidgetBackgroundKind.allCases.compactMap { kind -> (String, UIImage)? in
            guard let name = kind.assetName,
                  let image = UIImage(named: name)?.preparingThumbnail(of: CGSize(width: 640, height: 640)) else { return nil }
            return (name, image)
        })

    static func image(named name: String) -> UIImage? { images[name] }
}

/// A deliberately illustrated sample, also used while live assets are being prepared.
struct PetIllustration: View {
    var recipe: PetRecipe = .sample
    var sleeping = false
    var phase: Double = 0
    var playful = false

    private var fur: Color {
        let color = recipe.color.lowercased()
        if color.contains("red") { return Color(red: 0.92, green: 0.39, blue: 0.35) }
        if color.contains("green") { return Color(red: 0.57, green: 0.77, blue: 0.55) }
        if color.contains("yellow") || color.contains("gold") { return Color(red: 0.96, green: 0.76, blue: 0.35) }
        if color.contains("blue") { return Color(red: 0.52, green: 0.73, blue: 0.91) }
        return Color(red: 0.69, green: 0.57, blue: 0.83)
    }

    var body: some View {
        Canvas { context, size in
            let scale = min(size.width, size.height) / 240
            context.translateBy(x: (size.width - 240 * scale) / 2, y: (size.height - 240 * scale) / 2)
            context.scaleBy(x: scale, y: scale)
            func ellipse(_ rect: CGRect, _ color: Color) { context.fill(Path(ellipseIn: rect), with: .color(color)) }
            func rounded(_ rect: CGRect, _ radius: CGFloat, _ color: Color) { context.fill(Path(roundedRect: rect, cornerRadius: radius), with: .color(color)) }
            func line(_ points: [CGPoint], color: Color = FurTheme.ink, width: CGFloat = 3) {
                var path = Path(); if let first = points.first { path.move(to: first) }; for point in points.dropFirst() { path.addLine(to: point) }
                context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
            }
            let cat = recipe.animal.lowercased().contains("cat")
            ellipse(CGRect(x: 49, y: 212, width: 147, height: 17), FurTheme.ink.opacity(0.10))
            if sleeping {
                ellipse(CGRect(x: 46, y: 159, width: 155, height: 63), FurTheme.pink.opacity(0.24))
                let breath = CGFloat(sin(phase * .pi * 2)) * 3
                ellipse(CGRect(x: 88, y: 84 - breath, width: 80, height: 119 + breath), fur)
                ellipse(CGRect(x: 104, y: 113 - breath, width: 46, height: 66 + breath), Color.white.opacity(0.55))
                for rect in [CGRect(x: 61, y: 110, width: 35, height: 43), CGRect(x: 162, y: 110, width: 35, height: 43), CGRect(x: 81, y: 177, width: 33, height: 32), CGRect(x: 144, y: 177, width: 33, height: 32)] { ellipse(rect, fur) }
                ellipse(CGRect(x: 53, y: 47, width: 48, height: 74), fur.opacity(0.85))
                ellipse(CGRect(x: 155, y: 47, width: 42, height: 72), fur.opacity(0.85))
                ellipse(CGRect(x: 78, y: 40, width: 100, height: 86), fur)
                line([CGPoint(x: 99, y: 79), CGPoint(x: 108, y: 83), CGPoint(x: 117, y: 78)])
                line([CGPoint(x: 143, y: 79), CGPoint(x: 152, y: 83), CGPoint(x: 161, y: 78)])
                ellipse(CGRect(x: 121, y: 94, width: 17, height: 13), FurTheme.ink)
                let z = Text("z Z").font(.system(size: 26, weight: .heavy, design: .rounded)).foregroundColor(FurTheme.ink.opacity(0.55))
                context.draw(z, at: CGPoint(x: 194, y: 44 - CGFloat(phase) * 8))
            } else {
                if playful {
                    let bounce = CGFloat(sin(phase * .pi * 2))
                    context.translateBy(x: bounce * 2, y: -abs(bounce) * 3)
                }
                ellipse(CGRect(x: 154, y: 127, width: 56, height: 45), fur.opacity(0.8))
                ellipse(CGRect(x: 79, y: 133, width: 92, height: 82), fur)
                ellipse(CGRect(x: 101, y: 150, width: 49, height: 62), Color.white.opacity(0.42))
                rounded(CGRect(x: 74, y: 184, width: 42, height: 35), 16, fur)
                rounded(CGRect(x: 136, y: 184, width: 42, height: 35), 16, fur)
                if cat {
                    var left = Path(); left.move(to: CGPoint(x: 66, y: 82)); left.addLine(to: CGPoint(x: 76, y: 19)); left.addLine(to: CGPoint(x: 111, y: 69)); left.closeSubpath(); context.fill(left, with: .color(fur))
                    var right = Path(); right.move(to: CGPoint(x: 143, y: 64)); right.addLine(to: CGPoint(x: 175, y: 19)); right.addLine(to: CGPoint(x: 185, y: 84)); right.closeSubpath(); context.fill(right, with: .color(fur))
                } else {
                    ellipse(CGRect(x: 44, y: 48, width: 46, height: 100), fur.opacity(0.83))
                    ellipse(CGRect(x: 164, y: 48, width: 41, height: 100), fur.opacity(0.83))
                    ellipse(CGRect(x: 53, y: 63, width: 24, height: 59), FurTheme.pink.opacity(0.20))
                    ellipse(CGRect(x: 173, y: 63, width: 21, height: 57), FurTheme.pink.opacity(0.20))
                }
                ellipse(CGRect(x: 65, y: 42, width: 119, height: 116), fur)
                ellipse(CGRect(x: 85, y: 112, width: 79, height: 40), Color.white.opacity(0.75))
                let blink = phase > 0.90 && phase < 0.96
                if blink {
                    line([CGPoint(x: 88, y: 94), CGPoint(x: 107, y: 94)])
                    line([CGPoint(x: 143, y: 94), CGPoint(x: 162, y: 94)])
                } else {
                    ellipse(CGRect(x: 89, y: 80, width: 22, height: 28), FurTheme.ink)
                    ellipse(CGRect(x: 141, y: 80, width: 22, height: 28), FurTheme.ink)
                    ellipse(CGRect(x: 95, y: 84, width: 7, height: 8), .white)
                    ellipse(CGRect(x: 147, y: 84, width: 7, height: 8), .white)
                }
                ellipse(CGRect(x: 76, y: 110, width: 24, height: 12), FurTheme.pink.opacity(0.36))
                ellipse(CGRect(x: 152, y: 110, width: 24, height: 12), FurTheme.pink.opacity(0.36))
                ellipse(CGRect(x: 115, y: 114, width: 24, height: 17), FurTheme.ink)
                line([CGPoint(x: 127, y: 130), CGPoint(x: 127, y: 139), CGPoint(x: 117, y: 142)])
                line([CGPoint(x: 127, y: 139), CGPoint(x: 139, y: 142)])
                if playful {
                    let lift = CGFloat((sin(phase * .pi * 2) + 1) / 2) * 20
                    ellipse(CGRect(x: 64, y: 155 - lift, width: 35, height: 33), fur)
                }
                if !recipe.accessories.isEmpty {
                    rounded(CGRect(x: 82, y: 147, width: 87, height: 13), 5, FurTheme.pink)
                    ellipse(CGRect(x: 118, y: 155, width: 19, height: 21), FurTheme.lime)
                    if recipe.accessories.lowercased().contains("hat") {
                        rounded(CGRect(x: 97, y: 15, width: 54, height: 40), 7, FurTheme.ink)
                        rounded(CGRect(x: 81, y: 49, width: 88, height: 9), 4, FurTheme.ink)
                        rounded(CGRect(x: 98, y: 39, width: 52, height: 7), 0, FurTheme.pink)
                    }
                    if recipe.accessories.lowercased().contains("monocle") { context.stroke(Path(ellipseIn: CGRect(x: 134, y: 73, width: 36, height: 38)), with: .color(FurTheme.lime), lineWidth: 3) }
                }
            }
        }
        .accessibilityLabel(sleeping ? "Pet sleeping on its back" : playful ? "Pet playing" : "Illustrated pet preview")
    }
}

struct PetArtworkView: View {
    let pet: FurPet
    var sleeping = false
    var playful = false
    var running = false
    var idling = false
    var phase = 0.0
    var animationTime: Double?
    var animationFrame: Int?
    var preparedActionImages: [UIImage]?
    var preparedIdleImages: [UIImage]?
    var usesPreparedImages = false
    var body: some View {
        let action = sleeping ? pet.sleepingAnimation : running ? pet.runningAnimation : playful ? pet.playfulAnimation : nil
        let duration = action?.duration ?? 4
        let idleInterval = animationTime.map { PetPlayback.isIdle(at: $0, duration: duration) } ?? false
        let useIdle = idling || (!sleeping && idleInterval && pet.idleAnimation?.isValid == true)
        let sequence = useIdle ? pet.idleAnimation : action
        let playbackTime = animationTime.map {
            if sleeping { return $0 }
            let elapsed = PetPlayback.cycleTime(at: $0, duration: duration)
            return idleInterval ? elapsed - duration : elapsed
        }
        let filename = sleeping ? pet.sleepingArtwork ?? pet.artwork : playful ? pet.playfulArtwork ?? pet.artwork : pet.artwork
        let animatedAsset = (sleeping && pet.sleepingArtwork != nil) || (playful && pet.playfulArtwork != nil)
        let frame = animatedAsset && pet.animationFrames == 4 ? Int(phase * 4) % 4 : nil
        if let sequence, sequence.isValid,
           let image = sequenceImage(sequence, useIdle: useIdle, playbackTime: playbackTime) {
            // The video already contains movement. Keep the complete canvas and add no synthetic transforms.
            Image(uiImage: image).resizable().scaledToFit()
                .accessibilityLabel("\(pet.name), \(sleeping ? "sleeping" : useIdle ? "waiting" : running ? "running" : "playful")")
        } else if let image = SharedStorage.image(filename, frame: frame) {
            Image(uiImage: image).resizable().scaledToFit()
                .scaleEffect(sleeping ? 1 + sin(phase * .pi * 2) * 0.025 : 1)
                .rotationEffect(.degrees(sleeping ? 0 : sin(phase * .pi * 2) * 2))
                .accessibilityLabel("\(pet.name), \(sleeping ? "sleeping" : playful ? "playful" : "awake")")
        } else {
            PetIllustration(recipe: pet.recipe, sleeping: sleeping, phase: phase, playful: playful)
        }
    }

    private func sequenceImage(_ sequence: PetAnimation, useIdle: Bool, playbackTime: Double?) -> UIImage? {
        let index = animationFrame.map { min(sequence.files.count - 1, max(0, $0)) }
            ?? sequence.frameIndex(at: playbackTime ?? (sleeping ? sequence.duration * 0.6 : 0))
        if usesPreparedImages {
            let images = useIdle ? preparedIdleImages : preparedActionImages
            guard let images, images.count == sequence.files.count else { return nil }
            return images[index]
        }
        return SharedStorage.image(sequence.files[index])
    }
}
