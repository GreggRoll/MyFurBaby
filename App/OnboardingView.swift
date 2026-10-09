import SwiftUI
import AVKit

struct OnboardingView: View {
    @Environment(FurStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var answerFocused: Bool

    private var progress: OnboardingProgress { store.onboarding }
    private var pet: FurPet? { store.pets.first { $0.id == progress.petID } }
    private var gender: PetGender { progress.recipe.gender ?? .boy }
    var body: some View {
        if progress.stage == .paywall, let pet {
            ProView(onboardingPet: pet) { store.onboarding.stage = .complete }
        } else {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        HStack {
                            HStack(spacing: 8) {
                                FurBrandIcon(size: 28)
                                Text("MY FUR BABY").font(.system(size: 11, weight: .bold, design: .rounded))
                            }
                            .padding(.horizontal, 11).padding(.vertical, 7)
                            .background(FurTheme.pink.opacity(0.09), in: Capsule())
                            Spacer()
                            if progress.stage == .questions { Text("\(progress.question + 1) / 5").font(.caption.bold()).foregroundStyle(.secondary) }
                        }
                        content
                    }.padding(25).frame(maxWidth: 560, alignment: .leading).frame(maxWidth: .infinity)
                }
                .scrollDismissesKeyboard(.interactively)
                .background(FurTheme.cream.ignoresSafeArea())
                .foregroundStyle(FurTheme.ink)
                .safeAreaInset(edge: .bottom, spacing: 0) { footer }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        if canGoBack { Button("Back", systemImage: "chevron.left", action: goBack) }
                    }
                }
                .task(id: progress.stage) {
                    if progress.stage == .creating { await createBaby() }
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active && progress.stage == .creating && store.hasPendingImage && !store.isBusy {
                        Task { await createBaby() }
                    }
                }
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch progress.stage {
        case .welcome:
            title("Hi! You’re about to create your very own Fur Baby.")
            BirthAnimationView().frame(height: 285)
            Text("Any animal. Any color. A little best friend, dreamed up by you.").font(.system(size: 18)).foregroundStyle(FurTheme.ink.opacity(0.65))
            Pill(text: "YOUR FIRST FUR BABY IS FREE", symbol: "gift.fill", fill: FurTheme.lime)
        case .adventures:
            title("A little friend for every kind of day.")
            OnboardingVideoView(resource: "onboarding-adventures", label: "Demo of a Fur Baby on a moon adventure, then relaxing at home")
            benefit("You can take them on adventures with you", symbol: "photo.on.rectangle.angled")
            benefit("Or just hang out", symbol: "heart.fill")
        case .widgets:
            title("You can always keep them with you!")
            OnboardingVideoView(resource: "onboarding-widgets", label: "Demo of the small and medium Fur Baby Home Screen widgets")
            benefit("A little home on your Home Screen", symbol: "square.grid.2x2.fill")
            Text("Small and medium widgets, so your best friend is always close.").font(.system(size: 17)).foregroundStyle(FurTheme.ink.opacity(0.65))
        case .introduction:
            title("Let’s start with some questions.")
            PetIllustration().frame(maxWidth: .infinity).frame(height: 265).background(FurTheme.lavender.opacity(0.6), in: RoundedRectangle(cornerRadius: 30))
            Text("Tell us about your Fur Baby. We’ll add a little magic and bring your imagination to life.").font(.system(size: 18)).foregroundStyle(FurTheme.ink.opacity(0.65))
        case .questions:
            question
        case .creating:
            title("Bringing your baby to life…")
            BirthAnimationView().frame(height: 300)
            if store.isBusy {
                CreationMessagesView()
                Text(store.isReconnecting ? "Still here! Reconnecting to your little friend…" : "Good things take a little love. We’ll show your baby as soon as they’re ready.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                Text(store.creationRecoveryMessage ?? "Your answers are saved. Let’s try bringing your little friend home again.")
                    .font(.system(size: 18)).foregroundStyle(FurTheme.ink.opacity(0.65))
            }
            Pill(text: "FREE CREATION · NO PURCHASE NEEDED", symbol: "gift.fill", fill: FurTheme.lime)
        case .reveal, .paywall:
            if let pet {
                Pill(text: "A STAR IS BORN", symbol: "sparkles", fill: FurTheme.lime)
                title("Meet your Fur Baby!")
                PetArtworkView(pet: pet).frame(maxWidth: .infinity).frame(height: 285)
                    .background(FurTheme.lavender.opacity(0.65), in: RoundedRectangle(cornerRadius: 30))
                Text("What should we call \(gender == .boy ? "him" : "her")?").font(.system(size: 21, weight: .bold, design: .rounded))
                TextField("Their forever name", text: Binding(get: { store.onboarding.name }, set: { store.onboarding.name = $0 }))
                    .font(.system(size: 23, weight: .medium, design: .rounded)).padding(21)
                    .background(.white, in: RoundedRectangle(cornerRadius: 22)).focused($answerFocused)
                    .submitLabel(.done).accessibilityIdentifier("onboardingPetName")
                Text("Keep the name you chose, or try one that feels just right.").font(.subheadline).foregroundStyle(.secondary)
                if pet.isSample { Text("Illustrated sample preview").font(.caption).foregroundStyle(.secondary) }
            }
        case .complete: EmptyView()
        }
    }

    private var question: some View {
        PetQuestionForm(
            progress: Binding(get: { store.onboarding }, set: { store.onboarding = $0 }),
            answerFocused: $answerFocused,
            creationNote: store.isSampleMode ? "We’ll create an illustrated sample in this preview." : "Your answers are sent to our image service to create your Fur Baby. Your first creation is free."
        )
    }

    @ViewBuilder private var footer: some View {
        VStack(spacing: 10) {
            switch progress.stage {
            case .creating:
                if store.isBusy { ProgressView().tint(FurTheme.pink).padding(16) }
                else {
                    PrimaryButton(title: store.hasPendingImage ? "Recover my Fur Baby" : "Try again · free") { Task { await createBaby() } }
                    Button("Review my answers") { store.onboarding.stage = .questions }
                        .disabled(store.hasPendingImage).font(.subheadline)
                }
            case .reveal, .paywall:
                PrimaryButton(title: "Let’s go, \(progress.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "little one" : progress.name)!", symbol: "heart.fill", disabled: !OnboardingProgress.validAnswer(progress.name, limit: 40) || pet == nil) {
                    answerFocused = false
                    if let pet { store.namePet(id: pet.id, name: progress.name); store.onboarding.name = progress.name.trimmingCharacters(in: .whitespacesAndNewlines); store.onboarding.stage = .paywall }
                }
            case .questions:
                PrimaryButton(title: progress.question == 4 ? "Bring my baby to life · free" : "Next", disabled: !progress.canContinue) {
                    answerFocused = false
                    if progress.question < 4 { store.onboarding.question += 1 }
                    else { store.onboarding.stage = .creating }
                }
            default:
                PrimaryButton(title: progress.stage == .welcome ? "Let’s meet my Fur Baby" : progress.stage == .introduction ? "Tell you about my Fur Baby" : "Continue") {
                    switch progress.stage {
                    case .welcome: store.onboarding.stage = .adventures
                    case .adventures: store.onboarding.stage = .widgets
                    case .widgets: store.onboarding.stage = .introduction
                    default: store.onboarding.stage = .questions
                    }
                }
            }
        }.padding(.horizontal, 25).padding(.vertical, 14).frame(maxWidth: 560).frame(maxWidth: .infinity).background(FurTheme.cream)
    }
    private var canGoBack: Bool { [.adventures, .widgets, .introduction, .questions].contains(progress.stage) }
    private func goBack() {
        answerFocused = false
        switch progress.stage {
        case .adventures: store.onboarding.stage = .welcome
        case .widgets: store.onboarding.stage = .adventures
        case .introduction: store.onboarding.stage = .widgets
        case .questions:
            if progress.question > 0 { store.onboarding.question -= 1 }
            else { store.onboarding.stage = .introduction }
        default: break
        }
    }
    private func createBaby() async {
        if let existing = store.pets.first(where: { $0.id == progress.petID }) {
            store.onboarding.petID = existing.id; store.onboarding.stage = .reveal; return
        }
        if store.hasPendingImage { await store.resumePendingImage() }
        else { _ = await store.generate(recipe: progress.recipe, name: progress.name.trimmingCharacters(in: .whitespacesAndNewlines), onboardingCreation: true) }
    }
    private func title(_ text: String) -> some View {
        Text(text).font(.system(size: 36, weight: .heavy, design: .rounded)).tracking(-1).fixedSize(horizontal: false, vertical: true)
    }
    private func benefit(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol).font(.system(size: 18, weight: .bold, design: .rounded)).labelStyle(.titleAndIcon)
    }
}

