import XCTest
@testable import ItemManager

// MARK: - 价格编辑校验（用户 2026-09-18 改价入口）单测
//
// 覆盖 `MidsummerPriceValidator` 的纯函数口径——它与上新表单的价格规则同源，
// 校验口径漂了，改价面板就会写出表单不允许的价格。界面交互由 UI 测试验收。

@MainActor
final class MidsummerPriceEditingTests: XCTestCase {

  // MARK: 单项解析

  func testParseAmountEmptyMeansUnfilled() throws {
    for text in ["", "   ", "\n"] {
      let result = MidsummerPriceValidator.parseAmount(text, label: "现货价")
      let value = try result.get()
      XCTAssertNil(value, "「\(text)」应表示未填（nil）")
    }
  }

  func testParseAmountAcceptsNonNegativeIntegers() throws {
    XCTAssertEqual(try MidsummerPriceValidator.parseAmount("199", label: "现货价").get(), 199)
    XCTAssertEqual(try MidsummerPriceValidator.parseAmount(" 60 ", label: "定金").get(), 60)
    XCTAssertEqual(try MidsummerPriceValidator.parseAmount("0", label: "尾款").get(), 0)
  }

  func testParseAmountRejectsNonIntegers() {
    // 小数、文字、科学计数都不收——与表单「需填整数金额（元）」同文案同口径。
    for text in ["19.9", "abc", "1e3", "１９９"] {
      guard case .failure(let error) = MidsummerPriceValidator.parseAmount(text, label: "预约价")
      else {
        XCTFail("「\(text)」应解析失败")
        continue
      }
      XCTAssertEqual(error.message, "预约价 需填整数金额（元）。")
    }
  }

  func testParseAmountRejectsNegative() {
    guard case .failure(let error) = MidsummerPriceValidator.parseAmount("-5", label: "定金")
    else {
      XCTFail("负数应被拒绝")
      return
    }
    XCTAssertEqual(error.message, "定金 不能为负数。")
  }

  func testParseAmountRejectsOverflow() {
    let huge = String(repeating: "9", count: 30)
    guard case .failure = MidsummerPriceValidator.parseAmount(huge, label: "现货价") else {
      XCTFail("超 Int 范围应解析失败")
      return
    }
  }

  // MARK: 整表校验

  func testValidateAllEmptyIsRejected() {
    guard case .failure(let error) = MidsummerPriceValidator.validate(
      price: "", preorder: "", deposit: "", balance: "")
    else {
      XCTFail("四项全空应被必填校验拦截")
      return
    }
    XCTAssertTrue(error.message.contains("至少填写一项价格"), error.message)
  }

  func testValidateSingleFieldPasses() throws {
    let values = try MidsummerPriceValidator.validate(
      price: "", preorder: "299", deposit: "", balance: ""
    ).get()
    XCTAssertEqual(values.preorderPrice, 299)
    XCTAssertNil(values.price)
    XCTAssertNil(values.deposit)
    XCTAssertNil(values.balance)
  }

  func testValidateFourFieldsTogether() throws {
    let values = try MidsummerPriceValidator.validate(
      price: "399", preorder: "299", deposit: "60", balance: "239"
    ).get()
    XCTAssertEqual(values, MidsummerPriceValues(price: 399, preorderPrice: 299, deposit: 60, balance: 239))
  }

  func testValidateReportsFirstBadField() {
    guard case .failure(let error) = MidsummerPriceValidator.validate(
      price: "12.5", preorder: "", deposit: "", balance: "")
    else {
      XCTFail("小数现货价应被拦截")
      return
    }
    XCTAssertTrue(error.message.contains("现货价"), error.message)
  }

  // MARK: 自动尾款与口径提示

  func testAutoBalanceMatchesFormRule() {
    XCTAssertEqual(MidsummerPriceValidator.autoBalance(preorderPrice: 299, deposit: 60), 239)
    XCTAssertNil(MidsummerPriceValidator.autoBalance(preorderPrice: 60, deposit: 299), "倒挂不算尾款")
    XCTAssertNil(MidsummerPriceValidator.autoBalance(preorderPrice: 299, deposit: nil))
    XCTAssertNil(MidsummerPriceValidator.autoBalance(preorderPrice: nil, deposit: 60))
    XCTAssertNil(MidsummerPriceValidator.autoBalance(preorderPrice: 299, deposit: 299), "相等也不算")
  }

  func testResolvingAutoBalanceFillsOnlyWhenEmpty() {
    // 尾款留空 + 预约价/定金齐全 → 自动补「预约价 − 定金」。
    let filled = MidsummerPriceValidator.resolvingAutoBalance(
      MidsummerPriceValues(price: nil, preorderPrice: 299, deposit: 60, balance: nil))
    XCTAssertEqual(filled.balance, 239)
    // 手改过的尾款不被覆盖（用户 2026-09-18：尾款可手动改）。
    let manual = MidsummerPriceValidator.resolvingAutoBalance(
      MidsummerPriceValues(price: nil, preorderPrice: 299, deposit: 60, balance: 100))
    XCTAssertEqual(manual.balance, 100)
  }

  func testConsistencyHintConsistentAndInconsistent() {
    let consistent = MidsummerPriceValidator.consistencyHint(
      MidsummerPriceValues(price: nil, preorderPrice: 299, deposit: 60, balance: 239))
    XCTAssertEqual(consistent?.consistent, true)
    XCTAssertTrue(consistent?.text.contains("口径一致") == true)

    let drifted = MidsummerPriceValidator.consistencyHint(
      MidsummerPriceValues(price: nil, preorderPrice: 299, deposit: 60, balance: 100))
    XCTAssertEqual(drifted?.consistent, false)
    XCTAssertTrue(drifted?.text.contains("相差") == true)

    // 三者缺一不提示。
    XCTAssertNil(
      MidsummerPriceValidator.consistencyHint(
        MidsummerPriceValues(price: 199, preorderPrice: nil, deposit: nil, balance: nil)))
  }
}
