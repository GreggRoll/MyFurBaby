import SwiftUI

/// One five-question form for the free onboarding pet and additional pets.
struct PetQuestionForm: View {
    @Binding var progress: OnboardingProgress
    var answerFocused: FocusState<Bool>.Binding
    let creationNote: String

    private var gender: PetGender { progress.recipe.gender ?? .boy }
    private var answer: Binding<String> {
        switch progress.question {
        case 1: $progress.recipe.animal
        case 2: $progress.recipe.color
        case 3: $progress.recipe.accessories
        default: $progress.name
        }
    }
    private var title: String {
        switch progress.question {
        case 0: "Tell us about your Fur Baby."
        case 1: "What kind of animal is \(gender.subject)?"
        case 2: "What color is \(gender.subject)?"
        case 3: "Does \(gender.subject) have any accessories?"
        default: "What is \(gender.possessive) name?"
        }
    }
    private var hint: String {
        switch progress.question {
        case 1: "Real, rare, or entirely imaginary."
        case 2: "One shade, a rainbow, or a perfect ombré."
        case 3: "A collar, a crown, a tiny tuxedo. Leave blank for no accessories."
        default: "You can change it once you’ve met \(gender == .boy ? "him" : "her")."
        }
    }
    private var placeholder: String {
        switch progress.question {
        case 1: "A floppy-eared puppy, a tiny dragon…"
        case 2: "Purple with a pink ombré tail…"
        case 3: "A top hat and monocle…"
        default: "Their forever name"
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 6) {
                ForEach(0..<5, id: \.self) { index in
                    Capsule().fill(index <= progress.question ? FurTheme.pink : FurTheme.ink.opacity(0.10)).frame(height: 4)
                }
            }
            Text(title).font(.system(size: 36, weight: .heavy, design: .rounded))
                .tracking(-1).fixedSize(horizontal: false, vertical: true)
            if progress.question == 0 {
                Text("Boy or Girl?").font(.system(size: 23, weight: .bold, design: .rounded))
                HStack(spacing: 14) {
                    ForEach(PetGender.allCases) { option in
                        Button { progress.recipe.gender = option } label: {
                            VStack(spacing: 18) {
                                Image(systemName: option == .boy ? "sun.max.fill" : "sparkles")
                                    .font(.system(size: 34)).foregroundStyle(FurTheme.pink)
                                Text(option.title).font(.system(size: 23, weight: .bold, design: .rounded))
                                Image(systemName: progress.recipe.gender == option ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(FurTheme.pink)
                            }.frame(maxWidth: .infinity).padding(.vertical, 32)
                                .background(.white, in: RoundedRectangle(cornerRadius: 26))
                                .overlay { RoundedRectangle(cornerRadius: 26).stroke(progress.recipe.gender == option ? FurTheme.pink : .clear, lineWidth: 2) }
                        }.buttonStyle(.plain)
                            .accessibilityAddTraits(progress.recipe.gender == option ? .isSelected : [])
                            .accessibilityIdentifier("petGender-\(option.rawValue)")
                    }
                }
            } else {
                Text(hint).font(.system(size: 17)).foregroundStyle(FurTheme.ink.opacity(0.65))
                TextField(placeholder, text: answer, axis: .vertical)
                    .lineLimit(progress.question == 4 ? 1...2 : 3...5)
                    .font(.system(size: 23, weight: .medium, design: .rounded)).padding(23)
                    .background(.white, in: RoundedRectangle(cornerRadius: 26))
                    .focused(answerFocused).accessibilityIdentifier("onboardingAnswer")
                let limit = progress.question == 3 ? 500 : progress.question == 4 ? 40 : 300
                if answer.wrappedValue.utf16.count > limit {
                    Text("Please keep this answer under \(limit) characters.").font(.caption).foregroundStyle(FurTheme.pink)
                }
                if progress.question == 4 {
                    Text(creationNote).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct CreatePetView: View {
    @Environment(FurStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var progress = OnboardingProgress(stage: .questions)
    @State private var createdPet: FurPet?
    @FocusState private var answerFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(spacing: 8) {
                        FurBrandIcon(size: 28)
                        Text("MY FUR BABY").font(.system(size: 11, weight: .bold, design: .rounded))
                        Spacer()
                        if createdPet == nil {
                            Text("\(progress.question + 1) / 5").font(.caption.bold()).foregroundStyle(.secondary)
                        }
                    }
                    if let pet = createdPet { naming(pet) }
                    else {
                        PetQuestionForm(progress: $progress, answerFocused: $answerFocused,
                            creationNote: store.isSampleMode ? "We’ll create an illustrated sample in this preview. One pet costs 250 credits." : "Your answers are sent to our image service to create your Fur Baby. One pet costs 250 credits.")
                        if store.isBusy {
                            ProgressView(store.activity).padding(.vertical, 8)
                        }
                    }
                }.padding(25).frame(maxWidth: 560, alignment: .leading).frame(maxWidth: .infinity)
            }.scrollDismissesKeyboard(.interactively)
                .background(FurTheme.cream.ignoresSafeArea()).foregroundStyle(FurTheme.ink)
                .safeAreaInset(edge: .bottom, spacing: 0) { footer }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        if progress.question > 0 && createdPet == nil {
                            Button("Back") { answerFocused = false; progress.question -= 1 }.disabled(store.isBusy)
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { dismiss() } label: {
                            Image(systemName: "xmark").font(.system(size: 13, weight: .bold))
                                .padding(9).background(FurTheme.ink.opacity(0.06), in: Circle())
                        }.accessibilityLabel("Close creation").disabled(store.isBusy)
                    }
                }
                .interactiveDismissDisabled(store.isBusy)
        }
    }
    @ViewBuilder private var footer: some View {
        Group {
            if let pet = createdPet {
                PrimaryButton(title: "Welcome home", symbol: "heart.fill",
                    disabled: !OnboardingProgress.validAnswer(progress.name, limit: 40)) {
                    answerFocused = false
                    store.namePet(id: pet.id, name: progress.name); dismiss()
                    if !store.isPro { store.showPaywall = true }
                }
            } else {
                PrimaryButton(title: progress.question == 4 ? "Bring my baby to life · 250 credits" : "Next",
                    disabled: !progress.canContinue || store.isBusy) {
                    answerFocused = false
                    if progress.question < 4 { progress.question += 1 }
                    else {
                        Task {
                            createdPet = await store.generate(recipe: progress.recipe,
                                name: progress.name.trimmingCharacters(in: .whitespacesAndNewlines))
                        }
                    }
                }
            }
        }.padding(.horizontal, 25).padding(.vertical, 14)
            .frame(maxWidth: 560).frame(maxWidth: .infinity).background(FurTheme.cream)
    }
    private func naming(_ pet: FurPet) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            Pill(text: "A STAR IS BORN", symbol: "sparkles", fill: FurTheme.lime)
            Text("Meet your Fur Baby!").font(.system(size: 36, weight: .heavy, design: .rounded)).tracking(-1)
            PetArtworkView(pet: pet).frame(maxWidth: .infinity).frame(height: 285)
                .background(FurTheme.lavender.opacity(0.65), in: RoundedRectangle(cornerRadius: 30))
            Text("What should we call \(pet.recipe.gender == .boy ? "him" : "her")?")
                .font(.system(size: 21, weight: .bold, design: .rounded))
            TextField("Their forever name", text: $progress.name)
                .font(.system(size: 23, weight: .medium, design: .rounded)).padding(21)
                .background(.white, in: RoundedRectangle(cornerRadius: 22))
                .focused($answerFocused).submitLabel(.done).accessibilityIdentifier("petName")
            Text("Keep the name you chose, or try one that feels just right.").font(.subheadline).foregroundStyle(.secondary)
            if pet.isSample { Text("Illustrated sample preview").font(.caption).foregroundStyle(.secondary) }
        }
    }
}
