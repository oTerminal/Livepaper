import Foundation
import Testing

/// Whether the tests run on a virtual Mac, as CI's is. The system calls a Metal
/// display link on a layer on no screen for a few frames, then none; on a
/// virtual Mac those few come only now and then, so a test's window may see none.
enum VirtualMac {
    static let isRunning: Bool = {
        var present: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctlbyname("kern.hv_vmm_present", &present, &size, nil, 0) == 0 && present == 1
    }()
}

/// Expectations on the pictures a scene's display link was called for: required
/// on a Mac, and on a virtual Mac a known issue that may not show (`VirtualMac`).
func whereTheSystemCallsTheDisplayLink(
    isolation: isolated (any Actor)? = #isolation, _ body: () async -> Void
) async {
    await withKnownIssue(
        "a virtual Mac calls a Metal display link only now and then", isIntermittent: true, isolation: isolation
    ) {
        await body()
    } when: {
        VirtualMac.isRunning
    }
}
