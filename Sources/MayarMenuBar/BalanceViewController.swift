import AppKit

final class BalanceViewController: NSViewController {

    enum Tab: Int { case paid, unpaid, products }

    struct LoadedData {
        let balance: BalanceResponse.Balance?
        let paid: [PaidTransaction]
        let paidPage: PageInfo
        let unpaid: [UnpaidTransaction]
        let unpaidPage: PageInfo
        let products: [Product]
        let productsPage: PageInfo
    }

    // Callbacks
    var onRefresh: (() -> Void)?
    var onSettings: (() -> Void)?
    var onTabChanged: ((Tab) -> Void)?
    var onOpenURL: ((URL) -> Void)?
    var onPrevPage: ((Tab) -> Void)?
    var onNextPage: ((Tab) -> Void)?

    /// Set by AppDelegate while a tab's pagination request is in flight.
    /// renderList shows skeletons for that specific tab.
    var paginatingTab: Tab? {
        didSet { if oldValue != paginatingTab { renderList() } }
    }

    // Header
    private let logoView = NSImageView()
    private let brandLabel = makeLabel("Mayar", font: Theme.font(15, .semibold), color: Theme.textPrimary)
    private let refreshBtn = IconButton(symbol: "arrow.clockwise", accessibility: "Refresh")
    private let settingsBtn = IconButton(symbol: "gearshape", accessibility: "Settings")

    // Balance card
    private let balanceCard = RoundedView()
    private let totalCaption = makeKernLabel("TOTAL BALANCE",
                                             font: Theme.font(11, .medium),
                                             color: Theme.textSecondary,
                                             kern: 1.0)
    private let totalAmount = makeLabel("—", font: Theme.font(28, .bold), color: Theme.textPrimary)
    private let activeCaption = makeLabel("Active", font: Theme.font(12), color: Theme.textSecondary)
    private let activeAmount = makeLabel("—", font: Theme.font(15, .semibold), color: Theme.textPrimary)
    private let pendingCaption = makeLabel("Pending", font: Theme.font(12), color: Theme.textSecondary)
    private let pendingAmount = makeLabel("—", font: Theme.font(15, .semibold), color: Theme.textPrimary)

    // Tabs
    private let paidTab = TabButton(title: "Paid")
    private let unpaidTab = TabButton(title: "Unpaid")
    private let productsTab = TabButton(title: "Products")

    // Content
    private let scrollView = NSScrollView()
    private let contentStack = FlippedStackView()
    private let emptyLabel = makeLabel("nothing to show yet", font: Theme.font(12), color: Theme.textTertiary, alignment: .center)
    private let statusLabel = makeLabel("", font: Theme.font(12), color: Theme.textSecondary, alignment: .center)

    // Pagination bar
    private let prevBtn = SoftButton(title: "‹ Prev")
    private let nextBtn = SoftButton(title: "Next ›")
    private let pageLabel = makeLabel("1 / 1", font: Theme.font(11, .medium), color: Theme.textSecondary, alignment: .center)
    private let paginationBar = NSView()

    private var currentTab: Tab = .paid
    private var lastBalance: BalanceResponse.Balance?
    private var lastPaid: [PaidTransaction] = []
    private var lastPaidPage: PageInfo = .unknown
    private var lastUnpaid: [UnpaidTransaction] = []
    private var lastUnpaidPage: PageInfo = .unknown
    private var lastProducts: [Product] = []
    private var lastProductsPage: PageInfo = .unknown
    private var lastError: String?
    private var unconfigured = false

    override func loadView() {
        let v = AppearanceAwareView(frame: NSRect(x: 0, y: 0, width: 380, height: 620))
        v.fillColor = Theme.windowBg
        v.appearance = NSAppearance(named: .aqua)
        view = v
        buildLayout()
    }

    /// Apply the user's chosen appearance to this entire popover (and trigger
    /// `updateLayer` cascades so layer-backed views recolor).
    func applyAppearance(_ appearance: Theme.Appearance) {
        view.appearance = appearance.nsAppearance
        // Force walk-and-update for cleanup on appearance toggle.
        propagateUpdateLayer(view)
    }

