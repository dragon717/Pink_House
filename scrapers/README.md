# Pink House · 商品素材采集器（淘宝 / 天猫 / 闲鱼）

为「时光馆」模块提供商品素材（标题、价格、描述、**图片静态文件**）的结构化采集工具。

## 方案选型（2026-09 调研）

| 方案 | 代表开源项目 | 结论 |
|---|---|---|
| Playwright 浏览器自动化 + 登录态注入 | MarketSpider、pachong-cursor | ✅ 本工具采用，对淘宝改版适应性最好 |
| 淘宝 H5/mtop 接口直接请求 | sku_spider（京东/拼多多路线） | ❌ 需要复杂签名（sign/h5tk），维护成本高 |
| Android 真机 uiautomator2 | floatin/xianyu_spider | 备选，闲鱼被风控时再启用 |

关键事实：商品图片 CDN（`img.alicdn.com` / `img.goofish.com`）**无需登录即可直接下载**，
已实测验证（见下「验证状态」），因此图片静态化是本工具最稳的能力。

## 目录结构

```text
scrapers/
├── run_collect.py          # 采集入口 CLI
├── login_helper.py         # 一次性扫码登录，生成登录态文件
├── config.example.json     # 配置模板（复制为 config.json）
├── requirements.txt
├── common/                 # HTTP 客户端 / 图片下载器 / 结构化存储
├── collectors/             # taobao.py（含天猫）、xianyu.py
├── data/                   # 输出：结构化 JSON
│   ├── index.json          # 所有采集 run 的索引
│   └── runs/<时间戳>_<平台>_<关键词>/items.json
├── assets/images/          # 输出：商品图片静态文件
│   └── <平台>/<关键词>/<商品ID>/001.jpg ...
└── cookies/                # 登录态文件（git 忽略，勿提交）
```

`items.json` 字段：`item_id / title / price / description / detail_url / images[]`，
`images[]` 是相对 `scrapers/assets/images/` 的静态文件路径，时光馆可直接读取。

**链接规范（2026-09-15 定）**：淘宝/天猫商品的 `detail_url` 统一为
`https://item.taobao.com/item.htm?id=<商品ID>`（纯净地址，无 skuId/spm 等跟踪参数），
天猫商品同样适用；搜索结果原始链接降级存入 `source_url` 留档。
闲鱼商品仍用 `https://www.goofish.com/item?id=<商品ID>`。

## 快速开始

```bash
# 1. 安装依赖（用受管 Python）
/Users/sangyu/.workbuddy/binaries/python/envs/default/bin/pip install -r scrapers/requirements.txt
/Users/sangyu/.workbuddy/binaries/python/envs/default/bin/python -m playwright install chromium

# 2. 生成登录态（弹浏览器，人工扫码，登录后回终端按回车）
cd scrapers
/Users/sangyu/.workbuddy/binaries/python/envs/default/bin/python login_helper.py taobao
/Users/sangyu/.workbuddy/binaries/python/envs/default/bin/python login_helper.py xianyu
cp config.example.json config.json   # 路径默认即指向生成的文件

# 3. 采集
/Users/sangyu/.workbuddy/binaries/python/envs/default/bin/python run_collect.py \
    -p taobao -p xianyu -k "JK制服 冬季" --max-items 20
```

遇到滑块验证码时加 `--no-headless` 显示浏览器手动过一次。

已有 `items.json` 但图片没下全时，可单独补图：

```bash
python run_collect.py --only-images-from data/runs/20260915_xxxx/items.json
```

## 验证状态（2026-09-15）

- ✅ 模块语法检查通过、CLI 可运行
- ✅ 图片下载链路实测：alicdn 真实商品图（31 KB JPEG）成功落盘、按 md5 去重
- ⚠️ 淘宝/天猫/闲鱼页面抓取依赖登录态与当前页面结构，首次实跑可能需按注释
  调整 `collectors/*_extract_*` 中的选择器（平台改版属常态）

## 合规约束（务必遵守）

- 仅用于 **Pink House 个人项目的素材调研**，不商用、不转售数据
- 使用本人自己的账号登录态，不爬取个人隐私信息
- 内置随机限速（每请求 0.8–2s、每商品 2–5s），请勿调大并发或移除限速
- 尊重平台 robots 与服务条款；图片版权归原商家所有，时光馆内仅作个人参考展示
