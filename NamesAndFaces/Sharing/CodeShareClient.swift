import Foundation

/// Talks to the small server that holds decks shared by code. It knows nothing
/// about who anyone is: the only identifier it sees is a random ID made on this
/// phone, used to count wrong guesses.
enum CodeShareClient {
    static let baseURL = URL(string: "https://ntf-codes.wadesellers.workers.dev/v1/decks")!

    struct Shared: Decodable {
        let code: String
        let ownerToken: String
        let expiresAt: Date
    }

    enum Failure: LocalizedError {
        case noConnection
        case wrongCode(guessesRemaining: Int?)
        case locked(minutes: Int)
        case tooManyShares
        case tooLarge
        case server

        var errorDescription: String? {
            switch self {
            case .noConnection:
                return "Couldn't reach the internet. Check your connection and try again."
            case .wrongCode(let remaining):
                if let remaining, remaining <= 3 {
                    return remaining == 0
                        ? "That code didn't match a deck. You're out of tries for now."
                        : "That code didn't match a deck. \(remaining) \(remaining == 1 ? "try" : "tries") left this hour."
                }
                return "That code didn't match a deck. Check the numbers — codes also expire after 30 days."
            case .locked(let minutes):
                return "Too many wrong codes. Try again in \(minutes) \(minutes == 1 ? "minute" : "minutes")."
            case .tooManyShares:
                return "You've shared a lot of decks today. Try again tomorrow."
            case .tooLarge:
                return "This deck is too large to share by code. Send it as a file instead."
            case .server:
                return "Something went wrong on our end. Try again in a moment."
            }
        }
    }

    // MARK: - Calls

    static func share(_ file: DeckFile) async throws -> Shared {
        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.setValue(installID, forHTTPHeaderField: "X-Install-ID")
        request.httpBody = try file.encoded()

        let (data, response) = try await send(request)
        switch response.statusCode {
        case 201:
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .custom { decoder in
                let string = try decoder.singleValueContainer().decode(String.self)
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                guard let date = formatter.date(from: string) else {
                    throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: string))
                }
                return date
            }
            return try decoder.decode(Shared.self, from: data)
        case 413: throw Failure.tooLarge
        case 429: throw Failure.tooManyShares
        default: throw Failure.server
        }
    }

    static func redeem(code: String) async throws -> DeckFile {
        var request = URLRequest(url: baseURL.appendingPathComponent(code))
        request.setValue(installID, forHTTPHeaderField: "X-Install-ID")

        let (data, response) = try await send(request)
        switch response.statusCode {
        case 200:
            return try DeckFile.read(from: data)
        case 404:
            let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            throw Failure.wrongCode(guessesRemaining: body?["guessesRemaining"] as? Int)
        case 429:
            let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let seconds = body?["retryAfterSeconds"] as? Int ?? 3600
            throw Failure.locked(minutes: max(1, Int((Double(seconds) / 60).rounded(.up))))
        default:
            throw Failure.server
        }
    }

    static func stopSharing(code: String, ownerToken: String) async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent(code))
        request.httpMethod = "DELETE"
        request.setValue(ownerToken, forHTTPHeaderField: "X-Owner-Token")
        let (_, response) = try await send(request)
        guard response.statusCode == 204 else { throw Failure.server }
    }

    // MARK: - Plumbing

    private static func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw Failure.server }
            return (data, http)
        } catch let error as Failure {
            throw error
        } catch {
            throw Failure.noConnection
        }
    }

    /// Random, made on this phone, never tied to a person. Its only job is to
    /// let the server count wrong guesses per phone rather than per Wi-Fi.
    private static var installID: String {
        let key = "codeShareInstallID"
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let fresh = UUID().uuidString
        UserDefaults.standard.set(fresh, forKey: key)
        return fresh
    }
}
