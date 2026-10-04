import CoreGraphics
import LivepaperCore
import LivepaperSystem
import Testing

struct CoveredDisplaysTests {
    // The built-in display, with a camera housing, an external one to its right,
    // and one above it: global display space, points, y growing downwards, as
    // the window list gives it. The built-in's numbers are a MacBook's, macOS 27:
    // a 38 pt safe-area inset at the top, and a menu bar 39 pt tall.
    static let builtIn = ConnectedDisplay(
        identity: .numbered(1),
        displayID: 1,
        pixelSize: Size(width: 3600, height: 2338),
        frame: rect(0, 0, 1800, 1169),
        topSafeAreaInset: 38
    )
    static let external = ConnectedDisplay(
        identity: .numbered(2), displayID: 3, pixelSize: Size(width: 1920, height: 1080), frame: rect(1800, 0, 1920, 1080)
    )
    static let above = ConnectedDisplay(
        identity: .numbered(3), displayID: 4, pixelSize: Size(width: 1920, height: 1080), frame: rect(0, -1080, 1920, 1080)
    )
    static let displays = [builtIn, external, above]

    static let ownPID: Int32 = 100
    static let otherPID: Int32 = 200
    static let dockPID: Int32 = 300
    static let windowServerPID: Int32 = 400
    static let loginwindowPID: Int32 = 500
    static let windowManagerPID: Int32 = 600
    static let shieldLevel = Int(CGShieldingWindowLevel())

    static func rect(_ x: Double, _ y: Double, _ width: Double, _ height: Double) -> Rect {
        Rect(origin: Point(x: x, y: y), size: Size(width: width, height: height))
    }

    static func window(_ bounds: Rect, layer: Int = 0, owner: Int32 = otherPID) -> WindowListEntry {
        WindowListEntry(bounds: bounds, layer: layer, ownerPID: owner)
    }

    // The built-in's menu bar and the Dock's window, as the window list gives them.
    static let menuBar = window(rect(0, 0, 1800, 39), layer: 24, owner: windowServerPID)
    static let dock = window(builtIn.frame, layer: 20, owner: dockPID)
    // What Show Desktop adds, macOS 27: WindowManager's window over the whole display, above the normal level.
    static let showDesktop = window(builtIn.frame, layer: 18, owner: windowManagerPID)

