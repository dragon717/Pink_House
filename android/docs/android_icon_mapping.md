# Pink House Android Icon Mapping

本文件记录 Android 复刻 iOS SwiftUI/SF Symbols 语义时使用的 Material Icons 替代。Android 端不提取、不打包、不重命名 Apple SF Symbols。

| UI 语义 | iOS SF Symbol 参考 | Android Material Icon | 使用位置 |
| --- | --- | --- | --- |
| 主入口：衣橱 | `cabinet.fill` | `Icons.Filled.Inventory2` | Bottom navigation |
| 主入口：House | `house.fill` | `Icons.Filled.Home` | Bottom navigation |
| 主入口：我 | `face.smiling` | `Icons.Filled.Face` | Bottom navigation |
| 主入口：萌宠对话 | `bubble.left.and.bubble.right.fill` | `Icons.Filled.ChatBubble` | Bottom navigation |
| 排序 | `arrow.up.arrow.down` | `Icons.Filled.Sort` | Wardrobe top actions |
| 筛选 | `line.3.horizontal.decrease.circle` | `Icons.Filled.FilterList` | Wardrobe top actions |
| 网格/布局 | `square.grid.*` / `list.*` | `Icons.Filled.GridView` / `Icons.Filled.ViewList` | Wardrobe layout menu |
| 更多 | `ellipsis.circle` | `Icons.Filled.MoreVert` | Wardrobe top actions |
| 添加 | `plus` | `Icons.Filled.Add` | Wardrobe top actions and empty state |
| 搜索 | `magnifyingglass` | `Icons.Filled.Search` | More menu / search field |
| 编辑 | `pencil.circle` | `Icons.Filled.Edit` | More menu / create entry |
| 删除 | `trash` | `Icons.Filled.Delete` | Batch action bar |
| 恢复/回收站 | `arrow.uturn.backward` / recycle bin semantic | `Icons.Filled.Restore` | More menu / recycle bin |
| 保存 | `checkmark` / save semantic | `Icons.Filled.Save` | Deposit reminder settings |
| 心愿尾款提醒 | `bell` | `Icons.Filled.Notifications` | Deposit top action |
| 图片占位/导入 | photo/image symbol | `Icons.Filled.Image` | Cards and create sheet |

## Original Asset Mapping

以下资源来自 Pink House 原项目，不是 SF Symbols。Android 以资源图直接引用，文件名统一改为 Android 合法命名。

| iOS / 原项目资源 | Android 资源 | 用途 |
| --- | --- | --- |
| `SplashScreen.imageset/splash.jpg` | `@drawable/pink_splash` | 启动窗口背景 |
| `少女心愿logo.appiconset/logo-new.png` | `@drawable/pink_house_logo` | App 图标 / Splash icon |
| `naicha_peeking.imageset/PetPeekingIcon.png` | `@drawable/naicha_peeking` | 底部猫咪覆盖 |
| `maomao_peeking.imageset/maomao_peeking.png` | `@drawable/maomao_peeking` | 萌宠资产预置 |
| `naicha_portrait.imageset/naicha.png` | `@drawable/naicha_portrait` | House / 宠物占位 |
| `maomao_portrait.imageset/maomao.png` | `@drawable/maomao_portrait` | 萌宠对话占位 |
| `small_world_bg_normal.imageset/small_world_bg_normal.png` | `@drawable/small_world_bg_normal` | House 背景 |
| `WealthContainerBackground.imageset/wealth_bg.png` | `@drawable/wealth_bg` | 财富入口资产预置 |
| `card_front.imageset/card_front.png` | `@drawable/vip_card_front` | “我”/VIP 占位 |
| `meowcoin_120.imageset/mcoin120.png` | `@drawable/meowcoin_120` | 喵金币资产预置 |
| `asserts/open_dress.mp4` | `@raw/open_dress` | 后续衣橱/开裙动画预置 |
