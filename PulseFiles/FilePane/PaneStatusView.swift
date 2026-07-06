import AppKit

final class PaneStatusView: NSVisualEffectView {
    private let label = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        material = .hudWindow
        blendingMode = .withinWindow
        state = .active
        label.font = .systemFont(ofSize: 12)
        label.textColor = LiquidGlassStyle.secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -10),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }

    func configure(items: [FileItem], selectedItems: [FileItem], isLoading: Bool, errorMessage: String?) {
        if isLoading {
            label.stringValue = "Loading...".localized
            return
        }
        if let errorMessage {
            label.stringValue = "Unable to read folder: %@".localized(with: errorMessage)
            return
        }
        let selectedSize = selectedItems.reduce(Int64(0)) { $0 + $1.size }
        let folderCount = items.filter(\.isDirectory).count
        let size = selectedItems.isEmpty ? "" : " · %@ selected".localized(with: FileSizeFormatter.string(fromByteCount: selectedSize))
        label.stringValue = "%d items · %d folders · %d selected%@".localized(with: items.count, folderCount, selectedItems.count, size)
    }
}
