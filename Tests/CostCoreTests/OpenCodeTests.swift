import Foundation
import Testing
@testable import CostCore

struct OpenCodeTests {
    @Test func parsesModernSeparateCategoriesAndIgnoresRecordedCost() throws {
        let scan = OpenCodeSessionParser.parse(data: Data(openCodeFixture().utf8), id: "msg", sessionID: "s", modern: true)
        let event = try #require(scan.events.first)
        #expect(event.model == "claude-sonnet-4-6")
        #expect(event.requestInput == 130)
        #expect(event.openCodeUsage?.output == 40)
        #expect(event.openCodeUsage?.reasoning == 10)
        // 100*3 + 20*.30 + 10*3.75 + (40+10)*15, per million.
        #expect(try PricingCatalog.load().cost(for: event).usd == Decimal(string: "0.0010935"))
    }
    @Test func completedCompactionUsageIsCountedOnce() throws {
        try withOpenCodeHome { home in
            let data = openCodeFixture().replacingOccurrences(of: "\"completed\":1791633600100", with: "\"unused\":0").replacingOccurrences(of: "\"agent\":\"build\"", with: "\"status\":\"completed\"")
            try openCodeDatabase(home, sql: "INSERT INTO session_message VALUES ('compaction','s','compaction',0,'\(data)');")
            let scan = try OpenCodeSessionScanner().scan(home: home)
            #expect(scan.events.count == 1)
            #expect(try scan.events.first.map { try PricingCatalog.load().cost(for: $0).usd } == Decimal(string: "0.0010935"))
        }
    }
    @Test func exactProviderUsesItsOwnPricingAndUnknownProviderIsUnpriced() throws {
        let pricing = try PricingCatalog.load()
        for (provider, expected) in [("opencode", "0.00053414"), ("openai", "0.0006275"), ("custom", nil)] {
            let data = openCodeFixture(provider: provider, model: "gpt-5.1", writes: 0)
            let event = try #require(OpenCodeSessionParser.parse(data: Data(data.utf8), id: "msg", sessionID: "s", modern: true).events.first)
            #expect(pricing.cost(for: event).usd == expected.flatMap { Decimal(string: $0) })
            if expected == nil { #expect(pricing.cost(for: event).reason?.contains("custom") == true) }
        }
    }
    @Test func zeroPublishedRatesArePricedButUnavailableWriteRateIsNot() throws {
        let pricing = try PricingCatalog.load()
        let free = try #require(OpenCodeSessionParser.parse(data: Data(openCodeFixture(model: "big-pickle", writes: 0).utf8), id: "m", sessionID: "s", modern: true).events.first)
        #expect(pricing.cost(for: free).usd == 0)
        let missing = try #require(OpenCodeSessionParser.parse(data: Data(openCodeFixture(model: "big-pickle").utf8), id: "m", sessionID: "s", modern: true).events.first)
        #expect(pricing.cost(for: missing).usd == nil)
    }
    @Test func verifiedFireworksModelUsesStandardRatesAndRejectsUnknownWrites() throws {
        let pricing = try PricingCatalog.load()
        for (writes, expected) in [(Int64(0), "0.00009012"), (Int64(10), nil)] {
            let data = openCodeFixture(provider: "fireworks-ai", model: "accounts/fireworks/models/deepseek-v4p1-flash", writes: writes)
            let event = try #require(OpenCodeSessionParser.parse(data: Data(data.utf8), id: "m", sessionID: "s", modern: true).events.first)
            #expect(pricing.cost(for: event).usd == expected.flatMap { Decimal(string: $0) })
        }
    }
    @Test func contextThresholdIncludesAllInputCategories() throws {
        let pricing = try PricingCatalog.load()
        for (input, expected) in [(Int64(271970), "0.0544569"), (Int64(271971), "0.1088842")] {
            let event = try #require(OpenCodeSessionParser.parse(data: Data(openCodeFixture(model: "gpt-5.6-luna", input: input).utf8), id: "m", sessionID: "s", modern: true).events.first)
            #expect(pricing.cost(for: event).usd == Decimal(string: expected))
        }
    }
    @Test func legacyOutputTotalResolvesReasoningWithoutDoubleCounting() throws {
        let base = openCodeFixture(provider: "openai", model: "gpt-5.1", writes: 0, modern: false)
        for (total, output, priced) in [("160", Int64(40), true), ("170", Int64(50), true), ("999", Int64(50), false)] {
            let data = base.replacingOccurrences(of: "\"input\":100", with: "\"total\":\(total),\"input\":100")
            let event = try #require(OpenCodeSessionParser.parse(data: Data(data.utf8), id: "m", sessionID: "s", modern: false).events.first)
            #expect(event.usage.output == output)
            #expect((try PricingCatalog.load().cost(for: event).usd != nil) == priced)
        }
    }
    @Test func malformedCountsMissingIdentityAndUnfinishedUsageAreDiagnosed() {
        let base = openCodeFixture()
        for data in [base.replacingOccurrences(of: "\"input\":100", with: "\"input\":true"),
                     base.replacingOccurrences(of: "\"input\":100", with: "\"input\":1.5"),
                     base.replacingOccurrences(of: "\"input\":100", with: "\"input\":-1"),
                     base.replacingOccurrences(of: "\"completed\":1791633600100", with: "\"completed\":null"),
                     base.replacingOccurrences(of: "\"input\":100", with: "\"input\":9223372036854775807"), "{broken"] {
            let scan = OpenCodeSessionParser.parse(data: Data(data.utf8), id: "m", sessionID: "s", modern: true)
            #expect(scan.events.isEmpty)
            #expect(scan.diagnostics == 1)
        }
        #expect(OpenCodeSessionParser.parse(data: Data(base.utf8), id: "", sessionID: "s", modern: true).events.isEmpty)
    }
    @Test func migratedIDsPreferModernAndSnapshotsAreReadOnly() throws {
        try withOpenCodeHome { home in
            try openCodeDatabase(home, sql: """
            INSERT INTO message VALUES ('m','s',1791633600000,'\(openCodeFixture(modern: false))');
            INSERT INTO session_message VALUES ('m','s','assistant',1791633600000,'\(openCodeFixture())');
            """)
            let db = home.appendingPathComponent("opencode.db")
            let before = try Data(contentsOf: db)
            let scanner = OpenCodeSessionScanner()
            #expect(try scanner.scan(home: home).events.count == 1)
            #expect(try scanner.scan(home: home).events.count == 1)
            #expect(try Data(contentsOf: db) == before)
            #expect(!FileManager.default.fileExists(atPath: db.path + "-wal"))
            #expect(!FileManager.default.fileExists(atPath: db.path + "-shm"))
        }
    }
    @Test func inheritedHistoricalCopyDeduplicatesButDistinctCallsCount() throws {
        try withOpenCodeHome { home in
            try openCodeDatabase(home, sql: """
            INSERT INTO session VALUES ('s',1791633590000);
            INSERT INTO session VALUES ('fork',1791633700000);
            INSERT INTO session VALUES ('independent',1791633590000);
            INSERT INTO session_message VALUES ('m','s','assistant',1791633600000,'\(openCodeFixture())');
            INSERT INTO session_message VALUES ('copy','fork','assistant',1791633600000,'\(openCodeFixture())');
            INSERT INTO session_message VALUES ('distinct','independent','assistant',1791633600000,'\(openCodeFixture())');
            INSERT INTO session_message VALUES ('fresh','fork','assistant',1791633800000,'\(openCodeFixture(created: 1791633800000))');
            """)
            #expect(try OpenCodeSessionScanner().scan(home: home).events.count == 3)
        }
    }
    @Test func duplicateIDWithConflictingUsageIsUnpriced() throws {
        try withOpenCodeHome { home in
            try openCodeDatabase(home, sql: """
            INSERT INTO session_message VALUES ('m','s','assistant',1791633600000,'\(openCodeFixture())');
            INSERT INTO session_message VALUES ('m','fork','assistant',1791633600000,'\(openCodeFixture(input: 101))');
            """)
            let scan = try OpenCodeSessionScanner().scan(home: home)
            #expect(scan.events.count == 1)
            #expect(scan.diagnostics > 0)
            #expect(try PricingCatalog.load().cost(for: scan.events[0]).usd == nil)
        }
    }
    @Test func localDayMonthAndFutureBoundaries() throws {
        try withOpenCodeHome { home in
            try openCodeDatabase(home, sql: """
            INSERT INTO session_message VALUES ('prior','s','assistant',0,'\(openCodeFixture(created: 1790827199000))');
            INSERT INTO session_message VALUES ('yesterday','s','assistant',0,'\(openCodeFixture(created: 1791691199000))');
            INSERT INTO session_message VALUES ('today','s','assistant',0,'\(openCodeFixture(created: 1791691200000))');
            INSERT INTO session_message VALUES ('future','s','assistant',0,'\(openCodeFixture(created: 1791691202000))');
            """)
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "America/New_York")!
            let scan = try OpenCodeSessionScanner().scan(home: home)
            let summary = SummaryBuilder.build(events: scan.events, now: Date(timeIntervalSince1970: 1791691201), calendar: calendar, pricing: try PricingCatalog.load())
            #expect(summary.today.total == Decimal(string: "0.0010935"))
            #expect(summary.month.total == Decimal(string: "0.002187"))
        }
    }
    @Test func unstableSnapshotRetriesThenRejectsAndCleansUp() throws {
        try withOpenCodeHome { home in
            try openCodeDatabase(home, sql: "INSERT INTO session_message VALUES ('m','s','assistant',0,'\(openCodeFixture())');")
            let retrying = SnapshotChangingFileManager(changes: 1)
            #expect(try OpenCodeSessionScanner(fileManager: retrying).scan(home: home).events.count == 1)
            #expect(retrying.copies == 2)
            #expect(retrying.targets.allSatisfy { !FileManager.default.fileExists(atPath: $0.deletingLastPathComponent().path) })
            let changing = SnapshotChangingFileManager(changes: 3)
            #expect(throws: OpenCodeScanError.changingDatabase) { try OpenCodeSessionScanner(fileManager: changing).scan(home: home) }
            #expect(changing.copies == 3)
            #expect(changing.targets.allSatisfy { !FileManager.default.fileExists(atPath: $0.deletingLastPathComponent().path) })
        }
    }
    @Test func missingDatabaseIsEmptyAndInvalidDatabaseThrows() throws {
        try withOpenCodeHome { home in
            #expect(try OpenCodeSessionScanner().scan(home: home).events.isEmpty)
            try Data("not sqlite".utf8).write(to: home.appendingPathComponent("opencode.db"))
            #expect(throws: (any Error).self) { try OpenCodeSessionScanner().scan(home: home) }
        }
    }
    @Test func walRecordsReadWithoutChangingSourceSidecars() throws {
        try withOpenCodeHome { home in
            let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
            process.arguments = [home.appendingPathComponent("opencode.db").path]
            let input = Pipe(); let output = Pipe(); process.standardInput = input; process.standardOutput = output
            try process.run()
            input.fileHandleForWriting.write(Data((openCodeSchema + "PRAGMA journal_mode=WAL; INSERT INTO session_message VALUES ('wal','s','assistant',0,'" + openCodeFixture() + "');\n.print ready\n").utf8))
            var ready = Data()
            while !String(decoding: ready, as: UTF8.self).contains("ready") { ready += output.fileHandleForReading.availableData }
            let db = home.appendingPathComponent("opencode.db")
            // Keep the writer connection alive so the committed record remains in WAL.
            let before = try Data(contentsOf: URL(fileURLWithPath: db.path + "-wal"))
            let dbBefore = try Data(contentsOf: db)
            let directoryBefore = try FileManager.default.contentsOfDirectory(atPath: home.path)
            #expect(try OpenCodeSessionScanner().scan(home: home).events.count == 1)
            #expect(try Data(contentsOf: URL(fileURLWithPath: db.path + "-wal")) == before)
            #expect(try Data(contentsOf: db) == dbBefore)
            #expect(try FileManager.default.contentsOfDirectory(atPath: home.path) == directoryBefore)
            input.fileHandleForWriting.closeFile(); process.waitUntilExit()
            #expect(process.terminationStatus == 0)
        }
    }
}

