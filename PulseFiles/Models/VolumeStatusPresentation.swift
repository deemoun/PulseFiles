import Foundation
import PulseFilesUtilities

/// A lightweight, directory-level summary of the volume that contains a pane.
/// This deliberately uses volume resource values only; it never walks a directory
/// or calculates directory sizes.
package struct VolumeStatusPresentation: Equatable {
    package enum Availability: Equatable {
        case available
        case unavailable
        case permissionDenied
    }

    package let volumeURL: URL?
    package let localizedName: String
    package let availableCapacity: Int64?
    package let totalCapacity: Int64?
    package let isReadOnly: Bool
    package let availability: Availability

    package init(
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

    /// Resolves volume metadata on a utility-priority background task. Callers may
    /// cancel their task while the resource lookup is in progress; in that case the
    /// result is discarded before it can be returned to the caller.
    package static func resolve(for directory: URL) async -> VolumeStatusPresentation {
        let task = Task.detached(priority: .utility) {
            guard !Task.isCancelled else { return loading(for: directory) }
            let presentation = resolveSynchronously(for: directory)
            return Task.isCancelled ? loading(for: directory) : presentation
        }
        return await withTaskCancellationHandler(operation: {
            await task.value
        }, onCancel: {
            task.cancel()
        })
    }

    package static func loading(for directory: URL) -> VolumeStatusPresentation {
        unavailable(for: directory, availability: .unavailable)
    }

    package static func resolveSynchronously(for directory: URL) -> VolumeStatusPresentation {
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

    package var label: String {
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

    package var isWarning: Bool {
        availability != .available || isReadOnly || isNearlyFull
    }

    package var isNearlyFull: Bool {
        guard let availableCapacity, let totalCapacity, totalCapacity > 0 else { return false }
        return Double(availableCapacity) / Double(totalCapacity) <= 0.10
    }

    package var detail: String {
        var parts = [label]
        if isReadOnly { parts.append("Read-only".localized) }
        return parts.joined(separator: " • ")
    }

    package var locationDescription: String {
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
