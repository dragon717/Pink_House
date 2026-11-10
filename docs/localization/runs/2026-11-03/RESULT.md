# 4.4 海外上架核验 · 2026-11-03

App ID `6758352161`，Bundle ID `bugod2.ItemManager`。本次候选构建为 **4.4（3）**。北京时间 2026-11-04 01:15:31，Apple 返回 `Upload succeeded.` 和 `Uploaded package is processing.`。随后在 TestFlight 后台看到构建 3 的状态为「准备提交」。4.4 的商店版本草稿尚未选择构建，等待最终更新包。[构建 3 上传回执](../../../../output/app-store-4.4/proof/testflight-upload-3.log)

**4.4（2）禁止用于正式提审。** 随后的 Xcode 本地 StoreKit 测试中，60 喵币档的同一笔交易（`transactionID=0`）产生了两条 `coin_delivery_completed`。未完成交易补发路径 `Transaction.unfinished` 入账 120 喵币，监听路径 `Transaction.updates` 又入账 66 喵币，合计 186。该首购应入账 120，实测多发 66。[构建 2 本地交易诊断](../../../../output/app-store-4.4/proof/local27-listener-diagnostics/)

**4.4（3）通过本地 StoreKit 防重验收。** 两项测试全部通过，零失败、零跳过。60 喵币档首购流水 0 仅入账 120，复购流水 1 仅入账 66，中断恢复没有再次入账。Release 归档、签名和导出均通过。[测试结果](../../../../output/app-store-4.4/proof/credit-confirm-3.xcresult) · [充值流水摘要](../../../../output/app-store-4.4/proof/4.4-3-充值核验.txt) · [签名记录](../../../../output/app-store-4.4/proof/archive-3-signature.log) · [导出记录](../../../../output/app-store-4.4/proof/export-3.log)

主上架对话已保存并回读 4.4 九语版本资料、App 名称及副标题。九语商店资料包已与保存的名称对齐。TestFlight 实购、生产购买及地区开放仍待后台验证或操作。

## 商店地区

2026-11-03 逐区查询的 175 个商店中，仅中国大陆返回《少女心愿》1.0.7，其余 174 个海外商店均返回零条记录。本次公开查询全部成功。

