import Foundation

struct BalanceResponse: Decodable {
    let data: Balance
    struct Balance: Decodable {
        let balanceActive: Int
        let balancePending: Int
        let balance: Int
    }
}

struct PaidTransactionsResponse: Decodable {
    let data: [PaidTransaction]
    let hasMore: Bool?
    let page: Int?
    let pageCount: Int?
}

struct PaidTransaction: Decodable {
    let id: String
    let credit: Int?
    let status: String?
    let balanceHistoryType: String?
    let paymentMethod: String?
    let createdAt: Double?
    let customer: Customer?
    let paymentLink: PaymentLinkRef?

    struct Customer: Decodable {
        let name: String?
        let email: String?
    }
    struct PaymentLinkRef: Decodable {
        let name: String?
    }
}

struct UnpaidTransactionsResponse: Decodable {
    let data: [UnpaidTransaction]
    let hasMore: Bool?
    let page: Int?
    let pageCount: Int?
    let total: Int?
}

struct ProductsResponse: Decodable {
    let data: [Product]
    let hasMore: Bool?
    let page: Int?
    let pageCount: Int?
    let total: Int?
}

// MARK: - Page metadata

struct PageInfo {
    let page: Int
    let pageCount: Int
    let hasMore: Bool
    static let unknown = PageInfo(page: 1, pageCount: 1, hasMore: false)
}

extension PaidTransactionsResponse {
    var pageInfo: PageInfo {
        PageInfo(page: page ?? 1, pageCount: max(pageCount ?? 1, 1), hasMore: hasMore ?? false)
    }
}
extension UnpaidTransactionsResponse {
    var pageInfo: PageInfo {
        PageInfo(page: page ?? 1, pageCount: max(pageCount ?? 1, 1), hasMore: hasMore ?? false)
    }
}
extension ProductsResponse {
    var pageInfo: PageInfo {
        PageInfo(page: page ?? 1, pageCount: max(pageCount ?? 1, 1), hasMore: hasMore ?? false)
    }
}

struct Product: Decodable {
    let id: String
    let name: String
    let link: String?           // unique slug
    let type: String?           // "membership", "saas", "event", …
    let status: String?         // "active" / "inactive"
    let amount: Int?            // price (IDR) — nullable
    let category: String?
    let createdAt: Double?
    let linkUrl: String?        // public product page
    let linkPayment: String?    // customer checkout URL
}

struct UnpaidTransaction: Decodable {
    let id: String
    let type: String?
    let amount: Int?
    let status: String?
    let createdAt: Double?
    let paymentUrl: String?
    let customer: PaidTransaction.Customer?
    let paymentLink: PaidTransaction.PaymentLinkRef?
}

enum MayarAPIError: Error, LocalizedError {
    case missingConfig
    case http(Int, String)
    case transport(Error)
    case decoding(Error)

    var errorDescription: String? {
        switch self {
        case .missingConfig: return "API key not set"
        case .http(let code, let body): return "HTTP \(code): \(body.prefix(200))"
        case .transport(let e): return e.localizedDescription
        case .decoding(let e): return "Decode error: \(e)"
        }
    }
}

final class MayarAPI {
    private let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 15
        cfg.waitsForConnectivity = false
        return URLSession(configuration: cfg)
    }()

    var config: Config?

    func balance() async throws -> BalanceResponse.Balance {
        let resp: BalanceResponse = try await get(path: "/hl/v1/balance")
        return resp.data
    }

    func paidTransactions(page: Int = 1, pageSize: Int = 10) async throws -> PaidTransactionsResponse {
        return try await get(
            path: "/hl/v1/transactions",
            query: [URLQueryItem(name: "page", value: String(page)),
                    URLQueryItem(name: "pageSize", value: String(pageSize))]
        )
    }

    func unpaidTransactions(page: Int = 1, pageSize: Int = 10) async throws -> UnpaidTransactionsResponse {
        return try await get(
            path: "/hl/v1/transactions/unpaid",
            query: [URLQueryItem(name: "page", value: String(page)),
                    URLQueryItem(name: "pageSize", value: String(pageSize))]
        )
    }

    func products(page: Int = 1, pageSize: Int = 10) async throws -> ProductsResponse {
        return try await get(
            path: "/hl/v1/product",
            query: [URLQueryItem(name: "page", value: String(page)),
                    URLQueryItem(name: "pageSize", value: String(pageSize))]
        )
    }

    private func get<T: Decodable>(path: String, query: [URLQueryItem] = []) async throws -> T {
        guard let config = config else { throw MayarAPIError.missingConfig }
        var components = URLComponents(url: config.environment.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var req = URLRequest(url: components.url!)
        req.httpMethod = "GET"
        req.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw MayarAPIError.transport(error)
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw MayarAPIError.http(http.statusCode, body)
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw MayarAPIError.decoding(error)
        }
    }
}
