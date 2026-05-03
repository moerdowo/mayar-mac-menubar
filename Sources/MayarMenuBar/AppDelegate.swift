import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private let vc = BalanceViewController()
    private let api = MayarAPI()
    private var refreshTimer: Timer?
    private var eventMonitor: Any?

    private var balance: BalanceResponse.Balance?
    private var paid: [PaidTransaction] = []
    private var paidPage = 1
    private var paidPageInfo = PageInfo.unknown
    private var unpaid: [UnpaidTransaction] = []
    private var unpaidPage = 1
    private var unpaidPageInfo = PageInfo.unknown
    private var products: [Product] = []
    private var productsPage = 1
    private var productsPageInfo = PageInfo.unknown
    private var lastError: String?
    private var isLoading = false
    private var paginatingTab: BalanceViewController.Tab?

    private let pageSize = 10

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            applyStatusBarIcon(to: button)
            button.imagePosition = .imageLeading
            button.title = " Mayar"
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentViewController = vc

        vc.onRefresh = { [weak self] in self?.refresh() }
        vc.onSettings = { [weak self] in self?.showSettingsMenu() }
        vc.onOpenURL = { url in NSWorkspace.shared.open(url) }
        vc.onTabChanged = { _ in /* tab is local UI state */ }
        vc.onPrevPage = { [weak self] tab in self?.changePage(tab: tab, delta: -1) }
        vc.onNextPage = { [weak self] tab in self?.changePage(tab: tab, delta: +1) }

        // Force loadView() to run now, so subsequent render() calls operate on
        // a real, attached view hierarchy.
        _ = vc.view

        api.config = ConfigStore.load()
        applyAppearancePreference()
        renderState()
        if api.config == nil {
            promptForAPIKey(initial: true)
        } else {
            refresh()
        }

        refreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    // MARK: - Status item icon

    private static let statusBarIcon: NSImage? = {
        guard let url = Bundle.main.url(forResource: "MayarLogo", withExtension: "svg") else {
            NSLog("[Mayar] MayarLogo.svg not in bundle")
            return nil
        }
        guard let img = NSImage(contentsOf: url) else {
            NSLog("[Mayar] NSImage failed to load MayarLogo.svg")
            return nil
        }
        let h: CGFloat = 18
        let w: CGFloat = h * (133.95 / 108.0)  // preserve aspect
        img.size = NSSize(width: w, height: h)
        // Template image: macOS uses only the alpha channel and tints to match
        // the menu bar appearance (white in dark menu bar, black in light).
        img.isTemplate = true
        NSLog("[Mayar] menu bar icon ready: \(w)x\(h) (template)")
        return img
    }()

    private func applyStatusBarIcon(to button: NSStatusBarButton) {
        if let logo = AppDelegate.statusBarIcon {
            button.image = logo
        } else {
            button.image = NSImage(systemSymbolName: "creditcard", accessibilityDescription: "Mayar")
        }
    }

    // MARK: - Appearance

    private func applyAppearancePreference() {
        let appearance = api.config?.appearance ?? .light
        vc.applyAppearance(appearance)
    }

    // MARK: - Status item interaction

    @objc private func statusItemClicked(_ sender: Any?) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            guard let button = statusItem.button else { return }
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            refresh()
            startMonitoringOutsideClicks()
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(item("Refresh", #selector(menuRefresh)))
        menu.addItem(item("Set API Key…", #selector(menuSetKey)))
        menu.addItem(item("Toggle Environment", #selector(menuToggleEnv)))
        menu.addItem(item("Launch at Login", #selector(menuToggleLogin)))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(item("Open Dashboard", #selector(menuDashboard)))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(item("Quit", #selector(menuQuit)))
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func showSettingsMenu() {
        let menu = buildSettingsMenu()
        if let win = popover.contentViewController?.view.window {
            let p = NSPoint(x: win.frame.maxX - 140, y: win.frame.maxY - 30)
            menu.popUp(positioning: nil, at: p, in: nil)
        } else {
            menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        }
    }

    private func buildSettingsMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(item("Set API Key…", #selector(menuSetKey)))
        menu.addItem(NSMenuItem.separator())

        // Environment
        let envItem = item("Environment: \(api.config?.environment.rawValue ?? "—") (toggle)",
                           #selector(menuToggleEnv))
        menu.addItem(envItem)

        // Hide balance toggle
        let hideItem = item("Hide Balance in Menu Bar", #selector(menuToggleHideBalance))
        hideItem.state = (api.config?.hideBalance ?? false) ? .on : .off
        menu.addItem(hideItem)

        // Appearance submenu
        let appearanceItem = NSMenuItem(title: "Appearance", action: nil, keyEquivalent: "")
        let appearanceSub = NSMenu()
        let current = api.config?.appearance ?? .light
        for opt in Theme.Appearance.allCases {
            let mi = item(appearanceLabel(opt), #selector(menuPickAppearance(_:)))
            mi.tag = appearanceTag(opt)
            mi.state = (opt == current) ? .on : .off
            appearanceSub.addItem(mi)
        }
        appearanceItem.submenu = appearanceSub
        menu.addItem(appearanceItem)

        menu.addItem(item("Launch at Login", #selector(menuToggleLogin)))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(item("Open Dashboard", #selector(menuDashboard)))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(item("Quit", #selector(menuQuit)))
        return menu
    }

    private func appearanceLabel(_ a: Theme.Appearance) -> String {
        switch a {
        case .light:  return "Light"
        case .dark:   return "Dark"
        case .system: return "System"
        }
    }
    private func appearanceTag(_ a: Theme.Appearance) -> Int {
        switch a {
        case .light:  return 1
        case .dark:   return 2
        case .system: return 3
        }
    }
    private func appearance(forTag tag: Int) -> Theme.Appearance {
        switch tag {
        case 2: return .dark
        case 3: return .system
        default: return .light
        }
    }

    private func item(_ title: String, _ sel: Selector) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: sel, keyEquivalent: "")
        i.target = self
        return i
    }

    @objc private func menuRefresh() { refresh() }
    @objc private func menuSetKey() { promptForAPIKey(initial: false) }
    @objc private func menuToggleEnv() { toggleEnv() }
    @objc private func menuToggleLogin() { toggleLaunchAtLogin() }
    @objc private func menuDashboard() { openDashboard() }
    @objc private func menuQuit() { NSApp.terminate(nil) }

    @objc private func menuToggleHideBalance() {
        guard var cfg = api.config else { return }
        cfg.hideBalance.toggle()
        try? ConfigStore.save(cfg)
        api.config = cfg
        renderState()
    }

    @objc private func menuPickAppearance(_ sender: NSMenuItem) {
        guard var cfg = api.config else { return }
        cfg.appearance = appearance(forTag: sender.tag)
        try? ConfigStore.save(cfg)
        api.config = cfg
        applyAppearancePreference()
    }

    private func startMonitoringOutsideClicks() {
        if eventMonitor != nil { return }
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self = self, self.popover.isShown else { return }
            self.popover.performClose(nil)
        }
    }

    func popoverDidClose(_ notification: Notification) {
        if let m = eventMonitor { NSEvent.removeMonitor(m); eventMonitor = nil }
    }

    // MARK: - Pagination

    private func changePage(tab: BalanceViewController.Tab, delta: Int) {
        var didChange = false
        switch tab {
        case .paid:
            let next = max(1, paidPage + delta)
            if next != paidPage && (delta < 0 || paidPageInfo.hasMore || next <= paidPageInfo.pageCount) {
                paidPage = next; didChange = true
            }
        case .unpaid:
            let next = max(1, unpaidPage + delta)
            if next != unpaidPage && (delta < 0 || unpaidPageInfo.hasMore || next <= unpaidPageInfo.pageCount) {
                unpaidPage = next; didChange = true
            }
        case .products:
            let next = max(1, productsPage + delta)
            if next != productsPage && (delta < 0 || productsPageInfo.hasMore || next <= productsPageInfo.pageCount) {
                productsPage = next; didChange = true
            }
        }
        if didChange {
            paginatingTab = tab
            vc.paginatingTab = tab
            refresh()
        }
    }

    // MARK: - Refresh

    @objc private func refresh() {
        guard !isLoading else { return }
        guard api.config != nil else { renderState(); return }
        isLoading = true
        if balance == nil { renderState() }

        Task { [weak self] in
            guard let self = self else { return }
            do {
                async let bResp = self.api.balance()
                async let pResp = self.api.paidTransactions(page: self.paidPage, pageSize: self.pageSize)
                async let uResp = self.api.unpaidTransactions(page: self.unpaidPage, pageSize: self.pageSize)
                async let prResp = self.api.products(page: self.productsPage, pageSize: self.pageSize)
                let (b, p, u, pr) = try await (bResp, pResp, uResp, prResp)
                await MainActor.run {
                    self.balance = b
                    self.paid = p.data
                    self.paidPageInfo = p.pageInfo
                    self.unpaid = u.data
                    self.unpaidPageInfo = u.pageInfo
                    self.products = pr.data
                    self.productsPageInfo = pr.pageInfo
                    self.lastError = nil
                    self.isLoading = false
                    self.paginatingTab = nil
                    self.vc.paginatingTab = nil
                    self.renderState()
                }
            } catch {
                await MainActor.run {
                    self.lastError = (error as? LocalizedError)?.errorDescription ?? "\(error)"
                    self.isLoading = false
                    self.paginatingTab = nil
                    self.vc.paginatingTab = nil
                    self.renderState()
                }
            }
        }
    }

    private func renderState() {
        let hide = api.config?.hideBalance ?? false
        if hide {
            // Just the icon — no text at all.
            statusItem.button?.title = ""
        } else if let b = balance {
            statusItem.button?.title = " " + Format.shortRupiah(b.balance)
        } else if api.config == nil {
            statusItem.button?.title = " Mayar"
        } else if isLoading {
            statusItem.button?.title = " …"
        } else {
            statusItem.button?.title = " Mayar"
        }

        if api.config == nil {
            vc.render(.unconfigured)
        } else if let err = lastError, balance == nil {
            vc.render(.error(err))
        } else if let b = balance {
            vc.render(.loaded(.init(
                balance: b,
                paid: paid, paidPage: paidPageInfo,
                unpaid: unpaid, unpaidPage: unpaidPageInfo,
                products: products, productsPage: productsPageInfo
            )))
        } else {
            vc.render(.loading)
        }
    }

    // MARK: - Settings actions

    private func toggleEnv() {
        guard var cfg = api.config else { promptForAPIKey(initial: true); return }
        cfg.environment = cfg.environment == .production ? .sandbox : .production
        try? ConfigStore.save(cfg)
        api.config = cfg
        balance = nil; paid = []; unpaid = []; products = []
        paidPage = 1; unpaidPage = 1; productsPage = 1
        refresh()
    }

    private func openDashboard() {
        let url = api.config?.environment == .sandbox
            ? URL(string: "https://web.mayar.club")!
            : URL(string: "https://web.mayar.id")!
        NSWorkspace.shared.open(url)
    }

    private func toggleLaunchAtLogin() {
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
            balance = nil
            refresh()
        } catch {
            let e = NSAlert()
            e.messageText = "Couldn't save config"
            e.informativeText = "\(error)"
            e.runModal()
        }
    }
}
