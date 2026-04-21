# iOS → HarmonyOS ArkUI 复刻经验

> 来源：2026-04-21 衣橱首页首轮复刻复盘（Downloads/Pink_House 仓库）。

## 流程

1. **先读对应 SwiftUI View 的 body**，画组件树，再动鸿蒙代码。
   - 例：衣橱统计是 3 列（总件数/款·裙装价值·总价值），不是 2 列；action 是 3 个大 tile，不是 chips。第一版就是因为只看设计图没看 `WardrobeView.swift:1441-1524` 拆错了。
2. **取色走纯色 + 渐变近似**，水彩/园林底图等富素材留占位并建资源清单。
3. **增量编译**：AppTheme → 最小 Index 壳 → 单页 stub → 扩展。一次堆 5 个文件会让命名冲突和 API 误用同时爆。
4. **每轮交付给用户一个可 DevEco 编译的最小 diff**，按错误反馈迭代。

## ArkTS @Prop 命名反模式

自定义 `@Component` 的 `@Prop` 不能和基类 `CustomComponent` 的属性方法同名，否则报：`Property 'X' is not assignable to same property in base type 'CustomComponent'`。

| 别用 | 改用 |
|---|---|
| `padding` | `innerPadding` |
| `size` | `diameter` |
| `radius` | `cornerRadius` |
| `color` | `tintColor` |
| `margin` / `width` / `height` / `border` / `background` / `opacity` / `visibility` | 加前缀如 `inner*` / `custom*` |

## 布局套路

- **自定义组件 + `@BuilderParam` 尾随块不能再 `.chain()` 属性**。报错：`Declaration or statement expected`。包一层内置容器：
  ```ts
  Column() {
    MyCard({ ... }) { ... }
  }
  .layoutWeight(1)
  ```
- **`@Builder` 方法调用同理**：`this.Something()` 之后的 `.layoutWeight` 是链到父容器，不是 Builder 返回值。
- **`@BuilderParam` 默认值必须指向同类 `@Builder` 方法**：
  ```ts
  @Builder defaultContent() {}
  @BuilderParam content: () => void = this.defaultContent;
  ```

## 响应式注意

- **TS `get` 访问器不纳入 ArkUI 响应式追踪**，模板里会拿到 `undefined`，表现为 `undefined/NaN`。改用方法或内联 `this.field` 表达式。
- `@State` 字段改写才会触发 rebuild；嵌套对象的字段改写不会，得整体赋值或用 `@Observed`/`@ObjectLink`。
- 数组用 `@State items: T[] = []` 可观察 length/reassign；原地 `push/splice` 不稳，走 `this.items = [...this.items, x]`。

## 组件级坑点

- **`bindSheet($$this.isOpen, ...)`** 的 `$$` 是双向绑定语法，部分 ArkUI 版本里需写成普通 `this.isOpen` + `onDisappear` 回调。遇到就降级。
- **`Divider().vertical(true)`** 用于水平 Row 中做竖线分隔，需配 `.strokeWidth` + `.color` + `.height`。
- **Emoji 不是图标方案**。真项目用 `SymbolGlyph($r('sys.symbol.xxx'))` 或者把 iOS 的 `imageset` 资源转 PNG 塞进 `entry/src/main/resources/base/media/`。

## Pink_House 专属资源缺口

| 缺口 | 用途 | 来源 |
|---|---|---|
| 浅粉水彩 + 国风园林底图 | 所有页面背景 | `temp/design` 切图或 iOS `WealthContainerBackground.imageset` |
| 橘猫陪伴（多姿态） | 底部 tab 贴录、聊天主角 | iOS `maomao_*.imageset`、`happy_cat.imageset` 等 |
| 商品/衣物图标 | 宠物商店 / 衣橱网格 | iOS `catFood`/`catRice` 等 + 真实衣物 imageUri |
| 黄金/银币/纸币 | 财富三段 | iOS `mcoin_*`、`GoldTextureGenerator` 动态生成 |

## HarmonyOS 6 / API 16+ 可用的 UI 新能力（待利用）

- `Tabs` 新增底部悬浮 + 毛玻璃兼容选项
- `Navigation` / `NavPathStack` 替代手搓 `@State currentIndex`（P1 往后再引）
- `SymbolGlyph` + 丰富 sys.symbol 资源
- `BlurStyle.BACKGROUND_THIN` 系列做玻璃卡
- 兼容鸿蒙 5：新能力用 `if (canIUse('SystemCapability.ArkUI.ArkUI.Full'))` 降级

## 下次改进清单

1. 写代码前先把鸿蒙布局用注释 tree 画出来（对齐 SwiftUI body 顺序），让用户先 review 布局再开写
2. 接 DevEco 预览器 / 模拟器截图验证再交付
3. 把色值 / 字号 / 圆角 / 阴影放 `AppTheme` 单一真源，禁止 inline 硬编码（除非覆写特殊情况）
4. 宠物陪伴层放进 Index shell 的 Stack 里先占位，素材到位再显示
5. 每改 1 个页面 / 1 个共享组件就让用户跑一次编译，别堆积
