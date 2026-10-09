import SwiftUI

struct WidgetStudioView: View {
    @Environment(FurStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var backgroundPrompt = ""
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 23) {
                Pill(text: "A HOME ON YOUR HOME SCREEN", symbol: "square.grid.2x2", color: FurTheme.pink, fill: FurTheme.pink.opacity(0.08))
                SectionTitle(title: "Always a little closer.", subtitle: "Pick a mood. Give them a little home.")
                if let pet = store.selectedPet {
                    HStack { Text("SMALL").font(.system(size: 10, weight: .heavy)).foregroundStyle(.secondary); Spacer(); Text("WIDE").font(.system(size: 10, weight: .heavy)).foregroundStyle(.secondary) }
                    HStack(alignment: .center, spacing: 16) {
                        preview(pet: pet, wide: false).frame(width: 145, height: 155)
                        VStack(alignment: .leading, spacing: 10) { Text("Their own\nlittle corner.").font(.system(size: 23, weight: .heavy, design: .rounded)); Text("Made for your Home Screen.").font(.caption).foregroundStyle(.secondary) }
                    }
                    preview(pet: pet, wide: true).frame(height: 166)
                    if store.isPro {
                        backgroundPicker
                        customBackgroundSection
                        rightSidePicker
                        HStack(spacing: 8) {
                            ForEach(PetBehavior.widgetCases) { behavior in
                                Button { store.setBehavior(behavior) } label: { Label(behavior.title, systemImage: behavior.symbol).font(.system(size: 12, weight: .bold)).frame(maxWidth: .infinity).padding(.vertical, 14).background(store.behavior == behavior ? FurTheme.pink.opacity(0.13) : .white, in: Capsule()).foregroundStyle(store.behavior == behavior ? FurTheme.pink : FurTheme.ink) }.buttonStyle(.plain)
                            }
                        }
                        let progress = store.animationProgress.flatMap { $0.petID == pet.id ? $0 : nil }
                        if !pet.isSample && (pet.sleepingAnimation == nil || pet.playfulAnimation == nil || pet.idleAnimation == nil || progress?.isRunning == true) {
                            let cost = ["idle", "playful", "sleep"].filter { pet.animation(kind: $0) == nil }.count * FurTokenCost.animation
                            AnimationPreparationButton(cost: cost, progress: progress, disabled: store.isBusy) {
                                Task { await store.preparePoses() }
                            }
                            Text("Create idle, playful and sleeping animations. Each costs 1,500 tokens. Your pet idles for 10 seconds between actions; saved animations replay for free.").font(.caption).foregroundStyle(.secondary)
                        }
                        if let progress { AnimationPipelineStatus(progress: progress) }
                        if store.isBusy && !store.isGeneratingWidgetBackground && progress?.isRunning != true { HStack { ProgressView(); Text(store.activity).font(.caption) } }
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Put your pet on your Home Screen").font(.system(size: 17, weight: .bold, design: .rounded))
                            Text("1. Touch and hold your Home Screen.\n2. Tap Edit, then Add Widget.\n3. Search My Fur Baby.\n4. Choose the small or wide size and add it.").font(.system(size: 14)).lineSpacing(8).foregroundStyle(FurTheme.ink.opacity(0.7))
                        }.padding(21).frame(maxWidth: .infinity, alignment: .leading).background(.white, in: RoundedRectangle(cornerRadius: 24))
                    } else {
                        PrimaryButton(title: "Unlock widgets with Pro", symbol: "crown.fill") { store.showPaywall = true }
                    }
                } else {
                    PetIllustration(sleeping: true).frame(maxWidth: .infinity).frame(height: 245).background(FurTheme.lavender.opacity(0.5), in: RoundedRectangle(cornerRadius: 26))
                    Text("Create your Fur Baby first, then choose a home for them here.").font(.subheadline).foregroundStyle(.secondary)
                }
            }.padding(.horizontal, 24).padding(.bottom, 25)
        }.foregroundStyle(FurTheme.ink)
            .task(id: store.widgetRightSide) { await store.refreshDailyQuote() }
    }
    private var backgroundPicker: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Widget background").font(.system(size: 19, weight: .bold, design: .rounded))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 12)], spacing: 12) {
                ForEach(WidgetBackgroundKind.allCases.filter { $0 != .custom }) { kind in
                    Button {
                        var background = store.widgetBackground
                        background.kind = kind
                        store.setWidgetBackground(background)
                    } label: {
                        VStack(alignment: .leading, spacing: 9) {
                            ZStack {
                                if kind == .clear {
                                    RoundedRectangle(cornerRadius: 16).fill(FurTheme.cream)
                                    Image(systemName: "circle.slash").font(.title2).foregroundStyle(.secondary)
                                } else {
                                    WidgetBackgroundView(background: optionBackground(kind))
                                }
                            }.frame(height: 86).clipShape(RoundedRectangle(cornerRadius: 16))
                                .overlay(alignment: .topTrailing) {
                                    if store.widgetBackground.kind == kind {
                                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.white, FurTheme.pink).padding(8)
                                    }
                                }
                            Text(kind.title).font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(FurTheme.ink).frame(maxWidth: .infinity, alignment: .leading)
                        }.padding(8).background(.white, in: RoundedRectangle(cornerRadius: 22))
                            .overlay { RoundedRectangle(cornerRadius: 22).strokeBorder(store.widgetBackground.kind == kind ? FurTheme.pink : .clear, lineWidth: 2) }
                    }.buttonStyle(.plain).accessibilityAddTraits(store.widgetBackground.kind == kind ? .isSelected : [])
                }
            }
            if store.widgetBackground.kind == .solidColor {
                HStack {
                    Text("Pick a background color")
                    Spacer()
                    ColorPicker("Pick a background color", selection: Binding(
                    get: { store.widgetBackground.color },
                    set: { value in
                        guard let components = UIColor(value).cgColor.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil)?.components,
                              components.count >= 3 else { return }
                        var background = store.widgetBackground
                        background.red = Double(components[0]); background.green = Double(components[1]); background.blue = Double(components[2])
                        store.setWidgetBackground(background)
                    }), supportsOpacity: false).labelsHidden()
                }.font(.system(size: 14, weight: .bold)).padding(16).background(.white, in: RoundedRectangle(cornerRadius: 18))
            }
        }
    }
    private var customBackgroundSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Dream up your own background").font(.system(size: 19, weight: .bold, design: .rounded))
            Text("A moonlit garden? A cozy cloud castle? Describe a little world for your pet. Create it for 200 tokens, then use it anytime for free.")
                .font(.system(size: 13)).foregroundStyle(.secondary)
            TextField("A cozy treehouse with fairy lights…", text: $backgroundPrompt, axis: .vertical)
                .lineLimit(3...5).padding(15).background(.white, in: RoundedRectangle(cornerRadius: 18))
                .accessibilityLabel("Describe your widget background")
            HStack {
                Text("\(backgroundPrompt.utf16.count)/500").font(.caption)
                    .foregroundStyle(backgroundPrompt.utf16.count > 500 ? .red : .secondary)
                Spacer()
                Text("200 tokens").font(.system(size: 12, weight: .bold))
            }
            PrimaryButton(title: "Create background · 200 tokens", symbol: "sparkles",
                disabled: store.isBusy || backgroundPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || backgroundPrompt.utf16.count > 500 || store.hasPendingImage) {
                Task {
                    if await store.createWidgetBackground(prompt: backgroundPrompt) { backgroundPrompt = "" }
                }
            }
            if store.isGeneratingWidgetBackground {
                HStack(spacing: 10) {
                    ProgressView()
                    Text(store.isReconnecting ? "Reconnecting to your saved creation…" : store.activity).font(.caption)
                }
            }
            if store.hasPendingImage {
                Button("Recover unfinished image") { Task { await store.resumePendingImage() } }
                    .font(.system(size: 14, weight: .bold)).disabled(store.isBusy)
                Text("Recover your saved creation before starting another. Recovery costs no extra tokens.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !store.customWidgetBackgrounds.isEmpty {
                Text("Your backgrounds").font(.system(size: 14, weight: .bold))
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 12)], spacing: 12) {
                    ForEach(store.customWidgetBackgrounds) { value in
                        let selected = store.widgetBackground.kind == .custom && store.widgetBackground.imageFilename == value.imageFilename
                        Button { store.setWidgetBackground(value.background) } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                WidgetBackgroundView(background: value.background).frame(height: 86)
                                    .clipShape(RoundedRectangle(cornerRadius: 16))
                                    .overlay(alignment: .topTrailing) {
                                        if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(.white, FurTheme.pink).padding(8) }
                                    }
                                Text(value.prompt).font(.system(size: 12, weight: .bold)).lineLimit(2)
                            }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
                                .background(.white, in: RoundedRectangle(cornerRadius: 22))
                                .overlay { RoundedRectangle(cornerRadius: 22).strokeBorder(selected ? FurTheme.pink : .clear, lineWidth: 2) }
                        }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
            }
        }
    }

    private var rightSidePicker: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Medium widget · right side").font(.system(size: 19, weight: .bold, design: .rounded))
            Text("Choose what sits beside your pet.").font(.system(size: 13)).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(WidgetRightSide.allCases) { option in
                    Button { store.setWidgetRightSide(option) } label: {
                        Label(option.title, systemImage: option.symbol).font(.system(size: 13, weight: .bold))
                            .frame(maxWidth: .infinity, alignment: .leading).padding(15)
                            .foregroundStyle(store.widgetRightSide == option ? FurTheme.pink : FurTheme.ink)
                            .background(store.widgetRightSide == option ? FurTheme.pink.opacity(0.13) : .white, in: RoundedRectangle(cornerRadius: 18))
                    }.buttonStyle(.plain).accessibilityAddTraits(store.widgetRightSide == option ? .isSelected : [])
                }
            }
            if store.widgetRightSide == .dailyQuote, let quote = store.dailyQuote {
                VStack(alignment: .leading, spacing: 10) {
                    Text(quote.content).font(.system(size: 15, weight: .semibold, design: .rounded))
                    Text("— \(quote.author)").font(.caption).foregroundStyle(.secondary)
                    Link("Inspirational quotes provided by ZenQuotes", destination: DailyQuote.sourceURL)
                        .font(.caption).foregroundStyle(FurTheme.pink)
                }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white, in: RoundedRectangle(cornerRadius: 20))
            }
        }
    }
    private func optionBackground(_ kind: WidgetBackgroundKind) -> WidgetBackground {
        var value = store.widgetBackground; value.kind = kind; return value
    }
    private func preview(pet: FurPet, wide: Bool) -> some View {
        let background = store.widgetBackground
        return HStack(spacing: 8) {
            LivePetStage(pet: pet, behavior: store.behavior.widgetBehavior, animate: store.isPro && !reduceMotion).frame(maxWidth: .infinity)
            if wide {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    WidgetRightSideView(selection: store.widgetRightSide, pet: pet,
                        sleeping: store.behavior.isSleeping(at: context.date), date: context.date, background: background,
                        dailyQuote: store.dailyQuote)
                        .task(id: Calendar.current.startOfDay(for: context.date)) { await store.refreshDailyQuote() }
                }.frame(maxWidth: .infinity)
            }
        }.padding(10).foregroundStyle(background.foreground)
            .background { WidgetBackgroundView(background: background) }
            .overlay(alignment: .bottomLeading) {
                if !wide { Text(pet.name.isEmpty ? "Your Fur Baby" : pet.name).font(.system(size: 11, weight: .heavy, design: .rounded)).foregroundStyle(background.foreground).padding(7).background(background.labelFill, in: Capsule()).padding(9) }
            }.clipShape(RoundedRectangle(cornerRadius: 26))
            .overlay { RoundedRectangle(cornerRadius: 26).strokeBorder(FurTheme.ink.opacity(0.1), lineWidth: 1) }
    }
}

