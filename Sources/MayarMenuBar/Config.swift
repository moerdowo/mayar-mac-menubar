import Foundation

struct Config: Codable {
    var apiKey: String
    var environment: Environment

    enum Environment: String, Codable {
        case production
        case sandbox

        var baseURL: URL {
            switch self {
            case .production: return URL(string: "https://api.mayar.id")!
            case .sandbox:    return URL(string: "https://api.mayar.club")!
            }
        }
    }
}

enum ConfigStore {
    static let fileURL: URL = {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("MayarMenuBar", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("config.json")
    }()

    static func load() -> Config? {
        if let key = ProcessInfo.processInfo.environment["MAYAR_API_KEY"], !key.isEmpty {
            let envName = ProcessInfo.processInfo.environment["MAYAR_ENV"] ?? "production"
            let env = Config.Environment(rawValue: envName) ?? .production
            return Config(apiKey: key, environment: env)
        }
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(Config.self, from: data)
    }

    static func save(_ config: Config) throws {
        let data = try JSONEncoder().encode(config)
        try data.write(to: fileURL, options: [.atomic])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }
}
