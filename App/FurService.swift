import Foundation
import Security
import CryptoKit

struct ServiceSession: Codable { var token: String; var accountID: String }
struct SessionResponse: Decodable { var token: String; var accountID: String; var wallet: WalletSnapshot }
struct JobReceipt: Decodable { var id: String }
struct PendingGeneration: Codable {
    var key: String
    var payloadHash: String
    var recipe: PetRecipe
    var isPhoto: Bool
    var receiptID: String?
    var petID: String?
    var petName: String?
    var placement: String?
    var backgroundPrompt: String?
}
struct GenerationResult: Decodable {
    var imageBase64: String
    var petID: String?
    var wallet: WalletSnapshot
}
struct JobResponse: Decodable {
    var status: String
    var result: GenerationResult?
    var error: String?
}
struct PoseResult: Decodable { var playfulBase64: String; var sleepingBase64: String; var wallet: WalletSnapshot }
extension PoseResult {
    private enum CodingKeys: String, CodingKey {
        case playfulBase64, sleepingBase64, wallet
        case legacyPlayful = "lickingBase64"
    }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        playfulBase64 = try values.decodeIfPresent(String.self, forKey: .playfulBase64)
            ?? values.decode(String.self, forKey: .legacyPlayful)
        sleepingBase64 = try values.decode(String.self, forKey: .sleepingBase64)
        wallet = try values.decode(WalletSnapshot.self, forKey: .wallet)
    }
}
struct AnimationResult: Decodable { var animation: AnimationPayload; var wallet: WalletSnapshot }
struct AnimationJobResponse: Decodable { var status: String; var result: AnimationResult?; var error: String?; var progress: AnimationPipelineProgress? }

struct AnimationPipelineProgress: Decodable, Equatable, Identifiable {
    var kind: String
    var stage: String
    var completedStages: Int
    var totalStages: Int
    var id: String { kind }
    var fraction: Double { min(1, max(0, Double(completedStages) / Double(max(1, totalStages)))) }
    var title: String { kind == "idle" ? "Idle" : kind == "sleep" ? "Sleeping" : "Playful" }
    var stageTitle: String {
        switch stage {
        case "waiting": "Waiting to start"
        case "prepare": "Preparing your pet"
        case "sleep_pose_video": "Creating a sleeping pose"
        case "sleep_pose_background": "Removing the pose background"
        case "sleep_pose_frames": "Extracting the sleeping pose"
        case "sleep_pose_check": "Checking the sleeping pose"
        case "video": "Animating your pet"
        case "background": "Removing the background"
        case "frames": "Extracting animation frames"
        case "verify": "Checking the sleep and snore"
        case "snore": "Adding floating Zs"
        case "encode": "Finishing the sleeping video"
        case "save": "Saving animation"
        case "completed": "Ready to replay"
        default: "Preparing animation"
        }
    }
    static func waiting(kind: String) -> Self {
        Self(kind: kind, stage: "waiting", completedStages: 0, totalStages: kind == "sleep" ? 12 : 5)
    }
}

extension AnimationPipelineProgress {
    private enum CodingKeys: String, CodingKey { case kind, stage, completedStages, totalStages }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let savedKind = try values.decode(String.self, forKey: .kind)
        kind = savedKind == "lick" ? "playful" : savedKind
        stage = try values.decode(String.self, forKey: .stage)
        completedStages = try values.decode(Int.self, forKey: .completedStages)
        totalStages = try values.decode(Int.self, forKey: .totalStages)
    }
}

struct AnimationPreparationProgress {
    var petID: String
    var animations: [AnimationPipelineProgress]
    var isRunning = true
    var failed = false
    var fraction: Double {
        let total = animations.reduce(0) { $0 + max(1, $1.totalStages) }
        return animations.reduce(0) { $0 + $1.fraction * Double(max(1, $1.totalStages)) } / Double(max(1, total))
    }
}

enum FurError: LocalizedError {
    case message(String)
    case connectionInterrupted
    case stillProcessing
    case response(status: Int, message: String)
    var errorDescription: String? {
        switch self {
        case .message(let value), .response(_, let value): value
        case .connectionInterrupted: "Your Fur Baby is safe. We’re having trouble connecting—try recovering them when your connection is back."
        case .stillProcessing: "Your Fur Baby is taking a little longer. Their creation is saved, and you can check again without another charge."
        }
    }
    var canRecoverGeneration: Bool {
        switch self {
        case .connectionInterrupted, .stillProcessing: true
        case .response(let status, _): [408, 429, 500, 502, 503, 504].contains(status)
        case .message: false
        }
    }
}

struct FurNetworkPolicy {
    var maximumAttempts = 4
    var retryDelay: Double = 2
    var pollInterval: Double = 2
    var maximumPolls = 240
    var generationWaitLimit: Double = 600
}

