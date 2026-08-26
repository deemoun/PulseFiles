// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit

final class PatternSelectionPanelController: NSWindowController, NSTextFieldDelegate {
    private let items: [FileItem]
    private let mutation: MarkMutation
    private let patternField = NSTextField()
    private let modeControl = NSSegmentedControl(labels: ["Glob".localized, "Regular Expression".localized], trackingMode: .selectOne, target: nil, action: nil)
    private let countLabel = NSTextField(labelWithString: "")
    private let previewLabel = NSTextField(wrappingLabelWithString: "")
    private let errorLabel = NSTextField(wrappingLabelWithString: "")
    private let applyButton = NSButton()
    var onApply: ((Set<URL>) -> Void)?
    var onClose: (() -> Void)?

    init(items: [FileItem], mutation: MarkMutation) {
        self.items = items
        self.mutation = mutation
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 460, height: 250), styleMask: [.titled], backing: .buffered, defer: false)
        super.init(window: panel)
        panel.title = (mutation == .select ? "Select by Pattern" : "Deselect by Pattern").localized
        configureContent(in: panel)
        updatePreview()
    }

    required init?(coder: NSCoder) { nil }

    private func configureContent(in panel: NSPanel) {
        guard let contentView = panel.contentView else { return }
        let prompt = NSTextField(labelWithString: "Pattern:".localized)
        patternField.placeholderString = "Example: *.swift".localized
        patternField.delegate = self
        patternField.setAccessibilityIdentifier(AccessibilityIdentifiers.Pattern.patternField)
        modeControl.selectedSegment = 0
        modeControl.target = self
        modeControl.action = #selector(modeChanged)
        modeControl.setAccessibilityIdentifier(AccessibilityIdentifiers.Pattern.mode)
        countLabel.setAccessibilityIdentifier(AccessibilityIdentifiers.Pattern.matchCount)
        previewLabel.maximumNumberOfLines = FilePatternMatcher.defaultPreviewLimit
        previewLabel.lineBreakMode = .byTruncatingTail
        errorLabel.textColor = .systemRed
        errorLabel.maximumNumberOfLines = 2

        let cancel = NSButton(title: "Cancel".localized, target: self, action: #selector(cancel))
        cancel.keyEquivalent = "\u{1b}"
        cancel.setAccessibilityIdentifier(AccessibilityIdentifiers.Pattern.cancel)
        applyButton.title = mutation == .select ? "Select".localized : "Deselect".localized
        applyButton.target = self
        applyButton.action = #selector(apply)
        applyButton.keyEquivalent = "\r"
        applyButton.setAccessibilityIdentifier(AccessibilityIdentifiers.Pattern.apply)
        let buttons = NSStackView(views: [cancel, applyButton])
        buttons.orientation = .horizontal
        buttons.alignment = .centerY
        buttons.distribution = .fillEqually
        buttons.spacing = 8

        let stack = NSStackView(views: [prompt, patternField, modeControl, errorLabel, countLabel, previewLabel, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 18),
            patternField.widthAnchor.constraint(equalTo: stack.widthAnchor),
            modeControl.widthAnchor.constraint(equalTo: stack.widthAnchor),
            previewLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            buttons.trailingAnchor.constraint(equalTo: stack.trailingAnchor)
        ])
        panel.initialFirstResponder = patternField
    }

    func controlTextDidChange(_ obj: Notification) { updatePreview() }
    @objc private func modeChanged() { updatePreview() }

    private var mode: FilePatternMode { modeControl.selectedSegment == 0 ? .glob : .regularExpression }

    private func updatePreview() {
        if let error = FilePatternMatcher.validationError(pattern: patternField.stringValue, mode: mode) {
            errorLabel.stringValue = error
            countLabel.stringValue = "0 matches".localized
            previewLabel.stringValue = ""
            applyButton.isEnabled = false
            return
        }
        errorLabel.stringValue = ""
        let result = try? FilePatternMatcher.matches(pattern: patternField.stringValue, mode: mode, items: items)
        countLabel.stringValue = "%d matches".localized(with: result?.totalCount ?? 0)
        previewLabel.stringValue = result?.sampleNames.joined(separator: "\n") ?? ""
        applyButton.isEnabled = true
    }

    @objc private func cancel() { closeSheet() }
    @objc private func apply() {
        guard let result = try? FilePatternMatcher.matches(pattern: patternField.stringValue, mode: mode, items: items) else { return }
        onApply?(result.matchingURLs)
        closeSheet()
    }

    private func closeSheet() {
        guard let window else { return }
        if let parent = window.sheetParent { parent.endSheet(window) } else { window.orderOut(nil) }
        onClose?()
    }
}
