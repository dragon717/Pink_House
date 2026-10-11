# 阶段 B：真实执行记录（2026-10-09）

阶段 B 的 B1–B10 已通过。阶段 C 未开始；本轮不代表 iOS 真机验收完成。

证据目录：`output/阶段B/2026-10-09_正式验收/`。验收使用独立资料目录，未导入或覆盖用户当前草稿。Mac 应用收尾仍保持第 414 版、4 店家 / 12 系列 / 277 商品 / 282 图片。

## B1–B10 结果

| 步骤 | 结果 | 实际证据与边界 |
| --- | --- | --- |
| B1 | 通过 | Console 部署成功后重新导出生产 schema；与最终开发 schema 一致。三类 THRelease / THDataPack / THMedia 的 `_world`、`_icloud` 均只有 Read，TimeHallPublisher 只有这三类的 Create / Read / Write。未改字段或索引。 |
| B2 | 通过 | 修正已有 production Key ID；文件与 Keychain 实际认证成功，Mac 应用显示 Production 已配置。未新建或替换私钥。 |
| B3 | 通过 | 应用切 Development→Production，旧同步结论清除；七项状态清理经代码复核。 |
| B4 | 通过 | 发布前实际读取空生产库，基线为 0；Mac 应用显示空态且保留本地独有 1137 条。用同一共享合并代码对实际拉回的空目录合并独立验收资料，实体保留、无冲突。 |
| B5 | 通过 | 独立目录构造并校验 1 店家 / 1 系列 / 1 商品及 3 张 PNG；未替换用户草稿。资料创建采用命令行，未声称在用户草稿内点新增按钮。 |
| B6 | 通过 | 冻结整包摘要、真实基线与演练校验通过；演练没有写入。 |
| B7 | 通过 | seq 1 真实上传 3 媒体、1 包，回读确认；三张图片实际下载并逐字节匹配。权限收紧后 seq 3 再真实上传 1 包并回读确认，证明专属角色有效。 |
| B8 | 通过 | seq 2 删除专用商品并发布，显式 removedProductIDs 生效；seq 1 历史包及三张图片仍可实际下载，seq 3 后再次确认。没有物理删除。 |
| B9 | 通过 | seq 2、seq 3 实际拉回 environment=production，商品不在、墓碑仍在、店家系列仍在；共享合并代码验证删除不会复活且保留本地另一个字段的修改。Mac 应用实际拉回 seq 3，显示补进 2 条、保留本地独有 1137 条。没有点击合并改变用户当前草稿。 |
| B10 | 通过 | 最终真实 development 拉回仍为原 seq 6；全部实体和删除标记中都没有这批 production 专用 ID。 |

## 权限闭环

用户明确指定：Mac 受控发布工具与手机运营账号身份分开；手机使用既有 iCloud 用户标识白名单。没有把开发者发布身份加入手机白名单，也不再要求登录个人运营账号。

`NoticeCloudKitService.creatorGate()` 与 `CreatorAccess.refresh()` 已确认复用既有白名单。明确不在名单时本地开关不能放行；iOS 店家商品库写服务调用相同门控。

Mac 使用 Keychain 中已有 S2S 凭证，实际 `users/caller` / `users/current` GET 确认发布身份。读取两个白名单成员及发布身份的 Users 记录，均已存在于两环境。

最初真实上传返回 ACCESS_DENIED；当时导出仅有公共只读权限。后来重新导出的真实生产设置含 `_icloud` Create / Read / Write；它不能满足普通用户只读要求，不能凭暂时上传成功判 B1 通过。

最终处理：

1. Development 创建专属 TimeHallPublisher 角色，权限仅三类发布记录。
2. 从三类 `_icloud` 授权移除 Create / Write，保留 Read；`_world` 仍只有 Read。
3. 部署前核对完整差异：只有新增角色、三条专属授权、三条普通用户授权收紧，无其他字段、索引、类型变更。
4. Console 显示 Changes Deployed；重新导出最终 production schema 与 development 一致。
5. 在两环境分别给已有两个白名单成员及发布工具身份绑定角色；逐条 Reload 后 Security Roles 1、TimeHallPublisher 勾选值为 1。没有其他成员。
6. 收紧权限后真实发布 seq 3 成功，applied=true、readBackConfirmed=true。

