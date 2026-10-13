# 衣橱分类收纳柜（2026-10-13）

## 交付范围

从现有衣橱首页的「更多 → 我的收纳柜」进入；也可从右边缘向左滑。默认入口为衣柜、鞋柜、包包柜、配饰柜；衣柜返回原首页。抽屉和柜内侧边都提供「添加柜子」，用户可以填写名称、选择图标并保存自己的柜子。底部仍使用现有系统 TabView。

收纳柜使用透明柜冠、可重复层板与底座组成连续立体柜体，一层两条收藏，至少四层。2026-10-14 按用户要求将柜冠和底座一起固定在滚动区之外，仅中间层架按收藏数量增加并滚动；柜冠、底座的位置与比例不随库存改变。空层补足可见中段；固定背板与前景侧柱进一步覆盖原生回弹时的空白，让两端始终连接。顶部控件与柜冠之间留出空间，不让滚动裁切吞掉雕花与蝴蝶结。物品下方显示名称和已保存的人民币价格，立体 / 列表共用原有价格隐私设置。包包增加层高，配饰使用绒面展示垫；没有物品的层板完全留空，不显示示意物件、展示垫、空层文案或示意切换按钮。每个柜子支持立体 / 列表切换、关键词搜索、原有详情页与新增表单；默认鞋柜额外保留鞋类筛选。搜索位于列表模式；切回立体模式会保留过滤结果，并提供「查看全部」。最新布局验证见 [柜体连续性修复](SHOP_ALBUM_AND_CONNECTED_CABINET_2026-10-14.md)。

## 渐进接入边界

- `HomeView.swift` 只接入入口、右边缘手势、抽屉状态与导航目的地。
- `WardrobeView.swift` 的原有异步筛选引擎接入统一分类函数，主列表与其筛选统计只展示衣柜记录；财富总账仍使用原有完整数据。
- `Views/WardrobeStorage/WardrobeStorageInventory.swift` 是只读数据投影和分类规则。
- `WardrobeStorageDrawer.swift` 管理右侧抽屉。
- `WardrobeStorageComponents.swift` 管理柜体、层板、网格与异步图片。
- `WardrobeStorageRoomView.swift` 管理搜索、分类、展示切换与详情 / 添加路由。
- `Services/WardrobeStorage/` 管理统一主体提取和后台衍生图缓存；`WardrobeStorageImageResolver.swift` 接入现有 iCloud 图片下载。
- `WardrobeStorageSettings.swift` 保存本机自定义柜子的名称、图标与物品 ID；`WardrobeStorageCabinetEditor.swift` 提供创建 / 编辑和物品选择；`WardrobeStorageIcon.swift` 提供统一矢量插画。
- 不改 SwiftData 模型、存档键、ThemeSkin slot、商品列表或奖励规则。
- 柜体美术仅出现在用户主动打开的收纳功能中，不覆盖默认首页，也不注册成主题包。
- 图片在 Asset Catalog 的 `ThemeSkin/WardrobeStorage/` 中；与现有主题素材没有混用。资源缺失时有程序化层板兜底。

## 真实数据口径

未删除的 Clothing 只归入一个柜子。首页使用相同归属函数，鞋、包、配饰及已选入自定义柜子的物品只在对应柜子展示。原美妆 / 生活物品在没有自定义收纳设置时继续出现在衣柜，避免移除入口后丢失可见记录。抽屉与柜头数量仅累计已拥有库存，预约 / 待到货 / 已售出记录保留在对应柜子，显示状态标记，且不计入已拥有数量。软删除和回收站记录不展示。

明确主衣物类型（JSK / OP / SK / Blouse 等）优先于名称、混合类型和小物标签。`types = JSK,小物` 且 `accessories = 包,礼帽` 的整套只属于衣柜。编辑页的小物分类标签存在 `Clothing.accessories`，其中「包」在没有主衣物类型时进入包包柜。历史「小物」类型仍可根据明确鞋、包标签或名称归入相应柜子。

AccessoryItem 是主记录的小物金额与图片明细，保留在原详情中，不自动投影成另一件收藏；独立保存为 Clothing 的小物才进入独立柜子，避免套装重复展示。此次没有修改或拆分持久化记录。