struct CreationMessagesView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var index = 0
    private static let messages = [
        "Building toe beans…",
        "Filling them with love…",
        "Adding a little mischief…",
        "Sprinkling in personality…",
        "Packing tiny adventures…",
        "Making room for cuddles…",
        "Teaching the cutest head tilt…",
        "Fluffing the final floofs…"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("A LITTLE MAGIC IN THE MAKING", systemImage: "sparkles")
                .font(.system(size: 10, weight: .bold, design: .rounded)).foregroundStyle(FurTheme.pink)
            ZStack(alignment: .leading) {
                Text(Self.messages[index])
                    .font(.system(size: 23, weight: .bold, design: .rounded))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .id(index)
                    .transition(reduceMotion ? .opacity : .asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .move(edge: .top).combined(with: .opacity)))
            }.frame(height: 65, alignment: .leading).clipped()
                .animation(.easeInOut(duration: reduceMotion ? 0.2 : 0.5), value: index)
        }.accessibilityElement(children: .ignore)
            .accessibilityLabel("Bringing your Fur Baby to life. Your creation is in progress.")
            .task(id: scenePhase) {
                guard scenePhase == .active else { return }
                do {
                    while !Task.isCancelled {
                        try await Task.sleep(for: .seconds(3))
                        index = (index + 1) % Self.messages.count
                    }
                } catch { /* Leaving the creation screen stops the message loop. */ }
            }
    }
}

