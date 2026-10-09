import SwiftUI
import PhotosUI
import Photos
import ImageIO

struct AdventureView: View {
    @Environment(FurStore.self) private var store
    @State private var selection: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var photo: UIImage?
    @State private var result: UIImage?
    @State private var placement = "Sitting beside me, looking at the camera"
    @State private var loadingPhoto = false
    @State private var saved = false
    @State private var openedAdventure: AdventureMemory?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 23) {
                Pill(text: "PHOTO ADVENTURES", symbol: "photo.badge.plus", color: FurTheme.pink, fill: FurTheme.pink.opacity(0.08))
                SectionTitle(title: "Make a memory together.", subtitle: "Your real world. Their little adventure.")
                if store.selectedPet == nil {
                    empty("First, dream up a pet.", detail: "Create your Fur Baby from the My pet tab, then bring them into a photo.")
                } else if !store.isPro {
                    empty("Every adventure starts with Pro.", detail: "Upload your own photo and let GPT Image 2 add your pet with matching lighting and perspective.")
                    PrimaryButton(title: "Unlock photo adventures", symbol: "crown.fill") { store.showPaywall = true }
                } else {
                    if let image = result ?? photo {
                        Image(uiImage: image).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 25))
                        if result != nil { Pill(text: "YOUR NEW MEMORY", symbol: "heart.fill", fill: FurTheme.lime) }
                    } else {
                        VStack(spacing: 15) { Image(systemName: "photo.on.rectangle.angled").font(.system(size: 47)).foregroundStyle(FurTheme.pink); Text("Pick a place for your pet.").font(.system(size: 17, weight: .bold, design: .rounded)); Text("A selfie, your sofa, a favorite vacation.").font(.caption).foregroundStyle(.secondary) }
                            .frame(maxWidth: .infinity).frame(height: 220).background(FurTheme.lavender.opacity(0.55), in: RoundedRectangle(cornerRadius: 26))
                    }
                    PhotosPicker(selection: $selection, matching: .images, photoLibrary: .shared()) {
                        Label(photo == nil ? "Choose a photo" : "Choose a different photo", systemImage: "photo.badge.plus").font(.system(size: 15, weight: .bold)).frame(maxWidth: .infinity).padding(17).background(.white, in: RoundedRectangle(cornerRadius: 18))
                    }.disabled(store.isBusy || loadingPhoto)
                    Text("Where should your pet be?").font(.system(size: 17, weight: .bold, design: .rounded))
                    TextField("On my lap, beside the window…", text: $placement, axis: .vertical).lineLimit(2...4).padding(20).background(.white, in: RoundedRectangle(cornerRadius: 20))
                    if store.isBusy || loadingPhoto { HStack { ProgressView(); Text(loadingPhoto ? "Opening your photo…" : store.activity).font(.caption) } }
                    PrimaryButton(title: "Add my pet · 250 credits", symbol: "sparkles", disabled: photoData == nil || store.isBusy || loadingPhoto) {
                        guard let photoData else { return }
                        Task {
                            if let image = await store.insertPet(photo: photoData, placement: placement) { result = image; saved = false }
                        }
                    }
                    Text("Your selected photo and pet reference are sent to OpenAI to create this adventure.").font(.caption).foregroundStyle(.secondary)
                    if let result {
                        HStack(spacing: 15) {
                            ShareLink(item: Image(uiImage: result), preview: SharePreview("My Fur Baby adventure", image: Image(uiImage: result))) { Label("Share", systemImage: "square.and.arrow.up") }
                            Spacer()
                            Button { Task { await savePhoto(result) } } label: { Label(saved ? "Saved" : "Save to Photos", systemImage: saved ? "checkmark" : "arrow.down.to.line") }.disabled(saved)
                        }.font(.system(size: 14, weight: .bold)).padding(.vertical, 8)
                    }
                }
                gallery
            }.padding(.horizontal, 24).padding(.bottom, 25)
        }.foregroundStyle(FurTheme.ink)
            .sheet(item: $openedAdventure) { adventure in AdventureDetailView(adventure: adventure).furErrorAlert() }
            .onChange(of: selection) { _, value in
                Task {
                    loadingPhoto = true; defer { loadingPhoto = false }
                    do {
                        guard let value, let data = try await value.loadTransferable(type: Data.self), data.count <= 30_000_000,
                              let source = CGImageSourceCreateWithData(data as CFData, nil),
                              let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 1536, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary),
                              let jpeg = UIImage(cgImage: thumb).jpegData(compressionQuality: 0.87) else { throw FurError.message("Choose a photo under 30 MB that iOS can open.") }
                        photoData = jpeg; photo = UIImage(data: jpeg); result = nil; saved = false
                    } catch { store.errorMessage = error.localizedDescription }
                }
            }
    }
    private var gallery: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Text("Your adventure gallery").font(.system(size: 22, weight: .heavy, design: .rounded))
                Spacer()
                if !store.adventures.isEmpty { Text(store.adventures.count.formatted()).font(.caption.bold()).padding(8).background(FurTheme.lime, in: Circle()) }
            }
            Text("Every completed adventure is saved here automatically on this device.").font(.caption).foregroundStyle(.secondary)
            if store.adventures.isEmpty {
                Label("Your first memory will appear here.", systemImage: "photo.on.rectangle")
                    .font(.subheadline).foregroundStyle(.secondary).padding(22)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white, in: RoundedRectangle(cornerRadius: 22))
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 14)], spacing: 16) {
                    ForEach(store.adventures) { adventure in
                        Button { openedAdventure = adventure } label: { AdventureThumbnail(adventure: adventure) }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Adventure with \(adventure.petName.isEmpty ? "your pet" : adventure.petName), \(adventure.createdAt.formatted(date: .abbreviated, time: .omitted))")
                    }
                }
            }
        }.padding(.top, 8)
    }
    private func empty(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 15) { Image(systemName: "photo.on.rectangle.angled").font(.system(size: 35)).foregroundStyle(FurTheme.pink); Text(title).font(.system(size: 21, weight: .bold, design: .rounded)); Text(detail).font(.subheadline).foregroundStyle(.secondary) }.padding(25).frame(maxWidth: .infinity, alignment: .leading).background(FurTheme.lavender.opacity(0.5), in: RoundedRectangle(cornerRadius: 27))
    }
    private func savePhoto(_ image: UIImage) async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { store.errorMessage = "Allow access to add images to Photos, or use Share to save your adventure elsewhere."; return }
        do { try await PHPhotoLibrary.shared().performChanges { PHAssetChangeRequest.creationRequestForAsset(from: image) }; saved = true }
        catch { store.errorMessage = error.localizedDescription }
    }
}

