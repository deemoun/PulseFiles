import Foundation

/// A lightweight, directory-level summary of the volume that contains a pane.
/// This deliberately uses volume resource values only; it never walks a directory
/// or calculates directory sizes.
struct VolumeStatusPresentation: Equatable {
    enum Availability: Equatable {
        case available
        case unavailable
        case permissionDenied
    }

    let volumeURL: URL?
    let localizedName: String
    let availableCapacity: Int64?
    let totalCapacity: Int64?
    let isReadOnly: Bool
    let availability: Availability

    init(
        volumeURL: URL?,
        localizedName: String,
        availableCapacity: Int64?,
        totalCapacity: Int64?,
        isReadOnly: Bool,
        availability: Availability = .available
    ) {
        self.volumeURL = volumeURL
        self.localizedName = localizedName
        self.availableCapacity = availableCapacity
        self.totalCapacity = totalCapacity
        self.isReadOnly = isReadOnly
        self.availability = availability
    }

    static func resolve(for directory: URL) -> VolumeStatusPresentation {
        do {
            let directoryValues = try directory.resourceValues(forKeys: [.volumeURLKey])
            guard let volumeURL = directoryValues.allValues[.volumeURLKey] as? URL else {
                return unavailable(for: directory, availability: .unavailable)
            }
            let values = try volumeURL.resourceValues(forKeys: [
                .volumeLocalizedNameKey,
                .volumeNameKey,
                .volumeAvailableCapacityKey,
                .volumeTotalCapacityKey,
                .volumeIsReadOnlyKey
            ])
            let name = values.volumeLocalizedName ?? values.volumeName ?? volumeURL.lastPathComponent
            return VolumeStatusPresentation(
                volumeURL: volumeURL,
                localizedName: name.isEmpty ? volumeURL.path : name,
                availableCapacity: values.volumeAvailableCapacity.map(Int64.init),
                totalCapacity: values.volumeTotalCapacity.map(Int64.init),
                isReadOnly: values.volumeIsReadOnly ?? false
            )
        } catch let error as CocoaError where error.code == .fileReadNoPermission {
            return unavailable(for: directory, availability: .permissionDenied)
        } catch {
            return unavailable(for: directory, availability: .unavailable)
        }
    }

    var label: String {
        switch availability {
        case .permissionDenied:
            return "\(localizedName) — Permission required".localized
        case .unavailable:
            return "\(localizedName) — Volume unavailable".localized
        case .available:
            guard let availableCapacity, let totalCapacity, totalCapacity > 0 else {
                return "\(localizedName) — Capacity unavailable".localized
            }
            return "%@ — %@ free of %@".localized(with: localizedName, FileSizeFormatter.string(fromByteCount: availableCapacity), FileSizeFormatter.string(fromByteCount: totalCapacity))
        }
    }

    var isWarning: Bool {
        availability != .available || isReadOnly || isNearlyFull
    }

    var isNearlyFull: Bool {
        guard let availableCapacity, let totalCapacity, totalCapacity > 0 else { return false }
        return Double(availableCapacity) / Double(totalCapacity) <= 0.10
    }

    var detail: String {
        var parts = [label]
        if isReadOnly { parts.append("Read-only".localized) }
        return parts.joined(separator: " • ")
    }

    var locationDescription: String {
        let path = volumeURL?.path ?? "Unknown volume path".localized
        return "%@ (%@)".localized(with: localizedName, path)
    }

    private static func unavailable(for directory: URL, availability: Availability) -> VolumeStatusPresentation {
        VolumeStatusPresentation(
            volumeURL: nil,
            localizedName: directory.path.isEmpty ? "Current volume".localized : directory.path,
            availableCapacity: nil,
            totalCapacity: nil,
            isReadOnly: false,
            availability: availability
        )
    }
}
