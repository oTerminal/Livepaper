import Foundation

/// The app the `livepaper` tool ships inside, from the tool's own path with its
/// links already resolved: `<app>.app/Contents/Helpers/<tool>`. Nil for a tool
/// anywhere else, which then asks LaunchServices for Livepaper by bundle
/// identifier. The tool opens its own app first because LaunchServices names
/// whichever registered copy it prefers, and a Mac that builds Livepaper has
/// several (found on screen: an old build opened in place of the one
/// the tool came from).
public func enclosingApp(ofTool tool: URL) -> URL? {
    let steps = tool.pathComponents
    guard steps.count >= 5, steps[steps.count - 2] == "Helpers", steps[steps.count - 3] == "Contents",
          steps[steps.count - 4].hasSuffix(".app") else { return nil }
    return tool.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
}
