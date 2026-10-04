import Testing
import DesignSystem

struct LayerMaterialTests {
    @Test(arguments: [LayerMaterial.sidebar, .toolbar, .popover, .inspectorControl])
    func `the floating functional layer is glass`(layer: LayerMaterial) {
        #expect(layer.fill(reduceTransparency: false) == .glass)
    }

    @Test func `wallpaper tiles are not glass`() {
        #expect(LayerMaterial.tile.fill(reduceTransparency: false) == .none)
    }

    @Test func `content sits on the window background`() {
        #expect(LayerMaterial.content.fill(reduceTransparency: false) == .windowBackground)
    }

    @Test(arguments: LayerMaterial.allCases)
    func `with Reduce Transparency no layer is glass`(layer: LayerMaterial) {
        #expect(layer.fill(reduceTransparency: true) != .glass)
    }

    @Test(arguments: [LayerMaterial.sidebar, .toolbar, .popover, .inspectorControl])
    func `with Reduce Transparency glass becomes an opaque raised surface`(layer: LayerMaterial) {
        #expect(layer.fill(reduceTransparency: true) == .opaqueRaised)
    }
}
