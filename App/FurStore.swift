import SwiftUI
import Observation
import WidgetKit
import StoreKit

@Observable @MainActor
final class FurStore {
    var pets: [FurPet] = []
    private(set) var adventures: [AdventureMemory] = []
    var selectedPetID: String?
    var wallet = WalletSnapshot.free
    var behavior: PetBehavior = .auto
    private(set) var widgetBackground = WidgetBackground()
    private(set) var customWidgetBackgrounds: [CustomWidgetBackground] = []
    private(set) var widgetRightSide: WidgetRightSide = .petInfo
    private(set) var dailyQuote: DailyQuote?
    var isBusy = false
    private(set) var isGeneratingWidgetBackground = false
    var activity = ""
    private(set) var animationProgress: AnimationPreparationProgress?
    var isReconnecting = false
    var creationRecoveryMessage: String?
    var errorMessage: String?
    var showPaywall = false
    var products: [Product] = []
    var recoveredPhoto: UIImage?
    var hasPendingImage = false
    var isSampleMode: Bool
    var serviceURL: String
    var onboarding = OnboardingProgress() {
        didSet { saveOnboarding() }
    }
    @ObservationIgnored private var service: FurService?
    @ObservationIgnored private var transactionTask: Task<Void, Never>?
    @ObservationIgnored private let local: UserDefaults

    var selectedPet: FurPet? { pets.first { $0.id == selectedPetID } ?? pets.first }
    var isPro: Bool { wallet.isPro && (wallet.expiresAt.map { $0 > Date() } ?? false) }

    init(defaults: UserDefaults = .standard, sessionReader: (String) -> ServiceSession? = SecureSession.read) {
        #if DEBUG
        if defaults === UserDefaults.standard, let suite = ProcessInfo.processInfo.environment["FURBABY_STORAGE_SUITE"], let previewDefaults = UserDefaults(suiteName: suite) { local = previewDefaults }
        else { local = defaults }
        #else
        local = defaults
        #endif
        let defaultServiceURL = "https://myfurbaby-api-production.up.railway.app"
        let savedURL = local.string(forKey: "serviceURL").flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        serviceURL = ProcessInfo.processInfo.environment["FURBABY_SERVICE_URL"] ?? savedURL ?? defaultServiceURL
        #if DEBUG
        isSampleMode = ProcessInfo.processInfo.environment["FURBABY_SAMPLE_MODE"].map { $0 != "false" } ?? local.object(forKey: "sampleMode") as? Bool ?? false
        #else
        isSampleMode = false
        #endif
        let key = isSampleMode ? "samplePets" : "livePets"
        if let data = local.data(forKey: key), let values = try? JSONDecoder().decode([FurPet].self, from: data) { pets = values }
        selectedPetID = local.string(forKey: key + "Selected")
        adventures = loadAdventures()
        if let data = local.data(forKey: "widgetBackground"), let background = try? JSONDecoder().decode(WidgetBackground.self, from: data) { widgetBackground = background }
        customWidgetBackgrounds = local.data(forKey: "customWidgetBackgrounds").flatMap { try? JSONDecoder().decode([CustomWidgetBackground].self, from: $0) } ?? []
        widgetRightSide = WidgetRightSide(rawValue: local.string(forKey: "widgetRightSide") ?? "") ?? .petInfo
        dailyQuote = DailyQuoteService.shared.cachedQuote()
        onboarding = local.data(forKey: onboardingKey).flatMap { try? JSONDecoder().decode(OnboardingProgress.self, from: $0) }
            ?? OnboardingProgress(stage: pets.isEmpty ? .welcome : .complete)
        if onboarding.stage == .creating, let pet = selectedPet {
            onboarding.petID = pet.id; onboarding.stage = .reveal
        }
        if let data = local.data(forKey: isSampleMode ? "sampleWallet" : "liveWallet"), let value = try? JSONDecoder().decode(WalletSnapshot.self, from: data) { wallet = value }
        // Inspect the existing identity before start() can create a first-time anonymous account.
        // Keychain survives reinstalls even when local pets/onboarding preferences do not.
        if !isSampleMode, let url = URL(string: serviceURL), sessionReader(url.absoluteString) != nil {
            onboarding.stage = .complete
        }
        behavior = (PetBehavior(rawValue: local.string(forKey: "behavior") ?? "auto") ?? .auto).widgetBehavior
        // Motion is automatic now, including for users who previously switched it off.
        local.removeObject(forKey: "experimentalMotion")
        refreshSampleAllowance()
        syncWidget()
    }