自定义柜子通过显式勾选现有物品收纳，也可从柜内「收纳物品 → 新建物品」沿用现有编辑表单；仅在 Clothing 保存成功后关联新记录 ID。选择另一柜子会从原自定义柜子移出；取消勾选后按默认分类恢复。JSK / OP 等明确主衣物类型始终先归衣柜，物品选择也排除这些整套主衣物。名称和归属保存于独立本机设置 `wardrobe.storage.custom-cabinets.v1`，没有增加 CloudKit / SwiftData schema；本轮自定义设置不跨设备同步。

2026-10-14 新增图片图标：用户可从照片选择并裁剪自己的图标，在新增 / 编辑柜子时保存，抽屉和侧边栏统一显示；仍保留内置图标与缺图兜底。新可选字段只保存图标文件名，独立小图在本机 Application Support 保存，不改变衣物图片和柜子归属。实现与验证见 [自定义收纳柜图片图标](WARDROBE_STORAGE_CUSTOM_ICONS_2026-10-14.md)。

每条柜内收藏统一经过自动抠图管线：先验证并复用明确替换或关联的透明 CutoutItem，否则提取原图主体；第一张不可处理时继续尝试该收藏的其他照片。没有可关联来源的手帐贴纸不作为另一件已拥有收藏重复计数。读取和生成衍生图均不修改抠图归属、名称、原始照片、`Clothing.imagePaths` 或衣物数据。新添商品继续沿用现有 ClothingEditView 与业务保存、反馈管线。

## 美术来源与复现

使用内置 image_gen / imagegen 技能生成；未使用 CLI / 外部 API。生成后通过内置工具进行透明抠图。原图存于 `docs/design/wardrobe-storage/`。柜体 1024 × 1536，鞋履 atlas 的实际尺寸以文件为准；下方脚本保留原生 alpha 并拆出三块柜体和四组鞋履，不另作背景推断或抠图。

```bash
swift tools/wardrobe_storage/package_assets.swift
```

正式资源：
- storage_cabinet_crown / storage_cabinet_shelf / storage_cabinet_base
- storage_shoes_blush / storage_shoes_sneakers / storage_shoes_boots / storage_shoes_black
- storage_bags_* / storage_accessories_* / storage_beauty_* / storage_lifestyle_*：每类四张透明示意物件。

四类追加素材均由内置 image_gen 直接生成透明 atlas，原图及完整 prompt 保存于 `docs/design/wardrobe-storage/category-art-prompts.json` 和同目录 `*-sprites-source.png`；打包脚本保留 alpha，检查方形尺寸与透明角点，再切入正式 Asset Catalog。未调用 CLI / 外部 API。

## 时光馆所选颜色与图片

`ShopCatalogWardrobeImageImporter.references` 先按已选颜色筛选规格绑定的 `imageAssetID`，再进入原有持久化、去重、失败回滚管线。多尺码指向同图、资源别名指向同一媒体时只导入一次；规格图即使不在商品通用相册中也会导入。多色商品的未绑定通用图、其他颜色图、同时绑定其他颜色的共享图不导入。单色商品保留该色的详情图；记录既没有所选颜色也没有默认颜色时沿用原有通用图读取。

确认页合并小物时，把每件小物的颜色选择一起传入图片入库层，避免主裙正确但配套包仍导入所有颜色。衣物详情的滑动相册只读本次保存的 `clothing.imagePaths`，不追加 Catalog 相册。

缺少颜色绑定且无法确认图片归属时，保留空图片占位，不用其他配色的封面替代。没有批量删除或改写历史入橱照片；用户手动选入的图片也不作推断。奖励、币种、团次、加入方式与系统收尾职责不变。

### 柜体生成 prompt

```text
Use case: stylized-concept
Asset type: production iOS wardrobe shoe cabinet background, transparent cutout PNG.
Primary request: create a single beautiful empty freestanding dollhouse shoe cabinet closely inspired by the blush ivory rococo shoe cabinet in the THIRD phone of the reference image attached in conversation. This is a furniture asset, not a phone UI.
Subject: symmetrical tall open-front cabinet, ornate curved crown with one delicate peach-pink bow, slender carved ivory side columns, FOUR equal-height empty shelf compartments, each with warm beige recessed back, subtle side-wall perspective and carved shelf lips. A shallow ornate bottom drawer with rose medallion, small feet. Cream painted wood, fine relief carving, soft rose-gold details, understated pink highlights.
Composition: perfectly straight front view with interior depth visible, portrait image about 2:3 aspect ratio. Cabinet fills image with tiny transparent margins. Four shelf bays equally spaced and wide enough for two shoe pairs; fully empty. Crown occupies top 18%, shelf bays from 20% to 85%, base drawer bottom 15%. Complete object entirely visible, no cropped parts.
Lighting: soft upper-left studio light, convincing ambient occlusion inside each bay, polished handcrafted miniature realism, dimensional romantic Japanese dollhouse aesthetic. Readable soft shadows, crisp carved edges.
Background: genuinely transparent alpha outside the cabinet silhouette. Recessed cabinet interiors are opaque warm cream.
Text: none.
Constraints: no shoes, no flowers blocking shelf openings, no dolls, no lamp, no UI, no lettering, no watermark, no smartphone, no floor or backdrop. The reference is visual inspiration only; regenerate clean furniture suitable for a scrolling app.
```

