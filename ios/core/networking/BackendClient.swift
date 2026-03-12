import Foundation
import FirebaseCore
import FirebaseAuth

/// Minimal HTTP client for the Noongil backend API (Cloud Run).
final class BackendClient {
    private let baseURL: URL
    private let session: URLSession
    private let authTokenProvider: AuthTokenProvider

    /// Set from AuthService token for authenticated requests.
    var authToken: String?

    typealias AuthTokenProvider = (_ forceRefresh: Bool) async throws -> String?

    init(
        baseURL: URL? = nil,
        session: URLSession = .shared,
        authTokenProvider: AuthTokenProvider? = nil
    ) {
        self.baseURL = baseURL ?? URL(string: Config.backendBaseURL)!
        self.session = session
        self.authTokenProvider = authTokenProvider ?? { forceRefresh in
            guard FirebaseApp.app() != nil else { return nil }
            guard let user = Auth.auth().currentUser else { return nil }
            return try await user.getIDToken(forcingRefresh: forceRefresh)
        }
    }

    /// GET a Decodable response from a backend path.
    func get<T: Decodable>(_ path: String, timeout: TimeInterval = 15) async throws -> T {
        let data = try await send(path: path, method: "GET", timeout: timeout)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: data)
    }

    /// POST JSON body to a backend path. Throws on non-2xx response.
    func post<T: Encodable>(_ path: String, body: T) async throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        _ = try await send(path: path, method: "POST", body: try encoder.encode(body))
    }

    /// POST JSON body and decode the response.
    func postAndDecode<T: Encodable, R: Decodable>(_ path: String, body: T, timeout: TimeInterval = 15) async throws -> R {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try await send(
            path: path,
            method: "POST",
            body: try encoder.encode(body),
            timeout: timeout
        )

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(R.self, from: data)
    }

    /// DELETE to a backend path.
    func delete(_ path: String) async throws {
        _ = try await send(path: path, method: "DELETE")
    }

    /// PUT JSON body to a backend path.
    func put<T: Encodable>(_ path: String, body: T) async throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        _ = try await send(path: path, method: "PUT", body: try encoder.encode(body))
    }

    // MARK: - Private

    private func send(
        path: String,
        method: String,
        body: Data? = nil,
        timeout: TimeInterval = 15
    ) async throws -> Data {
        let initialRequest = try await makeRequest(
            path: path,
            method: method,
            body: body,
            timeout: timeout,
            forceRefreshToken: false
        )
        let initialResponse = try await execute(initialRequest)

        if initialResponse.httpResponse.statusCode == 401 {
            let retryRequest = try await makeRequest(
                path: path,
                method: method,
                body: body,
                timeout: timeout,
                forceRefreshToken: true
            )
            let retryResponse = try await execute(retryRequest)
            return try validate(retryResponse.data, response: retryResponse.httpResponse)
        }

        return try validate(initialResponse.data, response: initialResponse.httpResponse)
    }

    private func makeRequest(
        path: String,
        method: String,
        body: Data?,
        timeout: TimeInterval,
        forceRefreshToken: Bool
    ) async throws -> URLRequest {
        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = timeout
        request.httpBody = body

        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        if let token = try await resolveAuthToken(forceRefresh: forceRefreshToken) {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        return request
    }

    private func resolveAuthToken(forceRefresh: Bool) async throws -> String? {
        if let providerToken = try await authTokenProvider(forceRefresh) {
            authToken = providerToken
            return providerToken
        }

        if !forceRefresh {
            return authToken
        }

        return nil
    }

    private func execute(_ request: URLRequest) async throws -> (data: Data, httpResponse: HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw BackendError.invalidResponse
        }

        return (data, httpResponse)
    }

    private func validate(_ data: Data, response: HTTPURLResponse) throws -> Data {
        guard (200...299).contains(response.statusCode) else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw BackendError.apiError(statusCode: response.statusCode, message: errorBody)
        }

        return data
    }

    enum BackendError: Error, LocalizedError {
        case invalidResponse
        case apiError(statusCode: Int, message: String)

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                return "Invalid response from backend"
            case .apiError(let code, let message):
                return "Backend error (\(code)): \(message)"
            }
        }
    }
}