private struct AnimationPreparationButton: View {
    let cost: Int
    let progress: AnimationPreparationProgress?
    let disabled: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                HStack(spacing: 9) {
                    Image(systemName: "sparkles")
                    Text(progress?.isRunning == true ? "Animating your pet…" : "Animate my pet · up to \(cost.formatted()) tokens")
                    Spacer()
                    if let progress, progress.isRunning {
                        Text(progress.fraction, format: .percent.precision(.fractionLength(0))).monospacedDigit()
                    } else { Image(systemName: "arrow.right") }
                }
                if let progress, progress.isRunning {
                    ProgressView(value: progress.fraction).tint(.white)
                        .accessibilityLabel("Animation preparation")
                }
            }.font(.system(size: 16, weight: .bold, design: .rounded)).padding(20)
                .foregroundStyle(.white).background(FurTheme.pink, in: RoundedRectangle(cornerRadius: 21))
        }.buttonStyle(.plain).disabled(disabled)
            .opacity(disabled && progress?.isRunning != true ? 0.45 : 1)
    }
}

private struct AnimationPipelineStatus: View {
    let progress: AnimationPreparationProgress
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(progress.animations) { animation in
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text(animation.title).font(.system(size: 14, weight: .bold, design: .rounded))
                        Spacer()
                        if animation.stage == "completed" {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(FurTheme.pink)
                        } else {
                            Text("\(min(max(0, animation.completedStages), animation.totalStages)) / \(animation.totalStages) stages")
                                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                    ProgressView(value: animation.fraction).tint(FurTheme.pink)
                        .accessibilityLabel("\(animation.title) animation")
                    Text(animation.stageTitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            if progress.failed {
                Text("Preparation stopped. Tap Animate my pet to retry the missing animations. Saved animations stay ready.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.padding(18).background(.white, in: RoundedRectangle(cornerRadius: 21))
    }
}