func openCodeFixture(provider: String = "opencode", model: String = "claude-sonnet-4-6", input: Int64 = 100, writes: Int64 = 10, modern: Bool = true, created: Int64 = 1791633600000) -> String {
    let modelFields = modern ? "\"model\":{\"providerID\":\"\(provider)\",\"id\":\"\(model)\"}" : "\"role\":\"assistant\",\"providerID\":\"\(provider)\",\"modelID\":\"\(model)\""
    return """
    {\(modelFields),"agent":"build","content":[],"cost":999,"tokens":{"input":\(input),"output":40,"reasoning":10,"cache":{"read":20,"write":\(writes)}},"time":{"created":\(created),"completed":\(created + 100)},"finish":"stop"}
    """
}
let openCodeSchema = "CREATE TABLE session(id TEXT, time_created INTEGER); CREATE TABLE message(id TEXT,session_id TEXT,time_created INTEGER,data TEXT); CREATE TABLE session_message(id TEXT,session_id TEXT,type TEXT,time_created INTEGER,data TEXT);\n"
func withOpenCodeHome(_ body: (URL) throws -> Void) throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: home) }
    try body(home)
}
func openCodeDatabase(_ home: URL, sql: String) throws {
    let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
    process.arguments = [home.appendingPathComponent("opencode.db").path, openCodeSchema + sql]
    try process.run(); process.waitUntilExit()
    guard process.terminationStatus == 0 else { throw CocoaError(.fileReadCorruptFile) }
}

// Simulate a source changing between copy and validation, with real file operations.
final class SnapshotChangingFileManager: FileManager, @unchecked Sendable {
    private var changes: Int
    var copies = 0
    var targets: [URL] = []
    init(changes: Int) { self.changes = changes; super.init() }
    override func copyItem(at srcURL: URL, to dstURL: URL) throws {
        try super.copyItem(at: srcURL, to: dstURL)
        copies += 1; targets.append(dstURL)
        if changes > 0 {
            try super.setAttributes([.modificationDate: Date(timeIntervalSinceNow: Double(changes))], ofItemAtPath: srcURL.path)
            changes -= 1
        }
    }
}
