# 穿搭手帐恢复与 iCloud 及时恢复 · 验收清单（harness）

> 配套执行计划：`docs/OOTD_JOURNAL_RESTORE_REFACTOR_EXEC_PLAN.md`。本清单按小版本滚动执行，每个小版本写入 `temp/_ootd_restore_harness/accept/<ts>/RESULT.md`。

## 0. 验收前准备

```bash
PROJ="/Users/muniao/Library/Mobile Documents/com~apple~CloudDocs/游戏/github/Pink_House"
ACCEPT_DIR="$PROJ/temp/_ootd_restore_harness/accept/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$ACCEPT_DIR"
cd "$PROJ"
```

记录：

```bash
git status --short --branch > "$ACCEPT_DIR/git-status.txt"
git diff --check > "$ACCEPT_DIR/diff-check.txt"
```

iOS 默认不由 Codex 主动跑 `xcodebuild`。如用户要求跑构建/单测，再把命令和结果贴入 `RESULT.md`。

## 1. 静态验收

- [ ] 业务代码改动只落在本阶段声明的目标文件，未误动 `/Users/muniao/Downloads/Pink_House`。
- [ ] 新增备份 DTO 字段均为 optional，旧 JSON fixture 不因 missing key 解码失败。
- [ ] `BackupService` 恢复顺序清晰：先有 BookGroup 映射，再恢复 `OOTDSnapshotDTO.bookID` 指向的 Outfit。
- [ ] 恢复结束有 final `context.save()` / pending changes 处理 / 完成通知。
- [ ] `BookShelfView` 不再在多手帐恢复场景中把无证据孤儿页直接迁到默认手帐。
- [ ] `CloudSyncManager` 对 OOTD 图片、theme/wealth/widget 文件使用正确目标目录。
- [ ] `RecycleBinView` 中手帐恢复路径有保存与 `lastModified` 更新。

## 2. 数据恢复验收矩阵

### A. 平面手帐空库恢复

夹具：
- `BookGroup A`：2 页。
- `BookGroup B`：1 页。
- `默认手帐`：1 页魔法贴纸。

期望：
- [ ] 恢复后 3 个 BookGroup 都存在。
- [ ] A 的 2 页仍在 A，B 的 1 页仍在 B。
- [ ] 默认手帐只包含魔法贴纸页，不吞并 A/B 的书页。
- [ ] `Outfit` 孤儿数为 0。
- [ ] 重复恢复同一 manifest 不新增重复 BookGroup/Outfit/OutfitItem。

### B. 平面手帐非空库合并恢复

夹具：目标库已有同 ID 手帐/书页，另有本地新增书页。

期望：
- [ ] 同 ID 书页按备份更新内容，不重复。
- [ ] 本地已删除的书页不会被备份复活，除非恢复动作明确是回收站恢复。
- [ ] 本地新增且无冲突的书页不被删。

### C. 旧备份兼容

夹具：旧 `OOTDSnapshotDTO` 缺 `mannequinAssetID`、缺新增可选字段；legacy `OutfitDTO` 不带 book 信息。

期望：
- [ ] 解码成功。
- [ ] 可确定 bookID 的新格式页回原书。
- [ ] 无法确定归属的旧格式页进入安全兜底报告，不批量误入默认手帐。

### D. 文件恢复

期望：
- [ ] snapshot/background/cutout 文件最终位于 `ImageManager.imagesDirectory`。
- [ ] theme/wealth 文件仍在 Documents。
- [ ] widget 背景仍在 App Group。
- [ ] 缺失图片时模型关系先恢复，图片可后续下载/重试，不阻塞书页归属。

### E. 云端恢复及时性

流程：使用 CloudKit 备份恢复入口恢复同一夹具。

期望：
- [ ] 恢复成功返回后书架立刻显示 BookGroup A/B/默认手帐。
- [ ] 进入 A/B 立即看到正确书页数量，不需要杀进程重启。
- [ ] 若图片 asset 未立刻下载，缩略图可显示加载/占位，但书页不会消失或跑到默认手帐。

### F. SwiftData iCloud 本地迁移

流程：本地库已有 A/B 手帐和书页，开启 SwiftData iCloud 同步迁移。

期望：
- [ ] 云同步容器中 `Outfit.book` 保持原归属。
- [ ] `OutfitItem.outfit` 与 `OutfitItem.cutout` 保持引用。
- [ ] `SpaceOutfit.book` 保持原归属，SceneObjectData 仍按 `spaceOutfitID` 可查。

### G. 回收站恢复

期望：
- [ ] 恢复单个 Outfit 后立即从回收站消失并回到原书。
- [ ] 恢复 BookGroup 后该书及其页立即可见。
- [ ] 恢复状态保存到 SwiftData，`lastModified` 更新，DeleteTracker 对应记录移除。

## 3. UI 验收

- [ ] 书架页恢复完成后自动刷新，不需要手动切 tab。
- [ ] BookDetail 页面恢复完成后 `loadPages()` 能显示正确 pages。
- [ ] 默认手帐只负责魔法贴纸专用页，不出现其它手帐恢复页。
- [ ] 批量新增/复制/移动页面后关系仍稳定，备份再恢复不串书。

## 4. RESULT.md 模板

```md
# OOTD Restore Harness RESULT

- 日期：
- 小版本：M?
- commit：
- 是否运行 xcodebuild：否 / 是（命令：...）

## 静态检查
- git diff --check：PASS/FAIL
- DTO optional 检查：PASS/FAIL

## 数据矩阵
| 项 | 结果 | 证据 |
|---|---|---|
| A 空库恢复 | PASS/FAIL | ... |
| B 非空库合并 | PASS/FAIL | ... |
| C 旧备份兼容 | PASS/FAIL | ... |
| D 文件恢复 | PASS/FAIL | ... |
| E 云端及时恢复 | PASS/FAIL | ... |
| F SwiftData iCloud 迁移 | PASS/FAIL | ... |
| G 回收站恢复 | PASS/FAIL | ... |

## 结论
- 可进入下一小版本：是/否
- 阻塞项：
```
