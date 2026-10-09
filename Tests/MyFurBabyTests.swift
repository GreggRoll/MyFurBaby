import XCTest
import UIKit
import SwiftUI
@testable import MyFurBaby

final class MyFurBabyTests: XCTestCase {
    @MainActor func testCustomWidgetBackgroundsPersistDeduplicateAndPublishBoundedArtwork() throws {
        let suite = "custom-background-test-\(UUID().uuidString)", defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let previousSnapshot = SharedStorage.load()
        defer { defaults.removePersistentDomain(forName: suite); SharedStorage.save(snapshot: previousSnapshot) }
        let store = FurStore(defaults: defaults, sessionReader: { _ in nil })
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1024, height: 1024))
        let data = try XCTUnwrap(renderer.image { context in
            UIColor.systemPurple.setFill(); context.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
        }.pngData())
        let id = UUID().uuidString
        let saved = try store.saveWidgetBackground(data, id: id, prompt: "Cloud castle")
        defer { try? FileManager.default.removeItem(at: SharedStorage.directory.appendingPathComponent(saved.imageFilename)) }
        let image = try XCTUnwrap(SharedStorage.image(saved.imageFilename)?.cgImage)
        XCTAssertLessThanOrEqual(max(image.width, image.height), 640)
        XCTAssertEqual(SharedStorage.load().resolvedBackground, saved.background)
        XCTAssertTrue(saved.background.usesLightText)
        XCTAssertEqual(try store.saveWidgetBackground(data, id: id, prompt: "Cloud castle"), saved)
        XCTAssertEqual(store.customWidgetBackgrounds.count, 1)
        store.setWidgetBackground(WidgetBackground(kind: .clear))
        let relaunched = FurStore(defaults: defaults, sessionReader: { _ in nil })
        XCTAssertEqual(relaunched.customWidgetBackgrounds, [saved])
        relaunched.setWidgetBackground(saved.background)
        XCTAssertEqual(SharedStorage.load().resolvedBackground, saved.background)
        XCTAssertThrowsError(try store.saveWidgetBackground(Data("invalid".utf8), id: UUID().uuidString, prompt: "Bad image"))
        XCTAssertEqual(store.customWidgetBackgrounds.count, 1)
    }

    @MainActor func testMediumWidgetChoicesPersistAndOlderSnapshotsDefaultToPetInfo() throws {
        let suite = "right-side-test-\(UUID().uuidString)", defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let previousSnapshot = SharedStorage.load()
        defer { defaults.removePersistentDomain(forName: suite); SharedStorage.save(snapshot: previousSnapshot) }
        let store = FurStore(defaults: defaults, sessionReader: { _ in nil })
        for selection in WidgetRightSide.allCases {
            store.setWidgetRightSide(selection)
            XCTAssertEqual(SharedStorage.load().resolvedRightSide, selection)
            XCTAssertEqual(FurStore(defaults: defaults, sessionReader: { _ in nil }).widgetRightSide, selection)
        }
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(WidgetSnapshot())) as? [String: Any])
        json.removeValue(forKey: "rightSide")
        let legacy = try JSONDecoder().decode(WidgetSnapshot.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(legacy.resolvedRightSide, .petInfo)
        let oldBackground = Data(#"{"kind":"cozyLivingRoom","red":0.86,"green":0.82,"blue":0.97}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(WidgetBackground.self, from: oldBackground).kind, .cozyLivingRoom)
    }

    func testDailyQuoteExpiresAtLocalMidnight() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let morning = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 9, hour: 8)))
        let evening = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 9, hour: 23)))
        let nextDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 10)))
        let quote = DailyQuote(id: "one", content: "A test quote.", author: "Test author", fetchedAt: morning)
        XCTAssertTrue(quote.isCurrent(at: evening, calendar: calendar))
        XCTAssertFalse(quote.isCurrent(at: nextDay, calendar: calendar))
    }

    @MainActor func testWidgetMotionIsAutomaticForNewAndPreviouslyDisabledUsers() throws {
        let previousSnapshot = SharedStorage.load()
        var files = Set<String>()
        defer {
            SharedStorage.save(snapshot: previousSnapshot)
            for file in files { try? FileManager.default.removeItem(at: SharedStorage.directory.appendingPathComponent(file)) }
        }
        var pet = FurPet.sample
        pet.recipe.personality = UUID().uuidString
        for oldPreference in [nil, false, true] as [Bool?] {
            let suite = "automatic-motion-test-\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            defaults.set(true, forKey: "sampleMode")
            if let oldPreference { defaults.set(oldPreference, forKey: "experimentalMotion") }
            defaults.set(try JSONEncoder().encode([pet]), forKey: "samplePets")
            let wallet = WalletSnapshot(isPro: true, subscriptionCredits: 5000, purchasedCredits: 0,
                trialCredits: 0, expiresAt: Date().addingTimeInterval(3600))
            defaults.set(try JSONEncoder().encode(wallet), forKey: "sampleWallet")
            let store = FurStore(defaults: defaults)
            XCTAssertTrue(store.isPro)
            XCTAssertNil(defaults.object(forKey: "experimentalMotion"))
            let snapshot = SharedStorage.load()
            XCTAssertTrue(snapshot.experimentalMotion)
            let frames = try XCTUnwrap(snapshot.motionFrames)
            XCTAssertEqual(frames.images(sleeping: false)?.count, 90)
            XCTAssertEqual(frames.images(sleeping: true)?.count, 60)
            files.formUnion(frames.playful + frames.sleepy + (frames.running ?? []))
        }
    }

    @MainActor func testClearWidgetTextContrastsWithLightAndDarkSystemSurfaces() throws {
        for scheme in [ColorScheme.light, .dark] {
            let renderer = ImageRenderer(content: Rectangle().fill(WidgetBackground().foreground)
                .frame(width: 8, height: 8).environment(\.colorScheme, scheme))
            let source = try XCTUnwrap(renderer.uiImage?.cgImage)
            var pixel = [UInt8](repeating: 0, count: 4)
            try pixel.withUnsafeMutableBytes { buffer in
                let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: 1, height: 1,
                    bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
                context.draw(source, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            }
            let brightness = (Double(pixel[0]) + Double(pixel[1]) + Double(pixel[2])) / (3 * 255)
            if scheme == .dark { XCTAssertGreaterThan(brightness, 0.8) }
            else { XCTAssertLessThan(brightness, 0.2) }
        }
    }
    @MainActor func testSavedAccountSkipsOnboardingWithoutLocalPetsOrProgress() throws {
        let suite = "launch-account-test-\(UUID().uuidString)", defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: "sampleMode")
        defaults.set("https://launch-account-tests.invalid", forKey: "serviceURL")
        var checkedURL: String?
        let store = FurStore(defaults: defaults, sessionReader: { url in
            checkedURL = url
            return ServiceSession(token: "saved-token", accountID: "existing-account")
        })
        XCTAssertEqual(checkedURL, "https://launch-account-tests.invalid")
        XCTAssertTrue(store.pets.isEmpty)
        XCTAssertEqual(store.onboarding.stage, .complete)
        let relaunched = FurStore(defaults: defaults, sessionReader: { _ in nil })
        XCTAssertEqual(relaunched.onboarding.stage, .complete)
    }

    @MainActor func testSavedAccountOverridesStaleOnboardingAndKeepsAnswers() throws {
        let suite = "launch-account-test-\(UUID().uuidString)", defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: "sampleMode")
        let progress = OnboardingProgress(stage: .creating, question: 4, recipe: .sample, name: "Luna")
        defaults.set(try JSONEncoder().encode(progress), forKey: "liveOnboarding")
        let store = FurStore(defaults: defaults, sessionReader: { _ in ServiceSession(token: "saved-token", accountID: "existing-account") })
        XCTAssertEqual(store.onboarding.stage, .complete)
        XCTAssertEqual(store.onboarding.name, "Luna")
        XCTAssertEqual(store.onboarding.recipe, .sample)
    }

    @MainActor func testFirstTimeUserShowsOnboardingAndChecksOnlyTheConfiguredService() throws {
        let suite = "launch-account-test-\(UUID().uuidString)", defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: "sampleMode")
        defaults.set("https://new-service-tests.invalid/", forKey: "serviceURL")
        var checkedURLs: [String] = []
        let store = FurStore(defaults: defaults, sessionReader: { url in checkedURLs.append(url); return nil })
        XCTAssertEqual(store.onboarding.stage, .welcome)
        XCTAssertEqual(checkedURLs, ["https://new-service-tests.invalid/"])
    }

    @MainActor func testSampleOnboardingIgnoresSavedConnectedAccounts() throws {
        let suite = "launch-account-test-\(UUID().uuidString)", defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "sampleMode")
        let store = FurStore(defaults: defaults, sessionReader: { _ in
            XCTFail("Sample mode must not check live accounts")
            return ServiceSession(token: "saved-token", accountID: "existing-account")
        })
        XCTAssertEqual(store.onboarding.stage, .welcome)
    }
    @MainActor func testAdventureGalleryPersistsImagesAndDoesNotDuplicateRecoveredJobs() throws {
        let suite = "adventure-test-\(UUID().uuidString)", defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = FurStore(defaults: defaults)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 900, height: 700))
        let data = try XCTUnwrap(renderer.image { context in
            UIColor.systemPink.setFill(); context.fill(CGRect(x: 0, y: 0, width: 900, height: 700))
        }.pngData())
        let id = UUID().uuidString
        let memory = try store.saveAdventure(data, id: id, petID: "pet-one", petName: "Luna", placement: "Beside me")
        defer {
            for filename in [memory.artwork, memory.thumbnail] { try? FileManager.default.removeItem(at: SharedStorage.directory.appendingPathComponent(filename)) }
        }
        XCTAssertEqual(try Data(contentsOf: SharedStorage.directory.appendingPathComponent(memory.artwork)), data)
        let thumbnail = try XCTUnwrap(SharedStorage.image(memory.thumbnail)?.cgImage)
        XCTAssertLessThanOrEqual(max(thumbnail.width, thumbnail.height), 480)
        XCTAssertEqual(try store.saveAdventure(data, id: id, petID: nil, petName: "", placement: ""), memory)
        let relaunched = FurStore(defaults: defaults)
        XCTAssertEqual(relaunched.adventures, [memory])
        XCTAssertFalse(relaunched.isPro)
        XCTAssertEqual(relaunched.adventures.first?.petID, "pet-one")
        XCTAssertEqual(relaunched.adventures.first?.placement, "Beside me")
        XCTAssertThrowsError(try store.saveAdventure(Data("invalid".utf8), petID: nil, petName: "", placement: ""))
        XCTAssertEqual(store.adventures.count, 1)
    }

    @MainActor func testWidgetBackgroundPersistsPickedColorAndPublishesToWidget() throws {
        let suite = "background-test-\(UUID().uuidString)", defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = FurStore(defaults: defaults)
        var background = WidgetBackground(kind: .solidColor, red: 0.1, green: 0.2, blue: 0.3)
        store.setWidgetBackground(background)
        XCTAssertEqual(SharedStorage.load().resolvedBackground, background)
        XCTAssertTrue(background.usesLightText)
        background.kind = .cozyLivingRoom; store.setWidgetBackground(background)
        XCTAssertFalse(background.usesLightText)
        let relaunched = FurStore(defaults: defaults)
        XCTAssertEqual(relaunched.widgetBackground, background)
        XCTAssertEqual(relaunched.widgetBackground.red, 0.1)
        XCTAssertEqual(SharedStorage.load().resolvedBackground.kind, .cozyLivingRoom)
        for kind in [WidgetBackgroundKind.cozyLivingRoom, .cyberpunkBedroom] {
            let name = try XCTUnwrap(kind.assetName)
            XCTAssertNotNil(UIImage(named: name))
            let image = try XCTUnwrap(WidgetBackgroundArtwork.image(named: name)?.cgImage)
            XCTAssertLessThanOrEqual(image.width, 640)
            XCTAssertLessThanOrEqual(image.height, 640)
        }
    }

    func testOldWidgetSnapshotDecodesWithoutBackground() throws {
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(WidgetSnapshot(pet: .sample, behavior: .sleepy))) as? [String: Any])
        json.removeValue(forKey: "background")
        let snapshot = try JSONDecoder().decode(WidgetSnapshot.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(snapshot.pet?.id, FurPet.sample.id)
        XCTAssertEqual(snapshot.behavior, .sleepy)
        XCTAssertEqual(snapshot.resolvedBackground.kind, .clear)
    }

    @MainActor func testStoreSavesOnboardingAnswersAcrossLaunches() throws {
        let suite = "onboarding-test-\(UUID().uuidString)", defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = FurStore(defaults: defaults, sessionReader: { _ in nil })
        XCTAssertEqual(store.onboarding.stage, .welcome)
        store.onboarding = OnboardingProgress(stage: .questions, question: 2,
            recipe: PetRecipe(animal: "dragon", color: "pink", personality: "Sweet", gender: .girl), name: "Luna")
        let resumed = FurStore(defaults: defaults, sessionReader: { _ in nil })
        XCTAssertEqual(resumed.onboarding, store.onboarding)
        XCTAssertEqual(resumed.wallet.trialCredits, 250)
    }
    @MainActor func testExistingOwnersSkipOnboardingAndSavedCreationResumesAtReveal() throws {
        let suite = "onboarding-test-\(UUID().uuidString)", defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let pets = try JSONEncoder().encode([FurPet.sample])
        defaults.set(pets, forKey: "livePets"); defaults.set(pets, forKey: "samplePets")
        XCTAssertEqual(FurStore(defaults: defaults, sessionReader: { _ in nil }).onboarding.stage, .complete)
        let interrupted = try JSONEncoder().encode(OnboardingProgress(stage: .creating, question: 4, recipe: .sample, name: "Mochi"))
        defaults.set(interrupted, forKey: "liveOnboarding"); defaults.set(interrupted, forKey: "sampleOnboarding")
        let resumed = FurStore(defaults: defaults, sessionReader: { _ in nil })
        XCTAssertEqual(resumed.onboarding.stage, .reveal)
        XCTAssertEqual(resumed.onboarding.petID, FurPet.sample.id)
        XCTAssertEqual(resumed.pets.count, 1)
    }
    func testOnboardingResumesWithGenderAnswersAndCreatedPet() throws {
        let progress = OnboardingProgress(stage: .reveal, question: 4,
            recipe: PetRecipe(animal: "dragon", color: "pink", personality: "Curious", gender: .girl), name: "Luna", petID: "created-pet")
        let decoded = try JSONDecoder().decode(OnboardingProgress.self, from: JSONEncoder().encode(progress))
        XCTAssertEqual(decoded, progress)
        XCTAssertEqual(decoded.recipe.gender?.subject, "she")
        XCTAssertEqual(decoded.recipe.gender?.possessive, "her")
    }
    func testOnboardingRequiresGenderSpeciesColorAndNameButAccessoriesAreOptional() {
        var progress = OnboardingProgress()
        XCTAssertFalse(progress.canContinue)
        progress.recipe.gender = .boy; XCTAssertTrue(progress.canContinue)
        progress.question = 1; XCTAssertFalse(progress.canContinue)
        progress.recipe.animal = "tiny dragon"; XCTAssertTrue(progress.canContinue)
        progress.question = 2; progress.recipe.color = "  "; XCTAssertFalse(progress.canContinue)
        progress.recipe.color = "pink"; XCTAssertTrue(progress.canContinue)
        progress.question = 3; XCTAssertTrue(progress.canContinue)
        progress.question = 4; progress.name = "  "; XCTAssertFalse(progress.canContinue)
        progress.name = "Mochi"; XCTAssertTrue(progress.canContinue)
        progress.name = String(repeating: "a", count: 41); XCTAssertFalse(progress.canContinue)
    }
    func testExistingPetRecipesDecodeWithoutGender() throws {
        let old = Data(#"{"animal":"cat","color":"purple","accessories":"","personality":"goofy"}"#.utf8)
        let recipe = try JSONDecoder().decode(PetRecipe.self, from: old)
        XCTAssertNil(recipe.gender); XCTAssertTrue(recipe.isValid)
    }
    func testPetPromptIncludesRequestedGenderAndKeepsCustomAppearance() {
        for gender in PetGender.allCases {
            let recipe = PetRecipe(animal: "dragon", color: "blue", accessories: "", personality: "Curious", gender: gender)
            let prompt = PetPrompt.create(recipe)
            XCTAssertTrue(prompt.contains("\"gender\":\"\(gender.rawValue)\""))
            XCTAssertTrue(prompt.contains("requested boy or girl animal"))
            XCTAssertTrue(prompt.contains("blue"))
        }
    }
    func testFreeTextRecipeAcceptsFantasyAnimalsAndOptionalAccessories() {
        let recipe = PetRecipe(animal: "A gigglegoop with six ears", color: "Green to yellow ombré", accessories: "", personality: "Sassy but sweet")
        XCTAssertTrue(recipe.isValid)
        let prompt = PetPrompt.create(recipe)
        XCTAssertTrue(prompt.contains("gigglegoop")); XCTAssertTrue(prompt.contains("Sassy but sweet")); XCTAssertTrue(prompt.contains("transparent"))
    }
    func testWhitespaceAndOverlongAnswersCannotGenerate() {
        XCTAssertFalse(PetRecipe(animal: "  ", color: "red", accessories: "", personality: "goofy").isValid)
        XCTAssertFalse(PetRecipe(animal: "cat", color: String(repeating: "a", count: 301), accessories: "", personality: "goofy").isValid)
        XCTAssertFalse(PetRecipe(animal: "cat", color: String(repeating: "🐾", count: 151), accessories: "", personality: "goofy").isValid)
    }
    func testExpiredProDoesNotUnlockWidget() {
        let now = Date()
        XCTAssertFalse(WidgetSnapshot(pet: .sample, isPro: true, proExpiresAt: now.addingTimeInterval(-1)).hasAccess(at: now))
        XCTAssertFalse(WidgetSnapshot(pet: .sample, isPro: true).hasAccess(at: now))
        XCTAssertTrue(WidgetSnapshot(pet: .sample, isPro: true, proExpiresAt: now.addingTimeInterval(100)).hasAccess(at: now))
    }
    func testPaidAllowanceIsTwentyImagesAndDoesNotIncludeTrial() {
        let wallet = WalletSnapshot(isPro: true, subscriptionCredits: 5000, purchasedCredits: 5000, trialCredits: 250)
        XCTAssertEqual(wallet.subscriptionCredits / 250, 20)
        XCTAssertEqual(wallet.total, 10000)
    }
    func testWidgetSnapshotRoundTripsPetAndBehavior() throws {
        let snapshot = WidgetSnapshot(pet: .sample, isPro: true, proExpiresAt: Date().addingTimeInterval(60), behavior: .sleepy, experimentalMotion: true)
        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: JSONEncoder().encode(snapshot))
        XCTAssertEqual(decoded.pet?.recipe, .sample); XCTAssertEqual(decoded.behavior, .sleepy); XCTAssertTrue(decoded.experimentalMotion)
    }
    func testAnimationSheetCropsEachCellRatherThanShowingFourPets() throws {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 40))
        let sheet = renderer.image { context in
            let colors: [UIColor] = [.red, .green, .blue, .yellow]
            for index in 0..<4 { context.cgContext.setFillColor(colors[index].cgColor); context.cgContext.fill(CGRect(x: (index % 2) * 20, y: (index / 2) * 20, width: 20, height: 20)) }
        }
        let filename = "test-\(UUID().uuidString).png"
        defer { try? FileManager.default.removeItem(at: SharedStorage.directory.appendingPathComponent(filename)) }
        try SharedStorage.saveImage(XCTUnwrap(sheet.pngData()), named: filename)
        let first = try XCTUnwrap(SharedStorage.image(filename, frame: 0)), last = try XCTUnwrap(SharedStorage.image(filename, frame: 3))
        XCTAssertEqual(first.cgImage?.width, sheet.cgImage!.width / 2)
        XCTAssertEqual(first.cgImage?.height, sheet.cgImage!.height / 2)
        XCTAssertNotEqual(first.pngData(), last.pngData())
    }
}
