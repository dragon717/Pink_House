> 后续更新：原 401 已定位并修复；当前阻塞为生产写权限，见 [最新实际执行记录](CLOUDKIT_STAGE_B_EXECUTION_2026-10-09.md)。下文保留诊断当时的证据。

# 阶段 B 未通过原因复核（2026-10-09）

## 结论

B1–B10 不是十项全部运行失败。已确认的远端失败是 B2 生产认证失败，并阻断 B4 可信基线读取；B1 尚无实际 schema 核验证据，后续真实发布、删除、拉回及隔离验证尚未执行。

没有写入生产库，没有进入阶段 C。

## 本次只读检测

1. 文件生产凭证重读发布头：HTTP 401，Apple 原始响应 `AUTHENTICATION_FAILED` / `Authentication failed`，桥接器退出码 4。Apple 请求 UUID：`a56610a3-9245-40c9-a6d4-bab81f704afe`。
2. development 独立 Keychain 凭证读取成功：发布号 6，根摘要 `31cd2af94f2fb5ced718d8a46bf5da626a8f337b060c0b5e9db38eb0d8a2c3a3`。
3. 本机凭证仅在进程内比较，没有输出私钥或完整 Key ID：
   - 生产文件与生产 Keychain 的 Key ID、公钥完全相同。它们是同一份凭证的两种存储来源，不是两把独立钥匙。
   - production 与 development 的 Key ID 不同，但使用同一对公私钥。复用公私钥本身不能证明错误；需核对 production Key ID 对应的注册公钥。
   - 生产容器值正确，私钥为 EC P-256（secp256r1）。
   - 使用生产私钥签名生产路径后，本机对应公钥验签通过。
4. `selftest_signing.py`：6 项通过、0 失败。
5. `xcrun cktool get-teams`：退出码 64，缺少 management token。当前仍不能通过该工具取得实际生产 schema。

先前电脑控制返回权限未授予；本次未重试电脑控制，也未取得 Console 注册状态。没有证据确认 schema 未部署，只能确认尚未核验。

## 为什么仍需 Console 核对

程序将所有 HTTP 401 翻译成“s2s key 没有 production 环境的访问权”。这是工具的通用诊断文案，不是 Apple 返回的具体原因。不能仅凭它断言密钥注册在错误环境。

现有证据将排查重点缩小到生产 Key ID 的注册状态及对应关系：是否属于目标容器/环境、是否撤销、注册公钥是否与本机私钥对应。具体是哪一项，仍需 Console 证据。development 成功与离线验签通过降低了共享网络/签名实现故障的可能性，但不能替代生产注册核验。

Apple 官方说明：本机生成公私钥，将公钥注册到 CloudKit Dashboard，再把生成的 Key ID 用于签名请求；见 [CloudKit Web Services：Server-to-Server Key 与请求认证](https://developer.apple.com/library/archive/documentation/DataManagement/Conceptual/CloudKitWebServicesReference/SettingUpWebServices.html)。

## B1–B10 状态

| 步骤 | 当前状态 | 未通过原因 |
| --- | --- | --- |
| B1 | 未核验 | 没有实际 production schema、索引与角色快照 |
| B2 | 失败 | 真实生产只读请求返回 401，注册对应关系待核对 |
| B3 | 未实测 | 尚无 Mac App 切环境并清运行态的实操证据 |
| B4 | 受阻 | 认证失败，无法取得可信生产基线；失败不能视为空库 |
| B5 | 离线准备通过 | 验收资料与 3 张图片可构建；尚未合入真实生产基线 |
| B6 | 未执行完整验收 | 没有基线上的真实发布冻结请求与生产门禁记录 |
| B7 | 未执行 | 尚未满足 schema、认证和基线前置条件 |
| B8 | 未执行 | 需先完成 B7，才能验证墓碑与历史资源保留 |
| B9 | 未执行 | 没有本轮生产发布可供拉回验收 |
| B10 | 未执行 | 本轮专用 ID 尚未发布到生产，无法完成有意义的隔离自证 |

## 复测命令

```sh
PINK_HOUSE_TIMEHALL_CREDENTIAL_FILE=/Users/sangyu/Downloads/cloudkit.production.json \
  tools/time_hall/publication/.venv/bin/python \
  tools/time_hall/publication/ops_publish_bridge.py --mode baseline \
  --request 'output/阶段B/2026-10-08_生产验收/production-readonly-request.json'
env -u PINK_HOUSE_TIMEHALL_CREDENTIAL_FILE \
  tools/time_hall/publication/.venv/bin/python \
  tools/time_hall/publication/ops_publish_bridge.py --mode baseline \
  --request 'output/阶段B/2026-10-08_生产验收/development-readonly-request.json'
tools/time_hall/publication/.venv/bin/python tools/time_hall/publication/selftest_signing.py
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun cktool get-teams
```

本次只读检查和文档更新，未修改凭证及运行代码，未另跑 Xcode 构建。

下一步先核对 production Key ID 与公钥注册，并取得 schema 快照；认证通过后读取真实生产基线，再继续 B3–B10。历史推进证据见 [2026-10-08 记录](CLOUDKIT_STAGE_B_PROGRESS_2026-10-08.md)。