按 Apple 的 storefront 列表，以各地区代码逐一查询公开目录，核对返回的 App ID 和 Bundle ID。每个结果附 UTC 时间。`listed` 表示找到匹配商品，`no_result` 表示 Apple Lookup 返回零条记录，`unverified` 表示请求未得出结论。主上架对话随后在后台确认主 App 为 1 个地区可供应、174 个未供应。[逐区 CSV](./public-storefronts.csv) · [Apple 地区表](https://developer.apple.com/help/app-store-connect/reference/app-information/app-store-localizations/) · [中国大陆查询](https://itunes.apple.com/lookup?id=6758352161&country=cn)

## 九语商品页交付

[下载 4.4 九语商店资料](../../../../output/app-store-4.4/少女心愿-4.4-九语商店资料.zip)。九种 ASC locale 各有名称、副标题、描述、推广文案、关键词和更新说明，TXT 可逐字段粘贴。每种语言另有一份六档喵币 CSV，按完整 Product ID 录入。包内 JSON 汇集所有字段，支持和隐私网址另列为待核项。

已从交付 ZIP 反读并核验 54 个商品页字段、54 组内购名称和描述及 43 张截图。简中 15 张、繁中和美国英语各 14 张，含 Duo 外屏和展开内屏。日、韩、法、德、西班牙语（西班牙）和巴西葡语采用主语言截图继承方案，新增语言后在媒体管理器核对每个槽位。该六语没有独立原生图。[Apple 本地化说明](https://developer.apple.com/help/app-store-connect/manage-app-information/localize-app-information/)

商店实际名称为「少女心愿」，繁体中文为「少女心願」。Apple 拒绝了已被占用的美式英语名称 Pink House。美式英语、日、韩、法、德、西班牙语及巴西葡语使用已保存的中文品牌名及各自的当地语言副标题。

重新生成资料包可运行 `python3 tools/localization/package_store_localizations.py output/app-store-4.4`。

## 本地已验证

| 范围 | 结果 |
|---|---|
| 商品页 | 9 份文案已备齐名称、副标题、描述、推广文案、关键词、更新说明及两个待核 URL。名称和副标题各不超过 30 字符，关键词不超过 100 个 UTF-8 字节。简中提交前与线上文案比对。 |
| 喵币商品文案 | 6 档 × 9 语，共 54 条。ID 与 `IAPProductType` 一致，名称 ≤ 30 字符、描述 ≤ 45 字符。首购及复购数量与本地发放逻辑一致。后台逐档进度见下表。TestFlight 及生产实购仍待验证。 |
| 主 App | 24 条导航标题和说明全部有 9 语。日、韩、法、德、西、巴葡已替换系统权限的英文占位。验证日语「保存」能保留原译，缺失键能与原文相同的译文区分。 |
| 衣橱和支付入口 | 已补 13 条衣橱操作文案。逐项匹配编译后的九语资源，覆盖衣橱首页 81、喵币购买页 39、VIP 中心 70、系统设置 25 个静态中文 `.appLocalized` 键。 |
| Widget | 修复扩展的资源归属，实测已构建的扩展含九语名称及每语 16 条文案。月份标签会随系统语言显示，越界月份保留数值。 |

主 App 目录计 3,742 个键。日、韩、法、德、西、巴葡各有 1,887 个标记为已译，各缺 1,855 个对应译值。英文有 360 个键无显式译值、10 个状态为 new，简中和繁中各有 377 个键无显式译值。部分键是标点、模板或运营端专用。英文也无译值的中文键可能在界面直接显示中文。尚待截图检查截断、混语和动态拼接。

### 英文商品图复查

主对话已重拍并核对英文 iPhone 12、iPhone 17 Pro 和 13 英寸 iPad Pro 原图。三台设备都完整显示 Deposit paid、Pet Chat 和尾款日期栏。衣橱快捷按钮显示 Daily Color、DIY Outfits、Journal 和 Stats，辅助功能仍朗读完整名称。

已检查 ZIP 完整性和每张 PNG 的像素尺寸。基础组共 36 张，英文、简中、繁中各 12 张。每种语言覆盖四款设备的衣橱、心愿尾款和衣橱统计三页。iPhone 12 为 1170 × 2532，iPhone 17 Pro 为 1206 × 2622，iPhone 17 Pro Max 为 1320 × 2868，13 英寸 iPad Pro 为 2064 × 2752。主上架对话已在 ASC 的简中、繁中、美国英语三个版本逐槽回读，四种设备每槽三张，共 36 张。其余六语的 iPad 槽位已看到「使用现有素材」及三张缩略图。iPhone Duo 已另行补传 7 张。简中 3 张，繁中和英语各 2 张。外屏为 1398 × 2034，展开内屏为 2853 × 2007。[截图包](../../../../output/app-store-4.4/少女心愿-4.4-商店截图.zip) · [主对话验收记录](../../../../output/app-store-4.4/验收记录.md)

### 美国商店的喵币商品

默认 scheme 下，App 已从 US storefront 通过 StoreKit 取得全部六档消耗型商品。60、120、300、500、1,280、3,280 喵币的 USD 显示价依次为 $0.99、$1.99、$3.99、$6.99、$19.99、$49.99。六个返回名称均为中文，英文商品名待在英语环境和 ASC 本地化字段核对。购买流程到达 Apple 登录页，没有产生这次购买的流水。TestFlight 首购、复购和实际到账待验。[StoreKit 拉取记录](../../../../output/app-store-4.4/proof/us-storekit-products.txt)

### 六档喵币的后台状态（2026-11-04）

本表按最后一次实际读取记录。六个商品在列表中均为已批准的消耗型内购。保存前核对商品 ID，保存后逐条比对名称、首购与复购数量。保留已有简中。App 与内购供应范围均未在本次操作中修改。

| Product ID | 最后回读的本地化 | 供应范围 |
|---|---|---|
| `com.pinkhouse.app.meowcoin_60` | 9 语。刷新后原有简中在列，新增八语均为「准备提交」。 | 133/175，核对未选名单 |
| `com.pinkhouse.app.meowcoin_120` | 9 语。刷新后原有简中在列，新增八语均为「准备提交」。 | 133/175，未选名单与 60 档一致 |
| `com.pinkhouse.app.meowcoin_300` | 4 语。原简中已批准。英文（美国）、繁中、日语保存时为「准备提交」，重新打开后全部为「正在等待审核」，新增按钮已消失。韩、法、德、西、巴葡待录。 | 133/175，未选名单与 60 档一致 |
| `com.pinkhouse.app.meowcoin_500` | 9 语。刷新后确认原简中和 8 条「准备提交」的译文。 | 133/175，未选名单与 60 档一致 |
| `com.pinkhouse.app.mcoin_1280` | 9 语。刷新后确认原简中和 8 条「准备提交」的译文。 | 133/175，未选名单与 60 档一致 |
| `com.pinkhouse.app.mcoin_3280` | 9 语。刷新后确认原简中和 8 条「准备提交」的译文。 | 133/175，未选名单与 60 档一致 |

本地 54 组商品文案齐备，后台已录入 49/54 组，包括原有简中 6 组、待提交 40 组、正在等待审核 3 组。完成其余五档后再次打开 300 档，状态仍为正在等待审核，新增语言入口仍未出现。待其恢复编辑后，按源稿补韩语、法语、德语、西班牙语（西班牙）、葡萄牙语（巴西），再刷新核对。

已逐档比对六个商品的供应情况。六份地区集合完全相同，42 个未选地区均位于 Apple 的欧洲分组。依后台顺序为阿尔巴尼亚、爱尔兰、爱沙尼亚、奥地利、白俄罗斯、保加利亚、北马其顿、比利时、冰岛、波兰、波斯尼亚和黑塞哥维那、丹麦、德国、俄罗斯、法国、芬兰、荷兰、黑山、捷克共和国、科索沃、克罗地亚、拉脱维亚、立陶宛、卢森堡、罗马尼亚、马耳他、摩尔多瓦、挪威、葡萄牙、瑞典、瑞士、塞尔维亚、塞浦路斯、斯洛伐克、斯洛文尼亚、土耳其、乌克兰、西班牙、希腊、匈牙利、意大利、英国。

本次填报仅使用「添加显示名称与描述」弹窗中的「保存」。300 档状态发生变化的原因未经确认。发现变化后暂停写入。重新进入商品详情，60、120 档仍为草稿，300 档新增入口仍锁定。随后只在拥有独立草稿入口的其他档位继续填报。Apple 将本地化的「准备提交」与「正在等待审核」分列为不同状态。[Apple 内购本地化状态](https://developer.apple.com/help/app-store-connect/reference/in-app-purchases-and-subscriptions/in-app-purchase-localization-statuses/)

## 构建与检查

- 主对话以 Xcode 27.0（27A266a）执行 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -scheme ItemManager -destination 'platform=iOS Simulator,id=050415C8-C28C-4961-B526-56AB689BAC33' -derivedDataPath "$DD" -jobs 2 -quiet build`，iPad 模拟器构建退出码为 0。复用这次构建的 App 与内嵌 Widget，比对 24 × 9、16 × 9 条实际资源及两套九语 InfoPlist。证据在 `output/app-store-4.4/proof/ipad-build-2.exit`。
- 随后补入的衣橱文案单独通过 `xcrun xcstringstool compile ItemManager/Resources/Localization/Localizable.xcstrings --output-directory "$OUT" --serialization-format binary`。Widget 月份保护通过 Swift 解析和正常、越界月份样例。4.4（3）已完成 Release 归档。
- `plutil -lint ItemManager.xcodeproj/project.pbxproj` 通过。未在本对话启动模拟器、完成九语视觉验收或产生 Apple 审核单。

## 剩余动作

1. **政策网站。** 中英文政策、支持 URL 的严格 TLS 请求均失败，服务器证书到期时间为 2026-07-08 15:27 UTC。为定位故障单独检查 HTTP 内容，中英文各两页中，中文返回 200，英文 `/en/privacy/`、`/en/contact/` 返回 404。腾讯云服务器可达，本机 SSH 公钥登录被拒。等待用户登录腾讯云，续期证书、部署仓库 `ops/legal-site/en/`，再以正常 HTTPS 核验四页的状态、语言和标题。
2. **可售地区。** 主对话取得同一 ASC 会话后，在 Pricing and Availability 留存当前逐区状态，保留中国大陆，对全部可售海外地区核对协议与地区要求。欧盟核对 DSA 身份验证，韩国和越南按正式分类、年龄问卷与后台提示核对所需材料。当前大陆公开分类为效率，现有证据不足以判定这两个地区必然需要游戏许可。将受限原因和可补材料逐区登记。[Apple 地区管理](https://developer.apple.com/help/app-store-connect/manage-your-apps-availability/manage-availability-for-your-app-on-the-app-store/) · [Apple 地区信息要求](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information/)
3. **商品页与 IAP。** 4.4 九语商品页与 36 张基础截图已保存。以本表为准续核六档内购，分别登记本地化审核状态和可售地区差异。价格及 Sandbox 验收另行记录。截图复用主对话的同一设备和版式。政策站恢复及发布门槛通过后才保存扩区并提交需要审核的更改。
4. **审核与上线。** 保存后记录实际开放范围、版本、Build、Submission ID 和 Apple 状态。地区生效后再查公开目录及代表地区的商品页。[Apple 审核与可用状态](https://developer.apple.com/help/app-store-connect/reference/app-information/app-and-submission-statuses/)
