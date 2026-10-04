import Foundation

/// Whether the tests run on a virtual Mac, as CI's is: a few cores, so a test
/// that runs heavy system tools slows the whole suite.
enum VirtualMac {
    static let isRunning: Bool = {
        var present: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctlbyname("kern.hv_vmm_present", &present, &size, nil, 0) == 0 && present == 1
    }()
}
