# 协议网站落地文档与 Review 计划（执行版）

> 适用范围：`sangsang.online` 协议与联系网站 + App 内协议入口改造  
> 当前状态：网站 HTTPS 已可用，App 侧入口代码已接入，待统一提测与上架同步。  
> 更新时间：2026-04-10

## 1. 目标与交付物

### 1.1 目标

1. 建立稳定可访问的线上协议中心，承载用户协议、隐私政策、会员协议、联系我们页面。
2. App 内形成统一入口，覆盖「我」首页快捷入口、系统页入口、IAP/VIP 关键触点。
3. 上架材料与应用内文案一致，降低审核风险与沟通成本。

### 1.2 交付物

1. 网站线上地址：
   - `https://sangsang.online/privacy/`
   - `https://sangsang.online/user-agreement/`
   - `https://sangsang.online/vip-agreement/`
   - `https://sangsang.online/contact/`
2. 网站源码目录（纳入仓库）：`ops/legal-site/`
3. 一键部署脚本：`scripts/deploy_legal_site.sh`
4. App 内入口与链接代码（已改）：
   - 我页快捷入口「联系我们」
   - 系统页「关于与协议」
   - IAP 协议按钮可点击
   - VIP 协议名称可点击

## 2. 线上信息基线（必须一致）

1. 协议来源：线上 URL（不走 App 内长文富文本）
2. 小红书文案：`@少女心愿（衣橱管家）`
3. 小红书号：`3621744284`
4. 邮箱：`huangsangmuniao@126.com`
5. 备案号：`沪ICP备2026008696号-1A`（仅展示）
6. 版权：`© 2026 桑桑桑 Inc.`

## 3. 运维落地方案

### 3.1 架构

1. Web Server：Nginx（TencentOS Server 3.3）
2. 内容类型：静态 HTML + CSS
3. 证书：Let's Encrypt（Certbot）自动续期

### 3.2 内容维护策略

1. 协议页面作为代码资产纳入仓库 `ops/legal-site/`
2. 修改协议文案时，通过 PR 审核
3. 审核通过后执行 `scripts/deploy_legal_site.sh` 一键发布

### 3.3 回滚策略

1. 脚本默认在服务器保留最新备份目录
2. 紧急回滚：将备份目录同步回 `/var/www/sangsang.online` 并 reload nginx
3. 回滚后必须复跑健康检查 URL

## 4. Review 计划（分阶段）

### 阶段 A：内容 Review（法务/产品）

1. 核对敏感点：
   - 是否出现“自动续费订阅”误导（VIP 为兑换型权益）
   - 退款、责任限制、未成年人条款是否完整
   - 联系方式与备案/版权是否一致
2. 输出：`v2` 协议文本定稿

### 阶段 B：技术 Review（研发）

1. App 链接一致性检查：
   - IAP、VIP、系统页、我页是否都跳 HTTPS 正确地址
2. 网站可用性检查：
   - 证书有效
   - 路由可访问
   - 重定向行为符合预期
3. 输出：可提测 build

### 阶段 C：QA Review（提测）

1. 执行本文件第 5 节「提测清单（10 条）」
2. 记录：通过/阻塞项/截图证据
3. 输出：测试结论 + 发布建议

### 阶段 D：发布 Review（上架）

1. App Store Connect 字段与应用内文案一致
2. Review Notes 中声明协议链接与 VIP 模式
3. 输出：提交审核版本

## 5. 提测清单（10 条）

1. `privacy` 页面 HTTPS 200，正文可读。
2. `user-agreement` 页面 HTTPS 200。
3. `vip-agreement` 页面 HTTPS 200。
4. `contact` 页面 HTTPS 200，邮箱链接可拉起邮件客户端。
5. App「我」页存在“联系我们”入口并可进入。
6. App「系统与更多」存在“关于与协议”入口并可进入。
7. IAP 页“用户服务协议 / 隐私政策”按钮打开正确 URL。
8. VIP 页“会员协议 / 使用协议”可点击；勾选门槛逻辑不回归。
9. “备案号 / 版权”在 App 展示正确：`沪ICP备2026008696号-1A`、`© 2026 桑桑桑 Inc.`。
10. 弱网/断网场景点击外链不崩溃，能返回并继续使用。

## 6. App Store Connect 同步点

1. Privacy Policy URL：`https://sangsang.online/privacy/`
2. Support URL：`https://sangsang.online/contact/`
3. Marketing URL：`https://sangsang.online/`
4. Copyright：`© 2026 桑桑桑 Inc.`
5. Review Contact Email：`huangsangmuniao@126.com`
6. Review Notes 需明确：
   - 协议页地址
   - VIP 为喵币兑换权益，非自动续费订阅

## 7. SSH 免复制工作流建议

### 方案 A（推荐）：SSH Host 别名 + 一键脚本

1. 在本机 `~/.ssh/config` 配置：

```sshconfig
Host sangsang-prod
  HostName 146.56.207.253
  User root
  IdentityFile ~/.ssh/id_rsa
  ServerAliveInterval 30
  ServerAliveCountMax 6
  ControlMaster auto
  ControlPath ~/.ssh/cm-%r@%h:%p
  ControlPersist 10m
```

2. 验证：

```bash
ssh sangsang-prod "hostname && date"
```

3. 发布：

```bash
./scripts/deploy_legal_site.sh
```

#### 更省事：直接用仓库脚本一键写 SSH 配置

```bash
./scripts/setup_sangsang_ssh.sh
ssh sangsang-prod "hostname && date"
./scripts/deploy_legal_site.sh
```

### 方案 B：远程执行单命令

```bash
ssh sangsang-prod "certbot renew --dry-run"
```

> 这样你就不需要每次手动复制长命令。

## 8. 变更记录

1. 2026-04-10：协议站点 HTTPS 上线；App 协议入口改造完成；新增一键部署方案。
