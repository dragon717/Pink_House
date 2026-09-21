# XCUITest 高频坑

读取时机：写或改 XCUITest / UI 测试之前。全部为本机实测。

## 一、定位元素

1. **查按钮用 `accessibilityLabel`，不是屏幕上的文字。** 例：品牌列表的「进店」按钮 label 其实是
   `进入品牌档案`，用 `app.buttons["进店"]` 会**永远找不到且不报错**。
   最快排查：把 `app.debugDescription` 当文本附件导出来搜。
2. **`app.buttons["xx"]` 返回单个元素**，多个匹配时不能用 `.count` / `.element(boundBy:)`。按顺序取要用 query：
   ```swift
   let q = app.buttons.matching(NSPredicate(format: "label == %@", "进入品牌档案"))
   q.element(boundBy: q.count - 1).tap()
   ```
3. **`app.buttons.element(boundBy: 0)` 不是"页面第一个业务按钮"**，很可能是底部 dock 的 tab。
   宁可先用 staticText 定位，再 `.tap()` 让它冒泡到父视图手势。
4. **SwiftUI `Image` 默认不是 a11y 元素**：直接贴 `.accessibilityIdentifier` 不会进层级，
   `app.images[...]` 永远查不到。必须先 `.accessibilityElement(children: .ignore)` 再加 label + identifier。
5. **identifier 必须纯 ASCII**：含中文会在层级里被截断成空前缀，查询永远落空。
   中文放 `accessibilityLabel`，再按 label 查。
6. **`.accessibilityElement(children: .combine)` 的落桶不定**（实测会落在 `StaticText` 而非 `otherElements`）。
   别赌元素类型，用 `app.descendants(matching: .any).matching(identifier:)`。
7. **`DisclosureGroup` 的 identifier 会覆盖全部子元素的 identifier**，但子元素自己的 label 保留。
   断言内部内容按 label 查。
8. **identifier 挂错层**：外层包 `.accessibilityElement(children: .contain)` 容器时，
   在视图外部加 identifier 会落到**整卡容器**上，点击 = 开详情。卡片内嵌按钮的 identifier 必须挂在按钮本体上。
9. **同一屏出现同名文案时 `firstMatch` 会点错行**：用 ASCII identifier 前缀 + `BEGINSWITH` 锁定。

## 二、点击命中

10. **`isHittable == true` ≠ 能点到。** 本工程底部有悬浮 dock（约占 y 788–852pt，窗口高 874pt）。
    实测屏底卡片按钮 frame `y=855.5, h=32.7`，`isHittable` 仍为 `true`，但中心点已落在 dock / 系统手势区，
    `tap()` 下去**什么都不会发生**——不报错、不抛异常、界面毫无变化。
    判定「真点得到」要自己加安全区边界：
    ```swift
    @MainActor
    private func isComfortablyVisible(_ e: XCUIElement, app: XCUIApplication) -> Bool {
      guard e.isHittable else { return false }
      let f = e.frame
      return f.minY >= 120 && f.maxY <= app.frame.height - 140
    }
    ```
11. **dock 压住的按钮可能"成功命中 dock"**：点击落到悬浮 dock 上把 App **切到「我」tab**，
    后续断言在错误页面上找不到目标。识别线索：失败截图根本不是预期页面。
12. **底部抽屉的滚动**：`app.swipeUp()` 起点在屏幕中央，会滑到抽屉**后面**的详情页上。
    用抽屉底部常驻确认按钮做坐标锚点，在其上方滚动区内自下而上拖：
    ```swift
    confirm.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: -0.6))
      .press(forDuration: 0.05, thenDragTo:
        confirm.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: -5.0)))
    ```
13. **scaledToFill 图的 a11y frame 是裁切前的溢出图框**，不能当几何锚点（详情头图可视槽位 200pt，
    a11y 却报 `{y:31, h:402}`）。几何锚点改用**唯一文本行**做基准。

## 三、懒渲染

14. **`LazyVStack` / `LazyVGrid` / `Form` 只渲染屏内元素**：屏外条目在层级里**根本不存在**
    （不是"不可点"）。断言列表尾部条目要 `swipeUp` 循环找；回顶部找不到时先 `swipeDown` 回顶——
    向下滚过头后顶部条目会被回收，怎么 swipeUp 都找不回来。
15. **别用首屏之外的字段当「页面打开了没有」的锚点**。`Form` 下部的字段不在层级里，
    会被误报成"点击没打开页面"。锚点要选**首屏必然可见**的元素（导航栏标题、静态说明文案）。

## 四、断言写法

16. **把「点了没反应」拆成三条分支**，否则排查信息量为零：
    ```swift
    if successFeedback.exists { capture("24-成功") }
    else if failureFeedback.exists { XCTFail("显示失败反馈 → 写库抛错，去查 App 日志") }
    else { XCTFail("两种反馈都没有 → 点击很可能没落到按钮上") }
    ```
    同时把待点元素的 `frame` / `isHittable` / 同名元素数量当文本附件留档。
17. **「guard 导航失败就 return」的测试是空跑通过**。修复导航路径后，过期断言会集中爆出来。
    打通新导航路径时要顺着走到最后一条断言逐条核对，不要只看"测试绿了"。
    识别特征：耗时异常短 + 附件里出现「00-找不到…」。
18. **锁卡前缀只写到逗号前**。卡片 a11y label 形如「樱花小羊，现货价 ¥59–999」，
    价格口径一改，用完整前缀匹配的 `openDetail` 会集体失效 → 整条用例空跑通过。

## 五、输入

19. **`typeText` 前必须确认键盘已弹出**：tap 后偶发没拿到焦点，`typeText` 直接抛
    "Neither element nor any descendant has keyboard focus"。本 SDK 的 `XCUIElement` **没有**
    `hasKeyboardFocus` 属性，用 `app.keyboards.firstMatch.waitForExistence(timeout:)` 作焦点信号，
    失败重试 tap（最多 3-4 次）。
20. **收键盘**：SwiftUI TextField 用 `typeText("...\n")`；numberPad 没有 return 键，用 `app.swipeDown()`
    （配合 `.scrollDismissesKeyboard(.interactively)`）。
21. **中文键盘的删除键可能滚不到可视区**：拼音键盘下 `app.keys["delete"]` label 是「删除」，
    AX scrollToVisible 反复失败会把单条用例拖到 10 分钟以上。行内编辑不要用 delete 键清空重输——
    改用"追加输入"后断言 value 包含追加内容。
22. **sheet 叠 sheet 时**等内层真正 dismiss（锚点元素消失）再操作外层，否则同名元素双匹配。

## 六、其他

23. **反模式：删掉错误提示会让失败变成静默。** 若某个 `@State` 错误文案原本渲染在界面上，
    重构时把渲染删了（只留赋值），失败就变成"点了没反应"。**写库失败必须有和成功一样显眼的就地反馈。**
24. **改种子 JSON 前先探字段形状**：同一资源里同义字段形状不一
    （`midsummer-series.json` 的 `variantImageNames` 是**字典**，`sizeChartImages`/`skus`/`colors` 是数组），
    用 `a + b` 合并会在字典上直接 `TypeError`。字典用 `update`，数组追加前先断言 id 无冲突。
25. **给带显式 init 的 SwiftUI 结构体加新参数**：memberwise init 不可用，新参数必须同时改 init 签名与赋值。
    可选回调放参数表**末尾**并给默认值 nil。
26. **一条消息里对同一文件发多个 Edit 会互相覆盖**：并行 Edit 同一文件时，后面的调用基于旧内容写回，
    前面的修改静默丢失。串行：一次消息只改同一文件的一处。
