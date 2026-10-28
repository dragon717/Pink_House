import XCTest
@testable import ItemManager

@MainActor
final class SeriesAnalyzerTests: XCTestCase {
    func testLiyuanBalanceUsesCurrentAmountsAndCountsStockExactlyOnce() async throws {
        // 真机副本的小物明细 + 截图中的衣物金额：重复的小物尾款恰好为 418。
        let clothes = liyuanClothes(opBalance: 518)
        let historicalTotal = clothes.reduce(Decimal(0)) { sum, clothing in
            let attached = (clothing.accessoryItems ?? []).reduce(Decimal(0)) { $0 + $1.balance }
            return sum + (clothing.balance + attached) * Decimal(clothing.stock)
        }
        XCTAssertEqual(historicalTotal, 8352)
        let beforeResult = await SeriesAnalyzer.shared.analyzeSeries(from: clothes)
        let before = try XCTUnwrap(beforeResult.first)
        XCTAssertEqual(before.name, "梨园梦瓷")
        XCTAssertEqual(before.itemCount, 10)
        XCTAssertEqual(before.totalBalance, 7934)
        XCTAssertEqual(historicalTotal - before.totalBalance, 418)
        XCTAssertEqual(before.totalDeposit, 2050)
        XCTAssertEqual(before.clothingIDs, Set(clothes.map(\.id)))
        // 列表与详情、系列、支付待付额必须共用同一份金额。
        XCTAssertEqual(clothes.reduce(0) { $0 + $1.wardrobeListTotalBalance }, 7934)
        XCTAssertEqual(clothes.reduce(0) { $0 + WealthSavingLedger.finalPaymentDueAmount(for: $1) }, 7934)
        clothes[0].balance += 50
        let updatedResult = await SeriesAnalyzer.shared.analyzeSeries(from: clothes)
        let updated = try XCTUnwrap(updatedResult.first)
        XCTAssertEqual(updated.totalBalance, 7984)
        XCTAssertEqual(updated.id, before.id)
    }

    func testReadOnlyPhoneSnapshotWithOlderUnitPricesExplainsSecondScreenshot() async throws {
        // 只读手机副本中前三条主衣物仍为 568，较图一每件高 50，共 5 件，相差 250。
        let clothes = liyuanClothes(opBalance: 568)
        let series = await SeriesAnalyzer.shared.analyzeSeries(from: clothes)
        XCTAssertEqual(series.first?.totalBalance, 8184)
        XCTAssertEqual(8184 - 7934, 250)
        let historicalTotal = clothes.reduce(Decimal(0)) { sum, clothing in
            let attached = (clothing.accessoryItems ?? []).reduce(Decimal(0)) { $0 + $1.balance }
            return sum + (clothing.balance + attached) * Decimal(clothing.stock)
        }
        XCTAssertEqual(historicalTotal, 8602)
        XCTAssertEqual(historicalTotal - (series.first?.totalBalance ?? 0), 418)
    }

    func testOverlappingMelodyPrefixesBecomeOneExclusiveSeries() async throws {
        let clothes = [
            Clothing(name: "美乐蒂联名 OP", balance: 100, isDepositPlan: true, stock: 2),
            Clothing(name: "【美乐蒂】联名 KC", balance: 40, isDepositPlan: true),
            Clothing(name: "美乐蒂蜜糖邦尼 同期", balance: 96, isDepositPlan: true),
            Clothing(name: "美乐蒂蜜糖 发带", balance: 40, isDepositPlan: true),
            Clothing(name: "蜜糖邦尼 OP", balance: 88, isDepositPlan: true)]
        let series = await SeriesAnalyzer.shared.analyzeSeries(from: clothes)
        XCTAssertEqual(series.count, 2)
        let melody = try XCTUnwrap(series.first { $0.name == "美乐蒂" })
        XCTAssertEqual(melody.itemCount, 5)
        XCTAssertEqual(melody.totalBalance, 376)
        XCTAssertEqual(melody.clothingIDs, Set(clothes.prefix(4).map(\.id)))
        XCTAssertEqual(series.reduce(0) { $0 + $1.totalBalance },
                       clothes.reduce(0) { $0 + $1.pendingFinalPaymentAmount })
        XCTAssertEqual(series.reduce(0) { $0 + $1.clothingIDs.count }, clothes.count)
        XCTAssertTrue(series[0].clothingIDs.isDisjoint(with: series[1].clothingIDs))
    }