    func start() async {
        if !isSampleMode && !serviceURL.isEmpty { await connect() }
        await refreshDailyQuote()
        do { products = try await Product.products(for: ProductIDs.all) } catch { /* Configuration may not exist in an unsigned development build. */ }
        transactionTask?.cancel()
        transactionTask = Task { [weak self] in
            for await result in StoreKit.Transaction.updates {
                guard let self, !self.isSampleMode else { continue }
                do { try await self.apply(result) } catch { self.errorMessage = error.localizedDescription }
            }
        }
    }

    func connect() async {
        guard let url = URL(string: serviceURL), ["https", "http"].contains(url.scheme), url.scheme == "https" || ["localhost", "127.0.0.1"].contains(url.host ?? "") else {
            errorMessage = "Enter an HTTPS service URL, or http://localhost:8787 for Simulator development."; return
        }
        let candidate = FurService(url: url)
        do { wallet = try await candidate.connect(); service = candidate; hasPendingImage = candidate.pendingGeneration != nil; persist() } catch { errorMessage = error.localizedDescription }
    }

    func generate(recipe: PetRecipe, name: String = "", onboardingCreation: Bool = false) async -> FurPet? {
        guard recipe.isValid, !isBusy else { return nil }
        if !isSampleMode && service == nil { await connect() }
        if onboardingCreation && hasPendingImage {
            await resumePendingImage(); return onboarding.stage == .reveal ? selectedPet : nil
        }
        guard !onboardingCreation || wallet.trialCredits >= 250 else {
            errorMessage = "This account’s free Fur Baby has already been created. Recover your saved baby to continue."; return nil
        }
        guard wallet.total >= 250 else {
            if onboardingCreation { errorMessage = "Your free creation may already be ready. Try recovering your Fur Baby." }
            else { showPaywall = true }
            return nil
        }
        isBusy = true; activity = "Dreaming up your Fur Baby…"; creationRecoveryMessage = nil; errorMessage = nil
        defer { isBusy = false; isReconnecting = false }
        do {
            let pet: FurPet
            if isSampleMode {
                #if DEBUG
                let previewDelay = ProcessInfo.processInfo.environment["FURBABY_SAMPLE_GENERATION_SECONDS"].flatMap(Double.init)
                try await Task.sleep(for: .seconds(onboardingCreation ? min(60, max(1, previewDelay ?? 3)) : 1))
                spendSampleCredits()
                pet = FurPet(id: UUID().uuidString, name: name, recipe: recipe, createdAt: Date(), isSample: true)
                #else
                throw FurError.message("Sample generation is only available in development builds.")
                #endif
            } else {
                guard let service else { throw FurError.message("Connect your image service in Settings to create your pet.") }
                let result = try await service.generate(recipe: recipe, name: name, onboarding: onboardingCreation) { self.isReconnecting = $0 }
                let id = result.petID ?? UUID().uuidString
                guard let data = Data(base64Encoded: result.imageBase64) else { throw FurError.message("The image could not be read.") }
                let filename = id + ".png"; try SharedStorage.saveImage(data, named: filename)
                wallet = result.wallet
                pet = FurPet(id: id, name: name, recipe: recipe, artwork: filename, createdAt: Date(), isSample: false)
            }
            pets.insert(pet, at: 0); selectedPetID = pet.id; persist()
            if onboardingCreation { onboarding.petID = pet.id; onboarding.stage = .reveal }
            service?.pendingGeneration = nil; hasPendingImage = false
            return pet
        } catch {
            recordGenerationError(error)
            if !hasPendingImage, let service, let value = try? await service.wallet() { wallet = value; persist() }
            return nil
        }
    }

