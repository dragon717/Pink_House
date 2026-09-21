
## ⚠️ 测试数据隔离硬规则（2026-09-21「小狗仪仗队」事故）
- 单测宿主 = 主 App（bugod2.ItemManager），测试进程里的 FileManager.default 就是用户真实沙盒。tearDown 删 Application Support 文件 = 删用户数据。
- ShopCatalog 系存储已统一走 `ShopCatalogStorage`（ShopCatalogOps.swift）：测试必须 setUp 调 `ShopCatalogStorage.useTemporaryForTesting()`、tearDown 调 `restoreDefaultForTesting()`；禁止对生产路径 removeItem。防线测试：ShopCatalogStorageIsolationTests。
- 新增任何落盘测试前先问：这条路径会不会指向宿主 App 沙盒？一律用注入目录，不准碰真实文件。
- BSD grep 不支持 `\|` 交替（会静默误报无匹配），搜索一律 `grep -E` 或 `grep -F`；JSONEncoder 默认把中文转义成 \uXXXX，搜中文数据要同时搜明文与 \u 转义。
- Xcode 环境现状：/Applications/Xcode-beta.app 已不存在，只有 /Applications/Xcode.app（不要再带 DEVELOPER_DIR=Xcode-beta）。