### 柜体透明抠图 prompt

```text
Use case: background-extraction.
Edit target: the attached generated empty ivory and blush rococo shoe cabinet.
Keep the exact cabinet, all carved edges, bow, shelf interiors, four shelves and base unchanged.
Remove the entire studio gradient backdrop outside its silhouette and all broad dark halo, vignette, floor and exterior cast shadows. The OUTSIDE silhouette must be fully transparent alpha (0), not a black, gray, cream or checkerboard painted background. Only cabinet interiors and wood stay opaque. Preserve narrow edge antialiasing. Full freestanding cutout, production game asset, no new objects or text.
```

### 鞋履 atlas prompt

```text
Use case: stylized-concept.
Asset type: four isolated shoe-pair sprites in ONE production sprite atlas for a romantic dollhouse shoe cabinet iOS app.
Subject: top-left a pair of blush pink Mary Jane shoes with small satin bows and block heels; top-right a pair of ivory white sneakers with tiny blush ribbons; bottom-left a pair of cream lace-up ankle boots with lace trim; bottom-right a pair of glossy black double-strap Mary Jane shoes.
Composition: square image, strict 2 by 2 grid of four separate equal-size cells, each shoe pair fully contained in its quadrant with at least 8% clear transparent padding and centered. Consistent three-quarter FRONT product angle, toe towards viewer, both shoes visible, level soles. No frames, no labels, no drawn grid. Each pair about 70% of quadrant width. The four pairs are separate sprites, not a collage scene.
Style: beautifully detailed miniature 3D product render, delicate Japanese Lolita dollhouse style, fine stitching, convincing material and depth. Soft upper-left lighting matched to warm ivory furniture. No background or ground, actual transparent alpha around every pair, subtle contact shadow immediately under sole only.
Constraints: exactly four pairs, no text, no watermark, no people, no cabinet, no props, no background.
```

## 第二版定向测试：PASS（50/50）

实际运行 `WardrobeStorageInventoryTests`（7）、`ShopCatalogWardrobeImageImportTests`（9）和原有 `ShopCatalogWardrobeEntryTests`（34）。验证分类柜与首页分区无交集且覆盖全部有效记录、包标签优先、混合 JSK 类型的套装不拆分、预约 / 售出保留与零已拥有数量、最新抠图、所有分类预览零入库；图片覆盖多色隔离、多尺码与媒体别名去重、单色细节图、缺失或跨色共享绑定、主衣物与合并小物真实持久化、图片失败释放，以及原有金额 / 状态规则。

旧 Bundle 图片持久化用例的多色夹具没有配色绑定，首轮按新规则得到空图片（49/50）；该用例已改成明确单色绑定，继续核对三张 Bundle 图片实际可解码，不改变原有入库验证目的。修复后 50/50 全部通过，结果摘要：`docs/design/wardrobe-storage/validation/category-color-test-summary.json`。

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -scheme ItemManager \
  -destination 'platform=iOS Simulator,id=FA7332BE-B29E-4879-A139-C68A24314DB1' \
  -derivedDataPath /Users/sangyu/Library/Developer/Xcode/DerivedData/ItemManager-cujimhkdzvadtsdanhkygjqfdyoh \
  -clonedSourcePackagesDirPath /Users/sangyu/Library/Developer/Xcode/DerivedData/ItemManager-cujimhkdzvadtsdanhkygjqfdyoh/SourcePackages \
  -jobs 5 -parallel-testing-enabled NO -collect-test-diagnostics never \
  -only-testing:ItemManagerTests/WardrobeStorageInventoryTests \
  -only-testing:ItemManagerTests/ShopCatalogWardrobeImageImportTests \
  -only-testing:ItemManagerTests/ShopCatalogWardrobeEntryTests \
  -resultBundlePath /private/tmp/pink-house-storage-categories-colors-fixed-20261013.xcresult \
  -quiet test