    func namePet(id: String, name: String) {
        guard let index = pets.firstIndex(where: { $0.id == id }) else { return }
        pets[index].name = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40)); persist()
    }
    func select(_ pet: FurPet) { selectedPetID = pet.id; persist() }
    func setBehavior(_ value: PetBehavior) { behavior = value.widgetBehavior; local.set(behavior.rawValue, forKey: "behavior"); syncWidget() }
    func setWidgetBackground(_ value: WidgetBackground) {
        widgetBackground = value
        if let data = try? JSONEncoder().encode(value) { local.set(data, forKey: "widgetBackground") }
        syncWidget()
    }

    func setWidgetRightSide(_ value: WidgetRightSide) {
        widgetRightSide = value
        local.set(value.rawValue, forKey: "widgetRightSide")
        syncWidget()
    }

    func refreshDailyQuote() async {
        guard isPro, widgetRightSide == .dailyQuote else { return }
        dailyQuote = await DailyQuoteService.shared.quote()
        syncWidget()
    }

    @discardableResult
    func saveWidgetBackground(_ data: Data, id: String, prompt: String) throws -> CustomWidgetBackground {
        if let existing = customWidgetBackgrounds.first(where: { $0.id == id }) {
            setWidgetBackground(existing.background)
            return existing
        }
        let value = CustomWidgetBackground(id: id, prompt: prompt, imageFilename: "widget-background-\(id).png")
        try SharedStorage.saveWidgetBackgroundImage(data, named: value.imageFilename)
        let updated = [value] + customWidgetBackgrounds
        local.set(try JSONEncoder().encode(updated), forKey: "customWidgetBackgrounds")
        customWidgetBackgrounds = updated
        setWidgetBackground(value.background)
        return value
    }

    func createWidgetBackground(prompt: String) async -> Bool {
        let description = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isBusy, !description.isEmpty, prompt.utf16.count <= 500 else { return false }
        guard isPro else { showPaywall = true; return false }
        if !isSampleMode && service == nil { await connect() }
        guard wallet.total >= FurTokenCost.background || hasPendingImage else { showPaywall = true; return false }
        isBusy = true; isGeneratingWidgetBackground = true; activity = "Dreaming up your widget background…"; errorMessage = nil
        defer { isBusy = false; isGeneratingWidgetBackground = false; isReconnecting = false }
        do {
            guard !isSampleMode else { throw FurError.message("Custom backgrounds need the connected image service. Sample mode does not spend tokens.") }
            guard let service else { throw FurError.message("Connect to the service to create your background.") }
            let result = try await service.generate(recipe: .sample, name: "", backgroundPrompt: description) { self.isReconnecting = $0 }
            wallet = result.wallet; persist()
            guard let data = Data(base64Encoded: result.imageBase64), let pending = service.pendingGeneration else { throw FurError.message("The completed background could not be opened.") }
            try saveWidgetBackground(data, id: pending.key, prompt: description)
            service.pendingGeneration = nil; hasPendingImage = false
            return true
        } catch {
            recordGenerationError(error)
            if let service, let value = try? await service.wallet() { wallet = value; persist() }
            return false
        }
    }

    /// Save before clearing a generation's recovery receipt. Its key prevents duplicate gallery entries.
    @discardableResult
    func saveAdventure(_ data: Data, id: String = UUID().uuidString, petID: String?, petName: String, placement: String) throws -> AdventureMemory {
        if let existing = adventures.first(where: { $0.id == id }) { return existing }
        let memory = AdventureMemory(id: id, petID: petID, petName: petName, placement: placement,
            artwork: "adventure-\(id).png", thumbnail: "adventure-\(id)-thumb.jpg", createdAt: Date())
        try SharedStorage.saveAdventureImages(data, artwork: memory.artwork, thumbnail: memory.thumbnail)
        let updated = [memory] + adventures
        let encoded = try JSONEncoder().encode(updated)
        local.set(encoded, forKey: adventuresKey)
        adventures = updated
        return memory
    }

    func preparePoses() async {
        guard isPro, let pet = selectedPet, !isBusy else { return }
        if pet.isSample { syncWidget(); return }
        let kinds = ["idle", "playful", "sleep"].filter { pet.animation(kind: $0) == nil }
        guard !kinds.isEmpty else { return }
        animationProgress = AnimationPreparationProgress(petID: pet.id, animations: kinds.map { .waiting(kind: $0) })
        isBusy = true; errorMessage = nil
        defer { isBusy = false; animationProgress?.isRunning = false }
        do {
            guard let service else { throw FurError.message("Connect to the service to prepare your pet's poses.") }
            for kind in kinds {
                guard let index = pets.firstIndex(where: { $0.id == pet.id }) else { return }
                let saved = pets[index].animation(kind: kind)
                if saved != nil { continue }
                let result = try await service.animation(petID: pet.id, kind: kind) { update in
                    self.updateAnimationProgress(update)
                    self.activity = "\(update.title): \(update.stageTitle)…"
                }
                wallet = result.wallet
                guard let currentIndex = pets.firstIndex(where: { $0.id == pet.id }) else { persist(); return }
                let sequence = try SharedStorage.saveAnimation(result.animation, petID: pet.id)
                if kind == "idle" { pets[currentIndex].idleAnimation = sequence }
                else if kind == "sleep" { pets[currentIndex].sleepingAnimation = sequence }
                else { pets[currentIndex].playfulAnimation = sequence }
                persist() // Preserve each completed animation if a later provider call fails.
                if var complete = animationProgress?.animations.first(where: { $0.kind == kind }) {
                    complete.stage = "completed"; complete.completedStages = complete.totalStages
                    updateAnimationProgress(complete)
                }
            }
        } catch { animationProgress?.failed = true; errorMessage = error.localizedDescription; if let service, let value = try? await service.wallet() { wallet = value; persist() } }
    }

    private func updateAnimationProgress(_ update: AnimationPipelineProgress) {
        guard let index = animationProgress?.animations.firstIndex(where: { $0.kind == update.kind }) else { return }
        animationProgress?.animations[index] = update
    }

    func insertPet(photo: Data, placement: String) async -> UIImage? {
        guard isPro else { showPaywall = true; return nil }
        guard wallet.total >= 250 else { showPaywall = true; return nil }
        guard let pet = selectedPet, !isBusy else { return nil }
        isBusy = true; activity = "Taking \(pet.name.isEmpty ? "your pet" : pet.name) on an adventure…"; defer { isBusy = false }
        do {
            guard !isSampleMode else { throw FurError.message("Photo insertion needs the connected GPT Image 2 service. Sample mode does not edit your photo or spend credits.") }
            guard let service else { throw FurError.message("Connect your image service in Settings first.") }
            let result = try await service.generate(recipe: pet.recipe, name: pet.name, photo: photo, pet: pet, placement: placement)
            guard let data = Data(base64Encoded: result.imageBase64), let image = UIImage(data: data) else { throw FurError.message("The completed photo could not be read.") }
            wallet = result.wallet; persist()
            try saveAdventure(data, id: service.pendingGeneration?.key ?? UUID().uuidString, petID: pet.id, petName: pet.name, placement: placement)
            service.pendingGeneration = nil; hasPendingImage = false; return image
        } catch { errorMessage = error.localizedDescription; hasPendingImage = service?.pendingGeneration != nil; if let service, let value = try? await service.wallet() { wallet = value; persist() }; return nil }
    }

    func resumePendingImage() async {
        guard !isBusy else { return }
        if service == nil { await connect() }
        guard let service else { return }
        isBusy = true; activity = "Recovering your image…"; creationRecoveryMessage = nil; errorMessage = nil
        defer { isBusy = false; isReconnecting = false }
        do {
            let recovered = try await service.resume { self.isReconnecting = $0 }, result = recovered.result
            guard let data = Data(base64Encoded: result.imageBase64), let image = UIImage(data: data) else { throw FurError.message("The completed image could not be opened.") }
            wallet = result.wallet; persist()
            if let prompt = recovered.pending.backgroundPrompt {
                try saveWidgetBackground(data, id: recovered.pending.key, prompt: prompt)
            } else if recovered.pending.isPhoto {
                try saveAdventure(data, id: recovered.pending.key, petID: recovered.pending.petID,
                    petName: recovered.pending.petName ?? "Your Fur Baby", placement: recovered.pending.placement ?? "")
                recoveredPhoto = image
            }
            else {
                let id = result.petID ?? UUID().uuidString, filename = id + ".png"
                try SharedStorage.saveImage(data, named: filename)
                if !pets.contains(where: { $0.id == id }) {
                    let name = recovered.pending.petName ?? (onboarding.stage == .creating ? onboarding.name : "New arrival")
                    pets.insert(FurPet(id: id, name: name, recipe: recovered.pending.recipe, artwork: filename, createdAt: Date(), isSample: false), at: 0)
                }
                selectedPetID = id
                if onboarding.stage == .creating { onboarding.petID = id; onboarding.stage = .reveal }
            }
            wallet = result.wallet; persist(); service.pendingGeneration = nil; hasPendingImage = false
        } catch { recordGenerationError(error) }
    }

    private func recordGenerationError(_ error: Error) {
        hasPendingImage = service?.pendingGeneration != nil
        if onboarding.stage == .creating && hasPendingImage,
           (error as? FurError)?.canRecoverGeneration == true || error is CancellationError {
            creationRecoveryMessage = error is CancellationError
                ? "Your baby’s creation is saved. We’ll pick up where we left off."
                : error.localizedDescription
        } else { errorMessage = error.localizedDescription }
    }

    func buy(_ id: String) async {
        guard !isBusy else { return }
        isBusy = true; activity = "Opening the App Store…"; defer { isBusy = false }
        do {
            guard !isSampleMode else { throw FurError.message("Use “Try Pro in sample mode” to explore without a purchase.") }
            guard let service, let identity = service.session, let accountToken = UUID(uuidString: identity.accountID) else { throw FurError.message("Connect to your service before purchasing.") }
            guard let product = products.first(where: { $0.id == id }) else { throw FurError.message("This product is not available yet. Configure the products in App Store Connect.") }
            switch try await product.purchase(options: [.appAccountToken(accountToken)]) {
            case .success(let result): try await apply(result); showPaywall = false
            case .pending: errorMessage = "Your purchase is waiting for approval."
            case .userCancelled: break
            @unknown default: break
            }
        } catch { errorMessage = error.localizedDescription }
    }
    private func apply(_ result: VerificationResult<StoreKit.Transaction>) async throws {
        guard case .verified(let transaction) = result else { throw FurError.message("The purchase could not be verified.") }
        guard let service else { throw FurError.message("Your purchase is safe. Reconnect to the service to finish activation.") }
        wallet = try await service.purchase(jws: result.jwsRepresentation)
        persist(); await transaction.finish()
    }
    func restore() async {
        guard !isSampleMode else { errorMessage = "Sample mode has no App Store purchases to restore."; return }
        do {
            try await AppStore.sync()
            for await result in StoreKit.Transaction.currentEntitlements { try await apply(result) }
            if let service { wallet = try await service.wallet() }
            persist()
        } catch { errorMessage = error.localizedDescription }
    }

    func demoPro(yearly: Bool = false) {
        #if DEBUG
        guard isSampleMode else { return }
        if !isPro {
            let now = Date(); local.set(now, forKey: "sampleStartedAt")
            wallet.isPro = true; wallet.subscriptionCredits = 5000; wallet.trialCredits = 0
            wallet.expiresAt = Calendar.current.date(byAdding: yearly ? .year : .month, value: 1, to: now)
            wallet.resetsAt = Calendar.current.date(byAdding: .month, value: 1, to: now)
        }
        persist(); showPaywall = false
        #endif
    }
    func demoPack() {
        #if DEBUG
        guard isSampleMode else { return }; wallet.purchasedCredits += 5000; persist()
        #endif
    }
    func changeMode(sample: Bool, url: String) async {
        persist(); serviceURL = url.trimmingCharacters(in: .whitespacesAndNewlines); local.set(serviceURL, forKey: "serviceURL")
        #if DEBUG
        isSampleMode = sample; local.set(sample, forKey: "sampleMode")
        #endif
        service = nil
        let key = isSampleMode ? "samplePets" : "livePets"
        pets = (local.data(forKey: key).flatMap { try? JSONDecoder().decode([FurPet].self, from: $0) }) ?? []
        selectedPetID = local.string(forKey: key + "Selected")
        adventures = loadAdventures(); recoveredPhoto = nil
        onboarding = local.data(forKey: onboardingKey).flatMap { try? JSONDecoder().decode(OnboardingProgress.self, from: $0) }
            ?? OnboardingProgress(stage: pets.isEmpty ? .welcome : .complete)
        wallet = (local.data(forKey: isSampleMode ? "sampleWallet" : "liveWallet").flatMap { try? JSONDecoder().decode(WalletSnapshot.self, from: $0) }) ?? .free
        if !isSampleMode { await connect() }
        persist()
    }

    func refresh() async {
        guard !isBusy else { return }
        if isSampleMode { refreshSampleAllowance() }
        else if let service { do { wallet = try await service.wallet() } catch { errorMessage = error.localizedDescription } }
        persist()
        await refreshDailyQuote()
    }
    private func refreshSampleAllowance() {
        guard isSampleMode else { return }
        if wallet.expiresAt.map({ $0 <= Date() }) == true { wallet.isPro = false; wallet.subscriptionCredits = 0 }
        if wallet.isPro, let reset = wallet.resetsAt, reset <= Date() {
            wallet.subscriptionCredits = 5000
            var next = reset
            while next <= Date() { next = Calendar.current.date(byAdding: .month, value: 1, to: next)! }
            wallet.resetsAt = next
        }
    }
    private func spendSampleCredits() {
        var remaining = 250
        let subscription = wallet.isPro ? min(remaining, wallet.subscriptionCredits) : 0
        wallet.subscriptionCredits -= subscription; remaining -= subscription
        let trial = wallet.isPro ? 0 : min(remaining, wallet.trialCredits)
        wallet.trialCredits -= trial; remaining -= trial
        wallet.purchasedCredits -= remaining
    }
    private var onboardingKey: String { isSampleMode ? "sampleOnboarding" : "liveOnboarding" }
    private var adventuresKey: String { isSampleMode ? "sampleAdventures" : "liveAdventures" }
    private func loadAdventures() -> [AdventureMemory] {
        local.data(forKey: adventuresKey).flatMap { try? JSONDecoder().decode([AdventureMemory].self, from: $0) } ?? []
    }
    private func saveOnboarding() {
        if let data = try? JSONEncoder().encode(onboarding) { local.set(data, forKey: onboardingKey) }
    }
    private func persist() {
        let key = isSampleMode ? "samplePets" : "livePets"
        if let data = try? JSONEncoder().encode(pets) { local.set(data, forKey: key) }
        local.set(selectedPetID, forKey: key + "Selected")
        if let data = try? JSONEncoder().encode(wallet) { local.set(data, forKey: isSampleMode ? "sampleWallet" : "liveWallet") }
        syncWidget()
    }
    private func syncWidget() {
        var frames: WidgetMotionFrames?
        if isPro, let pet = selectedPet {
            // The widget uses its still-pose fallback when saved frames aren't ready.
            frames = try? WidgetMotionFrameStorage.prepare(pet: pet)
        }
        SharedStorage.save(snapshot: WidgetSnapshot(pet: selectedPet, isPro: isPro, proExpiresAt: wallet.expiresAt, behavior: behavior.widgetBehavior, experimentalMotion: true, motionFrames: frames, background: widgetBackground, rightSide: widgetRightSide, dailyQuote: DailyQuoteService.shared.cachedQuote() ?? dailyQuote))
        WidgetCenter.shared.reloadAllTimelines()
    }
}
