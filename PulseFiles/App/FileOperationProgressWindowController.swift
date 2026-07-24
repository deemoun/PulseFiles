import AppKit

struct FileOperationProgressPresentation: Equatable {
    let title: String
    let currentItemName: String
    let itemCountDetail: String
    let byteCountDetail: String
    let isIndeterminate: Bool
    let progressValue: Double
    let isCancellationPending: Bool

    static func make(operationName: String, progress: FileOperationProgress?, isCancellationPending: Bool = false) -> Self {
        if isCancellationPending {
            return Self(
                title: operationName,
                currentItemName: "",
                itemCountDetail: "Cancelling operation…".localized,
                byteCountDetail: "",
                isIndeterminate: true,
                progressValue: 0,
                isCancellationPending: true
            )
        }

        guard let progress else {
            return Self(
                title: operationName,
                currentItemName: "Preparing operation…".localized,
                itemCountDetail: "",
                byteCountDetail: "Calculating size…".localized,
                isIndeterminate: true,
                progressValue: 0,
                isCancellationPending: false
            )
        }

        let itemDetail: String
        if let completed = progress.completedRecursiveItemCount, let total = progress.totalRecursiveItemCount {
            itemDetail = "%d/%d items".localized(with: completed, total)
        } else {
            itemDetail = "%d/%d items".localized(with: progress.completedCount, progress.totalCount)
        }
        let hasByteTotals = progress.completedByteCount != nil && progress.totalByteCount != nil
        let byteDetail: String
        let progressValue: Double
        if let completed = progress.completedByteCount, let total = progress.totalByteCount {
            let transferred = ByteCountFormatter.string(fromByteCount: completed, countStyle: .file)
            let totalText = ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
            byteDetail = "%@ of %@".localized(with: transferred, totalText)
            progressValue = total > 0 ? min(1, max(0, Double(completed) / Double(total))) : 0
        } else {
            byteDetail = "Calculating size…".localized
            progressValue = 0
        }
        return Self(
            title: operationName,
            currentItemName: progress.currentItemName,
            itemCountDetail: progress.isPreparingTransfer ? "Preparing transfer…".localized : itemDetail,
            byteCountDetail: byteDetail,
            isIndeterminate: progress.isPreparingTransfer || !hasByteTotals,
            progressValue: progressValue,
            isCancellationPending: false
        )
    }
}

@MainActor
final class FileOperationProgressWindowController: NSWindowController {
    private let titleLabel = NSTextField(labelWithString: "")
    private let currentItemLabel = NSTextField(labelWithString: "")
    private let itemCountLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private let progressIndicator = NSProgressIndicator()
    private let cancelButton = NSButton(title: "Cancel".localized, target: nil, action: nil)
    private let onCancel: () -> Void
    private let onStopWaiting: () -> Void
    private var operationName = ""
    private var watchdog: Timer?
    private var lastProgressDate = Date()
    private let noProgressInterval: TimeInterval

    init(
        noProgressInterval: TimeInterval = 20,
        onCancel: @escaping () -> Void,
        onStopWaiting: @escaping () -> Void
    ) {
        self.onCancel = onCancel
        self.onStopWaiting = onStopWaiting
        self.noProgressInterval = noProgressInterval
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 390, height: 190),
            styleMask: [.titled, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.titleVisibility = .hidden
        panel.setAccessibilityIdentifier(AccessibilityIdentifiers.FileOperationProgress.dialog)
        super.init(window: panel)
        buildInterface(in: panel)
    }

    required init?(coder: NSCoder) { nil }

    func show(operationName: String, parentWindow: NSWindow?) {
        self.operationName = operationName
        lastProgressDate = Date()
        startWatchdog()
        update(operationName: operationName, progress: nil)
        guard let window else { return }
        if let parentWindow, window.parent !== parentWindow {
            window.parent?.removeChildWindow(window)
            parentWindow.addChildWindow(window, ordered: .above)
        }
        if let parentWindow {
            let origin = NSPoint(
                x: parentWindow.frame.midX - window.frame.width / 2,
                y: parentWindow.frame.midY - window.frame.height / 2
            )
            window.setFrameOrigin(origin)
        } else {
            window.center()
        }
        window.orderFront(nil)
    }