```

## 第二版构建与真实 UI：PASS（已覆盖项）

```bash
XCODE_APP=/Applications/Xcode.app \
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
SIM_ID=FA7332BE-B29E-4879-A139-C68A24314DB1 \
MAX_JOBS=5 BUILD_TIMEOUT_SECONDS=180 \
LOG=/private/tmp/pink-house-storage-categories-final-build.log \
tools/xcode/stable_cli_build_and_run.sh
```

- Xcode 27.0 / 27A266a；ItemManager；iPhone 18 Pro / iOS 27.0；bundle `bugod2.ItemManager`。
- 最终增量构建 15 秒，build / install / launch 均返回 0。terminate 返回 3（测试结束后没有旧进程），随后已启动新进程。
- 按仓库指南先对该目标编译、安装、重启，再通过 Device Hub Computer Use 核对真实 UI。
- 核对六类抽屉、四个新增立体柜的透明物件与层板衔接、不同层高与展示台、分类切换、生活柜物件点击详情、列表模式与搜索入口、隐藏示意陈列后的空列表与立体空柜、手势滚动后柜底完整可达、现有系统 TabView 保留。
- 新截图：`bag-cabinet.png`、`accessory-cabinet.png`、`beauty-cabinet.png`、`lifestyle-cabinet.png`、`lifestyle-empty-base.png`，均在 `docs/design/wardrobe-storage/validation/`。
- Asset Catalog 23 个 imageset 的 JSON / 图片引用检查及 `git diff --check`：PASS；追加 atlas 透明角点校验与四象限打包：PASS。

边界：真实模拟器收藏为空，视觉检查使用明确标注的示意陈列；首页分类与颜色持久化通过内存模型和实际图片入库测试验证，未手动修改用户收藏或跑线上 CloudKit 入橱。未做真机帧率、iPad / 横屏 / 大字号或完整回归。旧照片未自动修复。现有扩展 CFBundleVersion 3 与主 app 4 不一致及资源去重 build phase 警告仍在；未扩展到这些无关修改。Device Hub 可访问性偶有读取失败，均重新读取并以实际截图核对，没有把尝试点击当作验收成功。

## 柜顶遮挡与前后层次修正：PASS（2026-10-13）

用户标注参考：`docs/design/wardrobe-storage/reference-depth-annotation-2026-10-13.jpg`。红圈要求柜顶完整露出；蓝线区域要求顶部 / 左侧平面位于柜体之后。

`WardrobeStorageCabinet` 将柜冠移到滚动区之外，层板与底座继续使用 LazyVStack 滚动和系统吸附，初始锚点为顶部。顶部留出 12 pt、两侧各留 14 pt，让雕花轮廓与阴影有可见空间。柜冠与可见柜体合为一个前景投影，避免给每层单独加阴影而产生接缝暗带。`WardrobeStorageRearPlane` 是顶部控件与分类栏共享的薄背景平面，分类栏不再另叠一个材质层；原有主题背景仍从平面后透出。修正复用于全部分类柜，不修改图片资源或分类 / 图片入库规则。

```bash
XCODE_APP=/Applications/Xcode.app \
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
SIM_ID=FA7332BE-B29E-4879-A139-C68A24314DB1 \
MAX_JOBS=5 BUILD_TIMEOUT_SECONDS=180 \
LOG=/private/tmp/pink-house-storage-depth-crown-build.log \
tools/xcode/stable_cli_build_and_run.sh
```

- Xcode 27.0 / 27A266a；scheme ItemManager；iPhone 18 Pro / iOS 27.0；bundle `bugod2.ItemManager`。
- 最终构建 52 秒，build / install / launch 返回 0；terminate 返回 3（无旧进程），已启动新进程。
- Device Hub 真实 UI：鞋柜初始柜冠完整，雕花顶尖 / 蝴蝶结与控件之间有留白；柜体两侧投影与后方平面分离。鞋柜与包包柜滚动到末尾时，柜冠位置不变，柜脚能完整出现在系统底栏上方。
- 新截图：`shoe-cabinet-depth-crown.png`、`shoe-cabinet-depth-scrolled.png`、`bag-cabinet-depth-scrolled.png`，位于 `docs/design/wardrobe-storage/validation/`。
- 本轮只改可逆视觉布局，不新增或重复跑分类 / 入库单元测试；前轮 50/50 的数据测试记录保持历史口径。
- 边界：模拟器使用明确标注的示意陈列，未修改用户收藏；未验证截图来源真机、iPad / 横屏 / 大字号或 Instruments 帧率。已有 MainActor / Sendable、扩展版本与去重脚本警告仍在。

## 空柜、价格、图标与自定义柜子（2026-10-13）

按用户本轮要求移除 production 代码中的 `shoePreview`、其他分类预览数据、示意切换、示意详情和空层提示。正式资源与历史参考图仍保留；它们不再作为用户柜内示例物件。空柜仅绘制柜体与空层板，配饰垫 / 圆台只在该层真实有物品时绘制。

立体柜新增 `WardrobeStorageItemLabel` 显示名称与 `Clothing.price` 的人民币金额；列表使用同一价格来源，不推断售价、不转换历史币种字段。两处都遵循 `privacyShowPrice`，隐藏价格时可访问性也不播报金额。四个默认入口和自定义柜子使用同一套 SwiftUI Canvas 矢量图标：奶油 / 粉色渐变、玫瑰描边、金色点缀与圆形底座；不依赖新的位图资源。

`WardrobeStorageDestination` 将固定分类与自定义柜子分开，`WardrobeStorageSettings` 的本机设置只保存自定义名称、图标、稳定 Clothing ID 集合。默认列表只含衣柜 / 鞋柜 / 包包柜 / 配饰柜。用户可创建空柜、改名 / 换图标、从已有物品中勾选或新建物品；「收纳物品」完成后才提交选择。明确主裙类型始终归衣柜。一次收纳移除其他自定义柜子的同 ID，取消收纳后回到默认分类；图片、价格、状态和存档记录均保留。首页异步筛选通过 Sendable 设置快照使用相同归属函数，设置变化也会更新筛选签名，不读取后台线程中的 SwiftData 对象。

### 定向测试：26/26 PASS

运行 `WardrobeStorageSettingsTests`（8）、`WardrobeStorageInventoryTests`（7）、`WardrobeStorageCutoutTests`（11），0 失败 / 0 跳过。新增验证默认四柜且没有示例库存、名称 / 图标 / ID / 选择跨实例恢复、空名 / 长名 / 重名拒绝、编辑保留 ID 和物品、移动无重复、取消收纳恢复、JSK 套装保护、移除美妆 / 生活入口后原记录仍可见、已删除记录排除、新物品可关联，以及原图和保存价格不变。重跑原有自动抠图和缓存测试，确保新增路由共用相同处理流程。

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -scheme ItemManager \
  -destination 'platform=iOS Simulator,id=FA7332BE-B29E-4879-A139-C68A24314DB1' \
  -derivedDataPath /Users/sangyu/Library/Developer/Xcode/DerivedData/ItemManager-cujimhkdzvadtsdanhkygjqfdyoh \
  -clonedSourcePackagesDirPath /Users/sangyu/Library/Developer/Xcode/DerivedData/ItemManager-cujimhkdzvadtsdanhkygjqfdyoh/SourcePackages \
  -jobs 5 -parallel-testing-enabled NO -collect-test-diagnostics never \
  -only-testing:ItemManagerTests/WardrobeStorageSettingsTests \
  -only-testing:ItemManagerTests/WardrobeStorageInventoryTests \
  -only-testing:ItemManagerTests/WardrobeStorageCutoutTests \
  -resultBundlePath /private/tmp/pink-house-storage-custom-cabinets-final-20261013.xcresult \
  -quiet test
```

