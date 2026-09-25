#!/usr/bin/env python3
"""给 ItemManager.xcodeproj 打两处补丁（幂等，重复跑不会重复插入）：

  1. 接入本地 Swift Package `Packages/SharedCatalog`，并让 ItemManager target 链接它；
  2. 新增 macOS app target `PinkHouseOps`（Mac 原生运营工具，计划 P1）。

## 为什么用脚本而不是手改

pbxproj 是 24 位十六进制对象图，手改一旦写错引用 ID，Xcode 会直接打不开工程。
脚本的好处是：替换串必须**精确命中一次**（`must_replace_once`），
任何一处没命中就整体退出，不会留下半成品工程。

所有新增对象 ID 统一用 `FA0B` 前缀，一眼能看出是自动化加的。
"""
import pathlib
import sys

PROJ = pathlib.Path("ItemManager.xcodeproj/project.pbxproj")

# ---- 本地包 ----
LOCAL_PKG_REF = "FA0B0000000000000000C001"
PKG_PROD_IOS = "FA0B0000000000000000C002"
BUILDFILE_IOS = "FA0B0000000000000000C003"
PKG_PROD_MAC = "FA0B0000000000000000C004"
BUILDFILE_MAC = "FA0B0000000000000000C005"

# ---- Mac target ----
APP_FILEREF = "FA0B0000000000000000D001"
TARGET = "FA0B0000000000000000D002"
PHASE_SOURCES = "FA0B0000000000000000D003"
PHASE_FRAMEWORKS = "FA0B0000000000000000D004"
PHASE_RESOURCES = "FA0B0000000000000000D005"
SYNC_GROUP = "FA0B0000000000000000D006"
CONFIG_LIST = "FA0B0000000000000000D007"
CFG_DEBUG = "FA0B0000000000000000D008"
CFG_RELEASE = "FA0B0000000000000000D009"

MAC_SETTINGS = """\t\t\t\tCODE_SIGN_ENTITLEMENTS = PinkHouseOps/PinkHouseOps.entitlements;
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tDEVELOPMENT_TEAM = 833FJ74GS2;
\t\t\t\tENABLE_APP_SANDBOX = YES;
\t\t\t\tENABLE_HARDENED_RUNTIME = YES;
\t\t\t\tENABLE_PREVIEWS = YES;
\t\t\t\tENABLE_USER_SELECTED_FILES = readwrite;
\t\t\t\tGENERATE_INFOPLIST_FILE = YES;
\t\t\t\tINFOPLIST_KEY_CFBundleDisplayName = "Pink House Ops";
\t\t\t\tINFOPLIST_KEY_LSApplicationCategoryType = "public.app-category.productivity";
\t\t\t\tINFOPLIST_KEY_NSHumanReadableCopyright = "";
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = "@executable_path/../Frameworks";
\t\t\t\tMACOSX_DEPLOYMENT_TARGET = 26.2;
\t\t\t\tMARKETING_VERSION = 1.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = bugod2.ItemManager.Ops;
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSDKROOT = macosx;
\t\t\t\tSTRING_CATALOG_GENERATE_SYMBOLS = YES;
\t\t\t\tSUPPORTED_PLATFORMS = macosx;
\t\t\t\tSWIFT_APPROACHABLE_CONCURRENCY = YES;
\t\t\t\tSWIFT_DEFAULT_ACTOR_ISOLATION = MainActor;
\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;
\t\t\t\tSWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY = YES;
\t\t\t\tSWIFT_VERSION = 5.0;
"""


def must_replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"❌ [{label}] 期望命中 1 次，实际 {count} 次：{old[:80]!r}")
    return text.replace(old, new, 1)


