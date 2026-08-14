/// Per-window, non-persistent state. A new window/session intentionally does not
/// inherit manual terminal visibility changes from another settings instance.
final class WindowSessionState {
    var runtimeTerminalVisible: Bool?
}
