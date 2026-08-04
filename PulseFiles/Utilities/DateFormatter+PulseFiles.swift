import Foundation

package extension DateFormatter {
    static let pulseFilesTableDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
