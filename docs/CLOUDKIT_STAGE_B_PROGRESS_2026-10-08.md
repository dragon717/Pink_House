# 阶段 B：Mac / production 推进记录（2026-10-08）

2026-10-09 复测仍为生产 401、开发读取成功。新增凭证比较发现两种生产存储来源是同一份凭证；401 的确切注册原因尚未确认，见 [未通过原因复核](CLOUDKIT_STAGE_B_DIAGNOSIS_2026-10-09.md)。

## 当前结果

承接四阶段上线计划。阶段 A 的历史验收记录已核对，R5 修复已落地；本轮开始 production 验收，但尚未通过门控 2。

真实只读请求使用 `/Users/sangyu/Downloads/cloudkit.production.json`，明确路由到 `iCloud.bugod2.ItemManager / production / public`，返回 `HTTP 401 / AUTHENTICATION_FAILED`，桥接器结果 `refused / exitCode 4`。这证明当前凭证未通过生产认证，不能推断生产库是空库，也没有取得可信生产基线。

随后检查 Keychain 的 `keyID.production`、`privateKey.production`、`containerID.production` 三项均存在，并取消文件凭证覆盖、用 Keychain 通道再次只读请求，结果同样为 401。没有把私钥打印或导出到证据文件；没有回退使用 development key 打 production。

development 的独立 Keychain 对照读取成功：`releaseSeq 6`，`rootIndexHash 31cd2af94f2fb5ced718d8a46bf5da626a8f337b060c0b5e9db38eb0d8a2c3a3`。这为读取/签名链路提供正面对照，不代表 B10 已完成（专用资料尚未发布到 production）。

电脑控制返回 `Computer Use permissions are not granted`，无法查看 CloudKit Console。`xcrun cktool get-teams` 返回 `No management token found`，因此也没有导出、核对或部署实际 production schema。

没有执行任何 production 写入，没有修改用户工作草稿或凭证文件，没有进入阶段 C。

## B1–B10 实际状态

| 步骤 | 状态 | 本轮证据与剩余条件 |
| --- | --- | --- |
| B1 schema 与索引冻结 | 待核验 | 已写 3 个类型的字段/权限核对清单；实际 production schema、现有索引与角色未取得 |
| B2 production 凭证 | 受阻 | JSON 声明 production、容器正确、EC P-256 私钥格式有效；真实生产请求仍为 401 |
| B3 切环境与清运行态 | 待实操 | 已审查环境切换清理代码；电脑控制未授权，没有在 App 中实测切换 |
| B4 生产基线与拉回 | 受阻 | 只读 baseline 认证失败；未执行 pull-catalog，不把失败解释成空库 |
| B5 三级文字与配图 | 已准备离线输入 | 独立验收资料为 1 店家 / 1 系列 / 1 商品 / 3 张 PNG；还需合入可信生产基线 |
| B6 门禁与冻结请求 | 待基线 | 输入已离线构建/校验；没有生成真实发布冻结请求，也没有绕过 R07 |
| B7 真实生产发布与回读 | 未执行 | B1–B4 条件满足后按实际线上发布号递增；不能假定第一版一定是 seq 1 |
| B8 删除与不可变历史验证 | 未执行 | 只对本轮专用验收商品做墓碑发布；需回读墓碑并确认旧 pack/media 仍在 |
| B9 再拉回生产 | 未执行 | 需核对路由、发布号、根摘要与图片字节 |
| B10 development 隔离自证 | 未执行 | 需 development 独立凭证真实回读，确认本轮生产专用 ID 不存在 |

## 已完成的准备与修复

产物目录：`output/阶段B/2026-10-08_生产验收/`。

