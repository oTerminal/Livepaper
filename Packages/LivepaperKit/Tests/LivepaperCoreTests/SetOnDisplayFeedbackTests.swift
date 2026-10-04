import Foundation
import Testing
import LivepaperCore

struct SetOnDisplayFeedbackTests {
    enum Event: Sendable {
        case started
        case applied(at: Double)
        case refused
        case tick(at: Double)
    }

    static let rows: [Row<[Event], SetOnDisplayFeedback.Phase>] = [
        Row("idle until a set starts", [], .idle),
        Row("working until the state is applied", [.started], .working),
        Row("done once applied", [.started, .applied(at: 0)], .done),
        Row("still done just short of 1.5 s", [.started, .applied(at: 0), .tick(at: 1.499)], .done),
        Row("idle again at 1.5 s", [.started, .applied(at: 0), .tick(at: 1.5)], .idle),
        Row("a tick while working changes nothing", [.started, .tick(at: 10)], .working),
        Row("an apply nobody started changes nothing", [.applied(at: 0)], .idle),
        Row("a second set while done works again", [.started, .applied(at: 0), .started], .working),
        Row(
            "the second set's done lasts its own 1.5 s",
            [.started, .applied(at: 0), .started, .applied(at: 1), .tick(at: 1.5)],
            .done
        ),
        Row("a set that was refused goes back to idle: nothing was saved", [.started, .refused], .idle),
        Row("a refusal once done changes nothing", [.started, .applied(at: 0), .refused], .done),
        Row("a refusal nobody started changes nothing", [.refused], .idle),
    ]

    @Test(arguments: rows)
    func `working until applied, done for 1.5 s, then idle`(row: Row<[Event], SetOnDisplayFeedback.Phase>) {
        var feedback = SetOnDisplayFeedback()

        for event in row.input {
            switch event {
            case .started: feedback.started()
            case .applied(let seconds): feedback.applied(at: Moment.after(seconds))
            case .refused: feedback.refused()
            case .tick(let seconds): feedback.tick(at: Moment.after(seconds))
            }
        }

        #expect(feedback.phase == row.expected)
    }

    @Test func `says when done gives way to idle, so the caller can schedule its tick`() {
        var feedback = SetOnDisplayFeedback()

        feedback.started()
        let whileWorking = feedback.idleAt
        feedback.applied(at: Moment.after(2))
        let whileDone = feedback.idleAt
        feedback.tick(at: Moment.after(3.5))

        #expect(whileWorking == nil)
        #expect(whileDone == Moment.after(3.5))
        #expect(feedback.idleAt == nil)
        #expect(SetOnDisplayFeedback.doneDuration == .milliseconds(1500))
    }
}
