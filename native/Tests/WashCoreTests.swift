import XCTest
@testable import WashCore

final class WashCoreTests: XCTestCase {
    func ownedCatalog() throws -> JSON {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try JSON.read(Data(contentsOf: root.appendingPathComponent("Resources/OwnedProducts.json")))
    }
    func testOwnedLibraryImportPreservesStockPurchasesAndSnapshotsAndIsOneTime() throws {
        var original = try completed()
        original["products"] = .array(original["products"].array.map { $0.replacing(["place": .string("我的购买地点"), "customTag": .string("保留")]) })
        let catalog = try ownedCatalog(), imported = PersonalLibrary.importOwned(original, catalog: catalog)
        try Backup.validate(imported)
        XCTAssertEqual(catalog.array.count, 21)
        XCTAssertEqual(imported["washes"], original["washes"])
        XCTAssertEqual(imported["history"], original["history"])
        XCTAssertEqual(imported["session"], original["session"])
        XCTAssertEqual(imported["plan"], original["plan"])
        XCTAssertEqual(Set(imported["products"].array.map(\.id)), Set(catalog.array.map(\.id)))
        XCTAssertEqual(Set(imported["deletedProducts"].array.map(\.id)), ["beast", "ironx", "wetcoat", "hydro"])
        let all = imported["products"].array + imported["deletedProducts"].array
        for old in original["products"].array {
            let current = try XCTUnwrap(all.first { $0.id == old.id })
            for key in ["capacity", "remaining", "stockStatus", "price", "date", "place", "instructions", "customTag"] { XCTAssertEqual(current[key], old[key]) }
        }
        let gsf = try XCTUnwrap(imported["products"].array.first { $0.id == "gsf" })
        XCTAssertTrue(PersonalLibrary.uses(gsf).contains("预洗"))
        XCTAssertTrue(PersonalLibrary.uses(gsf).contains("正洗"))
        let edited = imported.replacing(["products": .array(imported["products"].array.filter { $0.id != "qd" }.map { $0.replacing(["coverURL": .string("https://example.com/my-cover.png")]) })])
        XCTAssertEqual(PersonalLibrary.importOwned(edited, catalog: catalog), edited)
    }
    func testBuild5BackupAndActiveWashMigrateToOwnedListWithoutTouchingSnapshots() throws {
        let catalog = try ownedCatalog()
        var old = try completed()
        let bottle = try XCTUnwrap(old["products"].array.first { $0.id == "hydro" })
        let personal = bottle.replacing(["id": .string("personal-bottle"), "name": .string("自定义药剂"), "place": .string("保留购买信息")])
        let oldProducts = old["products"].array
        old["products"] = .array(oldProducts + [personal] + catalog.array.filter { item in !oldProducts.contains { $0.id == item.id } })
        old["catalogImports"] = .array([.string("20261112-01")])
        old = try WashEngine.prepare(old, now: 10000, id: "already-prepared")
        old = old.removing(["deletedProducts"]).replacing(["version": .number(6)])
        var backup = try JSON.read(Backup.encode(old))
        backup["appVersion"] = .number(6)
        let updated = PersonalLibrary.importOwned(try Backup.decode(backup.encoded()), catalog: catalog)
        try Backup.validate(updated)
        XCTAssertEqual(updated["products"].array.count, 21)
        XCTAssertTrue(updated["deletedProducts"].array.contains(personal))
        for key in ["session", "history", "washes", "plan", "templates"] { XCTAssertEqual(updated[key], old[key]) }
        XCTAssertEqual(updated["version"], .number(7))
        let started = try WashEngine.advance(updated["session"], action: "start", actor: "phone", now: 11000)
        try Backup.validate(WashEngine.replacingSession(updated, with: started))
        let restoredBottle = PersonalLibrary.restoreProduct(updated, id: personal.id)
        let newBottle = personal.replacing(["id": .string("bought-later")])
        let changed = restoredBottle.replacing(["products": .array(restoredBottle["products"].array + [newBottle])])
        let restarted = PersonalLibrary.importOwned(try Backup.decode(Backup.encode(changed)), catalog: catalog)
        XCTAssertEqual(restarted, changed)
    }
    func testManualProductDeletionBlocksPreparationAndPreservesAllReferences() throws {
        let catalog = try ownedCatalog(), state = PersonalLibrary.importOwned(try completed(), catalog: catalog)
        let product = try XCTUnwrap(state["products"].array.first { $0.id == "gsf" })
        let deleted = PersonalLibrary.removeProduct(state, id: product.id)
        XCTAssertEqual(PersonalLibrary.removeProduct(deleted, id: product.id), deleted)
        XCTAssertFalse(deleted["products"].array.contains(product))
        XCTAssertTrue(deleted["deletedProducts"].array.contains(product))
        for key in ["plan", "templates", "history", "washes", "session"] { XCTAssertEqual(deleted[key], state[key]) }
        XCTAssertThrowsError(try WashEngine.prepare(deleted)) { XCTAssertTrue($0.localizedDescription.contains(product["name"].text)) }
        XCTAssertThrowsError(try WashEngine.manualUsage(deleted, productID: product.id, amount: 1, location: ""))
        let reloaded = PersonalLibrary.importOwned(try Backup.decode(Backup.encode(deleted)), catalog: catalog)
        XCTAssertEqual(reloaded, deleted)
        let restored = PersonalLibrary.restoreProduct(reloaded, id: product.id)
        XCTAssertEqual(PersonalLibrary.restoreProduct(restored, id: product.id), restored)
        XCTAssertTrue(restored["products"].array.contains(product))
        XCTAssertFalse(restored["deletedProducts"].array.contains(product))
        XCTAssertNoThrow(try WashEngine.prepare(restored))
        XCTAssertThrowsError(try Backup.encode(deleted.replacing(["products": state["products"]])))
        let malformed = product.replacing(["remaining": .number(-1)])
        XCTAssertThrowsError(try Backup.encode(deleted.replacing(["deletedProducts": .array([malformed])])))
    }
    func testOwnedCatalogMatchesExistingBottleByNameAndBrand() throws {
        let catalog = try ownedCatalog(), state = try seed()
        let bottle = try XCTUnwrap(catalog.array.first { $0.id == "retyre" })
            .replacing(["id": .string("my-id"), "place": .string("原购买地点")])
        let updated = PersonalLibrary.importOwned(state.replacing(["products": .array(state["products"].array + [bottle])]), catalog: catalog)
        XCTAssertEqual(updated["products"].array.count, 21)
        XCTAssertFalse(updated["products"].array.contains { $0.id == "retyre" })
        XCTAssertEqual(updated["products"].array.first { $0.id == "my-id" }?["place"], bottle["place"])
    }
    func testOwnedLibraryUnknownCapacityAndGramUnitsRoundTrip() throws {
        let imported = PersonalLibrary.importOwned(try seed(), catalog: try ownedCatalog())
        let restored = try Backup.decode(Backup.encode(imported))
        XCTAssertEqual(restored["products"], imported["products"])
        let oil = try XCTUnwrap(restored["products"].array.first { $0.id == "oil" })
        XCTAssertEqual(PersonalLibrary.unit(oil), "g")
        XCTAssertEqual(oil["capacity"].number, 120)
        XCTAssertEqual(oil["remaining"], .null)
        let qd = try XCTUnwrap(restored["products"].array.first { $0.id == "qd" })
        XCTAssertEqual(qd["capacity"], .null)
        XCTAssertEqual(qd["remaining"], .null)
        var invalid = qd.replacing(["stockStatus": .string("exact"), "remaining": .number(1)])
        XCTAssertThrowsError(try Backup.validateProducts(.array([invalid])))
        invalid = oil.replacing(["quantityUnit": .string("oz")])
        XCTAssertThrowsError(try Backup.validateProducts(.array([invalid])))
    }
    func testGramProductDebitsOnceAndKeepsSnapshotUnit() throws {
        var state = try seed()
        let oil = try XCTUnwrap(try ownedCatalog().array.first { $0.id == "oil" }).replacing(["stockStatus": .string("exact"), "remaining": .number(100)])
        state["products"] = .array(state["products"].array + [oil])
        state["plan"]["steps"] = .array([state["plan"]["steps"].array[0].replacing(["productId": oil["id"], "amount": .number(5), "water": .number(0)])])
        let prepared = try WashEngine.prepare(state, now: 1000, id: "oil-wash")
        XCTAssertEqual(prepared["products"].array.first { $0.id == "oil" }?["remaining"].number, 95)
        XCTAssertEqual(try WashEngine.prepare(prepared), prepared)
        var session = try WashEngine.advance(prepared["session"], action: "start", actor: "phone", now: 2000)
        session = try WashEngine.advance(session, action: "next", actor: "phone", now: 3000)
        let done = WashEngine.replacingSession(prepared, with: session)
        try Backup.validate(done)
        XCTAssertEqual(done["products"], prepared["products"])
        XCTAssertEqual(PersonalLibrary.unit(done["washes"].array[0]["products"].array.first { $0.id == "oil" }!), "g")
        XCTAssertEqual(WashEngine.stockText(oil), "100 g")
    }
    func testDeleteRestorePreservesLedgerSnapshotsAndDoesNotResurrectOnReplay() throws {
        var done = try completed()
        done["washes"] = .array(done["washes"].array.map { $0.replacing(["notes": .string("下次注意玻璃"), "health": .object(["privateSample": .number(42)])]) })
        let id = done["washes"].array[0].id, deleted = PersonalLibrary.removeRecord(done, id: id)
        XCTAssertTrue(deleted["washes"].array.isEmpty)
        XCTAssertEqual(deleted["deletedWashes"].array[0], done["washes"].array[0])
        XCTAssertEqual(deleted["products"], done["products"])
        XCTAssertEqual(deleted["history"], done["history"])
        XCTAssertEqual(WashEngine.replacingSession(deleted, with: deleted["session"])["washes"], .array([]))
        XCTAssertEqual(PersonalLibrary.removeRecord(deleted, id: id), deleted)
        let backed = try Backup.decode(Backup.encode(deleted))
        XCTAssertEqual(backed["deletedWashes"].array[0]["notes"].text, "下次注意玻璃")
        XCTAssertEqual(backed["deletedWashes"].array[0]["health"], .null)
        let restored = PersonalLibrary.restoreRecord(deleted, id: id)
        XCTAssertEqual(restored["washes"], done["washes"])
        XCTAssertEqual(restored["products"], done["products"])
        XCTAssertEqual(restored["history"], done["history"])
        XCTAssertEqual(restored["deletedWashes"], .array([]))
        var duplicate = deleted
        duplicate["washes"] = done["washes"]
        XCTAssertThrowsError(try Backup.encode(duplicate))
    }
    func testActivationAloneDoesNotMeanCompanionIsReady() {
        var s = LinkState(); s.activated = true
        XCTAssertNotNil(s.transferIssue)
        s.paired = true
        XCTAssertTrue(s.transferIssue!.contains("尚未确认手表 App 已安装"))
        s.verified = true
        XCTAssertNotEqual(s.status, "双端通信已验证")
    }
    func testUnreachableInstalledPeerStillAllowsDurableTransfer() {
        var s = LinkState(); s.activated = true; s.paired = true; s.peerInstalled = true
        XCTAssertNil(s.transferIssue)
        XCTAssertTrue(s.status.contains("等待同步机会"))
        s.reachable = true
        XCTAssertTrue(s.status.contains("待验证通信"))
        s.verified = true
        XCTAssertEqual(s.status, "双端通信已验证")
    }
    func testWatchRequiresItsOwnCompanionInstallationFlag() {
        var s = LinkState(); s.phone = false; s.activated = true
        XCTAssertTrue(s.transferIssue!.contains("对应的 iPhone App"))
        s.peerInstalled = true
        XCTAssertNil(s.transferIssue)
    }
    func seed() throws -> JSON {
        let url = Bundle.module.url(forResource: "Seed", withExtension: "json", subdirectory: "Fixtures")!
        return Backup.migrate(try JSON.read(Data(contentsOf: url)))
    }
    func prepared() throws -> JSON { try WashEngine.prepare(seed(), now: 1000, id: "wash-1") }
    func completed() throws -> JSON {
        var state = try prepared()
        var session = try WashEngine.advance(state["session"], action: "start", actor: "phone", now: 2000)
        for i in 0..<session["plan"]["steps"].array.count { session = try WashEngine.advance(session, action: "next", actor: "phone", now: Double(3000 + i * 1000)) }
        state = WashEngine.replacingSession(state, with: session)
        return state
    }
    func testSeedIsValid() throws { try Backup.validate(seed()) }
    func testRealDemoV5ExportImportsWithoutLosingLedgerOrSnapshots() throws {
        let url = Bundle.module.url(forResource: "DemoV5Backup", withExtension: "json", subdirectory: "Fixtures")!
        let data = try Data(contentsOf: url), original = try JSON.read(data)["data"]
        let native = try Backup.decode(data)
        XCTAssertEqual(native["products"], original["products"])
        XCTAssertEqual(native["history"], original["history"])
        XCTAssertEqual(native["washes"].array.map { $0.removing(["noteStatus"]) }, original["washes"].array.map { $0.removing(["noteStatus"]) })
        XCTAssertEqual(native["washes"].array[0]["noteStatus"].text, "open")
        XCTAssertEqual(native["templates"], original["templates"])
        XCTAssertEqual(native["vehicles"], original["vehicles"])
    }
    func testInvalidVehicleAssociationIsRejectedBeforeMigration() throws {
        var backup = try JSON.read(Backup.encode(seed()))
        backup["data"]["plan"]["vehicleId"] = .string("missing-vehicle")
        XCTAssertThrowsError(try Backup.decode(backup.encoded()))
    }
    func testPrepareDebitsOnlyOnceAndDoesNotStartTimer() throws {
        let first = try prepared(), second = try WashEngine.prepare(first, now: 4000, id: "different-id")
        XCTAssertEqual(first, second)
        XCTAssertEqual(first["history"].array.count, 1)
        XCTAssertEqual(first["products"].array.first { $0.id == "gsf" }?["remaining"].number, 740)
        XCTAssertEqual(WashEngine.wallTime(first["session"], now: 9000), 0)
    }
    func testCancelPreparedRunningAndPausedReleasesPlanAndKeepsActualUsage() throws {
        var history = try completed()
        history["washes"] = .array(history["washes"].array.map { $0.replacing(["notes": .string("复查玻璃")]) })
        let previousID = history["session"].id
        XCTAssertEqual(WashEngine.cancel(history, sessionID: previousID), history)
        history["deferredNoteIds"] = .array([.string(previousID)])
        let prepared = try WashEngine.prepare(history, now: 10000, id: "cancel-me")
        let running = try WashEngine.advance(prepared["session"], action: "start", actor: "phone", now: 11000)
        let progressed = try WashEngine.advance(running, action: "next", actor: "phone", now: 12000)
        let paused = try WashEngine.advance(progressed, action: "pause", actor: "phone", now: 13000)
        for session in [prepared["session"], progressed, paused] {
            let active = WashEngine.replacingSession(prepared, with: session)
            let cancelled = WashEngine.cancel(active, sessionID: session.id)
            XCTAssertFalse(WashEngine.isActive(cancelled))
            XCTAssertEqual(cancelled["session"], .null)
            XCTAssertEqual(cancelled["products"], active["products"])
            XCTAssertEqual(cancelled["history"], active["history"])
            XCTAssertEqual(cancelled["washes"], history["washes"])
            XCTAssertEqual(cancelled["plan"], active["plan"])
            XCTAssertEqual(WashEngine.pendingNotes(cancelled).map(\.id), [previousID])
            XCTAssertEqual(WashEngine.cancel(cancelled, sessionID: session.id), cancelled)
            let restored = try Backup.decode(Backup.encode(cancelled))
            XCTAssertEqual(restored, cancelled)
            let next = try WashEngine.prepare(restored, now: 14000, id: "new-wash")
            XCTAssertEqual(next["session"].id, "new-wash")
            XCTAssertEqual(next["history"].array.count, cancelled["history"].array.count + 1)
            XCTAssertEqual(WashEngine.cancel(next, sessionID: session.id), next)
        }
    }
    func testCancelledWatchHandoffIgnoresLateCompletionAcrossNewWash() throws {
        let assigned = try WashEngine.assignWatch(prepared())
        var watch = try WashEngine.advance(assigned["session"], action: "start", actor: "watch", now: 2000)
        for _ in watch["plan"]["steps"].array {
            watch = try WashEngine.advance(watch, action: "next", actor: "watch", now: 3000)
        }
        let cancelled = WashEngine.cancel(assigned, sessionID: watch.id)
        XCTAssertEqual(try WashEngine.acceptWatchProgress(cancelled, incoming: watch), cancelled)
        let next = try WashEngine.assignWatch(WashEngine.prepare(cancelled, now: 4000, id: "another-watch"))
        XCTAssertEqual(try WashEngine.acceptWatchProgress(next, incoming: watch), next)
    }
    func testSameBottleAggregatesAcrossSteps() throws {
        var state = try seed()
        let step = state["plan"]["steps"].array[0].replacing(["id": .string("extra")])
        state["plan"]["steps"] = .array(state["plan"]["steps"].array + [step])
        let result = try WashEngine.prepare(state)
        XCTAssertEqual(result["products"].array.first { $0.id == "gsf" }?["remaining"].number, 720)
    }
    func testUnknownAndInsufficientInventoryAreBlocked() throws {
        var state = try seed()
        let original = state
        state["products"] = .array(state["products"].array.map { $0.id == "gsf" ? $0.replacing(["stockStatus": .string("unknown"), "remaining": .null]) : $0 })
        XCTAssertThrowsError(try WashEngine.prepare(state))
        state = original
        state["products"] = .array(state["products"].array.map { $0.id == "gsf" ? $0.replacing(["remaining": .number(1)]) : $0 })
        XCTAssertThrowsError(try WashEngine.prepare(state))
    }
    func testPauseAndCompletionDoNotDebitAgain() throws {
        let state = try prepared()
        var session = try WashEngine.advance(state["session"], action: "start", actor: "phone", now: 2000)
        session = try WashEngine.advance(session, action: "pause", actor: "phone", now: 4000)
        XCTAssertEqual(WashEngine.activeTime(session, now: 6000), 2000)
        XCTAssertEqual(try WashEngine.advance(session, action: "next", actor: "phone", now: 6000), session)
        session = try WashEngine.advance(session, action: "pause", actor: "phone", now: 7000)
        for _ in 0..<4 { session = try WashEngine.advance(session, action: "next", actor: "phone", now: 9000) }
        XCTAssertEqual(session["activeMs"].number, 4000)
        let done = WashEngine.replacingSession(state, with: session)
        XCTAssertEqual(done["products"], state["products"])
        XCTAssertEqual(done["washes"].array.count, 1)
        XCTAssertEqual(done["washes"].array[0]["durationMs"].number, 7000)
        XCTAssertEqual(WashEngine.replacingSession(done, with: session)["washes"].array.count, 1)
    }
    func testSnapshotsAreIndependentOfCurrentProductEdits() throws {
        var state = try completed()
        let snapshot = state["washes"]["unused"] // also verify absent paths are safe
        XCTAssertEqual(snapshot, .null)
        let old = state["washes"].array[0]["products"]
        state["products"] = .array(state["products"].array.map { $0.replacing(["instructions": .string("new instructions")]) })
        XCTAssertEqual(state["washes"].array[0]["products"], old)
    }
    func testBackupRoundTripKeepsExtraFieldsAndStripsHealth() throws {
        var state = try completed()
        state["customMetadata"] = .object(["tag": .string("保留")])
        state["washes"] = .array(state["washes"].array.map { $0.replacing(["health": .object(["sample": .number(42)]), "notes": .string("注意轮毂")]) })
        let restored = try Backup.decode(Backup.encode(state))
        XCTAssertEqual(restored["products"], state["products"])
        XCTAssertEqual(restored["history"], state["history"])
        XCTAssertEqual(restored["customMetadata"], state["customMetadata"])
        XCTAssertEqual(restored["washes"].array[0]["notes"].text, "注意轮毂")
        XCTAssertEqual(restored["washes"].array[0]["health"], .null)
    }
    func testMalformedBackupsAreRejected() throws {
        let data = try Backup.encode(seed())
        for patch: [String: JSON] in [["volumeUnit": .string("oz")], ["appVersion": .number(99)], ["healthDataIncluded": .bool(true)], ["attachments": .array([.string("photo")])]] {
            let modified = try JSON.read(data).replacing(patch)
            XCTAssertThrowsError(try Backup.decode(modified.encoded()))
        }
        var invalid = try seed()
        invalid["products"] = .array(invalid["products"].array + [invalid["products"].array[0]])
        XCTAssertThrowsError(try Backup.encode(invalid))
        XCTAssertThrowsError(try Backup.decode(Data(repeating: 0, count: Backup.maxBytes + 1)))
    }
    func testLegacyMigrationDoesNotReseedInventory() throws {
        var legacy = try seed()
        legacy = legacy.removing(["vehicles", "templates", "settings", "washes"])
        legacy["version"] = .number(2)
        legacy["products"] = .array([legacy["products"].array[0].removing(["stockStatus"]).replacing(["remaining": .number(123)])])
        legacy["plan"]["steps"] = .array([legacy["plan"]["steps"].array[1]])
        legacy["plan"] = legacy["plan"].removing(["vehicleId", "vehicleModel"])
        let migrated = Backup.migrate(legacy)
        try Backup.validate(migrated)
        XCTAssertEqual(migrated["products"].array.count, 1)
        XCTAssertEqual(migrated["products"].array[0]["remaining"].number, 123)
        XCTAssertEqual(migrated["products"].array[0]["stockStatus"].text, "estimated")
        XCTAssertFalse(migrated["plan"]["vehicleId"].text.isEmpty)
    }
    func testLegacyUntimedSessionContinuesWithoutAnotherDebit() throws {
        var legacy = try prepared()
        legacy["version"] = .number(2)
        legacy["session"] = legacy["session"].removing(["owner", "revision", "status", "preparedAt", "startedAt", "resumedAt", "activeMs"])
        let migrated = Backup.migrate(legacy, now: 9000)
        try Backup.validate(migrated)
        XCTAssertEqual(migrated["products"], legacy["products"])
        XCTAssertEqual(migrated["history"], legacy["history"])
        XCTAssertEqual(migrated["session"]["owner"].text, "phone")
        XCTAssertEqual(migrated["session"]["startedAt"].number, 9000)
        XCTAssertTrue(migrated["session"]["timingRestored"].flag)
        XCTAssertEqual(try WashEngine.prepare(migrated), migrated)
    }
    func testWatchOwnershipBlocksPhoneAndDuplicateProgress() throws {
        let assigned = try WashEngine.assignWatch(prepared())
        XCTAssertThrowsError(try WashEngine.advance(assigned["session"], action: "start", actor: "phone", now: 2000))
        var progress = try WashEngine.advance(assigned["session"], action: "start", actor: "watch", now: 2000)
        let started = try WashEngine.acceptWatchProgress(assigned, incoming: progress)
        XCTAssertEqual(try WashEngine.acceptWatchProgress(started, incoming: progress), started)
        let stale = progress
        progress = try WashEngine.advance(progress, action: "next", actor: "watch", now: 3000)
        let advanced = try WashEngine.acceptWatchProgress(started, incoming: progress)
        XCTAssertEqual(try WashEngine.acceptWatchProgress(advanced, incoming: stale), advanced)
        var tampered = progress
        tampered["plan"]["name"] = .string("unexpected")
        tampered["revision"] = .number(99)
        XCTAssertEqual(try WashEngine.acceptWatchProgress(advanced, incoming: tampered), advanced)
    }
    func testWatchFinishedRecordIsIdempotent() throws {
        let assigned = try WashEngine.assignWatch(prepared())
        var s = try WashEngine.advance(assigned["session"], action: "start", actor: "watch", now: 2000)
        for _ in 0..<4 { s = try WashEngine.advance(s, action: "next", actor: "watch", now: 4000) }
        let finished = try WashEngine.acceptWatchProgress(assigned, incoming: s)
        XCTAssertEqual(finished["washes"].array.count, 1)
        XCTAssertEqual(try WashEngine.acceptWatchProgress(finished, incoming: s), finished)
        XCTAssertEqual(finished["products"], assigned["products"])
    }
    func testActiveWatchBackupCannotCreateSecondExecutor() throws {
        let assigned = try WashEngine.assignWatch(prepared())
        XCTAssertThrowsError(try Backup.decode(Backup.encode(assigned)))
    }
    func testPendingWatchCancellationsStayWithLocalPairing() throws {
        let ids: JSON = .array([.string("previous-wash")])
        let original = try seed().replacing(["pendingWatchCancellations": ids])
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(identifier())
        defer { try? FileManager.default.removeItem(at: directory) }
        let repo = StateRepository(url: directory.appendingPathComponent("State.json"))
        try repo.save(original)
        let reloaded = try repo.load { XCTFail("Expected saved state"); return .null }
        XCTAssertEqual(reloaded["pendingWatchCancellations"], ids)
        var backup = try JSON.read(Backup.encode(original))
        XCTAssertEqual(backup["data"]["pendingWatchCancellations"], .null)
        backup["data"]["pendingWatchCancellations"] = ids
        XCTAssertEqual(try Backup.decode(backup.encoded())["pendingWatchCancellations"], .null)
    }
    func testPendingNotesOnlyForCurrentVehicle() throws {
        var state = try completed()
        state["washes"] = .array(state["washes"].array.map { $0.replacing(["notes": .string("轮毂水渍")]) })
        XCTAssertEqual(WashEngine.pendingNotes(state).count, 1)
        state["deferredNoteIds"] = .array([state["washes"].array[0]["id"]])
        XCTAssertEqual(WashEngine.pendingNotes(state).count, 0)
        state["deferredNoteIds"] = .array([])
        state["plan"]["vehicleId"] = .string("other-vehicle")
        XCTAssertEqual(WashEngine.pendingNotes(state).count, 0)
    }
    func testFailedWriteLeavesOriginalAndRestoreCreatesRollback() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(identifier())
        defer { try? FileManager.default.removeItem(at: directory) }
        let repo = StateRepository(url: directory.appendingPathComponent("State.json"))
        let original = try seed()
        try repo.save(original)
        var invalid = original; invalid["products"] = .null
        XCTAssertThrowsError(try repo.save(invalid))
        XCTAssertEqual(try JSON.read(Data(contentsOf: repo.url)), original)
        let next = try prepared()
        try repo.restore(next)
        XCTAssertEqual(try JSON.read(Data(contentsOf: directory.appendingPathComponent("BeforeRestore.json"))), original)
        XCTAssertEqual(try repo.load { XCTFail("Must not reseed"); return .null }, next)
    }
    func testFutureLocalStoreIsNotDowngradedOrReseeded() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(identifier())
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let repo = StateRepository(url: directory.appendingPathComponent("State.json"))
        var future = try seed(); future["version"] = .number(99)
        let bytes = try future.encoded()
        try bytes.write(to: repo.url)
        XCTAssertThrowsError(try repo.load { XCTFail("Must not replace future data with seed"); return .null })
        XCTAssertEqual(try Data(contentsOf: repo.url), bytes)
    }
}
