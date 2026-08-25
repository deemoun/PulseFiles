/// Per-window, non-persistent state. A new window/session intentionally does not
/// inherit manual terminal visibility changes from another settings instance.
package final class WindowSessionState {
    package var runtimeTerminalVisible: Bool?
}
