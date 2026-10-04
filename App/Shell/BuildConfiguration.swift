/// Which configuration this app was built in. A Debug build runs from `build/` or
/// DerivedData by design: it is never offered the move to Applications, and its
/// updater never starts.
enum BuildConfiguration {
    #if DEBUG
    static let isDebug = true
    #else
    static let isDebug = false
    #endif
}