    private func propagateUpdateLayer(_ v: NSView) {
        v.needsDisplay = true
        if v.wantsLayer { v.layer?.setNeedsDisplay() }
        for sub in v.subviews { propagateUpdateLayer(sub) }
    }

    // MARK: - Layout

    private func buildLayout() {
        // Header
        let header = AppearanceAwareView()
        header.fillColor = Theme.headerBg
        header.translatesAutoresizingMaskIntoConstraints = false

        let headerBorder = AppearanceAwareView()
        headerBorder.fillColor = Theme.cardBorder
        headerBorder.translatesAutoresizingMaskIntoConstraints = false

        logoView.image = Self.appIconImage
        logoView.imageScaling = .scaleProportionallyUpOrDown
        logoView.translatesAutoresizingMaskIntoConstraints = false

        refreshBtn.target = self; refreshBtn.action = #selector(refreshTapped(_:))
        settingsBtn.target = self; settingsBtn.action = #selector(settingsTapped(_:))

        header.addSubview(logoView)
        header.addSubview(brandLabel)
        header.addSubview(refreshBtn)
        header.addSubview(settingsBtn)
        header.addSubview(headerBorder)
        brandLabel.translatesAutoresizingMaskIntoConstraints = false
        refreshBtn.translatesAutoresizingMaskIntoConstraints = false
        settingsBtn.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            logoView.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 16),
            logoView.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            logoView.widthAnchor.constraint(equalToConstant: 28),
            logoView.heightAnchor.constraint(equalToConstant: 28),
            brandLabel.leadingAnchor.constraint(equalTo: logoView.trailingAnchor, constant: 10),
            brandLabel.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            settingsBtn.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -16),
            settingsBtn.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            refreshBtn.trailingAnchor.constraint(equalTo: settingsBtn.leadingAnchor, constant: -8),
            refreshBtn.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            headerBorder.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            headerBorder.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            headerBorder.bottomAnchor.constraint(equalTo: header.bottomAnchor),
            headerBorder.heightAnchor.constraint(equalToConstant: 1),
        ])

        // Balance card
        balanceCard.cornerRadius = 14
        balanceCard.borderWidth = 1
        balanceCard.borderColor = Theme.balanceBorder
        balanceCard.fillColor = .clear
        balanceCard.setGradient(top: Theme.balanceBgTop, bottom: Theme.balanceBgBot)
        balanceCard.translatesAutoresizingMaskIntoConstraints = false

        let topRow = NSStackView(views: [totalCaption])
        topRow.orientation = .horizontal

        let leftCol = NSStackView(views: [activeCaption, activeAmount])
        leftCol.orientation = .vertical
        leftCol.alignment = .leading
        leftCol.spacing = 4

        let rightCol = NSStackView(views: [pendingCaption, pendingAmount])
        rightCol.orientation = .vertical
        rightCol.alignment = .leading
        rightCol.spacing = 4

        let twoCol = NSStackView(views: [leftCol, rightCol])
        twoCol.orientation = .horizontal
        twoCol.distribution = .fillEqually
        twoCol.spacing = 16

        let cardStack = NSStackView(views: [topRow, totalAmount, twoCol])
        cardStack.orientation = .vertical
        cardStack.alignment = .leading
        cardStack.spacing = 6
        cardStack.setCustomSpacing(14, after: totalAmount)
        cardStack.translatesAutoresizingMaskIntoConstraints = false
        balanceCard.addSubview(cardStack)
        NSLayoutConstraint.activate([
            cardStack.leadingAnchor.constraint(equalTo: balanceCard.leadingAnchor, constant: 16),
            cardStack.trailingAnchor.constraint(equalTo: balanceCard.trailingAnchor, constant: -16),
            cardStack.topAnchor.constraint(equalTo: balanceCard.topAnchor, constant: 16),
            cardStack.bottomAnchor.constraint(equalTo: balanceCard.bottomAnchor, constant: -16),
        ])

        // Tabs
        for (i, t) in [paidTab, unpaidTab, productsTab].enumerated() {
            t.target = self
            t.action = #selector(tabTapped(_:))
            t.tag = i
        }
        paidTab.isSelectedTab = true

        let tabStrip = NSStackView(views: [paidTab, unpaidTab, productsTab, NSView()])
        tabStrip.orientation = .horizontal
        tabStrip.spacing = 8
        tabStrip.alignment = .centerY
        tabStrip.translatesAutoresizingMaskIntoConstraints = false

        // Scroll content
        contentStack.orientation = .vertical
        contentStack.spacing = 8
        contentStack.alignment = .leading
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.autohidesScrollers = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = contentStack

        // Pagination bar
        prevBtn.target = self; prevBtn.action = #selector(prevPageTapped(_:))
        nextBtn.target = self; nextBtn.action = #selector(nextPageTapped(_:))
        paginationBar.translatesAutoresizingMaskIntoConstraints = false
        prevBtn.translatesAutoresizingMaskIntoConstraints = false
        nextBtn.translatesAutoresizingMaskIntoConstraints = false
        pageLabel.translatesAutoresizingMaskIntoConstraints = false
        paginationBar.addSubview(prevBtn)
        paginationBar.addSubview(pageLabel)
        paginationBar.addSubview(nextBtn)
        NSLayoutConstraint.activate([
            prevBtn.leadingAnchor.constraint(equalTo: paginationBar.leadingAnchor),
            prevBtn.centerYAnchor.constraint(equalTo: paginationBar.centerYAnchor),
            nextBtn.trailingAnchor.constraint(equalTo: paginationBar.trailingAnchor),
            nextBtn.centerYAnchor.constraint(equalTo: paginationBar.centerYAnchor),
            pageLabel.centerXAnchor.constraint(equalTo: paginationBar.centerXAnchor),
            pageLabel.centerYAnchor.constraint(equalTo: paginationBar.centerYAnchor),
        ])

        // Compose
        view.addSubview(header)
        view.addSubview(balanceCard)
        view.addSubview(tabStrip)
        view.addSubview(scrollView)
        view.addSubview(paginationBar)
        view.addSubview(statusLabel)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            header.topAnchor.constraint(equalTo: view.topAnchor),
            header.heightAnchor.constraint(equalToConstant: 56),

            balanceCard.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            balanceCard.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            balanceCard.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 12),

            tabStrip.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            tabStrip.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            tabStrip.topAnchor.constraint(equalTo: balanceCard.bottomAnchor, constant: 14),

            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            scrollView.topAnchor.constraint(equalTo: tabStrip.bottomAnchor, constant: 12),
            scrollView.bottomAnchor.constraint(equalTo: paginationBar.topAnchor, constant: -8),

            paginationBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            paginationBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            paginationBar.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -10),
            paginationBar.heightAnchor.constraint(equalToConstant: 30),

            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            contentStack.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            contentStack.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),

            statusLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),
        ])
    }

    // MARK: - State / render

    enum State {
        case unconfigured
        case loading
        case loaded(LoadedData)
        case error(String)
    }

    func render(_ state: State) {
        switch state {
        case .unconfigured:
            NSLog("[Mayar] render: unconfigured")
            unconfigured = true
            totalAmount.stringValue = "—"
            activeAmount.stringValue = "—"
            pendingAmount.stringValue = "—"
            statusLabel.stringValue = "no api key — open settings"
            statusLabel.isHidden = false
            renderList()
        case .loading:
            NSLog("[Mayar] render: loading (have prior data: \(lastBalance != nil))")
            unconfigured = false
            statusLabel.isHidden = true
            if lastBalance == nil {
                totalAmount.stringValue = " "
                activeAmount.stringValue = " "
                pendingAmount.stringValue = " "
                renderSkeletons()
            }
        case .loaded(let d):
            NSLog("[Mayar] render: loaded paid=\(d.paid.count) unpaid=\(d.unpaid.count) products=\(d.products.count)")
            unconfigured = false
            lastBalance = d.balance
            lastPaid = d.paid; lastPaidPage = d.paidPage
            lastUnpaid = d.unpaid; lastUnpaidPage = d.unpaidPage
            lastProducts = d.products; lastProductsPage = d.productsPage
            lastError = nil
            if let b = d.balance {
                totalAmount.stringValue = Format.rupiah(b.balance)
                activeAmount.stringValue = Format.rupiah(b.balanceActive)
                pendingAmount.stringValue = Format.rupiah(b.balancePending)
            }
            statusLabel.isHidden = true
            renderList()
        case .error(let msg):
            NSLog("[Mayar] render: error: \(msg)")
            unconfigured = false
            lastError = msg
            statusLabel.stringValue = "error: \(msg)"
            statusLabel.isHidden = false
            if lastBalance == nil { clearList() }
        }
        updatePagination()
    }

    private func updatePagination() {
        let info: PageInfo
        switch currentTab {
        case .paid:     info = lastPaidPage
        case .unpaid:   info = lastUnpaidPage
        case .products: info = lastProductsPage
        }
        if unconfigured {
            paginationBar.isHidden = true
            return
        }
        paginationBar.isHidden = false
        pageLabel.stringValue = "\(info.page) / \(max(info.pageCount, 1))"
        prevBtn.isEnabled = info.page > 1
        nextBtn.isEnabled = info.hasMore || info.page < info.pageCount
    }

    func switchTab(_ tab: Tab) {
        currentTab = tab
        paidTab.isSelectedTab = tab == .paid
        unpaidTab.isSelectedTab = tab == .unpaid
        productsTab.isSelectedTab = tab == .products
        renderList()
        updatePagination()
    }

    private func clearList() {
        contentStack.arrangedSubviews.forEach {
            contentStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
    }

    /// Add a full-width row to the scroll content. Pins leading/trailing AFTER
    /// adding, so the constraints have a common ancestor and aren't dropped.
    private func addRow(_ row: NSView) {
        contentStack.addArrangedSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: contentStack.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: contentStack.trailingAnchor),
        ])
    }

    private func renderList() {
        clearList()
        if unconfigured { return }

        // While paginating the current tab, blank the cards and show skeletons
        // so the user gets immediate feedback that the page change is in flight.
        if let pt = paginatingTab, pt == currentTab {
            for _ in 0..<4 { addRow(skeletonCard()) }
            return
        }

        switch currentTab {
        case .paid:
            if lastPaid.isEmpty {
                addRow(emptyRow("no paid transactions"))
            } else {
                for tx in lastPaid { addRow(paidCard(tx)) }
            }
        case .unpaid:
            if lastUnpaid.isEmpty {
                addRow(emptyRow("no unpaid transactions"))
            } else {
                for tx in lastUnpaid { addRow(unpaidCard(tx)) }
            }
        case .products:
            if lastProducts.isEmpty {
                addRow(emptyRow("no products"))
            } else {
                for p in lastProducts { addRow(productCard(p)) }
            }
        }
    }

    private func renderSkeletons(count: Int = 4) {
        clearList()
        for _ in 0..<count { addRow(skeletonCard()) }
    }

    private func emptyRow(_ text: String) -> NSView {
        let label = makeLabel(text, font: Theme.font(12), color: Theme.textTertiary, alignment: .center)
        label.translatesAutoresizingMaskIntoConstraints = false
        let wrap = NSView()
        wrap.addSubview(label)
        wrap.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            wrap.heightAnchor.constraint(equalToConstant: 80),
            label.centerXAnchor.constraint(equalTo: wrap.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: wrap.centerYAnchor),
        ])
        return wrap
    }

    private func skeletonCard() -> NSView {
        let card = cardShell()
        let lineName = SkeletonView(height: 14, cornerRadius: 4, width: 140)
        let lineDetail = SkeletonView(height: 10, cornerRadius: 4, width: 200)
        let lineDate = SkeletonView(height: 10, cornerRadius: 4, width: 100)
        let lineAmount = SkeletonView(height: 14, cornerRadius: 4, width: 90)
        let linePill = SkeletonView(height: 16, cornerRadius: 8, width: 50)

        let leftCol = NSStackView(views: [lineName, lineDetail, lineDate])
        leftCol.orientation = .vertical
        leftCol.alignment = .leading
        leftCol.spacing = 8

        let rightCol = NSStackView(views: [lineAmount, NSView(), linePill])
        rightCol.orientation = .vertical
        rightCol.alignment = .trailing
        rightCol.spacing = 10

        let row = NSStackView(views: [leftCol, rightCol])
        row.orientation = .horizontal
        row.alignment = .top
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(row)
        row.pin(to: card, inset: NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14))
        return card
    }

    // MARK: - Card builders

    private func cardShell() -> RoundedView {
        let card = RoundedView()
        card.cornerRadius = 12
        card.borderWidth = 1
        card.borderColor = Theme.cardBorder
        card.fillColor = Theme.cardBg
        card.translatesAutoresizingMaskIntoConstraints = false
        return card
    }

    private func paidCard(_ tx: PaidTransaction) -> NSView {
        let card = cardShell()

        let name = makeLabel(tx.customer?.name ?? tx.customer?.email ?? "—",
                             font: Theme.font(14, .semibold), color: Theme.textPrimary)
        let detail = makeLabel("\(tx.balanceHistoryType ?? "—") · \(tx.paymentMethod ?? "—")",
                               font: Theme.font(12), color: Theme.textSecondary)
        let date = makeLabel(formatDate(tx.createdAt),
                             font: Theme.font(11), color: Theme.textTertiary)
        let amount = makeLabel("Rp " + Format.numberOnly(tx.credit ?? 0),
                               font: Theme.font(15, .semibold), color: Theme.paidGreen)
        let pill = Pill(text: "PAID", color: Theme.paidGreen, softBg: NSColor.white)
        pill.translatesAutoresizingMaskIntoConstraints = false

        let amountRow = NSStackView(views: [amount, pill, NSView()])
        amountRow.orientation = .horizontal
        amountRow.alignment = .centerY
        amountRow.spacing = 10

        let body = NSStackView(views: [name, detail, date, amountRow])
        body.orientation = .vertical
        body.alignment = .leading
        body.spacing = 4
        body.setCustomSpacing(10, after: date)
        body.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(body)
        body.pin(to: card, inset: NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14))

        return card
    }

    private func unpaidCard(_ tx: UnpaidTransaction) -> NSView {
        let card = cardShell()

        let name = makeLabel(tx.customer?.name ?? tx.customer?.email ?? "—",
                             font: Theme.font(14, .semibold), color: Theme.textPrimary)
        let detail = makeLabel("\(tx.type ?? tx.paymentLink?.name ?? "—")",
                               font: Theme.font(12), color: Theme.textSecondary)
        let date = makeLabel(formatDate(tx.createdAt) + "  ↗ open payment",
                             font: Theme.font(11), color: Theme.accentBlue)
        let amount = makeLabel("Rp " + Format.numberOnly(tx.amount ?? 0),
                               font: Theme.font(15, .semibold), color: Theme.unpaidPink)
        let pill = Pill(text: "UNPAID", color: Theme.unpaidPink, softBg: NSColor.white)
        pill.translatesAutoresizingMaskIntoConstraints = false

        let amountRow = NSStackView(views: [amount, pill, NSView()])
        amountRow.orientation = .horizontal
        amountRow.alignment = .centerY
        amountRow.spacing = 10

        let body = NSStackView(views: [name, detail, date, amountRow])
        body.orientation = .vertical
        body.alignment = .leading
        body.spacing = 4
        body.setCustomSpacing(10, after: date)
        body.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(body)
        body.pin(to: card, inset: NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14))

        if let s = tx.paymentUrl, let url = URL(string: s) {
            let click = NSClickGestureRecognizer(target: self, action: #selector(cardClick(_:)))
            card.addGestureRecognizer(click)
            objc_setAssociatedObject(card, &Self.urlKey, url, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }

        return card
    }

    private func productCard(_ p: Product) -> NSView {
        let card = cardShell()

        let name = makeLabel(p.name, font: Theme.font(14, .semibold), color: Theme.textPrimary)
        let typeStatus = "\(p.type ?? "—") · \(p.status ?? "—")"
        let detail = makeLabel(typeStatus, font: Theme.font(12), color: Theme.textSecondary)
        let amountStr = (p.amount.map { "Rp " + Format.numberOnly($0) }) ?? "—"
        let amount = makeLabel(amountStr, font: Theme.font(15, .semibold), color: Theme.textPrimary)

        let copyLinkBtn = SoftButton(title: "Copy Link")
        copyLinkBtn.target = self
        copyLinkBtn.action = #selector(copyProductLink(_:))
        objc_setAssociatedObject(copyLinkBtn, &Self.linkKey, p.linkUrl as Any, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        if (p.linkUrl ?? "").isEmpty { copyLinkBtn.isEnabled = false }

        let copyCheckoutBtn = SoftButton(title: "Copy Checkout")
        copyCheckoutBtn.target = self
        copyCheckoutBtn.action = #selector(copyProductCheckout(_:))
        objc_setAssociatedObject(copyCheckoutBtn, &Self.linkKey, p.linkPayment as Any, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        if (p.linkPayment ?? "").isEmpty { copyCheckoutBtn.isEnabled = false }

        let buttonRow = NSStackView(views: [copyLinkBtn, copyCheckoutBtn, NSView()])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 8
        buttonRow.alignment = .centerY

        let body = NSStackView(views: [name, detail, amount, buttonRow])
        body.orientation = .vertical
        body.alignment = .leading
        body.spacing = 4
        body.setCustomSpacing(8, after: detail)
        body.setCustomSpacing(12, after: amount)
        body.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(body)
        body.pin(to: card, inset: NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14))

        NSLayoutConstraint.activate([
            buttonRow.leadingAnchor.constraint(equalTo: body.leadingAnchor),
            buttonRow.trailingAnchor.constraint(equalTo: body.trailingAnchor),
        ])
        return card
    }

    // MARK: - Date format

    private func formatDate(_ epochMs: Double?) -> String {
        guard let epochMs = epochMs else { return "—" }
        let date = Date(timeIntervalSince1970: epochMs / 1000)
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "id_ID")
        fmt.dateFormat = "dd MMM yyyy, HH.mm"
        return fmt.string(from: date)
    }

    // MARK: - Actions / handlers

    private static var urlKey: UInt8 = 0
    private static var linkKey: UInt8 = 0

    @objc private func refreshTapped(_ sender: Any?) {
        NSLog("[Mayar] refresh tapped")
        onRefresh?()
    }
    @objc private func settingsTapped(_ sender: Any?) {
        NSLog("[Mayar] settings tapped")
        onSettings?()
    }

    @objc private func tabTapped(_ sender: TabButton) {
        guard let tab = Tab(rawValue: sender.tag) else { return }
        switchTab(tab)
        onTabChanged?(tab)
    }

    @objc private func prevPageTapped(_ sender: Any?) { onPrevPage?(currentTab) }
    @objc private func nextPageTapped(_ sender: Any?) { onNextPage?(currentTab) }

    @objc private func cardClick(_ g: NSClickGestureRecognizer) {
        guard let v = g.view,
              let url = objc_getAssociatedObject(v, &Self.urlKey) as? URL else { return }
        onOpenURL?(url)
    }

    @objc private func copyProductLink(_ sender: SoftButton) {
        copy(from: sender)
    }

    @objc private func copyProductCheckout(_ sender: SoftButton) {
        copy(from: sender)
    }

    private func copy(from sender: SoftButton) {
        guard let s = objc_getAssociatedObject(sender, &Self.linkKey) as? String, !s.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
        sender.flashCopied()
    }

    // MARK: - Logo

    private static let appIconImage: NSImage? = {
        if let path = Bundle.main.path(forResource: "AppIcon", ofType: "icns"),
           let img = NSImage(contentsOfFile: path) {
            return img
        }
        return NSImage(systemSymbolName: "creditcard", accessibilityDescription: "Mayar")
    }()
}

extension Format {
    /// "1.234.567" — Indonesian-style number, no currency prefix.
    static func numberOnly(_ amount: Int) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "id_ID")
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: amount)) ?? "\(amount)"
    }
}