enum SecureSession {
    static func read(_ key: String) -> ServiceSession? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "MyFurBaby", kSecAttrAccount as String: key, kSecReturnData as String: true]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(ServiceSession.self, from: data)
    }
    static func save(_ value: ServiceSession, key: String) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "MyFurBaby", kSecAttrAccount as String: key]
        let data = try JSONEncoder().encode(value)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query; item[kSecValueData as String] = data; item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw FurError.message("Unable to save your secure session.") }
        } else if status != errSecSuccess { throw FurError.message("Unable to update your secure session.") }
    }
}

@MainActor
final class FurService {
    let baseURL: URL
    private(set) var session: ServiceSession?
    private let network: URLSession
    private let storage: UserDefaults
    private let policy: FurNetworkPolicy
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { value in
            let string = try value.singleValueContainer().decode(String.self)
            let fractional = ISO8601DateFormatter(); fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            guard let date = fractional.date(from: string) ?? ISO8601DateFormatter().date(from: string) else { throw FurError.message("The service returned an invalid date.") }
            return date
        }
        return decoder
    }()

    init(url: URL, network: URLSession? = nil, storage: UserDefaults = .standard,
         identity: ServiceSession? = nil, policy: FurNetworkPolicy = FurNetworkPolicy()) {
        baseURL = url; session = identity ?? SecureSession.read(url.absoluteString)
        self.storage = storage; self.policy = policy
        if let network { self.network = network }
        else {
            let configuration = URLSessionConfiguration.default
            configuration.waitsForConnectivity = true
            configuration.timeoutIntervalForRequest = 60
            configuration.timeoutIntervalForResource = 600
            self.network = URLSession(configuration: configuration)
        }
    }
    private var pendingKey: String { "pendingImage:" + baseURL.absoluteString + ":" + (session?.accountID ?? "") }
    var pendingGeneration: PendingGeneration? {
        get { storage.data(forKey: pendingKey).flatMap { try? JSONDecoder().decode(PendingGeneration.self, from: $0) } }
        set { storage.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: pendingKey) }
    }

    func connect() async throws -> WalletSnapshot {
        if session != nil { return try await wallet() }
        let result: SessionResponse = try await request("v1/session", method: "POST", body: Data("{}".utf8), authenticated: false)
        let identity = ServiceSession(token: result.token, accountID: result.accountID)
        try SecureSession.save(identity, key: baseURL.absoluteString)
        session = identity
        return result.wallet
    }
    func wallet() async throws -> WalletSnapshot { try await request("v1/wallet") }
    func purchase(jws: String) async throws -> WalletSnapshot {
        try await request("v1/purchases", method: "POST", body: JSONSerialization.data(withJSONObject: ["signedTransaction": jws]))
    }
    func generate(recipe: PetRecipe, name: String, photo: Data? = nil, pet: FurPet? = nil, placement: String = "", onboarding: Bool = false, backgroundPrompt: String? = nil, onConnectionChange: (Bool) -> Void = { _ in }) async throws -> GenerationResult {
        var payload: [String: Any] = ["kind": photo == nil ? "pet" : "photo", "name": name, "recipe": ["animal": recipe.animal, "color": recipe.color, "accessories": recipe.accessories, "personality": recipe.personality]]
        if let gender = recipe.gender, var design = payload["recipe"] as? [String: String] {
            design["gender"] = gender.rawValue; payload["recipe"] = design
        }
        if let photo { payload["photoBase64"] = photo.base64EncodedString(); payload["petID"] = pet?.id; payload["placement"] = placement }
        if onboarding { payload["onboarding"] = true }
        if let backgroundPrompt { payload = ["kind": "background", "prompt": backgroundPrompt] }
        let data = try JSONSerialization.data(withJSONObject: payload, options: .sortedKeys)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        if let pending = pendingGeneration {
            guard pending.payloadHash == digest else { throw FurError.message("An earlier image needs to be recovered. Open Settings and choose Resume unfinished image before starting another.") }
            if pending.receiptID != nil { return try await resume(onConnectionChange: onConnectionChange).result }
        }
        var pending = pendingGeneration ?? PendingGeneration(key: UUID().uuidString, payloadHash: digest, recipe: recipe, isPhoto: photo != nil, petID: pet?.id, petName: name, placement: placement, backgroundPrompt: backgroundPrompt)
        pendingGeneration = pending
        do {
            let receipt: JobReceipt = try await request("v1/jobs", method: "POST", body: data, idempotencyKey: pending.key, onConnectionChange: onConnectionChange)
            pending.receiptID = receipt.id; pendingGeneration = pending
        } catch let error as FurError {
            if !error.canRecoverGeneration { pendingGeneration = nil }
            throw error
        }
        return try await resume(onConnectionChange: onConnectionChange).result
    }
    func resume(onConnectionChange: (Bool) -> Void = { _ in }) async throws -> (pending: PendingGeneration, result: GenerationResult) {
        guard var pending = pendingGeneration else { throw FurError.message("No unfinished image was found.") }
        if pending.receiptID == nil {
            let receipt: JobReceipt
            do { receipt = try await request("v1/jobs/by-key/\(pending.key)", onConnectionChange: onConnectionChange) }
            catch let error as FurError {
                if !error.canRecoverGeneration { pendingGeneration = nil }
                throw error
            }
            pending.receiptID = receipt.id; pendingGeneration = pending
        }
        guard let receiptID = pending.receiptID else { throw FurError.message("The image request could not be recovered.") }
        let clock = ContinuousClock(), deadline = ContinuousClock.now + .seconds(policy.generationWaitLimit)
        for _ in 0..<policy.maximumPolls {
            try Task.checkCancellation()
            guard clock.now < deadline else { break }
            let job: JobResponse = try await request("v1/jobs/\(receiptID)", timeout: 120, onConnectionChange: onConnectionChange)
            if job.status == "completed", let result = job.result { return (pending, result) }
            if job.status == "failed" { pendingGeneration = nil; throw FurError.message(job.error ?? "Generation failed. Reserved credits were returned.") }
            try await Task.sleep(for: .seconds(policy.pollInterval))
        }
        throw FurError.stillProcessing
    }
    func poses(petID: String) async throws -> PoseResult { try await request("v1/pets/\(petID)/poses", method: "POST", body: Data("{}".utf8), timeout: 600) }
    func animation(petID: String, kind: String, onProgress: (AnimationPipelineProgress) -> Void = { _ in }) async throws -> AnimationResult {
        var progress = AnimationPipelineProgress.waiting(kind: kind)
        progress.stage = "prepare"; onProgress(progress)
        // The server deduplicates by pet and kind, including retries after a lost response or app relaunch.
        let receipt: JobReceipt = try await request("v1/pets/\(petID)/animations", method: "POST",
            body: JSONSerialization.data(withJSONObject: ["kind": kind]), idempotencyKey: "animation-\(petID)-\(kind)")
        for _ in 0..<600 {
            let job: AnimationJobResponse = try await request("v1/jobs/\(receipt.id)")
            if let update = job.progress, update.kind == kind {
                progress = update
                if progress.stage == "completed" {
                    progress.stage = "save"; progress.completedStages = max(0, progress.totalStages - 1)
                }
                onProgress(progress)
            }
            if job.status == "completed", let result = job.result {
                if progress.stage != "save" {
                    progress.stage = "save"; progress.completedStages = max(0, progress.totalStages - 1); onProgress(progress)
                }
                return result
            }
            if job.status == "failed" { throw FurError.message(job.error ?? "Animation failed. Reserved credits were returned.") }
            try await Task.sleep(for: .seconds(policy.pollInterval))
        }
        throw FurError.message("Your animation is still being prepared. Tap Animate my pet again to recover it without another charge.")
    }

    private func request<T: Decodable>(_ path: String, method: String = "GET", body: Data? = nil, authenticated: Bool = true, idempotencyKey: String? = nil, timeout: Double = 60, onConnectionChange: (Bool) -> Void = { _ in }) async throws -> T {
        var request = URLRequest(url: baseURL.appendingPathComponent(path)); request.httpMethod = method; request.httpBody = body; request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if authenticated {
            guard let session else { throw FurError.message("Connect to your Fur Baby service first.") }
            request.setValue("Bearer \(session.token)", forHTTPHeaderField: "Authorization")
        }
        if let idempotencyKey { request.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key") }
        let canRetry = method == "GET" || idempotencyKey != nil
        let attempts = canRetry ? max(1, policy.maximumAttempts) : 1
        for attempt in 0..<attempts {
            try Task.checkCancellation()
            do {
                let (data, response) = try await network.data(for: request)
                guard let response = response as? HTTPURLResponse else { throw FurError.message("The service did not respond.") }
                guard (200..<300).contains(response.statusCode) else {
                    let error = (try? JSONSerialization.jsonObject(with: data) as? [String: String])?["error"]
                    throw FurError.response(status: response.statusCode, message: error ?? "The service could not complete that request.")
                }
                let result = try decoder.decode(T.self, from: data)
                onConnectionChange(false)
                return result
            } catch {
                try Task.checkCancellation()
                let transient: Bool
                if let urlError = error as? URLError {
                    transient = [.timedOut, .networkConnectionLost, .notConnectedToInternet, .cannotConnectToHost,
                                 .cannotFindHost, .dnsLookupFailed, .dataNotAllowed, .internationalRoamingOff].contains(urlError.code)
                } else { transient = (error as? FurError)?.canRecoverGeneration ?? false }
                guard transient else { throw error }
                guard attempt + 1 < attempts else { throw FurError.connectionInterrupted }
                onConnectionChange(true)
                try await Task.sleep(for: .seconds(min(8, policy.retryDelay * pow(2, Double(attempt)))))
            }
        }
        throw FurError.connectionInterrupted
    }
}
