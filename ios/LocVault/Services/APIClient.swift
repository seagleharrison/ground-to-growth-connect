import Foundation

@MainActor
final class APIClient {
    static let shared = APIClient()

    var baseURL: String {
        KeychainService.loadAPIBaseURL()
    }

    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        session = URLSession(configuration: config)
        decoder = JSONDecoder()
        encoder = JSONEncoder()
    }

    func register(_ payload: RegisterRequest) async throws -> RegisterResponse {
        try await request(
            path: "/api/users",
            method: "POST",
            body: payload,
            authenticated: false
        )
    }

    func fetchMe() async throws -> User {
        let response: MeResponse = try await request(path: "/api/me")
        return response.user
    }

    func deleteAccount() async throws {
        let _: DeleteResponse = try await request(path: "/api/account", method: "DELETE")
    }

    func fetchDisclosure() async throws -> DisclosureResponse {
        try await request(path: "/api/consent/disclosure", authenticated: false)
    }

    func fetchConsentStatus() async throws -> ConsentStatus {
        try await request(path: "/api/consent/status")
    }

    func fetchConsentHistory() async throws -> [ConsentRecord] {
        let response: ConsentHistoryResponse = try await request(path: "/api/consent/history")
        return response.records
    }

    func setConsent(granted: Bool) async throws -> ConsentRecord {
        let response: ConsentActionResponse = try await request(
            path: "/api/consent",
            method: "POST",
            body: ["granted": granted]
        )
        return response.record
    }

    func postLocation(_ payload: LocationReportPayload) async throws -> LocationReportMeta {
        let response: LocationReportResponse = try await request(
            path: "/api/locations",
            method: "POST",
            body: payload
        )
        return response.report
    }

    func fetchLatestLocations() async throws -> [UserLocation] {
        let response: LatestLocationsResponse = try await request(path: "/api/locations/latest")
        return response.locations
    }

    func fetchMyLocations() async throws -> [MyLocationReport] {
        let response: MyLocationsResponse = try await request(path: "/api/locations/mine")
        return response.reports
    }

    // MARK: - Document storage consent

    func fetchDocumentDisclosure() async throws -> DisclosureResponse {
        try await request(path: "/api/consent/documents/disclosure", authenticated: false)
    }

    func fetchDocumentConsentStatus() async throws -> ConsentStatus {
        try await request(path: "/api/consent/documents/status")
    }

    func fetchDocumentConsentHistory() async throws -> [ConsentRecord] {
        let response: ConsentHistoryResponse = try await request(path: "/api/consent/documents/history")
        return response.records
    }

    func setDocumentConsent(granted: Bool) async throws -> ConsentRecord {
        let response: ConsentActionResponse = try await request(
            path: "/api/consent/documents",
            method: "POST",
            body: ["granted": granted]
        )
        return response.record
    }

    // MARK: - Documents

    func uploadDocument(_ payload: UploadDocumentRequest) async throws -> DocumentMeta {
        // Longer timeout than the default 30s: this is a real file upload,
        // not a small JSON request, and may run over a slow connection.
        let response: UploadDocumentResponse = try await request(
            path: "/api/documents",
            method: "POST",
            body: payload,
            timeout: 60
        )
        return response.document
    }

    func fetchDocuments() async throws -> [DocumentMeta] {
        let response: ListDocumentsResponse = try await request(path: "/api/documents")
        return response.documents
    }

    func fetchDocument(id: String) async throws -> GetDocumentResponse {
        try await request(path: "/api/documents/\(id)", timeout: 60)
    }

    func deleteDocument(id: String) async throws {
        let _: DeleteResponse = try await request(path: "/api/documents/\(id)", method: "DELETE")
    }

    // MARK: - Private

    private func request<T: Decodable>(
        path: String,
        method: String = "GET",
        body: Encodable? = nil,
        authenticated: Bool = true,
        timeout: TimeInterval? = nil
    ) async throws -> T {
        guard let url = URL(string: baseURL.trimmingCharacters(in: .init(charactersIn: "/")) + path) else {
            throw LocVaultError.server("Invalid API URL.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("LocVault-iOS/0.1", forHTTPHeaderField: "User-Agent")
        if let timeout {
            request.timeoutInterval = timeout
        }

        if authenticated {
            guard let token = KeychainService.loadToken() else {
                throw LocVaultError.unauthorized
            }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body {
            request.httpBody = try encoder.encode(AnyEncodable(body))
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw LocVaultError.network(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw LocVaultError.server("Invalid server response.")
        }

        if http.statusCode == 401 {
            throw LocVaultError.unauthorized
        }

        if !(200...299).contains(http.statusCode) {
            if let apiError = try? decoder.decode(APIErrorResponse.self, from: data) {
                throw LocVaultError.server(apiError.error)
            }
            throw LocVaultError.server("Request failed (\(http.statusCode)).")
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw LocVaultError.decoding
        }
    }
}

private struct AnyEncodable: Encodable {
    private let encodeClosure: (Encoder) throws -> Void

    init(_ wrapped: Encodable) {
        encodeClosure = wrapped.encode
    }

    func encode(to encoder: Encoder) throws {
        try encodeClosure(encoder)
    }
}
