import MindMapDomain
import Testing

@Suite("Topic note")
struct MindNodeNoteTests {
    private func node(note: String?) -> MindNode {
        MindNode(mapID: MapID(), parentID: nil, title: "Plan", note: note)
    }

    @Test func textCountsAsANote() {
        #expect(node(note: "Why it matters").hasNote)
        #expect(node(note: "\n  Ghi chú").hasNote)
    }

    @Test func missingOrBlankNoteDoesNot() {
        #expect(!node(note: nil).hasNote)
        #expect(!node(note: "").hasNote)
        #expect(!node(note: " \n\t ").hasNote)
    }
}
