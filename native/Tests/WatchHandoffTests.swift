import XCTest
@testable import WashCore

extension WashCoreTests {
    func testReplacementHandoffWaitsForPersistedWatchCancellation() throws {
        let original = try WashEngine.assignWatch(prepared())
        let first = original["session"]
        let cancelled = WatchHandoff.cancel(original, sessionID: first.id)
        XCTAssertEqual(cancelled["products"], original["products"])
        XCTAssertEqual(cancelled["history"], original["history"])
        XCTAssertEqual(WatchHandoff.cancel(cancelled, sessionID: first.id), cancelled)

        let replacement = try WashEngine.assignWatch(WashEngine.prepare(cancelled, now: 3000, id: "wash-2"))
        // Reload the phone before the Watch has received either message.
        let phone = Backup.migrate(try JSON.read(replacement.encoded()))
        let control = try XCTUnwrap(WatchHandoff.nextTransfer(phone))
        XCTAssertEqual(control.kind, "cancel")
        XCTAssertEqual(control.payload.id, first.id)
        let hash = try WashEngine.checksum(control.payload)
        XCTAssertTrue(try WatchHandoff.validReceipt(control.payload, checksum: hash))
        XCTAssertFalse(try WatchHandoff.validReceipt(control.payload, checksum: "invalid"))
        XCTAssertEqual(WatchHandoff.acknowledge(phone, sessionID: "another"), phone)

        let retired = WatchHandoff.retiring(first.id, in: .object(["session": .null, "retired": .array([])]))
        // The watch restarts, then receives the delayed, original plan.
        let watch = try JSON.read(retired.encoded())
        XCTAssertEqual(try WatchHandoff.receivingPlan(first, checksum: WashEngine.checksum(first), in: watch), watch)
        let acknowledged = WatchHandoff.acknowledge(phone, sessionID: first.id)
        let packet = try XCTUnwrap(WatchHandoff.nextTransfer(acknowledged))
        XCTAssertEqual(packet.kind, "plan")
        XCTAssertEqual(packet.payload.id, "wash-2")

        let started = try startOnWatch(packet.payload, in: watch, now: 4000)
        XCTAssertEqual(WatchHandoff.retiring(first.id, in: started), started)
        XCTAssertEqual(try WatchHandoff.receivingPlan(first, checksum: WashEngine.checksum(first), in: started), started)
        XCTAssertEqual(try WatchHandoff.receivingPlan(packet.payload, checksum: WashEngine.checksum(packet.payload), in: started), started)
        XCTAssertEqual(WatchHandoff.acknowledge(acknowledged, sessionID: first.id), acknowledged)
    }

    func testWatchCancellationRetiresAnOfflineInProgressSession() throws {
        let assigned = try WashEngine.assignWatch(prepared())
        let plan = assigned["session"]
        let running = try startOnWatch(plan, in: .object([:]), now: 2000)
        let retired = WatchHandoff.retiring(plan.id, in: running)
        XCTAssertEqual(retired["session"], .null)
        XCTAssertEqual(retired["retired"], .array([.string(plan.id)]))
        XCTAssertEqual(WatchHandoff.retiring(plan.id, in: retired), retired)
        let phone = WatchHandoff.cancel(assigned, sessionID: plan.id)
        XCTAssertEqual(try WashEngine.acceptWatchProgress(phone, incoming: running["session"]), phone)
    }

    private func startOnWatch(_ plan: JSON, in document: JSON, now: Double) throws -> JSON {
        let accepted = try WatchHandoff.receivingPlan(plan, checksum: WashEngine.checksum(plan), in: document)
        let running = try WashEngine.advance(accepted["session"], action: "start", actor: "watch", now: now)
        return accepted.replacing(["session": running])
    }
}