def main() -> int:
    text = PROJ.read_text(encoding="utf-8")

    if LOCAL_PKG_REF in text:
        print("已经打过补丁，未做改动")
        return 0

    # ---- 1. PBXBuildFile ----
    # 锚点用 section 结束标记：`WidgetKit.framework in Frameworks` 在 Frameworks phase
    # 里也出现一次，拿它当锚点会命中两次（实测踩到）。
    text = must_replace_once(
        text,
        "/* End PBXBuildFile section */",
        f'\t\t{BUILDFILE_IOS} /* SharedCatalog in Frameworks */ = {{isa = PBXBuildFile; productRef = {PKG_PROD_IOS} /* SharedCatalog */; }};\n'
        f'\t\t{BUILDFILE_MAC} /* SharedCatalog in Frameworks */ = {{isa = PBXBuildFile; productRef = {PKG_PROD_MAC} /* SharedCatalog */; }};\n'
        "/* End PBXBuildFile section */",
        "PBXBuildFile")

    # ---- 2. PBXFileReference（Mac 产物）----
    # 锚点同样用 section 结束标记：产物文件名在 Products 组里也会出现一次
    text = must_replace_once(
        text,
        "/* End PBXFileReference section */",
        f'\t\t{APP_FILEREF} /* PinkHouseOps.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = PinkHouseOps.app; sourceTree = BUILT_PRODUCTS_DIR; }};\n'
        "/* End PBXFileReference section */",
        "PBXFileReference")

    # ---- 3. 文件同步组（Mac 源码目录）----
    text = must_replace_once(
        text,
        "/* End PBXFileSystemSynchronizedRootGroup section */",
        f'\t\t{SYNC_GROUP} /* PinkHouseOps */ = {{\n'
        "\t\t\tisa = PBXFileSystemSynchronizedRootGroup;\n"
        "\t\t\tpath = PinkHouseOps;\n"
        "\t\t\tsourceTree = \"<group>\";\n"
        "\t\t};\n"
        "/* End PBXFileSystemSynchronizedRootGroup section */",
        "PBXFileSystemSynchronizedRootGroup")

    # ---- 4. Mac Frameworks phase ----
    text = must_replace_once(
        text,
        "/* End PBXFrameworksBuildPhase section */",
        f'\t\t{PHASE_FRAMEWORKS} /* Frameworks */ = {{\n'
        "\t\t\tisa = PBXFrameworksBuildPhase;\n"
        "\t\t\tbuildActionMask = 2147483647;\n"
        "\t\t\tfiles = (\n"
        f"\t\t\t\t{BUILDFILE_MAC} /* SharedCatalog in Frameworks */,\n"
        "\t\t\t);\n"
        "\t\t\trunOnlyForDeploymentPostprocessing = 0;\n"
        "\t\t};\n"
        "/* End PBXFrameworksBuildPhase section */",
        "PBXFrameworksBuildPhase")

    # ---- 5. 接进 ItemManager 的 Frameworks phase ----
    text = must_replace_once(
        text,
        "\t\t\t\tA280DB932F443697002CBC10 /* GoogleGenerativeAI in Frameworks */,\n",
        "\t\t\t\tA280DB932F443697002CBC10 /* GoogleGenerativeAI in Frameworks */,\n"
        f"\t\t\t\t{BUILDFILE_IOS} /* SharedCatalog in Frameworks */,\n",
        "iOS Frameworks files")

    # ---- 6. 主组 children ----
    # `/* ItemManager */,` 在 target 的 fileSystemSynchronizedGroups 里也有同样一行，
    # 必须带上 mainGroup 的头部（对象 ID + isa + children）才能唯一命中
    text = must_replace_once(
        text,
        "\t\tA2AE586A2F19377400B4B6EB = {\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n"
        "\t\t\t\tA2AE58752F19377500B4B6EB /* ItemManager */,\n",
        "\t\tA2AE586A2F19377400B4B6EB = {\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n"
        "\t\t\t\tA2AE58752F19377500B4B6EB /* ItemManager */,\n"
        f"\t\t\t\t{SYNC_GROUP} /* PinkHouseOps */,\n",
        "mainGroup children")

    # ---- 7. Products children ----
    text = must_replace_once(
        text,
        "\t\t\t\tA2AE58732F19377500B4B6EB /* ItemManager.app */,\n",
        "\t\t\t\tA2AE58732F19377500B4B6EB /* ItemManager.app */,\n"
        f"\t\t\t\t{APP_FILEREF} /* PinkHouseOps.app */,\n",
        "Products children")

    # ---- 8. Mac target ----
    text = must_replace_once(
        text,
        "/* End PBXNativeTarget section */",
        f'\t\t{TARGET} /* PinkHouseOps */ = {{\n'
        "\t\t\tisa = PBXNativeTarget;\n"
        f"\t\t\tbuildConfigurationList = {CONFIG_LIST} /* Build configuration list for PBXNativeTarget \"PinkHouseOps\" */;\n"
        "\t\t\tbuildPhases = (\n"
        f"\t\t\t\t{PHASE_SOURCES} /* Sources */,\n"
        f"\t\t\t\t{PHASE_FRAMEWORKS} /* Frameworks */,\n"
        f"\t\t\t\t{PHASE_RESOURCES} /* Resources */,\n"
        "\t\t\t);\n"
        "\t\t\tbuildRules = (\n"
        "\t\t\t);\n"
        "\t\t\tdependencies = (\n"
        "\t\t\t);\n"
        "\t\t\tfileSystemSynchronizedGroups = (\n"
        f"\t\t\t\t{SYNC_GROUP} /* PinkHouseOps */,\n"
        "\t\t\t);\n"
        "\t\t\tname = PinkHouseOps;\n"
        "\t\t\tpackageProductDependencies = (\n"
        f"\t\t\t\t{PKG_PROD_MAC} /* SharedCatalog */,\n"
        "\t\t\t);\n"
        "\t\t\tproductName = PinkHouseOps;\n"
        f"\t\t\tproductReference = {APP_FILEREF} /* PinkHouseOps.app */;\n"
        "\t\t\tproductType = \"com.apple.product-type.application\";\n"
        "\t\t};\n"
        "/* End PBXNativeTarget section */",
        "PBXNativeTarget")

    # ---- 9. ItemManager target 链接本地包 ----
    text = must_replace_once(
        text,
        "\t\t\t\tA280DB922F443697002CBC10 /* GoogleGenerativeAI */,\n",
        "\t\t\t\tA280DB922F443697002CBC10 /* GoogleGenerativeAI */,\n"
        f"\t\t\t\t{PKG_PROD_IOS} /* SharedCatalog */,\n",
        "ItemManager packageProductDependencies")

    # ---- 10. PBXProject：TargetAttributes / packageReferences / targets ----
    text = must_replace_once(
        text,
        "\t\t\t\t\tA2AE59BF2F1EB85300B4B6EB = {\n\t\t\t\t\t\tCreatedOnToolsVersion = 26.2;\n\t\t\t\t\t};\n",
        "\t\t\t\t\tA2AE59BF2F1EB85300B4B6EB = {\n\t\t\t\t\t\tCreatedOnToolsVersion = 26.2;\n\t\t\t\t\t};\n"
        f"\t\t\t\t\t{TARGET} = {{\n\t\t\t\t\t\tCreatedOnToolsVersion = 26.2;\n\t\t\t\t\t}};\n",
        "TargetAttributes")

    text = must_replace_once(
        text,
        "\t\t\t\tA280DB912F443697002CBC10 /* XCRemoteSwiftPackageReference \"generative-ai-swift\" */,\n",
        "\t\t\t\tA280DB912F443697002CBC10 /* XCRemoteSwiftPackageReference \"generative-ai-swift\" */,\n"
        f"\t\t\t\t{LOCAL_PKG_REF} /* XCLocalSwiftPackageReference \"Packages/SharedCatalog\" */,\n",
        "packageReferences")

    text = must_replace_once(
        text,
        "\t\t\t\tA2AE59BF2F1EB85300B4B6EB /* 少女心愿衣橱Extension */,\n\t\t\t);\n\t\t};\n/* End PBXProject section */",
        "\t\t\t\tA2AE59BF2F1EB85300B4B6EB /* 少女心愿衣橱Extension */,\n"
        f"\t\t\t\t{TARGET} /* PinkHouseOps */,\n"
        "\t\t\t);\n\t\t};\n/* End PBXProject section */",
        "targets")

    # ---- 11. Mac Sources / Resources phase ----
    text = must_replace_once(
        text,
        "/* End PBXSourcesBuildPhase section */",
        f'\t\t{PHASE_SOURCES} /* Sources */ = {{\n'
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
        f'\t\t{PHASE_RESOURCES} /* Resources */ = {{\n'
        "\t\t\tisa = PBXResourcesBuildPhase;\n"
        "\t\t\tbuildActionMask = 2147483647;\n"
        "\t\t\tfiles = (\n"
        "\t\t\t);\n"
        "\t\t\trunOnlyForDeploymentPostprocessing = 0;\n"
        "\t\t};\n"
        "/* End PBXResourcesBuildPhase section */",
        "PBXResourcesBuildPhase")

    # ---- 12. Mac 构建配置 ----
    text = must_replace_once(
        text,
        "/* End XCBuildConfiguration section */",
        f'\t\t{CFG_DEBUG} /* Debug */ = {{\n'
        "\t\t\tisa = XCBuildConfiguration;\n"
        "\t\t\tbuildSettings = {\n"
        f"{MAC_SETTINGS}"
        "\t\t\t};\n"
        "\t\t\tname = Debug;\n"
        "\t\t};\n"
        f'\t\t{CFG_RELEASE} /* Release */ = {{\n'
        "\t\t\tisa = XCBuildConfiguration;\n"
        "\t\t\tbuildSettings = {\n"
        f"{MAC_SETTINGS}"
        "\t\t\t};\n"
        "\t\t\tname = Release;\n"
        "\t\t};\n"
        "/* End XCBuildConfiguration section */",
        "XCBuildConfiguration")

    # ---- 13. Mac 配置列表 ----
    text = must_replace_once(
        text,
        "/* End XCConfigurationList section */",
        f'\t\t{CONFIG_LIST} /* Build configuration list for PBXNativeTarget "PinkHouseOps" */ = {{\n'
        "\t\t\tisa = XCConfigurationList;\n"
        "\t\t\tbuildConfigurations = (\n"
        f"\t\t\t\t{CFG_DEBUG} /* Debug */,\n"
        f"\t\t\t\t{CFG_RELEASE} /* Release */,\n"
        "\t\t\t);\n"
        "\t\t\tdefaultConfigurationIsVisible = 0;\n"
        "\t\t\tdefaultConfigurationName = Release;\n"
        "\t\t};\n"
        "/* End XCConfigurationList section */",
        "XCConfigurationList")

    # ---- 14. 本地包引用 section（XCLocalSwiftPackageReference 按字母序在 XCRemote 之前）----
    text = must_replace_once(
        text,
        "/* Begin XCRemoteSwiftPackageReference section */",
        "/* Begin XCLocalSwiftPackageReference section */\n"
        f'\t\t{LOCAL_PKG_REF} /* XCLocalSwiftPackageReference "Packages/SharedCatalog" */ = {{\n'
        "\t\t\tisa = XCLocalSwiftPackageReference;\n"
        "\t\t\trelativePath = Packages/SharedCatalog;\n"
        "\t\t};\n"
        "/* End XCLocalSwiftPackageReference section */\n\n"
        "/* Begin XCRemoteSwiftPackageReference section */",
        "XCLocalSwiftPackageReference")

    # ---- 15. 包产物依赖 ----
    text = must_replace_once(
        text,
        "/* End XCSwiftPackageProductDependency section */",
        f'\t\t{PKG_PROD_IOS} /* SharedCatalog */ = {{\n'
        "\t\t\tisa = XCSwiftPackageProductDependency;\n"
        f"\t\t\tpackage = {LOCAL_PKG_REF};\n"
        "\t\t\tproductName = SharedCatalog;\n"
        "\t\t};\n"
        f'\t\t{PKG_PROD_MAC} /* SharedCatalog */ = {{\n'
        "\t\t\tisa = XCSwiftPackageProductDependency;\n"
        f"\t\t\tpackage = {LOCAL_PKG_REF};\n"
        "\t\t\tproductName = SharedCatalog;\n"
        "\t\t};\n"
        "/* End XCSwiftPackageProductDependency section */",
        "XCSwiftPackageProductDependency")

    PROJ.write_text(text, encoding="utf-8")
    print("✅ pbxproj 补丁已应用")
    return 0


if __name__ == "__main__":
    sys.exit(main())
