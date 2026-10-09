import SwiftUI

struct FurErrorAlert: ViewModifier {
    @Environment(FurStore.self) private var store
    var enabled = true
    func body(content: Content) -> some View {
        content.alert("A little hiccup", isPresented: Binding(get: { enabled && store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("OK") { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
    }
}
extension View {
    func furErrorAlert(enabled: Bool = true) -> some View { modifier(FurErrorAlert(enabled: enabled)) }
}

struct Pill: View {
    let text: String
    var symbol: String? = nil
    var color: Color = FurTheme.ink
    var fill: Color = .white.opacity(0.65)
    var body: some View {
        HStack(spacing: 5) { if let symbol { Image(systemName: symbol) }; Text(text) }
            .font(.system(size: 11, weight: .bold, design: .rounded)).foregroundStyle(color)
            .padding(.horizontal, 11).padding(.vertical, 7).background(fill, in: Capsule())
    }
}

struct PrimaryButton: View {
    let title: String
    var symbol = "sparkles"
    var disabled = false
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) { Image(systemName: symbol); Text(title); Spacer(); Image(systemName: "arrow.right") }
                .font(.system(size: 16, weight: .bold, design: .rounded)).padding(20)
                .foregroundStyle(.white).background(FurTheme.pink, in: RoundedRectangle(cornerRadius: 21))
        }.disabled(disabled).opacity(disabled ? 0.45 : 1).buttonStyle(.plain)
    }
}

struct SectionTitle: View {
    let title: String
    var subtitle: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 25, weight: .bold, design: .rounded))
            if let subtitle { Text(subtitle).font(.subheadline).foregroundStyle(FurTheme.ink.opacity(0.58)) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct LivePetStage: View {
    let pet: FurPet
    var behavior: PetBehavior = .auto
    var animate = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            let sleeping = behavior.isSleeping(at: timeline.date)
            let running = !sleeping && behavior == .running
            if animate {
                AnimatedPetStage(pet: pet, sleeping: sleeping, running: running)
            } else {
                PetArtworkView(pet: pet, sleeping: sleeping, running: running)
            }
        }
    }
}

private struct AnimatedPetStage: View {
    let pet: FurPet
    let sleeping: Bool
    let running: Bool
    @State private var playbackStart = Date()
    @State private var actionImages: [UIImage]?
    @State private var idleImages: [UIImage]?
    private var action: PetAnimation? {
        sleeping ? pet.sleepingAnimation : running ? pet.runningAnimation : pet.playfulAnimation
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 15)) { timeline in
            let time = timeline.date.timeIntervalSince(playbackStart)
            let phase = sleeping ? time.truncatingRemainder(dividingBy: 4) / 4
                : PetPlayback.phase(at: time, duration: 4)
            PetArtworkView(pet: pet, sleeping: sleeping, playful: !sleeping && !running,
                           running: running, phase: phase, animationTime: time,
                           preparedActionImages: actionImages, preparedIdleImages: idleImages,
                           usesPreparedImages: true)
        }
        .task(id: [action, sleeping ? nil : pet.idleAnimation]) {
            actionImages = nil; idleImages = nil
            async let loadedAction = SharedStorage.playbackImages(for: action)
            async let loadedIdle = SharedStorage.playbackImages(for: sleeping ? nil : pet.idleAnimation)
            let loaded = await (loadedAction, loadedIdle)
            guard !Task.isCancelled else { return }
            actionImages = loaded.0; idleImages = loaded.1
            playbackStart = Date()
        }
        .onChange(of: sleeping) { _, _ in playbackStart = Date() }
        .onChange(of: running) { _, _ in playbackStart = Date() }
    }
}

struct FeatureCard: View {
    let title: String
    let subtitle: String
    let symbol: String
    let color: Color
    let locked: Bool
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 15) {
                HStack { Image(systemName: symbol).font(.system(size: 22)); Spacer(); if locked { Image(systemName: "lock.fill").font(.caption) } }
                VStack(alignment: .leading, spacing: 4) { Text(title).font(.system(size: 16, weight: .bold, design: .rounded)); Text(subtitle).font(.system(size: 12)).foregroundStyle(FurTheme.ink.opacity(0.65)).multilineTextAlignment(.leading) }
            }.foregroundStyle(FurTheme.ink).frame(maxWidth: .infinity, alignment: .leading).padding(18)
                .background(color, in: RoundedRectangle(cornerRadius: 23))
        }.buttonStyle(.plain)
    }
}