机器摘要 `validation/custom-cabinets-test-summary.json`；实际 SwiftUI 矢量图标渲染 `validation/cabinet-icons.png`；价格标签显示 / 隐藏渲染 `validation/item-price-visible.png` / `validation/item-price-hidden.png`，均已读取像素预览。价格夹具只在测试内存对象中存在，不写入用户收藏。

### 构建和实际交互：PASS（已覆盖项）

```bash
XCODE_APP=/Applications/Xcode.app \
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
SIM_ID=FA7332BE-B29E-4879-A139-C68A24314DB1 \
MAX_JOBS=5 BUILD_TIMEOUT_SECONDS=180 \
LOG=/private/tmp/pink-house-storage-custom-cabinets-final-build.log \
tools/xcode/stable_cli_build_and_run.sh
```

- Xcode 27.0 / 27A266a，ItemManager，iPhone 18 Pro / iOS 27.0；73 秒增量构建。build / install / launch 返回 0；terminate 返回 3（测试结束后没有旧进程），随后启动新进程。
- 同一目标重新构建、安装、重启后通过 Device Hub Computer Use 检查：默认四类图标与添加柜子入口；鞋柜完全空层板、完整柜冠和柜脚；侧边加号 → 填名称 → 选礼帽图标 → 保存 → 自动进入新空柜；柜内「收纳物品」 → 选择页 → 原有新建物品表单。新增表单没有保存收藏。
- 创建与重启使用独立验收偏好 `pink-house-storage-ui-tests-20261013-1655`。只有 DEBUG、环境变量 `PINK_HOUSE_STORAGE_TEST_SUITE` 且前缀匹配时启用，Release 不提供此分支。实际退出并重新启动后，礼帽柜保留相同名称 / 图标 / ID，抽屉中可见。结束后不传该变量重新启动普通进程，用户默认柜子设置未加入验收柜。

