import AppKit

final class FileViewerViewController: NSViewController {
    private let url: URL
    private let service: ReadOnlyViewerService
    private let textView = NSTextView()
    private let statusLabel = NSTextField(labelWithString: "")
    private var loadTask: Task<Void, Never>?

    init(url: URL, service: ReadOnlyViewerService = ReadOnlyViewerService()) {
        self.url = url
        self.service = service
        super.init(nibName: nil, bundle: nil)
        title = url.lastPathComponent
    }

    required init?(coder: NSCoder) { nil }

    override func loadView() {
        let root = NSView()
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.setAccessibilityLabel("Read-only file contents".localized)
        scrollView.documentView = textView
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(scrollView)
        root.addSubview(statusLabel)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: root.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: statusLabel.topAnchor, constant: -6),
            statusLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 10),
            statusLabel.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -10),
            statusLabel.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -7),
            statusLabel.heightAnchor.constraint(equalToConstant: 18)
        ])
        view = root
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        guard loadTask == nil else { return }
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await snapshot in service.snapshots(for: url) {
                    guard !Task.isCancelled else { return }
                    textView.string = snapshot.content
                    let format = snapshot.kind == .hex ? "Hex".localized : "Text".localized
                    let suffix = snapshot.isTruncated ? " — retained data limit reached".localized : ""
                    statusLabel.stringValue = "\(format) · \(snapshot.bytesRead) bytes\(suffix)"
                }
            } catch {
                statusLabel.stringValue = error.localizedDescription
            }
        }
    }

    deinit { loadTask?.cancel() }
}
