import Testing
import DesignSystem

struct PressTests {
    @Test func `a pressed control scales to 0.96`() {
        #expect(Press.scale(isPressed: true) == 0.96)
    }

    @Test func `a released control is full size`() {
        #expect(Press.scale(isPressed: false) == 1)
    }

    @Test func `a static control does not move when pressed`() {
        #expect(Press.scale(isPressed: true, isStatic: true) == 1)
    }

    @Test func `a static control dims instead, so the press is still acknowledged`() {
        #expect(Press.opacity(isPressed: true, isStatic: true) == 0.7)
        #expect(Press.opacity(isPressed: false, isStatic: true) == 1)
    }

    @Test func `a control that scales does not dim as well`() {
        #expect(Press.opacity(isPressed: true) == 1)
    }
}
