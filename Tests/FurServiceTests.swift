import XCTest
@testable import MyFurBaby

private final class GenerationURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, [String: Any]))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            guard let handler = Self.handler else { throw URLError(.badServerResponse) }
            let (status, body) = try handler(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: try JSONSerialization.data(withJSONObject: body))
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

private func requestBody(_ request: URLRequest) -> Data? {
    if let data = request.httpBody { return data }
    guard let stream = request.httpBodyStream else { return nil }
    stream.open(); defer { stream.close() }
    var data = Data(), buffer = [UInt8](repeating: 0, count: 4096)
    while stream.hasBytesAvailable {
        let count = stream.read(&buffer, maxLength: buffer.count)
        guard count > 0 else { break }
        data.append(contentsOf: buffer.prefix(count))
    }
    return data
}

@MainActor final class FurServiceTests: XCTestCase {
    func testCustomBackgroundUsesBackgroundPayloadAndKeepsRecoveryContextAcrossLaunches() async throws {
        let completed = completed
        var keys: [String] = []
        GenerationURLProtocol.handler = { request in
            if request.httpMethod == "POST" {
                let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(requestBody(request))) as? [String: String])
                XCTAssertEqual(payload, ["kind": "background", "prompt": "A moonlit garden"])
                keys.append(request.value(forHTTPHeaderField: "Idempotency-Key") ?? "")
                if keys.count == 1 { throw URLError(.networkConnectionLost) }
                return (202, ["id": "background-job"])
            }
            XCTAssertEqual(request.url?.path, "/v1/jobs/background-job")
            return (200, completed)
        }
        _ = try await service.generate(recipe: .sample, name: "", backgroundPrompt: "A moonlit garden")
        let recovered = try await makeService().resume()
        XCTAssertEqual(recovered.pending.backgroundPrompt, "A moonlit garden")
        XCTAssertFalse(recovered.pending.isPhoto)
        XCTAssertEqual(keys.count, 2); XCTAssertEqual(keys.first, keys.last)
    }
    func testConnectingSavedAccountValidatesWalletWithoutCreatingAnotherAccount() async throws {
        var paths: [String] = []
        GenerationURLProtocol.handler = { request in
            paths.append(request.url!.path)
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
            return (200, ["isPro": false, "subscriptionCredits": 0, "purchasedCredits": 0, "trialCredits": 250, "accountID": "test-account"])
        }
        let wallet = try await service.connect()
        XCTAssertEqual(wallet.accountID, "test-account")
        XCTAssertEqual(paths, ["/v1/wallet"])
    }
    func testPhotoRecoveryKeepsOriginalPetAndPlacementAfterRelaunch() async throws {
        let completed = completed
        GenerationURLProtocol.handler = { request in
            request.httpMethod == "POST" ? (202, ["id": "photo-job"]) : (200, completed)
        }
        var pet = FurPet.sample; pet.id = "adventure-pet"; pet.name = "Luna"
        _ = try await service.generate(recipe: pet.recipe, name: pet.name, photo: Data("photo".utf8), pet: pet, placement: "Sitting beside me")
        let recovered = try await makeService().resume()
        XCTAssertTrue(recovered.pending.isPhoto)
        XCTAssertEqual(recovered.pending.petID, "adventure-pet")
        XCTAssertEqual(recovered.pending.petName, "Luna")
        XCTAssertEqual(recovered.pending.placement, "Sitting beside me")
        let old = Data(#"{"key":"old-job","payloadHash":"hash","recipe":{"animal":"cat","color":"pink","accessories":"","personality":"sweet"},"isPhoto":true,"receiptID":"receipt"}"#.utf8)
        let legacy = try JSONDecoder().decode(PendingGeneration.self, from: old)
        XCTAssertTrue(legacy.isPhoto); XCTAssertNil(legacy.petName)
    }
    func testAnimationSubmissionRetriesAndDecodesFullSequence() async throws {
        var keys: [String] = []
        let wallet: [String: Any] = ["isPro": true, "subscriptionCredits": 4750, "purchasedCredits": 0, "trialCredits": 0]
        GenerationURLProtocol.handler = { request in
            if request.httpMethod == "POST" {
                XCTAssertEqual(request.url?.path, "/v1/pets/test-pet/animations")
                let body = try XCTUnwrap(requestBody(request))
                let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: String])
                XCTAssertEqual(payload["kind"], "run")
                keys.append(request.value(forHTTPHeaderField: "Idempotency-Key") ?? "")
                if keys.count == 1 { throw URLError(.networkConnectionLost) }
                return (202, ["id": "animation-job"])
            }
            XCTAssertEqual(request.url?.path, "/v1/jobs/animation-job")
            return (200, ["status": "completed", "result": ["wallet": wallet, "animation": [
                "kind": "run", "fps": 15, "width": 512, "height": 512, "frameCount": 60,
                "duration": 4, "framesBase64": Array(repeating: "frame-bytes", count: 60)
            ]]])
        }
        let result = try await service.animation(petID: "test-pet", kind: "run")
        XCTAssertEqual(result.animation.framesBase64.count, 60)
        XCTAssertEqual(result.animation.fps, 15)
        XCTAssertEqual(result.wallet.subscriptionCredits, 4750)
        XCTAssertEqual(keys.count, 2); XCTAssertEqual(keys.first, keys.last)
    }
    func testAnimationProgressFollowsPolledStagesAndWaitsForLocalSave() async throws {
        var polls = 0
        let wallet: [String: Any] = ["isPro": true, "subscriptionCredits": 4750, "purchasedCredits": 0, "trialCredits": 0]
        GenerationURLProtocol.handler = { request in
            if request.httpMethod == "POST" { return (202, ["id": "progress-job"]) }
            polls += 1
            if polls == 1 {
                return (200, ["status": "pending", "progress": ["kind": "sleep", "stage": "sleep_pose_check", "completedStages": 4, "totalStages": 12]])
            }
            if polls == 2 {
                return (200, ["status": "pending", "progress": ["kind": "sleep", "stage": "snore", "completedStages": 9, "totalStages": 12]])
            }
            return (200, ["status": "completed", "progress": ["kind": "sleep", "stage": "completed", "completedStages": 12, "totalStages": 12], "result": [
                "wallet": wallet, "animation": ["kind": "sleep", "fps": 15, "width": 512, "height": 512, "frameCount": 60, "duration": 4, "framesBase64": Array(repeating: "frame-bytes", count: 60)]
            ]])
        }
        var updates: [AnimationPipelineProgress] = []
        _ = try await service.animation(petID: "test-pet", kind: "sleep") { updates.append($0) }
        XCTAssertEqual(updates.map(\.stage), ["prepare", "sleep_pose_check", "snore", "save"])
        XCTAssertEqual(updates.map(\.completedStages), [0, 4, 9, 11])
        XCTAssertTrue(updates.allSatisfy { $0.fraction < 1 }, "Only the store marks completion after saving the frames locally")
    }

    func testAnimationBatchProgressCountsStagesAcrossMissingAnimations() {
        let playful = AnimationPipelineProgress(kind: "playful", stage: "completed", completedStages: 5, totalStages: 5)
        let sleeping = AnimationPipelineProgress(kind: "sleep", stage: "snore", completedStages: 9, totalStages: 12)
        let batch = AnimationPreparationProgress(petID: "test", animations: [playful, sleeping])
        XCTAssertEqual(batch.fraction, 14.0 / 17.0, accuracy: 0.001)
        let retry = AnimationPreparationProgress(petID: "test", animations: [sleeping])
        XCTAssertEqual(retry.fraction, 0.75)
        XCTAssertEqual(AnimationPipelineProgress(kind: "playful", stage: "save", completedStages: 99, totalStages: 5).fraction, 1)
        XCTAssertEqual(AnimationPipelineProgress(kind: "playful", stage: "waiting", completedStages: -1, totalStages: 0).fraction, 0)
    }
    func testAdditionalPetSendsGenderAndNameWithoutFreeOnboardingFlag() async throws {
        let completed = completed
        GenerationURLProtocol.handler = { request in
            if request.httpMethod == "POST" {
                let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(requestBody(request))) as? [String: Any])
                let recipe = try XCTUnwrap(payload["recipe"] as? [String: String])
                XCTAssertEqual(recipe["gender"], "girl")
                XCTAssertEqual(recipe["animal"], "dragon")
                XCTAssertEqual(payload["name"] as? String, "Luna")
                XCTAssertNil(payload["onboarding"])
                return (202, ["id": "additional-pet"])
            }
            return (200, completed)
        }
        _ = try await service.generate(recipe: PetRecipe(animal: "dragon", color: "pink", personality: "Curious", gender: .girl), name: "Luna")
    }
    func testFailedSleepAnimationCanSubmitFreshRetry() async throws {
        var submissions = 0
        GenerationURLProtocol.handler = { request in
            if request.httpMethod == "POST" {
                submissions += 1
                return (202, ["id": submissions == 1 ? "failed-sleep" : "retried-sleep"])
            }
            if request.url?.path == "/v1/jobs/failed-sleep" {
                return (200, ["status": "failed", "error": "Sleeping pose could not be prepared. Credits were returned."])
            }
            return (200, ["status": "completed", "result": [
                "wallet": ["isPro": true, "subscriptionCredits": 4750, "purchasedCredits": 0, "trialCredits": 0],
                "animation": ["kind": "sleep", "fps": 15, "width": 512, "height": 512, "frameCount": 60,
                    "duration": 4, "framesBase64": Array(repeating: "frame-bytes", count: 60)]
            ]])
        }
        do {
            _ = try await service.animation(petID: "test-pet", kind: "sleep")
            XCTFail("The failed job must surface its error.")
        } catch { XCTAssertTrue(error.localizedDescription.contains("Credits were returned")) }
        let result = try await service.animation(petID: "test-pet", kind: "sleep")
        XCTAssertEqual(submissions, 2)
        XCTAssertEqual(result.animation.kind, "sleep")
    }
    private let identity = ServiceSession(token: "test-token", accountID: "test-account")
    private var suite = ""
    private var storage: UserDefaults!
    private var network: URLSession!
    private var service: FurService!
    private let completed: [String: Any] = [
        "status": "completed",
        "result": ["imageBase64": "cGV0", "petID": "one-pet", "wallet": [
            "isPro": false, "subscriptionCredits": 0, "purchasedCredits": 0, "trialCredits": 0
        ]]
    ]

    override func setUp() async throws {
        suite = "generation-network-test-\(UUID().uuidString)"
        storage = UserDefaults(suiteName: suite)!
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [GenerationURLProtocol.self]
        network = URLSession(configuration: configuration)
        service = makeService()
    }
    override func tearDown() async throws {
        network.invalidateAndCancel()
        GenerationURLProtocol.handler = nil
        storage.removePersistentDomain(forName: suite)
    }
    private func makeService(maximumPolls: Int = 4) -> FurService {
        FurService(url: URL(string: "https://fur-service-tests.invalid")!, network: network, storage: storage,
            identity: identity, policy: FurNetworkPolicy(maximumAttempts: 2, retryDelay: 0, pollInterval: 0, maximumPolls: maximumPolls))
    }

    func testPollingTimeoutRecoversTheSameJobWithoutResubmitting() async throws {
        var submissions = 0, polls = 0, reconnecting: [Bool] = []
        let completed = completed
        GenerationURLProtocol.handler = { request in
            if request.httpMethod == "POST" { submissions += 1; return (202, ["id": "accepted-job"]) }
            XCTAssertEqual(request.url?.path, "/v1/jobs/accepted-job")
            XCTAssertEqual(request.timeoutInterval, 120)
            polls += 1
            if polls == 1 { throw URLError(.timedOut) }
            return (200, polls == 2 ? ["status": "pending"] : completed)
        }
        let pet = try await service.generate(recipe: .sample, name: "Mochi", onboarding: true) { reconnecting.append($0) }
        XCTAssertEqual(pet.petID, "one-pet")
        XCTAssertEqual(submissions, 1); XCTAssertEqual(polls, 3)
        XCTAssertTrue(reconnecting.contains(true)); XCTAssertEqual(reconnecting.last, false)
    }

    func testLostSubmissionResponseRetriesWithTheSameIdempotencyKeyAndBody() async throws {
        var keys: [String] = [], bodies: [Data?] = []
        let completed = completed
        GenerationURLProtocol.handler = { request in
            if request.httpMethod == "POST" {
                keys.append(request.value(forHTTPHeaderField: "Idempotency-Key")!)
                bodies.append(requestBody(request))
                if keys.count == 1 { throw URLError(.networkConnectionLost) }
                return (202, ["id": "accepted-job"])
            }
            return (200, completed)
        }
        _ = try await service.generate(recipe: .sample, name: "Mochi", onboarding: true)
        XCTAssertEqual(keys.count, 2); XCTAssertEqual(Set(keys).count, 1)
        XCTAssertNotNil(bodies[0])
        XCTAssertEqual(bodies[0], bodies[1])
        XCTAssertEqual(service.pendingGeneration?.key, keys[0])
    }

    func testExtendedOutageKeepsReceiptAndRelaunchRecoversWithoutAnotherPost() async throws {
        var submissions = 0
        GenerationURLProtocol.handler = { request in
            if request.httpMethod == "POST" { submissions += 1; return (202, ["id": "accepted-job"]) }
            throw URLError(.timedOut)
        }
        do {
            _ = try await service.generate(recipe: .sample, name: "Mochi", onboarding: true)
            XCTFail("Expected recoverable connection interruption")
        } catch let error as FurError { XCTAssertTrue(error.canRecoverGeneration) }
        let saved = try XCTUnwrap(service.pendingGeneration)
        XCTAssertEqual(saved.receiptID, "accepted-job")
        let relaunched = makeService(), completed = completed
        GenerationURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/v1/jobs/accepted-job")
            return (200, completed)
        }
        let recovered = try await relaunched.resume()
        XCTAssertEqual(recovered.result.petID, "one-pet")
        XCTAssertEqual(recovered.pending.key, saved.key); XCTAssertEqual(submissions, 1)
    }

    func testLostReceiptCanBeLookedUpAfterRelaunch() async throws {
        GenerationURLProtocol.handler = { _ in throw URLError(.timedOut) }
        do { _ = try await service.generate(recipe: .sample, name: "Mochi", onboarding: true); XCTFail("Expected timeout") }
        catch let error as FurError { XCTAssertTrue(error.canRecoverGeneration) }
        let saved = try XCTUnwrap(service.pendingGeneration)
        XCTAssertNil(saved.receiptID)
        let relaunched = makeService(), completed = completed
        GenerationURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            if request.url?.path == "/v1/jobs/by-key/\(saved.key)" { return (200, ["id": "accepted-job"]) }
            XCTAssertEqual(request.url?.path, "/v1/jobs/accepted-job")
            return (200, completed)
        }
        let recovered = try await relaunched.resume()
        XCTAssertEqual(recovered.result.petID, "one-pet")
    }

    func testTemporaryServerFailureRetriesButInvalidAnswersDoNot() async throws {
        var attempts = 0
        let completed = completed
        GenerationURLProtocol.handler = { request in
            if request.httpMethod == "POST" {
                attempts += 1
                return attempts == 1 ? (503, ["error": "Temporarily unavailable"]) : (202, ["id": "accepted-job"])
            }
            return (200, completed)
        }
        _ = try await service.generate(recipe: .sample, name: "Mochi")
        XCTAssertEqual(attempts, 2)
        service.pendingGeneration = nil; attempts = 0
        GenerationURLProtocol.handler = { _ in attempts += 1; return (400, ["error": "Please adjust your description."]) }
        do { _ = try await service.generate(recipe: .sample, name: "Mochi"); XCTFail("Expected rejection") }
        catch let error as FurError { XCTAssertFalse(error.canRecoverGeneration) }
        XCTAssertEqual(attempts, 1); XCTAssertNil(service.pendingGeneration)
    }

    func testLongRunningJobKeepsReceiptAndCanFinishOnResume() async throws {
        service = makeService(maximumPolls: 2)
        var submissions = 0
        GenerationURLProtocol.handler = { request in
            if request.httpMethod == "POST" { submissions += 1; return (202, ["id": "accepted-job"]) }
            return (200, ["status": "pending"])
        }
        do { _ = try await service.generate(recipe: .sample, name: "Mochi"); XCTFail("Expected processing notice") }
        catch let error as FurError { XCTAssertTrue(error.canRecoverGeneration) }
        XCTAssertEqual(service.pendingGeneration?.receiptID, "accepted-job")
        let completed = completed
        GenerationURLProtocol.handler = { request in XCTAssertEqual(request.httpMethod, "GET"); return (200, completed) }
        let recovered = try await service.resume()
        XCTAssertEqual(recovered.result.petID, "one-pet")
        XCTAssertEqual(submissions, 1)
    }

    func testProviderFailureReturnsItsMessageAndClearsFinishedJob() async throws {
        GenerationURLProtocol.handler = { request in
            if request.httpMethod == "POST" { return (202, ["id": "accepted-job"]) }
            return (200, ["status": "failed", "error": "Please adjust your description. Credits were returned."])
        }
        do { _ = try await service.generate(recipe: .sample, name: "Mochi"); XCTFail("Expected provider failure") }
        catch { XCTAssertEqual(error.localizedDescription, "Please adjust your description. Credits were returned.") }
        XCTAssertNil(service.pendingGeneration)
    }
}