    static let rows: [Row<[WindowListEntry], Set<DisplayIdentity>>] = [
        Row("nothing on screen covers nothing", [], []),
        Row("a fullscreen app covers its display", [window(builtIn.frame)], [builtIn.identity]),
        Row(
            "a fullscreen app below a camera housing covers its display, the strip beside the housing black",
            [menuBar, window(rect(0, 39, 1800, 1130))],
            [builtIn.identity]
        ),
        Row(
            "the same window on a display without a camera housing leaves wallpaper above it",
            [window(rect(1800, 39, 1920, 1041))],
            []
        ),
        Row(
            "a window that starts below the menu bar leaves wallpaper above it",
            [menuBar, window(rect(0, 40, 1800, 1129))],
            []
        ),
        Row("a fullscreen app on the external display covers only that one", [window(external.frame)], [external.identity]),
        Row("a fullscreen app on a display above the main one", [window(above.frame)], [above.identity]),
        Row(
            "a zoomed window stops at the Dock and leaves the menu bar showing the wallpaper",
            [menuBar, dock, window(rect(0, 39, 1800, 1050))],
            []
        ),
        Row("a window larger than the display covers it", [window(rect(-10, -10, 1900, 1300))], [builtIn.identity]),
        Row("a window one point short of the display does not", [window(rect(0, 0, 1800, 1168))], []),
        Row("a window on another display does not cover this one", [window(rect(1900, 100, 800, 600))], []),
        Row(
            "one window across two displays covers both",
            [window(rect(0, 0, 3720, 1169))],
            [builtIn.identity, external.identity]
        ),
        Row("the app's own window does not count", [window(builtIn.frame, owner: ownPID)], []),
        Row("the app's own fullscreen window below a camera housing does not count", [window(rect(0, 39, 1800, 1130), owner: ownPID)], []),
        Row(
            "the desktop's own windows are below the normal level",
            [window(builtIn.frame, layer: -2_147_483_624), window(builtIn.frame, layer: -2_147_483_603)],
            []
        ),
        Row("a floating panel as large as the display covers it", [window(builtIn.frame, layer: 3)], [builtIn.identity]),
        Row("the Dock's display-sized window does not cover it", [menuBar, dock], []),
        Row("the Dock's windows never count, whatever their level", [window(builtIn.frame, layer: 27, owner: dockPID)], []),
        Row("someone else's window at the Dock's level covers it", [window(builtIn.frame, layer: 20)], [builtIn.identity]),
        Row("a display-sized window above the Dock's level covers it", [window(builtIn.frame, layer: 25)], [builtIn.identity]),
        Row("a screen saver covers its display", [window(builtIn.frame, layer: 1000)], [builtIn.identity]),
        Row(
            "the lock screen's shield, still listed a second after unlocking, covers nothing",
            [
                window(builtIn.frame, layer: shieldLevel, owner: loginwindowPID),
                window(external.frame, layer: shieldLevel, owner: loginwindowPID),
            ],
            []
        ),
        Row("loginwindow's windows never count, whatever their level", [window(builtIn.frame, owner: loginwindowPID)], []),
        Row("Show Desktop's window, WindowManager's, as large as the display, covers nothing", [menuBar, dock, showDesktop], []),
        Row(
            "a display-sized window Show Desktop moved aside, a sliver left at the display's edge, covers nothing",
            [menuBar, dock, showDesktop, window(rect(0, 1157, 1800, 1169))],
            []
        ),
        Row("WindowManager's windows never count, whatever their level", [window(builtIn.frame, owner: windowManagerPID)], []),
        Row("someone else's window at the shield's level covers it", [window(builtIn.frame, layer: shieldLevel)], [builtIn.identity]),
        Row(
            "two windows that tile do not cover it, v1's known gap",
            [window(rect(0, 0, 900, 1169)), window(rect(900, 0, 900, 1169))],
            []
        ),
        Row(
            "two windows that tile below a camera housing do not cover it either",
            [menuBar, window(rect(0, 39, 900, 1130)), window(rect(900, 39, 900, 1130))],
            []
        ),
    ]

    @Test(arguments: rows)
    func `a display is covered by one window that contains it`(row: Row<[WindowListEntry], Set<DisplayIdentity>>) {
        let covered = coveredDisplays(
            windows: row.input,
            displays: Self.displays,
            ignoringOwners: [Self.ownPID, Self.dockPID, Self.loginwindowPID, Self.windowManagerPID]
        )

        #expect(covered == row.expected)
    }

    static let showingDesktopRows: [Row<[WindowListEntry], Bool>] = [
        Row("nothing on screen is not Show Desktop", [], false),
        Row("Show Desktop: WindowManager's window over the whole display", [menuBar, dock, showDesktop], true),
        Row(
            "Show Desktop on the external display",
            [window(external.frame, layer: 18, owner: windowManagerPID)],
            true
        ),
        Row(
            "a window of WindowManager's smaller than the display is not",
            [window(rect(0, 100, 200, 800), owner: windowManagerPID)],
            false
        ),
        Row("WindowManager's window below the normal level is not", [window(builtIn.frame, layer: -1, owner: windowManagerPID)], false),
        Row("someone else's window over the whole display is not", [menuBar, dock, window(builtIn.frame, layer: 18)], false),
    ]

    @Test(arguments: showingDesktopRows)
    func `a window of WindowManager's over a whole display means Show Desktop`(row: Row<[WindowListEntry], Bool>) {
        let showing = isShowingDesktop(windows: row.input, displays: Self.displays, windowManager: [Self.windowManagerPID])

        #expect(showing == row.expected)
    }
}
