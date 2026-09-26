#!/usr/bin/env python3
"""给 ItemManager.xcodeproj 再加一个补丁：macOS 单元测试 target `PinkHouseOpsTests`。

## 为什么需要它

`PinkHouseOps`（Mac 运营工具）在此之前**没有任何单测**，于是像
「中断原因只有一个记录点」这种结构性约束只能靠人读代码维持 ——
而真实事故恰恰是「`markCancelled` 忘了调用、错误分支一辈子走不到」。
这张补丁把测试 target 建起来，让那类约束能被**跑出来**而不是读出来。

## 为什么单独一份脚本（不并进 patch_pbxproj_mac_target.py）

那份脚本的幂等守卫是 `if LOCAL_PKG_REF in text: return 0` —— 一旦跑过就整体返回。
把新步骤追加在它后面，第二次跑就永远不会执行。分开写可以各自幂等。

## 约定

* 新增对象 ID 统一 `FA0B` 前缀 + `E` 段（`E` = 测试），一眼能看出是自动化加的；
* 每处替换都用 `must_replace_once`：**没精确命中一次就整体退出**，
  绝不留下半成品工程（pbxproj 写坏 = Xcode 打不开）。

跑法：

    cd /Users/sangyu/develop/Pink_House
    python3 tools/patch_pbxproj_mac_test_target.py
"""
import pathlib
import sys

PROJ = pathlib.Path("ItemManager.xcodeproj/project.pbxproj")

MAC_TARGET = "FA0B0000000000000000D002"   # PinkHouseOps（被测宿主）
PKG_PROD_MAC = "FA0B0000000000000000C004"  # SharedCatalog（Mac 侧包产物，见另一份脚本）

TEST_PRODUCT = "FA0B0000000000000000E001"
TEST_TARGET = "FA0B0000000000000000E002"
TEST_PHASE_SOURCES = "FA0B0000000000000000E003"
TEST_PHASE_FRAMEWORKS = "FA0B0000000000000000E004"
TEST_PHASE_RESOURCES = "FA0B0000000000000000E005"
TEST_SYNC_GROUP = "FA0B0000000000000000E006"
TEST_CONFIG_LIST = "FA0B0000000000000000E007"
TEST_CFG_DEBUG = "FA0B0000000000000000E008"
TEST_CFG_RELEASE = "FA0B0000000000000000E009"
TEST_DEPENDENCY = "FA0B0000000000000000E00A"
TEST_PROXY = "FA0B0000000000000000E00B"
PKG_PROD_TEST = "FA0B0000000000000000E00C"
BUILDFILE_TEST = "FA0B0000000000000000E00D"

# ⚠️ `TEST_HOST` + `BUNDLE_LOADER`：测试**注入宿主 App**跑，而不是独立进程。
# 这是 `@testable import PinkHouseOps` 能成立的前提（app target 不是库，没法直接链）。
#
# 代价是测试跟着宿主一起吃沙盒（见 PinkHouseOps.entitlements）——
# 所以测试里要开的子进程必须落在沙盒允许的范围内：
# 系统二进制（/bin/sh）可以，仓库里的 python 不行。
# 这一点决定了 `OpsPublisherBridgeTests` 用 `/bin/sh` + 桩脚本，而不是真 python。
MAC_TEST_SETTINGS = """\t\t\t\tBUNDLE_LOADER = "$(TEST_HOST)";
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tDEVELOPMENT_TEAM = 833FJ74GS2;
\t\t\t\tGENERATE_INFOPLIST_FILE = YES;
\t\t\t\tMACOSX_DEPLOYMENT_TARGET = 26.2;
\t\t\t\tMARKETING_VERSION = 1.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = bugod2.ItemManager.OpsTests;
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSDKROOT = macosx;
\t\t\t\tSTRING_CATALOG_GENERATE_SYMBOLS = NO;
\t\t\t\tSUPPORTED_PLATFORMS = macosx;
\t\t\t\tSWIFT_APPROACHABLE_CONCURRENCY = YES;
\t\t\t\tSWIFT_DEFAULT_ACTOR_ISOLATION = MainActor;
\t\t\t\tSWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY = YES;
\t\t\t\tSWIFT_VERSION = 5.0;
\t\t\t\tTEST_HOST = "$(BUILT_PRODUCTS_DIR)/PinkHouseOps.app/Contents/MacOS/PinkHouseOps";
"""


