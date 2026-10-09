import SwiftUI

enum FurTab: String, CaseIterable { case home = "My pet", photos = "Adventures", widgets = "Widgets"; var symbol: String { switch self { case .home: "pawprint.fill"; case .photos: "photo.on.rectangle.angled"; case .widgets: "square.grid.2x2.fill" } } }

struct RootView: View {
    @Environment(FurStore.self) private var store
    @State private var tab: FurTab = .home
    @State private var creating = false
    @State private var settings = false
    var body: some View {
        if store.onboarding.stage != .complete {
            OnboardingView().furErrorAlert()
        } else {
            mainContent
        }
    }
    @ViewBuilder private var mainContent: some View {
        @Bindable var store = store
        NavigationStack {
            ZStack {
                FurTheme.cream.ignoresSafeArea()
                VStack(spacing: 0) {
                    HStack(spacing: 10) {
                        FurBrandIcon(size: 32)
                        Text("my fur baby").font(.system(size: 21, weight: .heavy, design: .rounded))
                        Spacer()
                        Button { store.showPaywall = true } label: { Pill(text: store.wallet.total.formatted(), symbol: "sparkle", fill: FurTheme.lime) }.accessibilityLabel("\(store.wallet.total) credits")
                        Button { settings = true } label: { Image(systemName: "slider.horizontal.3").font(.system(size: 19)).padding(8) }.accessibilityLabel("Settings")
                    }.foregroundStyle(FurTheme.ink).padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 16)
                    Group {
                        switch tab {
                        case .home: HomeView(creating: $creating, tab: $tab)
                        case .photos: AdventureView()
                        case .widgets: WidgetStudioView()
                        }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                HStack {
                    ForEach(FurTab.allCases, id: \.rawValue) { item in
                        Button { tab = item } label: {
                            VStack(spacing: 6) { Image(systemName: item.symbol).font(.system(size: 20)); Text(item.rawValue).font(.system(size: 10, weight: .bold)) }
                                .foregroundStyle(tab == item ? FurTheme.pink : FurTheme.ink.opacity(0.40)).frame(maxWidth: .infinity).padding(.top, 17).padding(.bottom, 12)
                        }.accessibilityLabel(item.rawValue).buttonStyle(.plain)
                    }
                }.background(FurTheme.cream).overlay(alignment: .top) { Rectangle().fill(FurTheme.ink.opacity(0.07)).frame(height: 1) }
            }
            .sheet(isPresented: $creating) { CreatePetView().furErrorAlert() }
            .sheet(isPresented: $settings) { SettingsView().furErrorAlert() }
            .sheet(isPresented: $store.showPaywall) { ProView().furErrorAlert() }
            .furErrorAlert(enabled: !(creating || settings || store.showPaywall))
            .onOpenURL { url in if url.host == "widgets" { tab = .widgets } else { tab = .home } }
        }
    }
}

struct HomeView: View {
    @Environment(FurStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var creating: Bool
    @Binding var tab: FurTab
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 23) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(store.selectedPet == nil ? "Dream up your\nnew best friend." : "A little friend.\nA lot of personality.")
                        .font(.system(size: 35, weight: .heavy, design: .rounded)).tracking(-1.2).lineSpacing(-3).fixedSize(horizontal: false, vertical: true)
                    Text(store.selectedPet == nil ? "Any animal. Any color. Entirely yours." : "Your imagination, brought to life.").font(.system(size: 15)).foregroundStyle(FurTheme.ink.opacity(0.60))
                }
                hero
                PrimaryButton(title: store.selectedPet == nil ? "Create my Fur Baby" : "Dream up another pet") { creating = true }
                HStack(spacing: 12) {
                    FeatureCard(title: "Photo adventures", subtitle: "Take your pet anywhere", symbol: "photo.badge.plus", color: FurTheme.lime.opacity(0.72), locked: !store.isPro) { if store.isPro { tab = .photos } else { store.showPaywall = true } }
                    FeatureCard(title: "A home on screen", subtitle: "Small & wide widgets", symbol: "square.grid.2x2", color: FurTheme.lavender.opacity(0.65), locked: !store.isPro) { if store.isPro { tab = .widgets } else { store.showPaywall = true } }
                }
                if !store.pets.isEmpty {
                    SectionTitle(title: "Your little family", subtitle: "Tap a pet to bring it home.")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 13) {
                            ForEach(store.pets) { pet in
                                Button { store.select(pet) } label: {
                                    VStack(spacing: 4) { PetArtworkView(pet: pet).frame(width: 91, height: 90); Text(pet.name.isEmpty ? "New arrival" : pet.name).font(.system(size: 12, weight: .bold, design: .rounded)).lineLimit(1) }
                                        .padding(8).frame(width: 113).background(.white, in: RoundedRectangle(cornerRadius: 19))
                                        .overlay { RoundedRectangle(cornerRadius: 19).stroke(store.selectedPet?.id == pet.id ? FurTheme.pink : .clear, lineWidth: 2) }
                                }.buttonStyle(.plain)
                            }
                        }.padding(2)
                    }
                }
            }.padding(.horizontal, 24).padding(.bottom, 26)
        }.foregroundStyle(FurTheme.ink)
    }
    private var hero: some View {
        let pet = store.selectedPet ?? .sample
        return VStack(spacing: 0) {
            HStack { Pill(text: store.selectedPet == nil ? "ONE OF A KIND" : pet.recipe.personality.components(separatedBy: ",").first ?? "ONE OF A KIND", symbol: "heart.fill"); Spacer(); Image(systemName: "sparkle").font(.system(size: 22)).foregroundStyle(.white) }.padding(20)
            LivePetStage(pet: pet, behavior: store.behavior, animate: store.selectedPet != nil && store.isPro && !reduceMotion)
                .frame(height: 208).padding(.top, -12)
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) { Text(store.selectedPet == nil ? "Meet the possibilities." : pet.name.isEmpty ? "Your new arrival" : pet.name).font(.system(size: 25, weight: .heavy, design: .rounded)); Text(store.selectedPet == nil ? "A purple puppy? A sassy gigglegoop?" : pet.recipe.animal).font(.system(size: 12)).foregroundStyle(FurTheme.ink.opacity(0.6)).lineLimit(1) }
                Spacer()
                if store.selectedPet != nil {
                    Button { store.setBehavior(store.behavior == .sleepy ? .playful : .sleepy) } label: { Image(systemName: store.behavior == .sleepy ? "sun.max.fill" : "moon.zzz.fill").font(.system(size: 19)).padding(13).background(.white.opacity(0.6), in: Circle()) }.accessibilityLabel("Change pet behavior")
                }
            }.padding(20).padding(.top, -5)
        }
        .background(LinearGradient(colors: [FurTheme.lavender, Color(red: 0.93, green: 0.86, blue: 0.92)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 31))
    }
}
