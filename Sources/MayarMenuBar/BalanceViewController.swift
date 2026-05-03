import AppKit

final class BalanceViewController: NSViewController {

    enum Tab: Int { case paid, unpaid, products }

    enum DetailItem {
        case paid(PaidTransaction)
        case unpaid(UnpaidTransaction)
        case product(Product)

        var title: String {
            switch self {
            case .paid:    return "Paid Transaction"
            case .unpaid:  return "Unpaid Transaction"
            case .product: return "Product"
            }
        }
    }

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

    /// Set by AppDelegate around any data fetch — flips Prev/Next off so the
    /// user can't queue another page change while one is already in flight.
    var isFetching: Bool = false {
        didSet { if oldValue != isFetching { updatePagination() } }
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

    // Detail overlay
    private let detailContainer = AppearanceAwareView()
    private let detailScroll = NSScrollView()
    private let detailContent = FlippedStackView()
    private let detailTitleLabel = NSTextField(labelWithString: "")
    private let detailBackBtn = IconButton(symbol: "chevron.left", accessibility: "Back")

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
            logoView.widthAnchor.constraint(equalToConstant: 32),
            logoView.heightAnchor.constraint(equalToConstant: 26),
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

        buildDetailOverlay()
    }

    private func buildDetailOverlay() {
        detailContainer.fillColor = Theme.windowBg
        detailContainer.translatesAutoresizingMaskIntoConstraints = false
        detailContainer.isHidden = true
        view.addSubview(detailContainer)
        NSLayoutConstraint.activate([
            detailContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            detailContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            detailContainer.topAnchor.constraint(equalTo: view.topAnchor),
            detailContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        let dHeader = AppearanceAwareView()
        dHeader.fillColor = Theme.headerBg
        dHeader.translatesAutoresizingMaskIntoConstraints = false

        let dHeaderBorder = AppearanceAwareView()
        dHeaderBorder.fillColor = Theme.cardBorder
        dHeaderBorder.translatesAutoresizingMaskIntoConstraints = false

        detailBackBtn.target = self
        detailBackBtn.action = #selector(detailBackTapped(_:))
        detailBackBtn.translatesAutoresizingMaskIntoConstraints = false

        detailTitleLabel.font = Theme.font(15, .semibold)
        detailTitleLabel.textColor = Theme.textPrimary
        detailTitleLabel.translatesAutoresizingMaskIntoConstraints = false

        dHeader.addSubview(detailBackBtn)
        dHeader.addSubview(detailTitleLabel)
        dHeader.addSubview(dHeaderBorder)

        NSLayoutConstraint.activate([
            detailBackBtn.leadingAnchor.constraint(equalTo: dHeader.leadingAnchor, constant: 12),
            detailBackBtn.centerYAnchor.constraint(equalTo: dHeader.centerYAnchor),
            detailTitleLabel.leadingAnchor.constraint(equalTo: detailBackBtn.trailingAnchor, constant: 10),
            detailTitleLabel.centerYAnchor.constraint(equalTo: dHeader.centerYAnchor),
            dHeaderBorder.leadingAnchor.constraint(equalTo: dHeader.leadingAnchor),
            dHeaderBorder.trailingAnchor.constraint(equalTo: dHeader.trailingAnchor),
            dHeaderBorder.bottomAnchor.constraint(equalTo: dHeader.bottomAnchor),
            dHeaderBorder.heightAnchor.constraint(equalToConstant: 1),
        ])

        detailScroll.hasVerticalScroller = true
        detailScroll.drawsBackground = false
        detailScroll.borderType = .noBorder
        detailScroll.autohidesScrollers = true
        detailScroll.translatesAutoresizingMaskIntoConstraints = false

        detailContent.orientation = .vertical
        detailContent.alignment = .leading
        detailContent.spacing = 14
        detailContent.translatesAutoresizingMaskIntoConstraints = false
        detailScroll.documentView = detailContent

        detailContainer.addSubview(dHeader)
        detailContainer.addSubview(detailScroll)

        NSLayoutConstraint.activate([
            dHeader.leadingAnchor.constraint(equalTo: detailContainer.leadingAnchor),
            dHeader.trailingAnchor.constraint(equalTo: detailContainer.trailingAnchor),
            dHeader.topAnchor.constraint(equalTo: detailContainer.topAnchor),
            dHeader.heightAnchor.constraint(equalToConstant: 56),

            detailScroll.leadingAnchor.constraint(equalTo: detailContainer.leadingAnchor, constant: 16),
            detailScroll.trailingAnchor.constraint(equalTo: detailContainer.trailingAnchor, constant: -16),
            detailScroll.topAnchor.constraint(equalTo: dHeader.bottomAnchor, constant: 14),
            detailScroll.bottomAnchor.constraint(equalTo: detailContainer.bottomAnchor, constant: -14),

            detailContent.leadingAnchor.constraint(equalTo: detailScroll.contentView.leadingAnchor),
            detailContent.trailingAnchor.constraint(equalTo: detailScroll.contentView.trailingAnchor),
            detailContent.topAnchor.constraint(equalTo: detailScroll.contentView.topAnchor),
            detailContent.widthAnchor.constraint(equalTo: detailScroll.contentView.widthAnchor),
        ])
    }

    // MARK: - Detail show/hide + populate

    func showDetail(_ item: DetailItem) {
        detailTitleLabel.stringValue = item.title
        populateDetailContent(for: item)
        detailContainer.isHidden = false
        // Detail is read-only; the list-level controls don't apply here.
        refreshBtn.isHidden = true
        settingsBtn.isHidden = true
    }

    @objc private func detailBackTapped(_ sender: Any?) {
        detailContainer.isHidden = true
        refreshBtn.isHidden = false
        settingsBtn.isHidden = false
    }

    private func populateDetailContent(for item: DetailItem) {
        detailContent.arrangedSubviews.forEach {
            detailContent.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        switch item {
        case .paid(let tx):    populatePaidDetail(tx)
        case .unpaid(let tx):  populateUnpaidDetail(tx)
        case .product(let p):  populateProductDetail(p)
        }
    }

    private func populatePaidDetail(_ tx: PaidTransaction) {
        let name = tx.customer?.name ?? "—"
        addDetailHeadline(name: name, email: tx.customer?.email)
        addDetailHeroAmount("Rp " + Format.numberOnly(tx.credit ?? 0),
                            color: Theme.paidGreen,
                            pillText: "PAID", pillColor: Theme.paidGreen)
        addDetailDivider()
        addDetailField("Type", tx.balanceHistoryType ?? "—")
        addDetailField("Payment Method", tx.paymentMethod ?? "—")
        addDetailField("Status", tx.status ?? "—")
        addDetailField("Date", formatDate(tx.createdAt))
        if let plName = tx.paymentLink?.name {
            addDetailField("Payment Link", plName)
        }
        addDetailFieldCopy("Transaction ID", tx.id)
    }

    private func populateUnpaidDetail(_ tx: UnpaidTransaction) {
        let name = tx.customer?.name ?? "—"
        addDetailHeadline(name: name, email: tx.customer?.email)
        addDetailHeroAmount("Rp " + Format.numberOnly(tx.amount ?? 0),
                            color: Theme.unpaidPink,
                            pillText: "UNPAID", pillColor: Theme.unpaidPink)
        addDetailDivider()
        addDetailField("Type", tx.type ?? tx.paymentLink?.name ?? "—")
        addDetailField("Status", tx.status ?? "—")
        addDetailField("Date", formatDate(tx.createdAt))
        if let url = tx.paymentUrl, !url.isEmpty {
            addDetailURLField("Payment URL", url)
        }
        addDetailFieldCopy("Transaction ID", tx.id)
    }

    private func populateProductDetail(_ p: Product) {
        addDetailHeadline(name: p.name, email: nil)
        let amountStr = (p.amount.map { "Rp " + Format.numberOnly($0) }) ?? "—"
        let pillText = (p.status ?? "").uppercased().isEmpty ? "PRODUCT" : (p.status ?? "").uppercased()
        let pillColor: NSColor = (p.status?.lowercased() == "active") ? Theme.paidGreen : Theme.textSecondary
        addDetailHeroAmount(amountStr, color: Theme.textPrimary,
                            pillText: pillText, pillColor: pillColor)
        addDetailDivider()
        addDetailField("Type", p.type ?? "—")
        if let cat = p.category, !cat.isEmpty { addDetailField("Category", cat) }
        if let slug = p.link, !slug.isEmpty { addDetailField("Slug", slug) }
        if let url = p.linkUrl, !url.isEmpty {
            addDetailURLField("Public Link", url)
        }
        if let url = p.linkPayment, !url.isEmpty {
            addDetailURLField("Checkout Link", url)
        }
        addDetailFieldCopy("Product ID", p.id)
    }

    // MARK: - Detail row helpers

    private func addDetailRow(_ subview: NSView) {
        detailContent.addArrangedSubview(subview)
        NSLayoutConstraint.activate([
            subview.leadingAnchor.constraint(equalTo: detailContent.leadingAnchor),
            subview.trailingAnchor.constraint(equalTo: detailContent.trailingAnchor),
        ])
    }

    private func addDetailHeadline(name: String, email: String?) {
        let nameLbl = makeLabel(name, font: Theme.font(20, .bold), color: Theme.textPrimary)
        nameLbl.maximumNumberOfLines = 0
        nameLbl.lineBreakMode = .byWordWrapping
        nameLbl.preferredMaxLayoutWidth = 320
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        stack.addArrangedSubview(nameLbl)
        if let e = email, !e.isEmpty {
            let emailLbl = makeLabel(e, font: Theme.font(12), color: Theme.textSecondary)
            stack.addArrangedSubview(emailLbl)
        }
        addDetailRow(stack)
    }

    private func addDetailHeroAmount(_ amount: String, color: NSColor,
                                     pillText: String, pillColor: NSColor) {
        let amountLbl = makeLabel(amount, font: Theme.font(22, .bold), color: color)
        let pill = Pill(text: pillText, color: pillColor, softBg: NSColor.white)
        let row = NSStackView(views: [amountLbl, pill, NSView()])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        addDetailRow(row)
    }

    private func addDetailDivider() {
        let line = AppearanceAwareView()
        line.fillColor = Theme.cardBorder
        line.translatesAutoresizingMaskIntoConstraints = false
        line.heightAnchor.constraint(equalToConstant: 1).isActive = true
        addDetailRow(line)
    }

    private func addDetailField(_ label: String, _ value: String) {
        let lbl = makeKernLabel(label.uppercased(),
                                font: Theme.font(10, .medium),
                                color: Theme.textSecondary, kern: 0.8)
        let val = makeLabel(value, font: Theme.font(13), color: Theme.textPrimary)
        val.maximumNumberOfLines = 0
        val.lineBreakMode = .byWordWrapping
        val.preferredMaxLayoutWidth = 320
        let stack = NSStackView(views: [lbl, val])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        addDetailRow(stack)
    }

    private func addDetailFieldCopy(_ label: String, _ value: String) {
        let lbl = makeKernLabel(label.uppercased(),
                                font: Theme.font(10, .medium),
                                color: Theme.textSecondary, kern: 0.8)
        let val = makeLabel(value, font: Theme.font(12), color: Theme.textPrimary)
        val.maximumNumberOfLines = 0
        val.lineBreakMode = .byCharWrapping
        val.preferredMaxLayoutWidth = 240

        let copyBtn = SoftButton(title: "Copy")
        copyBtn.target = self
        copyBtn.action = #selector(copyDetailValue(_:))
        objc_setAssociatedObject(copyBtn, &Self.linkKey, value as Any, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

        let valRow = NSStackView(views: [val, copyBtn, NSView()])
        valRow.orientation = .horizontal
        valRow.alignment = .firstBaseline
        valRow.spacing = 8

        let stack = NSStackView(views: [lbl, valRow])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        addDetailRow(stack)
    }

    private func addDetailURLField(_ label: String, _ url: String) {
        let lbl = makeKernLabel(label.uppercased(),
                                font: Theme.font(10, .medium),
                                color: Theme.textSecondary, kern: 0.8)
        let val = makeLabel(url, font: Theme.font(12), color: Theme.textPrimary)
        val.maximumNumberOfLines = 0
        val.lineBreakMode = .byCharWrapping
        val.preferredMaxLayoutWidth = 320

        let copyBtn = SoftButton(title: "Copy")
        copyBtn.target = self
        copyBtn.action = #selector(copyDetailValue(_:))
        objc_setAssociatedObject(copyBtn, &Self.linkKey, url as Any, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

        let openBtn = SoftButton(title: "Open ↗")
        openBtn.target = self
        openBtn.action = #selector(openDetailURL(_:))
        objc_setAssociatedObject(openBtn, &Self.linkKey, url as Any, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

        let btnRow = NSStackView(views: [copyBtn, openBtn, NSView()])
        btnRow.orientation = .horizontal
        btnRow.spacing = 8

        let stack = NSStackView(views: [lbl, val, btnRow])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        addDetailRow(stack)
    }

    @objc private func copyDetailValue(_ sender: SoftButton) {
        guard let s = objc_getAssociatedObject(sender, &Self.linkKey) as? String, !s.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
        sender.flashCopied()
    }

    @objc private func openDetailURL(_ sender: SoftButton) {
        guard let s = objc_getAssociatedObject(sender, &Self.linkKey) as? String,
              let url = URL(string: s) else { return }
        onOpenURL?(url)
    }

    // MARK: - State / render

    enum State {
        case unconfigured
        /// `force == true` means a user-initiated refresh; show skeletons even
        /// if we have prior data. `false` is used for initial load + silent
        /// background refresh.
        case loading(force: Bool)
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
        case .loading(let force):
            NSLog("[Mayar] render: loading force=\(force) (have prior data: \(lastBalance != nil))")
            unconfigured = false
            statusLabel.isHidden = true
            // Only blank the balance amounts on a true cold load — a user
            // tapping refresh keeps the existing numbers visible until fresh
            // data arrives.
            if lastBalance == nil {
                totalAmount.stringValue = " "
                activeAmount.stringValue = " "
                pendingAmount.stringValue = " "
            }
            if force || lastBalance == nil {
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
        let canPrev = info.page > 1
        let canNext = info.hasMore || info.page < info.pageCount
        prevBtn.isEnabled = canPrev && !isFetching
        nextBtn.isEnabled = canNext && !isFetching
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

        attachDetail(.paid(tx), to: card)
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

        attachDetail(.unpaid(tx), to: card)
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

        attachDetail(.product(p), to: card)
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
    private static var detailItemKey: UInt8 = 0

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
        guard let v = g.view else { return }
        if let box = objc_getAssociatedObject(v, &Self.detailItemKey) as? DetailItemBox {
            showDetail(box.item)
        } else if let url = objc_getAssociatedObject(v, &Self.urlKey) as? URL {
            onOpenURL?(url)
        }
    }

    /// Wraps a DetailItem in a class so it survives `objc_setAssociatedObject`
    /// (which requires AnyObject for non-retained options).
    private final class DetailItemBox {
        let item: DetailItem
        init(_ item: DetailItem) { self.item = item }
    }

    private func attachDetail(_ item: DetailItem, to card: NSView) {
        let click = NSClickGestureRecognizer(target: self, action: #selector(cardClick(_:)))
        card.addGestureRecognizer(click)
        objc_setAssociatedObject(card, &Self.detailItemKey, DetailItemBox(item), .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
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
        // Prefer the transparent-bg SVG so the M shows cleanly on light AND
        // dark header backgrounds. The .icns fallback has a white square that
        // would block the dark header.
        if let url = Bundle.main.url(forResource: "MayarLogo", withExtension: "svg"),
           let img = NSImage(contentsOf: url) {
            let h: CGFloat = 24
            let w: CGFloat = h * (133.95 / 108.0)
            img.size = NSSize(width: w, height: h)
            img.isTemplate = false  // keep brand colors
            return img
        }
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
