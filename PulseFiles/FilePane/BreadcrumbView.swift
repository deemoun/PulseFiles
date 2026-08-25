import AppKit

package final class BreadcrumbView: NSStackView {
    package var onSelect: ((URL) -> Void)?
    private(set) var url: URL = FileManager.default.homeDirectoryForCurrentUser

    package init() {
        super.init(frame: .zero)
        orientation = .horizontal
        spacing = 4
        alignment = .centerY
    }

    required init?(coder: NSCoder) {
        nil
    }

    package func configure(url: URL) {
        self.url = url
        arrangedSubviews.forEach { removeArrangedSubview($0); $0.removeFromSuperview() }
        let components = url.standardizedFileURL.pathComponents
        var partial = URL(fileURLWithPath: "/")
        for (index, component) in components.enumerated() {
            if index == 0 {
                partial = URL(fileURLWithPath: component)
            } else {
                partial.appendPathComponent(component)
            }
            let title = index == 0 ? "/" : component
            let button = NSButton(title: title, target: self, action: #selector(selectComponent(_:)))
            button.bezelStyle = .inline
            button.isBordered = false
            button.tag = index
            button.setAccessibilityLabel("Open \(title)")
            addArrangedSubview(button)
            if index < components.count - 1 {
                let chevron = NSImageView(image: NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil) ?? NSImage())
                chevron.symbolConfiguration = .init(pointSize: 10, weight: .regular)
                addArrangedSubview(chevron)
            }
        }
    }

    @objc private func selectComponent(_ sender: NSButton) {
        let components = url.standardizedFileURL.pathComponents
        var path = "/"
        if sender.tag > 0 {
            path = "/" + components.dropFirst().prefix(sender.tag).joined(separator: "/")
        }
        onSelect?(URL(fileURLWithPath: path))
    }
}
