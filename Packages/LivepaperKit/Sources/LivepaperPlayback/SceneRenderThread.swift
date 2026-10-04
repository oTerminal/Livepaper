// The display link on a thread of its own with its own run loop follows the spike.

import Foundation
import Metal
import Synchronization

/// The device and the one command queue every surface's scene is drawn with.
/// Metal's devices and queues are safe to share between threads.
struct SceneGPU: @unchecked Sendable {
    let device: any MTLDevice
    let queue: any MTLCommandQueue

    static let shared: SceneGPU? = {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { return nil }
        queue.label = "app.livepaper.scene"
        return SceneGPU(device: device, queue: queue)
    }()
}

/// The thread every scene's display link runs on, with a run loop of its own
/// (the link fires in the extension, with no window).
final class SceneRenderThread: Thread, @unchecked Sendable {
    static let shared: SceneRenderThread = {
        let thread = SceneRenderThread()
        thread.name = "app.livepaper.scene"
        thread.qualityOfService = .userInteractive
        thread.start()
        thread.ready.wait()
        return thread
    }()

    private let ready = DispatchSemaphore(value: 0)
    /// Set once, before `ready` is signalled, and only read after it.
    private var runLoop: RunLoop?

    override func main() {
        runLoop = .current
        // A run loop with nothing in it returns at once.
        RunLoop.current.add(Port(), forMode: .default)
        ready.signal()
        while true {
            _ = autoreleasepool { RunLoop.current.run(mode: .default, before: .distantFuture) }
        }
    }

    func perform(_ block: @escaping @Sendable () -> Void) {
        guard let runLoop else { return }
        runLoop.perform(inModes: [.default], block: block)
        CFRunLoopWakeUp(runLoop.getCFRunLoop())
    }

    /// Whether the thread runs a block within `limit`: false when a frame hangs it.
    func answers(within limit: Duration) async -> Bool {
        let answer = Answer()
        perform { answer.given.store(true, ordering: .releasing) }
        let clock = ContinuousClock()
        let deadline = clock.now + limit
        while clock.now < deadline {
            if answer.given.load(ordering: .acquiring) { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return answer.given.load(ordering: .acquiring)
    }

    private final class Answer: Sendable {
        let given = Atomic(false)
    }
}
