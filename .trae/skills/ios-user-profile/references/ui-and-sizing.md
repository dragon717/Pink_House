# 展示与尺寸

**权威来源：`UserAvatarView.swift`、`UserProfileEditView.swift` 及各调用点。**

## UserAvatarView

```swift
struct UserAvatarView: View {
    let givenName: String
    let familyName: String
    let customAvatarPath: String?   // 文件名，nil/空 → 走兜底
    let size: CGFloat
    init(givenName: String, familyName: String, customAvatarPath: String? = nil, size: CGFloat)
}
```

自定义 `init` ⇒ **加参数必须同时改 init 签名和赋值**，memberwise init 不可用。
可选新参数放参数表**末尾**并给默认值，既有调用点才不用动。

## 各调用点的真实尺寸

| 位置 | size |
|---|---|
| `UserProfileEditView`（编辑页头像） | 120 |
| `MeView`（账户详情大头像） | 80 |
| `MeView`（列表行） | 50 |
| `Settings/Components/AccountCard` | 40 |
| `PetChat/PetChatBubbleView`（聊天气泡） | 40 |

改尺寸时按这张表核对，别只改编辑页。

## 显示优先级

1. 自定义头像（`customAvatarPath` 非空**且**文件存在）
2. Apple ID 首字母缩写（`PersonNameComponentsFormatter`，`.abbreviated`）
3. 默认图标

## 编辑页

`UserProfileEditView` 承担相册选择（`PhotosPicker`）、拍照（`UIImagePickerController`）、删除头像三部分。
头像本体 120×120，叠在头像上的操作按钮 36×36。

## Sheet 尺寸

账户与同步类 sheet 用 `.presentationDetents([.fraction(0.9)])` 占约 90% 屏高。

## 无障碍

头像这类纯装饰 `Image` 默认**不是** a11y 元素，直接贴 `.accessibilityIdentifier` 不会进 UI 层级。
需要被 UI 测试定位时，先 `.accessibilityElement(children: .ignore)`，再加 label + identifier；
identifier 必须纯 ASCII（中文会被截断成空前缀）。详见 xcode 技能的 `uitest-pitfalls.md`。