    func update(operationName: String, progress: FileOperationProgress?) {
        lastProgressDate = Date()
        apply(FileOperationProgressPresentation.make(operationName: operationName, progress: progress))
    }

    func showCancellationPending() {
        apply(FileOperationProgressPresentation.make(operationName: operationName, progress: nil, isCancellationPending: true))
        offerStopWaiting()
    }

    func dismiss() {
        watchdog?.invalidate()
        watchdog = nil
        guard let window else { return }
        window.orderOut(nil)
        window.parent?.removeChildWindow(window)
    }

    private func buildInterface(in panel: NSPanel) {
        let content = NSView()
        content.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = content
        let stack = NSStackView(views: [titleLabel, currentItemLabel, itemCountLabel, detailLabel, progressIndicator, cancelButton])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)

        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        currentItemLabel.lineBreakMode = .byTruncatingMiddle
        itemCountLabel.textColor = .secondaryLabelColor
        detailLabel.textColor = .secondaryLabelColor
        currentItemLabel.setAccessibilityIdentifier(AccessibilityIdentifiers.FileOperationProgress.currentItemLabel)
        detailLabel.setAccessibilityIdentifier(AccessibilityIdentifiers.FileOperationProgress.detailLabel)
        progressIndicator.style = .bar
        progressIndicator.isIndeterminate = true
        progressIndicator.setAccessibilityIdentifier(AccessibilityIdentifiers.FileOperationProgress.indicator)
        cancelButton.target = self
        cancelButton.action = #selector(cancel(_:))
        cancelButton.setAccessibilityLabel("Cancel file operation".localized)
        cancelButton.setAccessibilityIdentifier(AccessibilityIdentifiers.FileOperationProgress.cancelButton)
        cancelButton.toolTip = "Cancel the active file operation (Command-Period)".localized

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
            currentItemLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            progressIndicator.widthAnchor.constraint(equalTo: stack.widthAnchor),
            progressIndicator.heightAnchor.constraint(equalToConstant: 16),
            cancelButton.trailingAnchor.constraint(equalTo: stack.trailingAnchor)
        ])
    }

    private func apply(_ presentation: FileOperationProgressPresentation) {
        window?.title = presentation.title
        titleLabel.stringValue = presentation.title
        currentItemLabel.stringValue = presentation.currentItemName
        itemCountLabel.stringValue = presentation.itemCountDetail
        detailLabel.stringValue = presentation.byteCountDetail
        progressIndicator.isIndeterminate = presentation.isIndeterminate
        if presentation.isIndeterminate {
            progressIndicator.startAnimation(nil)
        } else {
            progressIndicator.stopAnimation(nil)
            progressIndicator.doubleValue = presentation.progressValue * 100
        }
        cancelButton.isEnabled = true
        cancelButton.title = presentation.isCancellationPending ? "Stop Waiting".localized : "Cancel".localized
        cancelButton.setAccessibilityLabel(presentation.isCancellationPending ? "Stop waiting for file operation".localized : "Cancel file operation".localized)
    }

    private func startWatchdog() {
        watchdog?.invalidate()
        let timer = Timer(
            timeInterval: 1,
            target: self,
            selector: #selector(watchdogDidFire(_:)),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(timer, forMode: .common)
        watchdog = timer
    }

    @objc private func watchdogDidFire(_ timer: Timer) {
        guard Date().timeIntervalSince(lastProgressDate) >= noProgressInterval else { return }
        offerStopWaiting()
    }

    private func offerStopWaiting() {
        watchdog?.invalidate()
        watchdog = nil
        apply(FileOperationProgressPresentation.make(operationName: operationName, progress: nil, isCancellationPending: true))
    }

    @objc private func cancel(_ sender: NSButton) {
        if cancelButton.title == "Stop Waiting".localized {
            onStopWaiting()
        } else {
            onCancel()
        }
    }
}
