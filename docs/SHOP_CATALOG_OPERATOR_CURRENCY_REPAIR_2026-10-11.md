# 运营已上传商品币种修复（2026-10-11）

## 用户确认与范围

用户明确要求：运营已上传的商品中，没有明确币种的都修改为人民币。该确认作为这批存量记录的币种来源依据；不是只修改录入默认值，也不进行金额换算。

- 实际读取 CloudKit `iCloud.bugod2.ItemManager` 两个公共环境。
- Development 第 20 版：278 件商品、371 条销售记录；333 条已为 CNY，8 条缺币种，30 条 UNKNOWN。
- 本次补填 26 件商品涉及的 38 条销售记录，以及 3 份价格修正快照：统一为 CNY。
- Production 第 6 版：没有商品与销售记录，没有待修复内容，未写生产环境。
- 商品 ID、销售记录 ID、价格、定金、尾款、尺码、图片引用、删除墓碑及其他内容全部保持原值。
- 有明确外币的记录原样保留；nil 价格修正继承明确日元来源时不改标人民币。
- 旧 JSON 的通用解码与外部迁移工具仍保留原始来源语义；本次是对已确认的运营公共库发布新版本，不对用户私有衣橱历史记录做金额迁移。

## 工具与发布方式

正式入口 `tools/time_hall/publication/repair_operator_currencies.py`：

1. 默认只读取线上，核对头、根清单和所有包的摘要，保存原版证据；输出修复产物及逐字段审计。
2. 只修改未明确币种的字段，保留其余数据；原旧包不可变，新包递增 partitionRevision，发布号严格 +1。
3. `--apply` 校验冻结产物全文件摘要、来源 seq/hash/changeTag、已有媒体可获取性，复用原 `publish_cloudkit.py` 的七步发布与条件更新。
4. 发布后回读根清单与全部数据包，与冻结字节逐一比对；没有图片上传或删除。
5. 同一输入再次执行没有任何币种变化，不额外发布；输出目录不能覆盖，以保留证据。

发布读取器补齐返回原 schemaVersion、minimumReaderVersion、previousReleaseSeq，修复产物沿用原兼容要求，不猜测最低客户端版本。后续可从较大的 `publish_adapters.py` 提取独立发布头解析器，本次只增加这些读取字段。

```sh
# 离线回归
 tools/time_hall/publication/.venv/bin/python tools/time_hall/publication/selftest_operator_currencies.py
 tools/time_hall/publication/.venv/bin/python tools/time_hall/publication/selftest_cloudkit_read.py

# 准备、校验并保留冻结证据（不写云端）
env -u PINK_HOUSE_TIMEHALL_CREDENTIAL_FILE tools/time_hall/publication/.venv/bin/python \
  tools/time_hall/publication/repair_operator_currencies.py \
  --environment development --output 'output/币种修复/2026-10-11/development-repair-final'

# 用户已授权本次存量修复；发布已检查的冻结产物
env -u PINK_HOUSE_TIMEHALL_CREDENTIAL_FILE tools/time_hall/publication/.venv/bin/python \
  tools/time_hall/publication/repair_operator_currencies.py \
  --environment development --output 'output/币种修复/2026-10-11/development-repair-final' --apply

# 独立普通读者回读
env -u PINK_HOUSE_TIMEHALL_CREDENTIAL_FILE tools/time_hall/publication/.venv/bin/python \
  tools/time_hall/publication/verify_publication.py --adapter cloudkit --environment development
```

## 验证与证据

- 离线修复与独立读者接线回归：10 项通过；原 CloudKit 只读/写入闸门回归：18 项通过；出网回退回归：16 项通过。
- 独立差异检查：把币种字段还原后，完整 JSON 与修复前逐字段相等；实体数量相等。
- 真实发布：Development seq 20 → 21，发布与条件更新成功；旧数据包仍保留。
- rootIndexHash：`00924ce7e8a832ec5981bfd1c565436b59822d3ffa5ae70f0b592c729e2db1b0`。
- 452 个既有云端媒体引用已确认可获取；未新增媒体。
- 独立回读：Development seq 21 的完整目录与冻结修复逐字段相等，371 条销售记录全部为 CNY，3 份价格修正全部为 CNY；未明确币种记录为 0。
- 普通读者验证器回读通过：发布头、根清单、1 个分片 / 1583 个实体自洽。
- Production 再次读取仍为 seq 6，与修复前目录及根清单摘要相同。

证据目录 `output/币种修复/2026-10-11/`：before/after 目录、冻结 audit.json、scope-check.json、publish-receipt.json、verified.json。日志 `/private/tmp/pink-house-currency-apply-20261011.log`。第一份准备产物因读取器未返回协议字段失败，未写云端；保留其目录作为诊断，最终使用 development-repair-final。

验证边界：服务端真实数据及独立读者路径已验证；未手动点击手机刷新、未覆盖本机尚未发布的运营草稿，也未迁移用户私有衣橱旧金额。

手机读取到第 21 版后会使用明确人民币记录；当前页面可点击刷新触发同步。

独立验证器首次使用裸 urlopen，遇到坏边缘地址的 TLS EOF；已将请求与资产下载接入发布器共用 open_https 回退，加入离线接线断言，真实再次回读通过。日志 `/private/tmp/pink-house-currency-verify-publication-final-20261011.log`。
