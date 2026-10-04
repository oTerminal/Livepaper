import Foundation
import Testing
import DesignSystem

struct HotkeyRecorderCaptionTests {
    // A 140 pt field, then the clear button's 40 pt slot after 4 pt.
    private let field: CGFloat = 140
    private let recorder: CGFloat = 184

    @Test(arguments: [0, 1, 150, 184] as [CGFloat])
    func `a caption that fits starts under the field`(caption: CGFloat) {
        #expect(HotkeyRecorderCaption.offset(width: caption, fieldWidth: field, recorderWidth: recorder) == 0)
    }

    @Test(arguments: [
        (caption: 185, offset: -45),
        (caption: 242, offset: -102),
    ] as [(caption: CGFloat, offset: CGFloat)])
    func `a wider caption hangs from the field's trailing edge`(caption: CGFloat, offset: CGFloat) {
        #expect(HotkeyRecorderCaption.offset(width: caption, fieldWidth: field, recorderWidth: recorder) == offset)
    }
}