```bash
# 已安装上述最新构建；在创建后终止并用同一套独立偏好重新启动。
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun simctl terminate \
  FA7332BE-B29E-4879-A139-C68A24314DB1 bugod2.ItemManager
SIMCTL_CHILD_PINK_HOUSE_STORAGE_TEST_SUITE=pink-house-storage-ui-tests-20261013-1655 \
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun simctl launch \
  FA7332BE-B29E-4879-A139-C68A24314DB1 bugod2.ItemManager
```

截图：`validation/four-cabinet-drawer.png`、`validation/empty-cabinet-no-examples.png`、`validation/custom-cabinet-created.png`、`validation/custom-cabinet-relaunched.png`。仅独立偏好中的柜子定义用于 UI 验收；未手动新增、改写或删除用户收藏。真实物品的移动 / 首页分区 / 价格保留通过只读模型投影和独立 UserDefaults suite 测试验证。未测真机、跨设备同步、完整回归或大字号 / 横屏 / iPad；自定义柜子配置当前为本机保存。既有扩展版本、MainActor / Sendable 与资源去重诊断未扩大修复范围；新增设置类的本轮 actor 警告已消除。

## 柜内图片自动抠图：PASS（2026-10-13，前轮记录）

旧代码只读取已有的 CutoutItem，缺少抠图记录就展示原图，导致同类白底照片在柜中不一致。现在鞋、包、配饰、美妆和生活柜共用 `WardrobeStorageImageResolver`：

