import Testing
@testable import LivepaperPlayback

struct TroubleResponseTests {
    enum Event: Sendable {
        /// The renderer failed or asked for a flush, or a reader broke.
        case trouble
        /// A start put its first frame on the layer and feeds it.
        case feeding
        case loopCompleted
    }

    static let rows: [Row<[Event], [TroubleResponse.Answer]>] = [
        Row("trouble starts again from a fresh reader", [.trouble], [.restart]),
        Row(
            "the same trouble reported twice, by notification and in the pull callback, is answered once",
            [.trouble, .trouble],
            [.restart, .ignore]
        ),
        Row("trouble once the restart feeds is new", [.trouble, .feeding, .trouble], [.restart, .restart]),
        Row(
            "three restarts with no loop between them, and the next trouble gives up",
            [.trouble, .feeding, .trouble, .feeding, .trouble, .feeding, .trouble],
            [.restart, .restart, .restart, .giveUp]
        ),
        Row(
            "once given up, trouble is not answered again",
            [.trouble, .feeding, .trouble, .feeding, .trouble, .feeding, .trouble, .trouble],
            [.restart, .restart, .restart, .giveUp, .ignore]
        ),
        Row(
            "a completed loop starts the count again",
            [.trouble, .feeding, .trouble, .feeding, .loopCompleted, .trouble, .feeding, .trouble],
            [.restart, .restart, .restart, .restart]
        ),
    ]

    @Test(arguments: rows)
    func `answers trouble on the layer`(row: Row<[Event], [TroubleResponse.Answer]>) {
        var response = TroubleResponse()
        var answers: [TroubleResponse.Answer] = []

        for event in row.input {
            switch event {
            case .trouble: answers.append(response.trouble())
            case .feeding: response.feeding()
            case .loopCompleted: response.loopCompleted()
            }
        }

        #expect(answers == row.expected)
    }
}
