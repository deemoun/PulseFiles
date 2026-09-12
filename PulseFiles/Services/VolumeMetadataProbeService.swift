// Copyright (c) 2026 Dmitry Yarygin
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

package struct VolumeMetadata: Sendable, Equatable {
    package let name: String?
    package let isRemovable: Bool
    package let isLocal: Bool
    package let isReadOnly: Bool
    package let totalCapacity: Int64?
    package let availableCapacity: Int64?
}

package protocol VolumeMetadataProbing: Sendable {
    func metadata(for url: URL) -> VolumeMetadata?
}

/// Service-layer boundary for resource-value calls. Callers invoke it only from
/// their asynchronous discovery worker, never from the UI actor.
package final class VolumeMetadataProbeService: VolumeMetadataProbing, @unchecked Sendable {
    package init() {}

    package func metadata(for url: URL) -> VolumeMetadata? {
        let keys: Set<URLResourceKey> = [.volumeNameKey, .volumeIsRemovableKey, .volumeIsLocalKey,
            .volumeIsReadOnlyKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey]
        guard let values = try? url.resourceValues(forKeys: keys) else { return nil }
        return VolumeMetadata(name: values.volumeName, isRemovable: values.volumeIsRemovable ?? false,
            isLocal: values.volumeIsLocal ?? false, isReadOnly: values.volumeIsReadOnly ?? false,
            totalCapacity: values.volumeTotalCapacity.map(Int64.init),
            availableCapacity: values.volumeAvailableCapacity.map(Int64.init))
    }
}
