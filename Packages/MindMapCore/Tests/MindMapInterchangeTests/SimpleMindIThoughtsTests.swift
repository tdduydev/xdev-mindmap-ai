import Foundation
import MindMapDomain
import MindMapGraph
import Testing
@testable import MindMapInterchange

/// Fixtures follow the shape of files SimpleMind 1.25–1.28 and iThoughts 7.4
/// saved (public on GitHub, see `SimpleMindMap` and `IThoughtsMap`); they are
/// written for these tests, not copied, since no file came with a licence.
@Suite struct SimpleMindIThoughtsTests {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private static let simpleMind = """
        \u{FEFF}<?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE simplemind-mindmaps>
        <simplemind-mindmaps generator="SimpleMindWin32" gen-version="1.28.3" doc-version="3">
        <mindmap>
        <meta>
        <guid guid="BBA084A03B6640129532ABD9BAB7D369"/>
        <title text="Trip" customized="True"/>
        <main-centraltheme id="0"/>
        </meta>
        <topics>
        <topic id="0" parent="-1" guid="a" x="324.00" y="785.00" palette="0" colorinfo="-1" text="Trip" textfmt="plain">
        <style>
        <strokecolor r="90" g="34" b="162"/>
        </style>
        <note>
          Summer
          plans
        </note>
        </topic>
        <topic id="2" parent="1" guid="c" x="0" y="0" checkbox="True" checked="True" text="Book\\Nflights" textfmt="plain"/>
        <topic id="1" parent="0" guid="b" x="0" y="0" collapsed="True" text="Travel" textfmt="plain">
        <strokecolor r="0" g="51" b="255"/>
        <link urllink="https://example.com/rail"/>
        </topic>
        <topic id="3" parent="0" guid="d" x="0" y="0" checkbox="True" checkbox-mode="roll-up-progress" text="Packing" textfmt="plain">
        <link urllink="cloud://../SimpleMind/Images/001.png"/>
        <image guid="i" name="3d6d5f9b" x="40.00" y="-56.39" scale="1.00" angle="0.00"/>
        </topic>
        <topic id="4" parent="-1" guid="e" x="900" y="900" text="Loose idea" textfmt="plain"/>
        </topics>
        <relations>
        <relation guid="r1" source="4" target="2">
        <children>
        <text guid="t" x="0.00" y="0.00">
        <note textfmt="plain">
          needs
        </note>
        </text>
        </children>
        </relation>
        <relation source="2" target="99"/>
        </relations>
        </mindmap>
        </simplemind-mindmaps>
        """

    private func smmx(_ xml: String) -> Data {
        ZipFixture([("document/mindmap.xml", Data(xml.utf8))]).data
    }

