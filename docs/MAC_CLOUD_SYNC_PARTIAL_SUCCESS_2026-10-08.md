# Mac 云端同步：三步进度与部分成功（2026-10-08）

本次承接 [云端同步根因修复](MAC_CLOUD_SYNC_ROOT_FIX_2026-10-07.md)，工作区为 `/Users/sangyu/develop/Pink_House`。

同日后续已核对旧交接包，并增加保留当前编辑的补图入口，详见 [174 张缺图交接恢复](MAC_MISSING_IMAGES_REPAIR_2026-10-08.md)。下文验证记录保留初次三步同步实现时的状态。

## 附件能证明什么

用户提供的 `20261008-001710-baseline-101F5FA7.log` 记录的是 `baseline` 模式：目标 Development，读到 `releaseSeq 5`，退出码 0。它证明读取发布头成功，不能证明商店目录、图片下载完成，也没有上传和合并保存记录。因此不能根据它把现场状态说成「第一步完整下载已经成功」或「上传网络失败」。

`缺图清单-174.txt` 列出 174 个不同的本机 `img-*.jpg` 文件及引用位置：147 个涉及尺码表原图、25 个涉及系列封面/价格表原图、2 个涉及店家 logo。显式本地引用没有对应字节，会在生成发布包之前被校验拦下。清单证明本机缺文件，不证明云端没有图片；也不能用它判断上传请求是否已经发出。

旧一键入口先读发布号，再导出上传，缺图会阻断后续动作。它没有先下载目录，也把读取发布头的成功与发布失败合成一个「更新失败」提示。这同时造成行为与状态反馈两方面的问题。

## 新流程

工具栏与系列发布共用 `OpsSyncWorkflow`，分别结算三步：

| 步骤 | 完成条件 | 出问题时的行为 |
| --- | --- | --- |
| 1. 下载平台内容 | 拉回可信目录，补齐它引用的远端媒体字节 | 目录失败时保留当前草稿并停止上传；图片中断时接收成功部分、列出缺失/坏图/未完成项，并继续合并可信目录 |
| 2. 上传本地变更 | 预处理合并后校验通过，真实上传并回读确认发布头 | 本机缺图、目录结构问题或双方修改同字段时显示「待修复，尚未发送发布请求」；桥接器失败显示该步骤的具体原因与独立日志 |
| 3. 合并落盘确认 | 下载内容与本地编辑已安全合并，工作副本落盘成功 | 即使第二步受阻或上传失败也执行；保存失败单独标出，不能显示整体成功 |

上传必须包含远端最新的内容，因此内部会在第二步发出请求之前合成并保存安全工作副本；第三步是最终落盘确认。界面按用户要求展示下载、上传、合并确认三步，不把上传前的合并伪装成最后才做。

同 ID 条目按共同基线逐字段合并；本地独有条目保留，明确的删除标记仍生效。自动流程遇到同字段冲突会暂保留本地值并阻止上传，同时保留旧共同基线，确保下次仍能看见争议。运营在设置的合并预览中确认来源后才推进基线。

只有三步都是「完成」才显示「同步完成」。例如本机缺图但平台目录能正常下载时，结果为：下载完成、上传待修复、合并保存完成，整体显示「同步部分完成」。图片部分下载时也不会把第一步标成全部完成。

## 问题定位与后续操作

- 主窗口显示三个独立进度条、状态和说明；失败步骤不会抹掉已完成步骤。
- 「查看问题与日志」列出缺失文件、所属商品/系列/尺码表/店家、冲突字段和每一步的日志入口。
- 「导出问题清单」保存 UTF-8 文本，包含三步结论、归属、处理说明和日志路径，方便交给运营/运维。
- 设置中保留最近一次同步的分步结果，关闭主窗口提示后仍能查阅。
- 本机缺图需要从原资料补回；确定不再使用的图片可在对应资料中明确清除引用。代码不会自动清空引用或伪造图片来绕过校验。
- 同步结果按草稿保存到工作区 `sync-status/<draftID>.json`。每个步骤开始和结束都记录状态；重启后保留已完成步骤，对中断步骤明确标出结果未完成。上传阶段中断会要求先查询结果，不能把结果不明当成确定没写入。
- 下载/合并成功而上传受阻，不会自动删掉系列待发布任务。修复资料后再次运行「云端更新」。

## 验证

环境：`/Applications/Xcode.app`，Xcode 27.0（27A266a）。

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test \
  --package-path Packages/SharedCatalog --scratch-path /tmp/pink-sync-shared --disable-sandbox
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test \
  --package-path Packages/PinkHouseOps --scratch-path /tmp/pink-sync-ops --disable-sandbox
python3 tools/time_hall/publication/selftest_ops_sync.py
python3 tools/time_hall/publication/selftest_cloudkit_read.py
python3 tools/time_hall/publication/selftest_shop_catalog.py
python3 tools/ops_ui/check_markdown_callsites.py
git diff --check
```

- SharedCatalog：205 项通过，含 10 项三方合并测试。
- PinkHouseOpsCore：79 项通过，含 7 项三步流程回归：上传失败仍保存、缺图只阻止上传、没有可信目录不上传、部分下载不抹掉上传回执、三步全完成才能成功、落盘失败、上传中断后的状态恢复。
- Python 同步离线回归：12 项通过；CloudKit 读写闸门：18 项通过；商店目录媒体回归通过。
- Markdown 渲染门禁：31 文件，0 违规；差异空白检查通过。

Mac 构建命令：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project ItemManager.xcodeproj -target PinkHouseOps -configuration Debug \
  -sdk macosx -jobs 5 \
  SYMROOT=/Users/sangyu/develop/Pink_House/build/sync-rootfix-products \
  OBJROOT=/Users/sangyu/develop/Pink_House/build/sync-rootfix-objects build
```

构建通过。产物为 `build/sync-rootfix-products/Debug/PinkHouseOps.app`，日志为 `/tmp/pink-sync-mac-build.log`。已有的架构、C++ 条件编译标记和 AppIntents 元数据警告不影响此次构建结果。

使用实际 `OpsSyncProgressView` 与包编译产物进行独立 AppKit 离屏渲染，检查部分完成的问题列表和全部完成状态。预览使用示例数据，未加载用户的 SwiftData 工作库。

验证边界：已读取用户明确提供的单个日志文件和缺图清单；未运行用户工作库的第二个 App 实例，未修改现场草稿，也未执行真实 CloudKit 上传。因此构建和离线测试通过不能作为本次现场下载、上传成功的证据。174 个缺失的原始本机文件仍需由资料来源补齐或由运营明确调整引用。
