import Foundation

struct Config: Codable {
    var apiKey: String
    var environment: Environment
    var hideBalance: Bool = false
    var appearance: Theme.Appearance = .light

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

    // Custom decoding so older config files (without the new fields) still
    // load instead of failing.
    enum CodingKeys: String, CodingKey {
        case apiKey, environment, hideBalance, appearance
    }
    init(apiKey: String, environment: Environment,
         hideBalance: Bool = false, appearance: Theme.Appearance = .light) {
        self.apiKey = apiKey
        self.environment = environment
        self.hideBalance = hideBalance
        self.appearance = appearance
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        apiKey = try c.decode(String.self, forKey: .apiKey)
        environment = try c.decode(Environment.self, forKey: .environment)
        hideBalance = (try? c.decode(Bool.self, forKey: .hideBalance)) ?? false
        appearance = (try? c.decode(Theme.Appearance.self, forKey: .appearance)) ?? .light
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
            // Production-only now; the MAYAR_ENV override has been removed.
            return Config(apiKey: key, environment: .production)
        }
        guard let data = try? Data(contentsOf: fileURL),
              var cfg = try? JSONDecoder().decode(Config.self, from: data) else {
            return nil
        }
        // Migrate older configs that used the sandbox environment — sandbox is
        // no longer supported by the app, so silently flip to production.
        if cfg.environment != .production {
            cfg.environment = .production
            try? save(cfg)
        }
        return cfg
    }

    static func save(_ config: Config) throws {
        let data = try JSONEncoder().encode(config)
        try data.write(to: fileURL, options: [.atomic])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }
}