    @Test func simpleMindBuildsTheTreeFromParentIDs() async throws {
        let imported = try await SimpleMindMap.read(smmx(Self.simpleMind), fileName: "File", now: now)
        let map = try #require(imported.maps.first)
        #expect(imported.maps.count == 1)
        #expect(map.outline == """
            Trip [Summer
            plans]
              Travel
                Book
            flights
              Packing [cloud://../SimpleMind/Images/001.png]
              Loose idea
            """)
        let travel = try #require(map.firstNode(titled: "Travel"))
        #expect(travel.isCollapsed)
        #expect(travel.color == .blue)
        #expect(travel.link?.string == "https://example.com/rail")
        #expect(map.firstNode(titled: "Book\nflights")?.taskState == .done)
        #expect(map.firstNode(titled: "Packing")?.taskState == .open)
        #expect(map.nodes.values.allSatisfy { $0.metadata.origin == .imported })
        #expect(imported.report.count(of: .image) == 1)
    }

    @Test func simpleMindRelationsBecomeLabelledConnections() async throws {
        let imported = try await SimpleMindMap.read(smmx(Self.simpleMind), fileName: "File", now: now)
        let map = try #require(imported.maps.first)
        let loose = try #require(map.firstNode(titled: "Loose idea"))
        let book = try #require(map.firstNode(titled: "Book\nflights"))
        #expect(map.edges.count == 1, "a relation to a missing topic is skipped")
        let edge = try #require(map.edges.values.first)
        #expect(edge.sourceNodeID == loose.id && edge.targetNodeID == book.id)
        #expect(edge.label == "needs")
    }

    @Test func simpleMindKeepsTopicsCaughtInAParentCycle() async throws {
        let xml = """
            <simplemind-mindmaps doc-version="3"><mindmap><meta><main-centraltheme id="0"/></meta><topics>
            <topic id="0" parent="-1" text="Root"/>
            <topic id="1" parent="2" text="A"/>
            <topic id="2" parent="1" text="B"/>
            </topics></mindmap></simplemind-mindmaps>
            """
        let imported = try await SimpleMindMap.read(smmx(xml), fileName: "File", now: now)
        #expect(imported.maps.first?.nodes.count == 3)
    }

    @Test func simpleMindRefusesOtherFiles() async throws {
        await #expect(throws: ForeignImportError.wrongFormat) {
            try await SimpleMindMap.read(Data("not a zip".utf8), fileName: "File", now: now)
        }
        await #expect(throws: ForeignImportError.wrongFormat) {
            try await SimpleMindMap.read(ZipFixture([("other.xml", Data("<a/>".utf8))]).data, fileName: "File", now: now)
        }
        await #expect(throws: ForeignImportError.wrongFormat) {
            try await SimpleMindMap.read(smmx("<map/>"), fileName: "File", now: now)
        }
        await #expect(throws: ForeignImportError.damaged) {
            try await SimpleMindMap.read(smmx("<simplemind-mindmaps><mindmap>"), fileName: "File", now: now)
        }
        await #expect(throws: ForeignImportError.emptyDocument) {
            try await SimpleMindMap.read(smmx("<simplemind-mindmaps><mindmap><topics/></mindmap></simplemind-mindmaps>"), fileName: "File", now: now)
        }
    }

    // MARK: iThoughts

    private static let iThoughts = """
        <iThoughts version="4.0" app="com.toketaware.ios.ithoughts" app-version="7.4" modified="2019-10-16T13:54:22"><topics>
        <topic uuid="A" position="{0, 0}" text="Informační koncepce" color="FFFFFF" created="2019-10-16T13:54:18">
        <topic uuid="B" position="{352, -64}" text="Principles" color="0033FF" note="Read first" link="https://example.com/p">
        <topic uuid="C" position="{293, -19}" text="Once only" link="file:///Users/me/a.pdf" summary1="B">
        </topic>
        </topic>
        <topic uuid="D" position="{-300, 20}" text="Risks">
        </topic>
        </topic>
        <topic uuid="E" position="{900, 900}" text="Floating">
        <topic uuid="F" position="{950, 950}" text="Child"/>
        </topic>
        </topics>
        <relationships><relationship/></relationships>
        </iThoughts>
        """

    private func itmz(_ xml: String) -> Data {
        ZipFixture([("mapdata.xml", Data(xml.utf8)), ("style.xml", Data("<style/>".utf8))]).data
    }

    @Test func iThoughtsNestsTopicsAndKeepsFloatingOnesUnderTheCentralTopic() async throws {
        let imported = try await IThoughtsMap.read(itmz(Self.iThoughts), fileName: "File", now: now)
        let map = try #require(imported.maps.first)
        #expect(map.outline == """
            Informační koncepce
              Principles [Read first]
                Once only [file:///Users/me/a.pdf]
              Risks
              Floating
                Child
            """)
        let principles = try #require(map.firstNode(titled: "Principles"))
        #expect(principles.link?.string == "https://example.com/p")
        #expect(principles.color == .blue)
        #expect(map.firstNode(titled: "Informační koncepce")?.color == nil, "white is no colour")
        #expect(imported.report.count(of: .connection) == 1)
        #expect(imported.report.count(of: .summary) == 1)
    }

    @Test func iThoughtsRefusesOtherFiles() async throws {
        await #expect(throws: ForeignImportError.wrongFormat) {
            try await IThoughtsMap.read(itmz("<map/>"), fileName: "File", now: now)
        }
        await #expect(throws: ForeignImportError.emptyDocument) {
            try await IThoughtsMap.read(itmz("<iThoughts><topics/></iThoughts>"), fileName: "File", now: now)
        }
        await #expect(throws: ForeignImportError.damaged) {
            try await IThoughtsMap.read(itmz("<iThoughts><topics><topic"), fileName: "File", now: now)
        }
    }

    @Test func iThoughtsReadsDeepNestingWithoutRecursion() async throws {
        let depth = 2_000
        let xml = "<iThoughts><topics>" + String(repeating: "<topic text=\"t\">", count: depth)
            + String(repeating: "</topic>", count: depth) + "</topics></iThoughts>"
        let imported = try await IThoughtsMap.read(itmz(xml), fileName: "File", now: now)
        #expect(imported.maps.first?.nodes.count == depth)
    }
}
