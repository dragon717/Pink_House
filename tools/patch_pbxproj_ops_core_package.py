#!/usr/bin/env python3
"""给 ItemManager.xcodeproj 加本地包 `Packages/PinkHouseOps` 的接线。

## 为什么需要它

`OpsPublisherBridge`（受控发布桥接的调用端）2026-09-27 从 App target 抽进本地包
`Packages/PinkHouseOps`（模块名 `PinkHouseOpsCore`），目的是让这层**能被跑起来验证**：
App 宿主式单测在本机跑不起来（`xcodebuild test` 永久挂起，取证见 skill
`pink-house-xcodebuild-acceptance` 的 `references/mac-xctest-hang-forensics.md`），
而按路径拆包之后 `swift test` 是通的（秒级，见 `Packages/PinkHouseOps`）。

App 侧要链这个新产物，而 pbxproj 只能改文件 —— 所以有这张补丁。

## 加的是四处（互相引用，缺一个就编不过或 Xcode 打不开）

| ID | 类型 | 作用 |
|---|---|---|
| `…F001` | `XCLocalSwiftPackageReference` | 指向 `Packages/PinkHouseOps` |
| `…F002` | `XCSwiftPackageProductDependency` | 产品 `PinkHouseOpsCore` |
| `…F003` | `PBXBuildFile` | 把产物链进 App 的 Frameworks 阶段 |

另外把 `…F002` 挂进 App target 的 `packageProductDependencies`、
把 `…F001` 挂进工程的 `packageReferences`。

## 只给 App target 挂，测试 target 不挂

`PinkHouseOpsTests` 里只剩 `OpsSnapshotHarnessTests`（要 AppKit + 整套视图层），
它不引用任何桥接类型 —— 需要桥接的那两个用例已经搬进包里了。

## 约定

* ID 用 `FA0B` 前缀 + `F` 段（`E` 段已被测试 target 占用），一眼能看出是自动化加的；
* 每处替换都走 `must_replace_once`：**没精确命中一次就整体退出**，
  绝不留下半成品工程（pbxproj 写坏 = Xcode 打不开）；
* 幂等守卫：只要 `…F001` 已存在就直接返回，重复跑无副作用。

跑法：

    cd /Users/sangyu/develop/Pink_House
    python3 tools/patch_pbxproj_ops_core_package.py
    plutil -lint ItemManager.xcodeproj/project.pbxproj
"""
import pathlib

PROJ = pathlib.Path("ItemManager.xcodeproj/project.pbxproj")

PKG_REF = "FA0B0000000000000000F001"
PKG_PROD = "FA0B0000000000000000F002"
PKG_BUILDFILE = "FA0B0000000000000000F003"

PKG_PATH = "Packages/PinkHouseOps"
PKG_PRODUCT = "PinkHouseOpsCore"

# ⚠️ 这两个是**既有**对象的 ID，用来定位插入点（不是我们新建的）：
BUILDFILE_MAC_SHARED = "FA0B0000000000000000C005"   # App 的 SharedCatalog build file
PROD_MAC_SHARED = "FA0B0000000000000000C004"        # App 的 SharedCatalog product dep
REF_SHARED = "FA0B0000000000000000C001"             # Packages/SharedCatalog 的包引用
BUILDFILE_TEST_SHARED = "FA0B0000000000000000E00D"  # 测试 target 的（仅用于定位文本）


def must_replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"❌ [{label}] 期望命中 1 次，实际 {count} 次：{old[:100]!r}")
    return text.replace(old, new, 1)


def main() -> int:
    text = PROJ.read_text(encoding="utf-8")

    if PKG_REF in text:
        print(f"✅ 已接线（找到 {PKG_REF}），跳过")
        return 0

    # ---- 1) PBXBuildFile 条目 ----
    anchor = (
        f"\t\t{BUILDFILE_TEST_SHARED} /* SharedCatalog in Frameworks */ = "
        "{isa = PBXBuildFile; productRef = FA0B0000000000000000E00C /* SharedCatalog */; };\n")
    addition = (
        f"\t\t{PKG_BUILDFILE} /* {PKG_PRODUCT} in Frameworks */ = "
        f"{{isa = PBXBuildFile; productRef = {PKG_PROD} /* {PKG_PRODUCT} */; }};\n")
    text = must_replace_once(text, anchor, anchor + addition, "PBXBuildFile")

    # ---- 2) 挂进 App 的 Frameworks 阶段 ----
    anchor = f"\t\t\t\t{BUILDFILE_MAC_SHARED} /* SharedCatalog in Frameworks */,\n"
    addition = f"\t\t\t\t{PKG_BUILDFILE} /* {PKG_PRODUCT} in Frameworks */,\n"
    text = must_replace_once(text, anchor, anchor + addition, "Frameworks 阶段")

    # ---- 3) 挂进 App 的 packageProductDependencies ----
    anchor = f"\t\t\t\t{PROD_MAC_SHARED} /* SharedCatalog */,\n"
    addition = f"\t\t\t\t{PKG_PROD} /* {PKG_PRODUCT} */,\n"
    text = must_replace_once(text, anchor, anchor + addition, "packageProductDependencies")

    # ---- 4) 挂进工程的 packageReferences ----
    anchor = (f"\t\t\t\t{REF_SHARED} /* XCLocalSwiftPackageReference "
              f"\"{PKG_PATH.replace('PinkHouseOps', 'SharedCatalog')}\" */,\n")
    addition = (f"\t\t\t\t{PKG_REF} /* XCLocalSwiftPackageReference \"{PKG_PATH}\" */,\n")
    text = must_replace_once(text, anchor, anchor + addition, "packageReferences")

    # ---- 5) 定义包引用 ----
    anchor = "/* End XCLocalSwiftPackageReference section */\n"
    addition = (f"\t\t{PKG_REF} /* XCLocalSwiftPackageReference \"{PKG_PATH}\" */ = {{\n"
                f"\t\t\tisa = XCLocalSwiftPackageReference;\n"
                f"\t\t\trelativePath = {PKG_PATH};\n"
                f"\t\t}};\n")
    text = must_replace_once(text, anchor, addition + anchor, "XCLocalSwiftPackageReference")

    # ---- 6) 定义产品依赖 ----
    anchor = "/* End XCSwiftPackageProductDependency section */\n"
    addition = (f"\t\t{PKG_PROD} /* {PKG_PRODUCT} */ = {{\n"
                f"\t\t\tisa = XCSwiftPackageProductDependency;\n"
                f"\t\t\tpackage = {PKG_REF} /* XCLocalSwiftPackageReference \"{PKG_PATH}\" */;\n"
                f"\t\t\tproductName = {PKG_PRODUCT};\n"
                f"\t\t}};\n")
    text = must_replace_once(text, anchor, addition + anchor, "XCSwiftPackageProductDependency")

    PROJ.write_text(text, encoding="utf-8")
    print(f"✅ 已接线 {PKG_PATH}（产品 {PKG_PRODUCT}，新增 3 个对象 + 3 处挂载）")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
