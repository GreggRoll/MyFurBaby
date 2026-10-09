import SwiftUI

struct SettingsView: View {
    @Environment(FurStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section("Your membership") {
                    LabeledContent("Plan", value: store.isPro ? "Pro" : "Free")
                    LabeledContent("Monthly credits", value: store.wallet.subscriptionCredits.formatted())
                    LabeledContent("Pack credits", value: store.wallet.purchasedCredits.formatted())
                    if let reset = store.wallet.resetsAt { LabeledContent("Monthly reset", value: reset.formatted(date: .abbreviated, time: .omitted)) }
                    Button("View Pro & credit packs") { dismiss(); store.showPaywall = true }
                    Button("Restore purchases") { Task { await store.restore() } }
                }
                Section {
                    Text("Monthly Pro includes 5,000 credits. A pet or photo adventure costs 250, a custom widget background costs 200, and each animation costs 1,500. Unused subscription credits expire at the monthly reset; purchased packs stay in your balance.").font(.footnote).foregroundStyle(.secondary)
                }
                if store.hasPendingImage {
                    Section("Unfinished image") {
                        Button("Resume unfinished image · no extra charge") { Task { await store.resumePendingImage() } }.disabled(store.isBusy)
                        if store.isBusy { ProgressView(store.activity) }
                    }
                }
                if let image = store.recoveredPhoto {
                    Section("Recovered adventure") {
                        Image(uiImage: image).resizable().scaledToFit()
                        ShareLink(item: Image(uiImage: image), preview: SharePreview("My Fur Baby adventure", image: Image(uiImage: image))) { Label("Share or save", systemImage: "square.and.arrow.up") }
                    }
                }
                Section("About") {
                    HStack(spacing: 12) {
                        FurBrandIcon(size: 48)
                        Text("My Fur Baby · MVP 1.0").font(.subheadline)
                    }
                    Text("Automatic widget motion remains experimental. Full animation previews run inside the app.").font(.footnote).foregroundStyle(.secondary)
                    Link("Apple standard license", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                }
            }.navigationTitle("Settings").toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
        }
    }
}