private struct AdventureThumbnail: View {
    let adventure: AdventureMemory
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Color.clear.aspectRatio(1, contentMode: .fit)
                .overlay {
                    if let image = SharedStorage.image(adventure.thumbnail) {
                        Image(uiImage: image).resizable().scaledToFill()
                    } else {
                        Image(systemName: "photo").font(.largeTitle).foregroundStyle(.secondary)
                    }
                }.clipped().background(FurTheme.lavender.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 18))
            Text(adventure.petName.isEmpty ? "Your Fur Baby" : adventure.petName).font(.system(size: 14, weight: .bold, design: .rounded)).lineLimit(1)
            Text(adventure.createdAt, format: .dateTime.month(.abbreviated).day().year()).font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct AdventureDetailView: View {
    let adventure: AdventureMemory
    @Environment(FurStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var saved = false
    @State private var saving = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let image = SharedStorage.image(adventure.artwork) {
                        Image(uiImage: image).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 24))
                        Text(adventure.createdAt, format: .dateTime.month(.wide).day().year()).font(.subheadline).foregroundStyle(.secondary)
                        if !adventure.placement.isEmpty { Text(adventure.placement).font(.subheadline) }
                        HStack {
                            ShareLink(item: Image(uiImage: image), preview: SharePreview("My Fur Baby adventure", image: Image(uiImage: image))) { Label("Share", systemImage: "square.and.arrow.up") }
                            Spacer()
                            Button {
                                Task { await savePhoto(image) }
                            } label: {
                                Label(saved ? "Saved" : "Save to Photos", systemImage: saved ? "checkmark" : "arrow.down.to.line")
                            }.disabled(saved || saving)
                        }.font(.system(size: 14, weight: .bold))
                    } else {
                        ContentUnavailableView("Photo unavailable", systemImage: "photo", description: Text("This adventure’s image could not be opened."))
                    }
                }.padding(24)
            }.background(FurTheme.cream).foregroundStyle(FurTheme.ink)
                .navigationTitle(adventure.petName.isEmpty ? "Your adventure" : "Adventure with \(adventure.petName)")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
    }
    private func savePhoto(_ image: UIImage) async {
        saving = true; defer { saving = false }
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            store.errorMessage = "Allow access to add images to Photos, or use Share to save your adventure elsewhere."; return
        }
        do { try await PHPhotoLibrary.shared().performChanges { PHAssetChangeRequest.creationRequestForAsset(from: image) }; saved = true }
        catch { store.errorMessage = error.localizedDescription }
    }
}
