import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let api = MayarAPI()
    private var refreshTimer: Timer?

    private var balance: BalanceResponse.Balance?
    private var paid: [PaidTransaction] = []
    private var unpaid: [UnpaidTransaction] = []
    private var lastError: String?
    private var isLoading = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.title = "Mayar …"
            button.image = NSImage(systemSymbolName: "creditcard", accessibilityDescription: "Mayar")
            button.imagePosition = .imageLeading
        }

        api.config = ConfigStore.load()
        rebuildMenu()
        if api.config == nil {
            promptForAPIKey(initial: true)
        } else {
            refresh()
        }

        refreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    // MARK: - Refresh

    @objc private func refresh() {
        guard !isLoading, let _ = api.config else { return }
        isLoading = true
        rebuildMenu()
        Task { [weak self] in
            guard let self = self else { return }
            do {
                async let b = self.api.balance()
                async let p = self.api.paidTransactions(pageSize: 8)
                async let u = self.api.unpaidTransactions(pageSize: 5)
                let (balance, paid, unpaid) = try await (b, p, u)
                await MainActor.run {
                    self.balance = balance
                    self.paid = paid
                    self.unpaid = unpaid
                    self.lastError = nil
                    self.isLoading = false
                    self.rebuildMenu()
                }
            } catch {
                await MainActor.run {
                    self.lastError = (error as? LocalizedError)?.errorDescription ?? "\(error)"
                    self.isLoading = false
                    self.rebuildMenu()
                }
            }
        }
    }

    // MARK: - Menu

    private func rebuildMenu() {
        let menu = NSMenu()

        if api.config == nil {
            menu.addItem(disabled("API key not set"))
            menu.addItem(NSMenuItem.separator())
            menu.addItem(action("Set API Key…", #selector(setAPIKeyAction)))
        } else if let b = balance {
            if let button = statusItem.button {
                button.title = Format.shortRupiah(b.balance)
            }
            menu.addItem(disabled("Active     \(Format.rupiah(b.balanceActive))"))
            menu.addItem(disabled("Pending  \(Format.rupiah(b.balancePending))"))
            menu.addItem(disabled("Total      \(Format.rupiah(b.balance))"))
            menu.addItem(NSMenuItem.separator())

            if !unpaid.isEmpty {
                let header = disabled("Unpaid (\(unpaid.count))")
                menu.addItem(header)
                for tx in unpaid.prefix(5) {
                    menu.addItem(unpaidItem(tx))
                }
                menu.addItem(NSMenuItem.separator())
            }

            menu.addItem(disabled("Recent paid"))
            if paid.isEmpty {
                menu.addItem(disabled("  (none yet)"))
            } else {
                for tx in paid.prefix(8) {
                    menu.addItem(paidItem(tx))
                }
            }
            menu.addItem(NSMenuItem.separator())
        } else if isLoading {
            statusItem.button?.title = "Mayar …"
            menu.addItem(disabled("Loading…"))
            menu.addItem(NSMenuItem.separator())
        }

        if let err = lastError {
            statusItem.button?.title = "Mayar !"
            menu.addItem(disabled("Error: \(err)"))
            menu.addItem(NSMenuItem.separator())
        }

        if let cfg = api.config {
            menu.addItem(disabled("Env: \(cfg.environment.rawValue)"))
        }
        menu.addItem(action("Refresh", #selector(refreshAction), key: "r"))
        menu.addItem(action("Open Mayar Dashboard", #selector(openDashboardAction)))

        let settings = NSMenu()
        settings.addItem(action("Set API Key…", #selector(setAPIKeyAction)))
        settings.addItem(NSMenuItem.separator())
        let prodItem = action("Use Production", #selector(useProductionAction))
        prodItem.state = api.config?.environment == .production ? .on : .off
        settings.addItem(prodItem)
        let sandItem = action("Use Sandbox", #selector(useSandboxAction))
        sandItem.state = api.config?.environment == .sandbox ? .on : .off
        settings.addItem(sandItem)
        settings.addItem(NSMenuItem.separator())
        let loginItem = action("Launch at Login", #selector(toggleLaunchAtLoginAction))
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        settings.addItem(loginItem)
        let settingsItem = NSMenuItem(title: "Settings", action: nil, keyEquivalent: "")
        settingsItem.submenu = settings
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(action("Quit", #selector(quitAction), key: "q"))

        statusItem.menu = menu
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func action(_ title: String, _ selector: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        item.target = self
        return item
    }

    private func paidItem(_ tx: PaidTransaction) -> NSMenuItem {
        let amount = Format.rupiah(tx.credit ?? 0)
        let who = tx.customer?.name ?? tx.customer?.email ?? "—"
        let when = tx.createdAt.map(Format.relativeTime) ?? ""
        let title = "  +\(amount)  \(who)  \(when)"
        let item = NSMenuItem(title: title, action: #selector(copyTxIdAction(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = tx.id
        item.toolTip = [tx.paymentLink?.name, tx.paymentMethod, tx.balanceHistoryType]
            .compactMap { $0 }
            .joined(separator: " · ")
        return item
    }

    private func unpaidItem(_ tx: UnpaidTransaction) -> NSMenuItem {
        let amount = Format.rupiah(tx.amount ?? 0)
        let who = tx.customer?.name ?? tx.customer?.email ?? "—"
        let title = "  \(amount)  \(who)  ↗"
        let item = NSMenuItem(title: title, action: #selector(openUnpaidURLAction(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = tx.paymentUrl
        item.toolTip = "Open payment URL"
        return item
    }

    // MARK: - Actions

    @objc private func refreshAction() { refresh() }

    @objc private func quitAction() { NSApp.terminate(nil) }

    @objc private func openDashboardAction() {
        let url = api.config?.environment == .sandbox
            ? URL(string: "https://web.mayar.club")!
            : URL(string: "https://web.mayar.id")!
        NSWorkspace.shared.open(url)
    }

    @objc private func copyTxIdAction(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(id, forType: .string)
    }

    @objc private func openUnpaidURLAction(_ sender: NSMenuItem) {
        guard let s = sender.representedObject as? String, let url = URL(string: s) else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func setAPIKeyAction() { promptForAPIKey(initial: false) }

    @objc private func useProductionAction() { switchEnv(.production) }
    @objc private func useSandboxAction() { switchEnv(.sandbox) }

    @objc private func toggleLaunchAtLoginAction() {
        let service = SMAppService.mainApp
        do {
            switch service.status {
            case .enabled:
                try service.unregister()
            case .requiresApproval:
                SMAppService.openSystemSettingsLoginItems()
            default:
                try service.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't toggle Launch at Login"
            alert.informativeText = """
            \(error.localizedDescription)

            This usually means the app isn't running from a proper bundle. \
            Build with scripts/build-app.sh, copy MayarMenuBar.app into \
            /Applications, and try again from there.
            """
            alert.runModal()
        }
        rebuildMenu()
    }

    private func switchEnv(_ env: Config.Environment) {
        guard var cfg = api.config else {
            promptForAPIKey(initial: true)
            return
        }
        cfg.environment = env
        try? ConfigStore.save(cfg)
        api.config = cfg
        refresh()
    }

    private func promptForAPIKey(initial: Bool) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = initial ? "Set Mayar API key" : "Update Mayar API key"
        alert.informativeText = "Bearer token from web.mayar.id/api-keys (or web.mayar.club for sandbox)."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let stack = NSStackView(frame: NSRect(x: 0, y: 0, width: 320, height: 56))
        stack.orientation = .vertical
        stack.spacing = 6
        stack.alignment = .leading

        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.placeholderString = "mayar_xxx…"
        if let existing = api.config?.apiKey { field.stringValue = existing }
        stack.addArrangedSubview(field)

        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 320, height: 24), pullsDown: false)
        popup.addItems(withTitles: ["Production", "Sandbox"])
        popup.selectItem(at: api.config?.environment == .sandbox ? 1 : 0)
        stack.addArrangedSubview(popup)

        alert.accessoryView = stack
        alert.window.initialFirstResponder = field

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }
        let key = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        let env: Config.Environment = popup.indexOfSelectedItem == 1 ? .sandbox : .production
        let cfg = Config(apiKey: key, environment: env)
        do {
            try ConfigStore.save(cfg)
            api.config = cfg
            refresh()
        } catch {
            let e = NSAlert()
            e.messageText = "Couldn't save config"
            e.informativeText = "\(error)"
            e.runModal()
        }
    }
}
