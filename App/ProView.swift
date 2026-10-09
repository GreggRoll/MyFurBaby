import SwiftUI

struct ProView: View {
    var onboardingPet: FurPet? = nil
    var onFinish: (() -> Void)? = nil
    @Environment(FurStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var yearly = false
    private var monthlyPrice: String { store.products.first { $0.id == ProductIDs.monthly }?.displayPrice ?? "$4.99" }
    private var yearlyPrice: String { store.products.first { $0.id == ProductIDs.yearly }?.displayPrice ?? "$50" }
    private var packPrice: String { store.products.first { $0.id == ProductIDs.credits }?.displayPrice ?? "$4.99" }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 23) {
                    HStack(spacing: 10) { FurBrandIcon(size: 32); Pill(text: "MY FUR BABY PRO", symbol: "crown.fill", fill: FurTheme.lime); Spacer() }
                    Text(onboardingPet.map { "Let’s keep \($0.name) close and take \($0.recipe.gender == .boy ? "him" : $0.recipe.gender == .girl ? "her" : "them") on adventures!" } ?? "More life.\nMore little adventures.").font(.system(size: 36, weight: .heavy, design: .rounded)).tracking(-1.2)
                    HStack { PetArtworkView(pet: onboardingPet ?? .sample).frame(width: 125, height: 142); VStack(alignment: .leading, spacing: 9) { Text("Their own little world.").font(.system(size: 19, weight: .bold, design: .rounded)); Text("Personal poses, Home Screen widgets, and a place in your photos.").font(.system(size: 13)).foregroundStyle(FurTheme.ink.opacity(0.65)) } }.padding(16).background(FurTheme.lavender.opacity(0.7), in: RoundedRectangle(cornerRadius: 27))
                    if onboardingPet != nil { Text("Your Fur Baby is yours. Pro unlocks widgets and photo adventures.").font(.subheadline).foregroundStyle(FurTheme.ink.opacity(0.65)) }
                    feature("5,000 credits every month", detail: "20 images at 250 credits each", symbol: "sparkles")
                    feature("Personal pet poses & widgets", detail: "Small square and wide rectangle", symbol: "square.grid.2x2")
                    feature("Your pet, in your photos", detail: "Upload a photo and create an adventure", symbol: "photo.badge.plus")
                    HStack(spacing: 12) {
                        plan("Monthly", price: monthlyPrice, cadence: "/ month", selected: !yearly) { yearly = false }
                        plan("Yearly", price: yearlyPrice, cadence: "/ year", selected: yearly) { yearly = true }
                    }
                    Text("Subscription credits reset monthly and don't carry over. Annual Pro also receives 5,000 each month.").font(.caption).foregroundStyle(FurTheme.ink.opacity(0.58))
                    PrimaryButton(title: store.isPro ? "Pro is active" : "Get Pro · \(yearly ? yearlyPrice + " / year" : monthlyPrice + " / month")", symbol: "crown.fill", disabled: store.isBusy || store.isPro) { Task { await store.buy(yearly ? ProductIDs.yearly : ProductIDs.monthly) } }
                    if store.isSampleMode {
                        #if DEBUG
                        Button("Try Pro in sample mode · no charge") { store.demoPro(yearly: yearly); finish() }.font(.system(size: 14, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 8)
                        #endif
                    }
                    Divider()
                    HStack {
                        VStack(alignment: .leading, spacing: 5) { Text("A little extra imagination").font(.system(size: 16, weight: .bold, design: .rounded)); Text("5,000 extra credits · 20 images").font(.caption).foregroundStyle(.secondary) }
                        Spacer()
                        Button(packPrice) { if store.isSampleMode { store.demoPack() } else { Task { await store.buy(ProductIDs.credits) } } }
                            .font(.system(size: 14, weight: .bold)).padding(13).background(FurTheme.lime, in: Capsule())
                    }
                    Text(store.isSampleMode ? "In sample mode, this pack adds sample credits without charging. Purchased packs in the connected app do not expire." : "Purchased packs do not expire. Photo adventures and widgets require Pro.").font(.caption).foregroundStyle(.secondary)
                    HStack { Button("Restore purchases") { Task { await store.restore() } }; Spacer(); Link("Terms", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!) }.font(.caption)
                    Text("Auto-renewing subscription. Payment is charged to your Apple Account. Manage or cancel in App Store settings. Widget motion is experimental on current iOS; automatic looping has not been verified for release.").font(.system(size: 10)).foregroundStyle(.secondary)
                }.padding(25)
            }.background(FurTheme.cream).foregroundStyle(FurTheme.ink)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(onboardingPet == nil ? "Done" : "Not now") { finish() } } }
                .onChange(of: store.isPro) { _, active in if active && onboardingPet != nil { finish() } }
        }
    }
    private func finish() { if let onFinish { onFinish() } else { dismiss() } }
    private func feature(_ title: String, detail: String, symbol: String) -> some View {
        HStack(spacing: 13) { Image(systemName: symbol).font(.system(size: 21)).foregroundStyle(FurTheme.pink).frame(width: 30); VStack(alignment: .leading, spacing: 3) { Text(title).font(.system(size: 15, weight: .bold, design: .rounded)); Text(detail).font(.system(size: 12)).foregroundStyle(.secondary) } }
    }
    private func plan(_ title: String, price: String, cadence: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) { HStack { Text(title).font(.system(size: 13, weight: .bold)); Spacer(); Image(systemName: selected ? "checkmark.circle.fill" : "circle").foregroundStyle(selected ? FurTheme.pink : FurTheme.ink.opacity(0.25)) }; Text(price).font(.system(size: 28, weight: .heavy, design: .rounded)); Text(cadence).font(.system(size: 10)) }
                .foregroundStyle(FurTheme.ink).frame(maxWidth: .infinity, alignment: .leading).padding(17).background(.white, in: RoundedRectangle(cornerRadius: 22))
                .overlay { RoundedRectangle(cornerRadius: 22).stroke(selected ? FurTheme.pink : FurTheme.ink.opacity(0.1), lineWidth: selected ? 2 : 1) }
        }.buttonStyle(.plain)
    }
}