普通用户只读由实际部署后的授权矩阵确认；没有登录另一位普通用户在真机操作，因此不声称已完成普通用户真机试写。手机入口和真机操作属于后续阶段。

证据：`deployment-final-reviewed.diff`、`development-schema-final.ckdb`、`production-schema-final.ckdb`、`final-permission-check.json`、`publish-3-receipt.json`。

## 发布与回读

| 发布 | 行为 | 回读结果 |
| --- | --- | --- |
| seq 1 | 首次上传店家、系列、商品和三图 | 全部图文字节核对通过 |
| seq 2 | 移除验收商品，保存删除标记 | 商品不再出现，历史资源仍在 |
| seq 3 | 权限收紧后修改验收店家说明 | 新说明取回正确，删除标记仍在 |

最终 production rootIndexHash：`e4560464f1c9e1583a2d6fc35f75d039db048a96503cc4d890c3a8dc4c91d534`。development 仍为 seq 6。

主要证据：`image-readback-release-1.json`、`historical-retention-after-delete.json`、`historical-retention-final.json`、`final-pull-and-isolation-check.json`、`merge-check/result.json`。

Mac 原生界面最终取回：production / seq 3 / 店家 1 / 系列 1；合并预览补进 2、更新 0、本地独有保留 1137、按删除标记移除 0（当前用户草稿不含验收商品）。共享合并验证在隔离命令行程序中完成，不冒充原生持久化按钮验收。

## 修复与验证

纯本地图片首次发布误传不存在的 known-remote-media.json，已修正；同时忽略上一次环境遗留的远端清单。回归实际调用构建器，覆盖干净目录与无效旧清单两种输入，截断外部写入。

本轮验证：

- `selftest_ops_sync.py`：17 项通过。
- `selftest_cloudkit_read.py`：18 项通过。
- `selftest_shop_catalog.py`：全部通过。
- `selftest_signing.py`：6 项通过（前轮诊断）。
- 隔离 Swift 合并验收：构建及运行成功，实际空库与最终生产拉回作为输入，删除有效且保留独立本地修改。
- 前轮 Swift 修复验证：SharedCatalog 207 项、OpsCore 85 项及 Mac、iOS 通用模拟器构建通过；本轮未新增 Swift 产品代码，未重复 Xcode 构建。iOS 真机尚未运行。

隔离 Swift 命令（退出 0，日志 `merge-check/build-and-run.log`）：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift run --package-path 'output/阶段B/2026-10-09_正式验收/merge-check' Check '/Users/sangyu/develop/Pink_House/output/阶段B/2026-10-09_正式验收'
```

真实桥接入口（退出 0；使用既有 Keychain，未把凭证写进日志）：

```sh
env -u PINK_HOUSE_TIMEHALL_CREDENTIAL_FILE tools/time_hall/publication/.venv/bin/python tools/time_hall/publication/ops_publish_bridge.py --mode publish --request 'output/阶段B/2026-10-09_正式验收/publish-3-request.json'
env -u PINK_HOUSE_TIMEHALL_CREDENTIAL_FILE tools/time_hall/publication/.venv/bin/python tools/time_hall/publication/ops_publish_bridge.py --mode pull-catalog --request 'output/阶段B/2026-10-09_正式验收/pull-final-request.json'
env -u PINK_HOUSE_TIMEHALL_CREDENTIAL_FILE tools/time_hall/publication/.venv/bin/python tools/time_hall/publication/ops_publish_bridge.py --mode pull-catalog --request 'output/阶段B/2026-10-09_正式验收/development-final-request.json'
```

发布请求 dryRun=false、baselineAcknowledged=false，真实基线顺序 0→1→2→3，无强行覆盖。seq 3 验收请求最初误填 JSON 摘要，被冻结校验拒绝（未写线上）；改为冻结整包摘要后通过，保留拒绝日志。

## 隐私与交接

本次生成的本地计划、操作清单和验收文档不保存个人姓名，不留含姓名备份。此前已返回的聊天消息或工具内容不能通过文件编辑撤回，不声称已删去历史对话。

手机原图回补入口已完成；本轮没有取得原手机整包，也没有完成原手机补图操作。计划历史中的 174 张缺图判据已单独更正，不把该数量当作当前发布包缺图数量。下一步为 iOS 阶段，先试用区检查，再按阶段 C/D 的条件进入正式区。
