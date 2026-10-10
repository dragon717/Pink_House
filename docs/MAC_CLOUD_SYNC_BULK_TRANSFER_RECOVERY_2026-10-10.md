# Mac 云端同步：大批媒体超时与恢复

## 证据与根因

用户提供的 `云端同步问题-2.txt` 记录 Development 的目录下载成功，图片下载与上传
分别在 900 秒被终止。本次通过文本编辑读取原始日志，未更改原始日志或业务草稿：

- `20261010-142708-fetch-media-56795FAD.log`：媒体下载被终止，没有最终媒体结果。
- `20261010-144209-publish-047750A2.log`：本次构建 442 张图片、247002337 字节，
  构建完成后长期没有后续阶段输出。

实际代码存在叠加的问题：

1. 发布端上传前、上传后的回读各逐张 lookup；下载端也逐张 lookup。
2. 图片传输串行，每次连接再次等待失效的本机代理。原连接超时随文件请求取 60/300 秒，
   并逐地址重复，连接建立与文件传输没有分开预算。
3. Mac 把 900 秒作为整个任务总时长，即使任务持续处理图片也会终止。
4. 子发布器输出被 Python 缓冲，上传数量没有转成桥接进度。原始阶段事件的 message
   也在 App 日志显示时丢失，使诊断只有重复的“下载远端图片”。
5. 下载清单只在函数结尾生成；强制终止后已下载的字节未被收进 staging。
6. 只终止桥接器不能保证发布子进程同步退出。只读下载超时也错误套用发布结果待确认文案。

## 修复后的行为

- 元数据分块批量读取（200 条一组）；442 个摘要只需三次 lookup。
- 不可变媒体最多四路并发；数据包、回读、条件更新发布头仍按既定顺序执行。
- 已成功的本机代理直连回退只在当前进程记住五分钟，目标、证书验证和环境保持一致。
  连接建立预算 20 秒、每地址最多 5 秒；建连后恢复请求的读写超时。
  系统 Python 的 `socket.timeout` 也正确识别为可回退的连接错误。
- 900 秒改为无进展超时。只有新阶段状态与严格增加的数量延续定时器；重复日志不延续。
- 下载清单逐张原子替换；中断后恢复部分结果。对旧版本的无清单工作目录，先核对原请求环境，
  再由 staging 接收逻辑逐文件验证内容摘要，下次只补缺。
- 子脚本关闭输出缓冲、转发上传数量；桥接器收到终止信号时终止并等待子进程组。
- 只读中断不再提示“可能已经切换发布头”。真实发布中断仍需查询结果。
- 上传重试成功后清掉上一轮错误，避免成功上传仍被旧异常判为失败。
- 日志头部指向本次日志文件，阶段计数明细保留。

## 验证

以下命令在 `/Users/sangyu/develop/Pink_House` 执行，均通过：

```sh
python3 tools/time_hall/publication/selftest_bulk_transfers.py
python3 tools/time_hall/publication/selftest_loopback_proxy.py
python3 tools/time_hall/publication/selftest_network_failover.py
python3 tools/time_hall/publication/selftest_ops_sync.py
python3 tools/time_hall/publication/selftest_cloudkit_read.py
swift test --package-path Packages/PinkHouseOps
xcodebuild -project ItemManager.xcodeproj -scheme PinkHouseOps \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/pink-house-ops-cascade-build build-for-testing
```

Python：9 + 12 + 16 + 17 + 18 项；Swift 服务层：90 项，合计 162 项通过。
验证包含批量请求数量、四路并发、部分清单中断恢复、旧工作目录环境隔离、只读文案、
进度去重、实际子进程终止，以及媒体失败/回读缺失不能进入发布头更新的执行链。
Mac `build-for-testing` 通过；未运行 App 宿主 XCTest。

使用 `open_https` 连续两次请求 `https://api.apple-cloudkit.com` 的未认证根路径：
首次 5.18 秒，第二次 0.28 秒，均收到 HTTP 400，直连路由成功复用。
这是传输层探测，无凭证、无目录上传、无发布头修改。

本次没有替用户执行带凭证的完整图片同步或正式发布；247 MB 全量传输的实际耗时、
当前线上发布号与最终回执仍需在新构建的运营端确认。