    func testCaseBracketsAndInputOrderDoNotCreateExtraGroupsOrChangingIDs() async {
        let clothes = [Clothing(name: "【Pink】 OP", balance: 100, isDepositPlan: true),
                       Clothing(name: "pink JSK", balance: 150, isDepositPlan: true),
                       Clothing(name: "PINK KC", balance: 25, isDepositPlan: true)]
        let series = await SeriesAnalyzer.shared.analyzeSeries(from: clothes)
        let reversed = await SeriesAnalyzer.shared.analyzeSeries(from: clothes.reversed())
        XCTAssertEqual(series, reversed)
        XCTAssertEqual(series.map(\.name), ["pink"])
        XCTAssertEqual(series.first?.totalBalance, 275)
    }

    func testAccessoriesAndStockUseModelTotalsWithoutAddingDepositAgain() async throws {
        let clothing = Clothing(name: "梨园梦瓷 OP", price: 800, deposit: 200, balance: 600,
                                isDepositPlan: true, stock: 2)
        clothing.accessoryItems = [AccessoryItem(name: "发带", price: 50, deposit: 10, balance: 40)]
        let seriesResult = await SeriesAnalyzer.shared.analyzeSeries(from: [clothing])
        let series = try XCTUnwrap(seriesResult.first)
        XCTAssertEqual(series.totalBalance, 1240)
        XCTAssertEqual(series.totalDeposit, 410)
        XCTAssertEqual(series.itemCount, 2)
    }

    func testFilteringAndRenamingRecomputeMembershipAndTotals() async throws {
        let first = Clothing(name: "美乐蒂联名 OP", balance: 200, isDepositPlan: true)
        let second = Clothing(name: "美乐蒂蜜糖 KC", balance: 50, isDepositPlan: true)
        let full = await SeriesAnalyzer.shared.analyzeSeries(from: [first, second])
        XCTAssertEqual(full.map(\.name), ["美乐蒂"])
        let filteredResult = await SeriesAnalyzer.shared.analyzeSeries(from: [second])
        let filtered = try XCTUnwrap(filteredResult.first)
        XCTAssertEqual(filtered.totalBalance, 50)
        XCTAssertEqual(filtered.clothingIDs, [second.id])
        second.name = "珍宝珠联名 KC"
        let renamed = await SeriesAnalyzer.shared.analyzeSeries(from: [first, second])
        XCTAssertEqual(renamed.count, 2)
        XCTAssertEqual(renamed.reduce(0) { $0 + $1.totalBalance }, 250)
    }

    func testEmptyShortNamesAndDuplicateInputNeverLoseOrDoubleCountRecords() async {
        let short = Clothing(name: "裙", balance: 10, isDepositPlan: true)
        let empty = Clothing(name: "【】 ", balance: 20, isDepositPlan: true)
        let groups = await SeriesAnalyzer.shared.analyzeSeries(from: [short, short, empty])
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups.reduce(0) { $0 + $1.totalBalance }, 30)
        XCTAssertEqual(groups.reduce(0) { $0 + $1.itemCount }, 2)
        let none = await SeriesAnalyzer.shared.analyzeSeries(from: [])
        XCTAssertTrue(none.isEmpty)
    }

    func testSingleLetterPrefixAndSpacedNameDoNotCreateDuplicateDisplayIDs() async {
        let groups = await SeriesAnalyzer.shared.analyzeSeries(from: [
            Clothing(name: "A", balance: 10, isDepositPlan: true),
            Clothing(name: "A OP", balance: 20, isDepositPlan: true)])
        XCTAssertEqual(groups.map(\.id), ["a"])
        XCTAssertEqual(groups.first?.totalBalance, 30)
    }
    private func liyuanClothes(opBalance: Int) -> [Clothing] {
        let rows: [(String, Int, Int, Int, [(String, Int, Int)])] = [
            ("高腰 op", 1, opBalance, 130, [("发箍", 79, 30), ("边夹", 44, 20)]),
            ("高腰 op", 2, opBalance, 130, [("发箍", 79, 30), ("边夹", 44, 20)]),
            ("op", 2, opBalance, 130, [("发箍", 79, 30)]),
            ("dress", 2, 939, 230, [("发带", 108, 40)]),
            ("dress", 2, 939, 230, [("发带", 108, 40)]),
            ("dress", 1, 939, 230, [("发带", 108, 40)])]
        return rows.map { name, stock, balance, deposit, accessories in
            let clothing = Clothing(name: "梨园梦瓷 \(name)", deposit: Decimal(deposit),
                                    balance: Decimal(balance), isDepositPlan: true, stock: stock)
            clothing.accessoryItems = accessories.map { name, balance, deposit in
                AccessoryItem(name: name, price: Decimal(balance + deposit),
                              deposit: Decimal(deposit), balance: Decimal(balance))
            }
            return clothing
        }
    }

}