- `production-readonly-request.json`：只读探测请求，`dryRun=true`，不是待发布请求。
- `production-baseline-before.ndjson`：真实生产认证失败日志，带 Apple 返回的请求 UUID。
- `production-keychain-baseline.ndjson`：独立 Keychain 通道同样认证失败的日志。
- `development-readonly-request.json`、`development-baseline-before.ndjson`：development 正面对照请求及 seq 6 的真实回读。
- `credential-check.json`：凭证环境、容器、公钥摘要与认证结果；没有私钥内容。
- `production-public-key.pem`：从已有凭证派生的公钥，可用于 Console 核对注册；没有新建/更换密钥。
- `schema-requirements.json`：期望字段/权限；明确标注尚无实际 schema 快照。发布通道按 recordName lookup，不要求新增 Query 索引；已有索引和其他记录类型须保留。
- `fixture/`：专用验收目录、3 张程序生成的测试图片、USTAR 交接包与摘要清单。ID 前缀为 `stage-b-20261008`，商品注明“非售卖”。未使用用户缺失的 174 张图，也未覆盖其草稿。
- `offline-validation/`、`offline-build.log`、`offline-validate.log`：离线产物和验证记录。它们只证明输入可构建，不是 production 发布回执。

发现并修复了空库首次发布的 R07 判定：`pull-catalog` 观察到无发布头时保存 `baseReleaseSeq=0`、无根摘要；桥接器原先会把这份已核对空基线当成过期，强迫走 `baselineAcknowledged` 例外。现在只有已记录 0、无摘要且实时读取同样确认无发布头时放行。未核对、此前有发布头、摘要不符、另一个发布者已建头、认证读取失败仍阻断。

## 命令与验证结果

真实只读探测：

```sh
PINK_HOUSE_TIMEHALL_CREDENTIAL_FILE=/Users/sangyu/Downloads/cloudkit.production.json \
  tools/time_hall/publication/.venv/bin/python \
  tools/time_hall/publication/ops_publish_bridge.py --mode baseline \
  --request 'output/阶段B/2026-10-08_生产验收/production-readonly-request.json'
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun cktool get-teams
env -u PINK_HOUSE_TIMEHALL_CREDENTIAL_FILE \
  tools/time_hall/publication/.venv/bin/python \
  tools/time_hall/publication/ops_publish_bridge.py --mode baseline \
  --request 'output/阶段B/2026-10-08_生产验收/production-readonly-request.json'
env -u PINK_HOUSE_TIMEHALL_CREDENTIAL_FILE \
  tools/time_hall/publication/.venv/bin/python \
  tools/time_hall/publication/ops_publish_bridge.py --mode baseline \
  --request 'output/阶段B/2026-10-08_生产验收/development-readonly-request.json'
```

production 的两条 baseline 命令桥接器均退出码 4、401；development 对照退出码 0、真实读到 seq 6；cktool 缺少管理 token。均未写远端。

离线构建与校验：

```sh
python3 tools/time_hall/publication/build_release.py \
  --input 'output/阶段B/2026-10-08_生产验收/fixture' \
  --shop-catalog-archive 'output/阶段B/2026-10-08_生产验收/fixture/fixture.tar' \
  --output 'output/阶段B/2026-10-08_生产验收/offline-validation' \
  --release-seq 1 --previous-release-seq 0
python3 tools/time_hall/publication/validate_release.py \
  --release 'output/阶段B/2026-10-08_生产验收/offline-validation'
python3 tools/time_hall/publication/selftest_ops_sync.py
python3 tools/time_hall/publication/selftest_cloudkit_read.py
python3 tools/time_hall/publication/selftest_shop_catalog.py
git diff --check
```

构建与媒体校验通过：1 分片、1 pack、3 media，目录覆盖标记 `partial`。同步故障回归 16 项通过（新增 4 项首次发布/认证失败保护）；读写闸门 18 项通过；商店目录媒体/归档自测通过；差异空白检查通过。本轮没有改 Swift，因此未另跑 Xcode 构建或模拟器。

## 恢复执行所需输入

需要能核对 CloudKit Console（开启电脑控制并登录），或提供实际 schema 导出及可用管理凭证的本机路径；并修复 production s2s 注册/凭证，使同一只读 baseline 请求通过认证。

权限与 schema 取得后，先审查实际字段、索引及角色再部署；先读 production 真实基线并保留已有内容，再加入专用验收资料、演练、真实发布、回读、墓碑删除和隔离验证。基线不采用旧 dev 版本，也不使用 `baselineAcknowledged` 绕过。