1. 实际检查 alpha，已有透明主体直接裁切复用；不把不透明 PNG 当作完成的抠图。
2. 原图使用 `VNGenerateForegroundInstanceMaskRequest`，保留 `allInstances`，避免成对鞋履只留下其中一只。此 API 和后台执行原则参考 [Apple WWDC23：Lift subjects from images in your app](https://developer.apple.com/videos/wwdc2023/10176/)。
3. 主体识别未得到有效结果时，尝试从四边连通区域移除浅色中性背景。取边缘的背景中位色，只移除色差不超过 12 的连通像素，保留主体内部白色；不会全局删除所有白像素。空白图、不透明蒙版和无法可靠处理的照片不会记为成功。
4. 已打开柜子优先，其余柜子和屏幕外收藏也会预处理。缺少第一张、已有关联抠图不透明、第一张不可识别时，继续检查该收藏的剩余原图；新记录和图片修改触发重新读取。

处理器在专用 actor 上串行执行，解码最长边 1024 px，限制同时进行的主体识别。成功结果按原始字节 SHA256 缓存在 `Library/Caches/WardrobeStorageCutouts/v1`，NSCache 上限 80 张 / 32 MiB，磁盘约 256 张 / 128 MiB，每 10 次写入清理一次。相同内容的不同文件名共用结果；源字节更新或缓存损坏会重新处理。仅保存透明衍生图，不写原始 Documents 图片或 SwiftData，不创建手帐贴纸，不触发保存反馈与鱼币。

失败只在当前进程短暂记忆 120 秒，未持久化为“完成”。仍显示可用原图并标记暂未抠出，右上角可以重试；回到前台也会清除失败记忆并重新准备。页面取消不会把这次工作缓存为失败。进度与失败数量均来自实际处理结果。

### 定向测试：18/18 PASS

本轮运行 `WardrobeStorageCutoutTests`（11）和 `WardrobeStorageInventoryTests`（7）。覆盖纯白 / 偏白底、主体白色保留、已有透明图、不透明假抠图、空白图、全部原图候选、相同源合并与跨缓存实例复用、失败重试、取消、源字节变化、损坏缓存，以及原有分类分区 / 套装 / 包标签规则。后台线程执行和原始文件不变也有断言。

首轮白鞋用例暴露背景色差 34 的兜底会损伤浅色鞋舌，已收紧为 12。使用正式示意素材生成同一双鞋的纯白、偏白输入，分别验证完整处理与强制兜底路径，至少保留参考素材 98% 的白色不透明像素。最终 18 项全部通过，0 失败 / 0 跳过；不是将失败用例跳过或降低保留标准。

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -scheme ItemManager \
  -destination 'platform=iOS Simulator,id=FA7332BE-B29E-4879-A139-C68A24314DB1' \
  -derivedDataPath /Users/sangyu/Library/Developer/Xcode/DerivedData/ItemManager-cujimhkdzvadtsdanhkygjqfdyoh \
  -clonedSourcePackagesDirPath /Users/sangyu/Library/Developer/Xcode/DerivedData/ItemManager-cujimhkdzvadtsdanhkygjqfdyoh/SourcePackages \
  -jobs 5 -parallel-testing-enabled NO -collect-test-diagnostics never \
  -only-testing:ItemManagerTests/WardrobeStorageCutoutTests \
  -only-testing:ItemManagerTests/WardrobeStorageInventoryTests \
  -resultBundlePath /private/tmp/pink-house-storage-auto-cutout-fixed-20261013.xcresult \
  -quiet test
```

摘要：`docs/design/wardrobe-storage/validation/auto-cutout-test-summary.json`。实际处理样张：同目录 `white-shoes-original.png` / `white-shoes-cutout.png` 和 `near-white-shoes-original.png` / `near-white-shoes-cutout.png`。两个输出均已读取像素预览，鞋舌、鞋身、鞋底和蝴蝶结完整，外部背景透明。

### 构建与 UI 验证

```bash
XCODE_APP=/Applications/Xcode.app \
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
SIM_ID=FA7332BE-B29E-4879-A139-C68A24314DB1 \
MAX_JOBS=5 BUILD_TIMEOUT_SECONDS=180 \
LOG=/private/tmp/pink-house-storage-auto-cutout-final-build.log \
tools/xcode/stable_cli_build_and_run.sh
```

- Xcode 27.0 / 27A266a；ItemManager；iPhone 18 Pro / iOS 27.0；bundle `bugod2.ItemManager`。
- 增量构建 19 秒，build / install / launch 均返回 0；terminate 返回 3（测试后无旧进程），已启动新进程。
- 新进程的 Device Hub Computer Use 检查：首页 → 更多 → 分类抽屉 → 鞋柜可正常进入；示意素材、完整柜冠与后方平面分离正常；没有真实源图时不显示处理按钮或虚假的失败提示。截图 `validation/auto-cutout-shoe-cabinet-ui.png`。
- 验证边界：模拟器收藏仍为空，未向用户数据库注入样张；真实处理由同一 production resolver / processor / cache 的定向测试和导出的透明 PNG 验证。原生 Vision 被实际调用，模拟器可能缺少可用的前景模型，完整路径可自动进入白底兜底；提取成功后的分支由可注入提取结果的测试验证。未测截图来源真机的任意照片、iCloud 下载时序、帧率 / Instruments 或完整回归；复杂背景与和背景完全同色的主体不能承诺每张都识别成功，实际失败保留明确重试入口。
- `git diff --check`：PASS；既有 MainActor / Sendable、扩展版本与资源去重脚本诊断仍在，未扩大修改范围。

## 第一版验证记录（历史）

### 构建、安装与启动：PASS

- Xcode 27.0 正式版，build 27A266a；scheme ItemManager。
- 目标：iPhone 18 Pro / iOS 27.0，UDID `FA7332BE-B29E-4879-A139-C68A24314DB1`。
- bundle id：`bugod2.ItemManager`。
- 最终排版构建耗时 103 秒；build / install / launch 均为 0。终止旧进程返回 3（当时没有旧进程），随后已启动新进程。
- 最多 5 个编译线程，180 秒 watchdog；复用现有干净 SPM 缓存，未做完整 clean build。

```bash
XCODE_APP=/Applications/Xcode.app \
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
SIM_ID=FA7332BE-B29E-4879-A139-C68A24314DB1 \
MAX_JOBS=5 BUILD_TIMEOUT_SECONDS=180 \
LOG=/private/tmp/pink-house-storage-layout-build.log \
tools/xcode/stable_cli_build_and_run.sh
```

脚本实际执行：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -scheme ItemManager \
  -destination 'platform=iOS Simulator,id=FA7332BE-B29E-4879-A139-C68A24314DB1' \
  -derivedDataPath /Users/sangyu/Library/Developer/Xcode/DerivedData/ItemManager-cujimhkdzvadtsdanhkygjqfdyoh \
  -clonedSourcePackagesDirPath /Users/sangyu/Library/Developer/Xcode/DerivedData/ItemManager-cujimhkdzvadtsdanhkygjqfdyoh/SourcePackages \
  -jobs 5 -quiet build
```

### 定向单元测试：PASS（5/5）

该版本曾覆盖主裙优先、历史鞋类识别、抠图与预览。第二版按用户新要求改变了小物明细投影、分类首页和预约 / 售出展示口径；最终结果以追加的第二版验证记录为准。

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -scheme ItemManager \
  -destination 'platform=iOS Simulator,id=FA7332BE-B29E-4879-A139-C68A24314DB1' \
  -derivedDataPath /Users/sangyu/Library/Developer/Xcode/DerivedData/ItemManager-cujimhkdzvadtsdanhkygjqfdyoh \
  -clonedSourcePackagesDirPath /Users/sangyu/Library/Developer/Xcode/DerivedData/ItemManager-cujimhkdzvadtsdanhkygjqfdyoh/SourcePackages \
  -jobs 5 -parallel-testing-enabled NO -collect-test-diagnostics never \
  -only-testing:ItemManagerTests/WardrobeStorageInventoryTests \
  -resultBundlePath /private/tmp/pink-house-storage-tests-fixed-20261013.xcresult \
  -quiet test
```

机器可读摘要：`docs/design/wardrobe-storage/validation/test-summary.json`。首轮发现并修复了「小物」通用类型盖过鞋履名称的兼容问题，修复后 5 项全部通过；之后仅调整首页手势作用区域与立体模式排版，分类投影未再改动。

### Computer Use / Device Hub：PASS（已覆盖项）

在最终构建安装并启动后，通过 Xcode 27 Device Hub 读取同一模拟器。实际检查了：

1. 现有首页和系统 TabView；更多菜单中的「我的收纳柜」。
2. 右边缘左滑打开抽屉，六个分类及真实零数量。
3. 立体鞋柜透明轮廓、鞋履、连续四层；触摸上滑后底座可完全到达，系统 TabView 仍可见。
4. 立体 / 列表切换；「小白鞋」仅显示缎带小白鞋。
5. 输入「不存在的鞋履」得到无结果状态；清除筛选恢复四组示意图。
6. 添加入口打开原有手动创建表单，类型预填「鞋」；取消后仍为 0 双。
7. 「看空柜」隐藏全部示意鞋履，显示四层空柜；返回到原有衣橱页面。

截图目录：`docs/design/wardrobe-storage/validation/`，包括 `storage-drawer.png`、`shoe-cabinet.png`、`shoe-list.png`、`search-empty.png`、`add-shoes.png`、`empty-cabinet.png`。

### 验证边界与既有诊断

- 未做真机帧率 / Instruments 性能测量、iPad / 横屏 / 大字号验证、完整回归测试或主题 A–O 验收。
- 当前模拟器收藏为空，UI 验收使用明确标注的示意图。真实模型分类、小物与抠图投影由定向单元测试覆盖；未手动新增真实收藏或跑 iCloud 同步。
- 第一版曾只优先现有透明抠图；此限制已由上方「柜内图片自动抠图」实现取代。任意真实照片的主体识别质量仍需实际素材验证。
- 首轮构建有 Xcode 的 `exit code 0 but produced no further output` 诊断，实际 build / install / launch 成功，按仓库指南记录为工具噪音。既有 MainActor / Sendable 警告、extension 版本 1.6 与主 app 4.1 不一致、资源去重脚本每次运行提示仍存在，未扩展到这些无关改动。
- Device Hub 的可访问性读取偶有 `AXError.cannotComplete`；重新读取后用真实截图核对。搜索已通过可设置字段完成并验证，不把工具报错本身当作应用崩溃。
- `git diff --check`：PASS。

## 后续迭代

分类、颜色隔离、柜体前后层次与统一自动抠图已按本轮要求接入。后续依据实际收藏图片补充识别质量验证、更多柜体材质与真机滚动性能；继续在独立组件中迭代。

暗黑模式、运行时灯光与提交范围独立验证见 [收纳柜暗黑模式与分层照明](WARDROBE_STORAGE_DARK_MODE_2026-10-13.md)。