private struct OnboardingVideoView: View {
    let resource: String
    let label: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var player: AVQueuePlayer?
    @State private var looper: AVPlayerLooper?
    @State private var paused = false

    var body: some View {
        VStack(spacing: 9) {
            ZStack {
                if let player { VideoPlayer(player: player) }
                else { Image(resource).resizable().scaledToFill() }
            }.aspectRatio(1, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 28))
                .accessibilityLabel(label)
            HStack {
                Text("DEMO PREVIEW").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
                Spacer()
                Button(paused ? "Play demo" : "Pause demo", systemImage: paused ? "play.fill" : "pause.fill") {
                    paused.toggle(); updatePlayback()
                }.font(.caption.bold())
            }
        }.frame(maxWidth: 285).frame(maxWidth: .infinity)
        .onAppear {
            guard player == nil, let url = Bundle.main.url(forResource: resource, withExtension: "mp4") else { return }
            let queue = AVQueuePlayer(); queue.isMuted = true
            looper = AVPlayerLooper(player: queue, templateItem: AVPlayerItem(url: url)); player = queue
            paused = reduceMotion; updatePlayback()
        }
        .onDisappear { player?.pause(); looper = nil; player = nil }
        .onChange(of: scenePhase) { _, _ in updatePlayback() }
        .onChange(of: reduceMotion) { _, value in paused = value; updatePlayback() }
    }
    private func updatePlayback() {
        if !paused && scenePhase == .active { player?.play() } else { player?.pause() }
    }
}

private struct BirthAnimationView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24, paused: reduceMotion)) { timeline in
            let time = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
            let pulse = sin(time * 2)
            ZStack {
                Circle().fill(FurTheme.lavender.opacity(0.5)).frame(width: 240, height: 240).scaleEffect(1 + pulse * 0.04)
                Circle().stroke(FurTheme.pink.opacity(0.2), style: StrokeStyle(lineWidth: 2, dash: [4, 9]))
                    .frame(width: 260, height: 260).rotationEffect(.degrees(time * 10))
                Ellipse().fill(.white).frame(width: 135, height: 168).shadow(color: FurTheme.pink.opacity(0.16), radius: 20, y: 12)
                    .rotationEffect(.degrees(pulse * 7)).offset(y: pulse * 5)
                FurBrandIcon(size: 82)
                    .scaleEffect(1 + pulse * 0.08).offset(y: pulse * 5)
                ForEach(0..<6, id: \.self) { index in
                    let angle = Double(index) * .pi / 3 + time * 0.25
                    Image(systemName: index.isMultiple(of: 2) ? "sparkle" : "heart.fill")
                        .font(.system(size: index.isMultiple(of: 2) ? 22 : 15)).foregroundStyle(index.isMultiple(of: 2) ? FurTheme.pink : FurTheme.ink.opacity(0.5))
                        .offset(x: cos(angle) * 116, y: sin(angle) * 116)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }.accessibilityElement(children: .ignore).accessibilityLabel("A magical egg surrounded by hearts and sparkles")
    }
}