def must_replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"❌ [{label}] 期望命中 1 次，实际 {count} 次：{old[:90]!r}")
    return text.replace(old, new, 1)


def main() -> int:
    text = PROJ.read_text(encoding="utf-8")

    if TEST_TARGET in text:
        print("已经打过测试 target 补丁，未做改动")
        return 0

    if MAC_TARGET not in text:
        raise SystemExit("❌ 找不到 Mac target —— 请先跑 tools/patch_pbxproj_mac_target.py")

    # ---- 1. 测试产物 FileReference ----
    text = must_replace_once(
        text,
        "/* End PBXFileReference section */",
        f'\t\t{TEST_PRODUCT} /* PinkHouseOpsTests.xctest */ = {{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = PinkHouseOpsTests.xctest; sourceTree = BUILT_PRODUCTS_DIR; }};\n'
        "/* End PBXFileReference section */",
        "PBXFileReference")

    # ---- 2. 依赖宿主用的 ContainerItemProxy ----
    text = must_replace_once(
        text,
        "/* End PBXContainerItemProxy section */",
        f'\t\t{TEST_PROXY} /* PBXContainerItemProxy */ = {{\n'
        "\t\t\tisa = PBXContainerItemProxy;\n"
        "\t\t\tcontainerPortal = A2AE586B2F19377500B4B6EB /* Project object */;\n"
        "\t\t\tproxyType = 1;\n"
        f"\t\t\tremoteGlobalIDString = {MAC_TARGET};\n"
        "\t\t\tremoteInfo = PinkHouseOps;\n"
        "\t\t};\n"
        "/* End PBXContainerItemProxy section */",
        "PBXContainerItemProxy")

    # ---- 3. 文件同步组（测试源码目录，新增测试文件不必再改 pbxproj）----
    text = must_replace_once(
        text,
        "/* End PBXFileSystemSynchronizedRootGroup section */",
        f"\t\t{TEST_SYNC_GROUP} /* PinkHouseOpsTests */ = {{\n"
        "\t\t\tisa = PBXFileSystemSynchronizedRootGroup;\n"
        "\t\t\tpath = PinkHouseOpsTests;\n"
        "\t\t\tsourceTree = \"<group>\";\n"
        "\t\t};\n"
        "/* End PBXFileSystemSynchronizedRootGroup section */",
        "PBXFileSystemSynchronizedRootGroup")

    # ---- 4. 测试 Frameworks phase（链 SharedCatalog，宿主模块的 swiftmodule 依赖它）----
    text = must_replace_once(
        text,
        "/* End PBXFrameworksBuildPhase section */",
        f"\t\t{TEST_PHASE_FRAMEWORKS} /* Frameworks */ = {{\n"
        "\t\t\tisa = PBXFrameworksBuildPhase;\n"
        "\t\t\tbuildActionMask = 2147483647;\n"
        "\t\t\tfiles = (\n"
        f"\t\t\t\t{BUILDFILE_TEST} /* SharedCatalog in Frameworks */,\n"
        "\t\t\t);\n"
        "\t\t\trunOnlyForDeploymentPostprocessing = 0;\n"
        "\t\t};\n"
        "/* End PBXFrameworksBuildPhase section */",
        "PBXFrameworksBuildPhase")

    # ---- 5. 测试 target ----
    text = must_replace_once(
        text,
        "/* End PBXNativeTarget section */",
        f"\t\t{TEST_TARGET} /* PinkHouseOpsTests */ = {{\n"
        "\t\t\tisa = PBXNativeTarget;\n"
        f"\t\t\tbuildConfigurationList = {TEST_CONFIG_LIST} /* Build configuration list for PBXNativeTarget \"PinkHouseOpsTests\" */;\n"
        "\t\t\tbuildPhases = (\n"
        f"\t\t\t\t{TEST_PHASE_SOURCES} /* Sources */,\n"
        f"\t\t\t\t{TEST_PHASE_FRAMEWORKS} /* Frameworks */,\n"
        f"\t\t\t\t{TEST_PHASE_RESOURCES} /* Resources */,\n"
        "\t\t\t);\n"
        "\t\t\tbuildRules = (\n"
        "\t\t\t);\n"
        "\t\t\tdependencies = (\n"
        f"\t\t\t\t{TEST_DEPENDENCY} /* PBXTargetDependency */,\n"
        "\t\t\t);\n"
        "\t\t\tfileSystemSynchronizedGroups = (\n"
        f"\t\t\t\t{TEST_SYNC_GROUP} /* PinkHouseOpsTests */,\n"
        "\t\t\t);\n"
        "\t\t\tname = PinkHouseOpsTests;\n"
        "\t\t\tpackageProductDependencies = (\n"
        f"\t\t\t\t{PKG_PROD_TEST} /* SharedCatalog */,\n"
        "\t\t\t);\n"
        "\t\t\tproductName = PinkHouseOpsTests;\n"
        f"\t\t\tproductReference = {TEST_PRODUCT} /* PinkHouseOpsTests.xctest */;\n"
        "\t\t\tproductType = \"com.apple.product-type.bundle.unit-test\";\n"
        "\t\t};\n"
        "/* End PBXNativeTarget section */",
        "PBXNativeTarget")

    # ---- 6. 主组 children ----
    text = must_replace_once(
        text,
        "\t\tA2AE586A2F19377400B4B6EB = {\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n"
        "\t\t\t\tA2AE58752F19377500B4B6EB /* ItemManager */,\n"
        "\t\t\t\tFA0B0000000000000000D006 /* PinkHouseOps */,\n",
        "\t\tA2AE586A2F19377400B4B6EB = {\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n"
        "\t\t\t\tA2AE58752F19377500B4B6EB /* ItemManager */,\n"
        "\t\t\t\tFA0B0000000000000000D006 /* PinkHouseOps */,\n"
        f"\t\t\t\t{TEST_SYNC_GROUP} /* PinkHouseOpsTests */,\n",
        "mainGroup children")

    # ---- 7. Products children ----
    text = must_replace_once(
        text,
        "\t\t\t\tFA0B0000000000000000D001 /* PinkHouseOps.app */,\n",
        "\t\t\t\tFA0B0000000000000000D001 /* PinkHouseOps.app */,\n"
        f"\t\t\t\t{TEST_PRODUCT} /* PinkHouseOpsTests.xctest */,\n",
        "Products children")

    # ---- 8. PBXProject targets ----
    text = must_replace_once(
        text,
        f"\t\t\t\t{MAC_TARGET} /* PinkHouseOps */,\n\t\t\t);\n\t\t}};\n/* End PBXProject section */",
        f"\t\t\t\t{MAC_TARGET} /* PinkHouseOps */,\n"
        f"\t\t\t\t{TEST_TARGET} /* PinkHouseOpsTests */,\n"
        "\t\t\t);\n\t\t};\n/* End PBXProject section */",
        "targets")

    # ---- 9. TargetAttributes（TestTargetID 指向宿主，Xcode 靠它认「测谁」）----
    text = must_replace_once(
        text,
        f"\t\t\t\t\t{MAC_TARGET} = {{\n\t\t\t\t\t\tCreatedOnToolsVersion = 26.2;\n\t\t\t\t\t}};\n",
        f"\t\t\t\t\t{MAC_TARGET} = {{\n\t\t\t\t\t\tCreatedOnToolsVersion = 26.2;\n\t\t\t\t\t}};\n"
        f"\t\t\t\t\t{TEST_TARGET} = {{\n\t\t\t\t\t\tCreatedOnToolsVersion = 26.2;\n"
        f"\t\t\t\t\t\tTestTargetID = {MAC_TARGET};\n\t\t\t\t\t}};\n",
        "TargetAttributes")

    # ---- 10. 测试 Sources / Resources phase ----
    text = must_replace_once(
        text,
        "/* End PBXSourcesBuildPhase section */",
        f"\t\t{TEST_PHASE_SOURCES} /* Sources */ = {{\n"
        "\t\t\tisa = PBXSourcesBuildPhase;\n"
        "\t\t\tbuildActionMask = 2147483647;\n"
        "\t\t\tfiles = (\n"
        "\t\t\t);\n"
        "\t\t\trunOnlyForDeploymentPostprocessing = 0;\n"
        "\t\t};\n"
        "/* End PBXSourcesBuildPhase section */",
        "PBXSourcesBuildPhase")

    text = must_replace_once(
        text,
        "/* End PBXResourcesBuildPhase section */",
        f"\t\t{TEST_PHASE_RESOURCES} /* Resources */ = {{\n"
        "\t\t\tisa = PBXResourcesBuildPhase;\n"
        "\t\t\tbuildActionMask = 2147483647;\n"
        "\t\t\tfiles = (\n"
        "\t\t\t);\n"
        "\t\t\trunOnlyForDeploymentPostprocessing = 0;\n"
        "\t\t};\n"
        "/* End PBXResourcesBuildPhase section */",
        "PBXResourcesBuildPhase")

    # ---- 11. TargetDependency ----
    text = must_replace_once(
        text,
        "/* End PBXTargetDependency section */",
        f"\t\t{TEST_DEPENDENCY} /* PBXTargetDependency */ = {{\n"
        "\t\t\tisa = PBXTargetDependency;\n"
        f"\t\t\ttarget = {MAC_TARGET} /* PinkHouseOps */;\n"
        f"\t\t\ttargetProxy = {TEST_PROXY} /* PBXContainerItemProxy */;\n"
        "\t\t};\n"
        "/* End PBXTargetDependency section */",
        "PBXTargetDependency")

    # ---- 12. 测试构建配置 ----
    text = must_replace_once(
        text,
        "/* End XCBuildConfiguration section */",
        f'\t\t{TEST_CFG_DEBUG} /* Debug */ = {{\n'
        "\t\t\tisa = XCBuildConfiguration;\n"
        "\t\t\tbuildSettings = {\n"
        f"{MAC_TEST_SETTINGS}"
        "\t\t\t};\n"
        "\t\t\tname = Debug;\n"
        "\t\t};\n"
        f'\t\t{TEST_CFG_RELEASE} /* Release */ = {{\n'
        "\t\t\tisa = XCBuildConfiguration;\n"
        "\t\t\tbuildSettings = {\n"
        f"{MAC_TEST_SETTINGS}"
        "\t\t\t};\n"
        "\t\t\tname = Release;\n"
        "\t\t};\n"
        "/* End XCBuildConfiguration section */",
        "XCBuildConfiguration")

    # ---- 13. 测试配置列表 ----
    text = must_replace_once(
        text,
        "/* End XCConfigurationList section */",
        f"\t\t{TEST_CONFIG_LIST} /* Build configuration list for PBXNativeTarget \"PinkHouseOpsTests\" */ = {{\n"
        "\t\t\tisa = XCConfigurationList;\n"
        "\t\t\tbuildConfigurations = (\n"
        f"\t\t\t\t{TEST_CFG_DEBUG} /* Debug */,\n"
        f"\t\t\t\t{TEST_CFG_RELEASE} /* Release */,\n"
        "\t\t\t);\n"
        "\t\t\tdefaultConfigurationIsVisible = 0;\n"
        "\t\t\tdefaultConfigurationName = Release;\n"
        "\t\t};\n"
        "/* End XCConfigurationList section */",
        "XCConfigurationList")

    # ---- 14. 测试侧对 SharedCatalog 的包产物依赖 ----
    text = must_replace_once(
        text,
        "/* End XCSwiftPackageProductDependency section */",
        f"\t\t{PKG_PROD_TEST} /* SharedCatalog */ = {{\n"
        "\t\t\tisa = XCSwiftPackageProductDependency;\n"
        "\t\t\tpackage = FA0B0000000000000000C001;\n"
        "\t\t\tproductName = SharedCatalog;\n"
        "\t\t};\n"
        "/* End XCSwiftPackageProductDependency section */",
        "XCSwiftPackageProductDependency")

    # ---- 15. 测试侧链接 SharedCatalog 的 PBXBuildFile ----
    text = must_replace_once(
        text,
        "/* End PBXBuildFile section */",
        f'\t\t{BUILDFILE_TEST} /* SharedCatalog in Frameworks */ = {{isa = PBXBuildFile; productRef = {PKG_PROD_TEST} /* SharedCatalog */; }};\n'
        "/* End PBXBuildFile section */",
        "PBXBuildFile")

    PROJ.write_text(text, encoding="utf-8")
    print("✅ pbxproj 测试 target 补丁已应用")
    return 0


if __name__ == "__main__":
    sys.exit(main())
