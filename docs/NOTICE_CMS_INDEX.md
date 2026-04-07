# 公告系统文档索引

> 更新时间：2026-04-07  
> 用途：汇总 Notice CMS 相关文档，作为产品、研发、测试和上线协同时的统一入口。

## 1. 总览文档

- [NOTICE_CMS_PRD_EXECUTION.md](/Users/muniao/Library/Mobile%20Documents/com~apple~CloudDocs/游戏/github/Pink_House/docs/NOTICE_CMS_PRD_EXECUTION.md)
  说明：公告系统可直接执行版 PRD

- [NOTICE_CMS_DEV_TASKS.md](/Users/muniao/Library/Mobile%20Documents/com~apple~CloudDocs/游戏/github/Pink_House/docs/NOTICE_CMS_DEV_TASKS.md)
  说明：研发任务单与分组排期依据

---

## 2. A 组：基础规则

- [NOTICE_CMS_FIELD_SPEC.md](/Users/muniao/Library/Mobile%20Documents/com~apple~CloudDocs/游戏/github/Pink_House/docs/NOTICE_CMS_FIELD_SPEC.md)
  说明：主模型与用户状态模型字段冻结表

- [NOTICE_CMS_STATE_MACHINE.md](/Users/muniao/Library/Mobile%20Documents/com~apple~CloudDocs/游戏/github/Pink_House/docs/NOTICE_CMS_STATE_MACHINE.md)
  说明：生命周期状态机

- [NOTICE_CMS_CHANNEL_MATRIX.md](/Users/muniao/Library/Mobile%20Documents/com~apple~CloudDocs/游戏/github/Pink_House/docs/NOTICE_CMS_CHANNEL_MATRIX.md)
  说明：`inbox / banner / modal` 渠道矩阵

- [NOTICE_CMS_ENV_ROLE_RULES.md](/Users/muniao/Library/Mobile%20Documents/com~apple~CloudDocs/游戏/github/Pink_House/docs/NOTICE_CMS_ENV_ROLE_RULES.md)
  说明：环境与角色规则

---

## 3. B 组：数据层设计

- [NOTICE_CMS_MODEL_MIGRATION.md](/Users/muniao/Library/Mobile%20Documents/com~apple~CloudDocs/游戏/github/Pink_House/docs/NOTICE_CMS_MODEL_MIGRATION.md)
  说明：旧公告主模型迁移设计

- [NOTICE_CMS_USER_STATE_MIGRATION.md](/Users/muniao/Library/Mobile%20Documents/com~apple~CloudDocs/游戏/github/Pink_House/docs/NOTICE_CMS_USER_STATE_MIGRATION.md)
  说明：用户状态迁移设计

- [NOTICE_CMS_QUERY_SORT_SPEC.md](/Users/muniao/Library/Mobile%20Documents/com~apple~CloudDocs/游戏/github/Pink_House/docs/NOTICE_CMS_QUERY_SORT_SPEC.md)
  说明：查询与排序策略

- [NOTICE_CMS_EXPIRATION_GOVERNANCE.md](/Users/muniao/Library/Mobile%20Documents/com~apple~CloudDocs/游戏/github/Pink_House/docs/NOTICE_CMS_EXPIRATION_GOVERNANCE.md)
  说明：过期治理规则

---

## 4. C / D 组：信息架构

- [NOTICE_CMS_USER_IA.md](/Users/muniao/Library/Mobile%20Documents/com~apple~CloudDocs/游戏/github/Pink_House/docs/NOTICE_CMS_USER_IA.md)
  说明：用户前端信息架构

- [NOTICE_CMS_ADMIN_IA.md](/Users/muniao/Library/Mobile%20Documents/com~apple~CloudDocs/游戏/github/Pink_House/docs/NOTICE_CMS_ADMIN_IA.md)
  说明：管理端信息架构

---

## 5. E / H 组：CloudKit 与运维

- [NOTICE_CMS_CLOUDKIT_SCHEMA_CHECKLIST.md](/Users/muniao/Library/Mobile%20Documents/com~apple~CloudDocs/游戏/github/Pink_House/docs/NOTICE_CMS_CLOUDKIT_SCHEMA_CHECKLIST.md)
  说明：CloudKit Schema、索引和环境部署清单

- [NOTICE_CMS_MODAL_DEBUG_CHECKLIST.md](/Users/muniao/Library/Mobile%20Documents/com~apple~CloudDocs/游戏/github/Pink_House/docs/NOTICE_CMS_MODAL_DEBUG_CHECKLIST.md)
  说明：当前阶段 `modal` 弹窗专项排查清单

- [NOTICE_CMS_RELEASE_SOP.md](/Users/muniao/Library/Mobile%20Documents/com~apple~CloudDocs/游戏/github/Pink_House/docs/NOTICE_CMS_RELEASE_SOP.md)
  说明：发布 / 下线 / 回滚 SOP

---

## 6. 测试与验收

- [NOTICE_CMS_TEST_MATRIX.md](/Users/muniao/Library/Mobile%20Documents/com~apple~CloudDocs/游戏/github/Pink_House/docs/NOTICE_CMS_TEST_MATRIX.md)
  说明：测试矩阵

- [NOTICE_CMS_EVENT_DICTIONARY.md](/Users/muniao/Library/Mobile%20Documents/com~apple~CloudDocs/游戏/github/Pink_House/docs/NOTICE_CMS_EVENT_DICTIONARY.md)
  说明：埋点事件字典

- [NOTICE_CMS_RELEASE_ACCEPTANCE.md](/Users/muniao/Library/Mobile%20Documents/com~apple~CloudDocs/游戏/github/Pink_House/docs/NOTICE_CMS_RELEASE_ACCEPTANCE.md)
  说明：上线验收总表

---

## 7. 推荐阅读顺序

### 产品/排期视角

1. `NOTICE_CMS_PRD_EXECUTION.md`
2. `NOTICE_CMS_DEV_TASKS.md`
3. `NOTICE_CMS_RELEASE_ACCEPTANCE.md`

### 研发实现视角

1. `NOTICE_CMS_FIELD_SPEC.md`
2. `NOTICE_CMS_STATE_MACHINE.md`
3. `NOTICE_CMS_CHANNEL_MATRIX.md`
4. `NOTICE_CMS_MODEL_MIGRATION.md`
5. `NOTICE_CMS_QUERY_SORT_SPEC.md`

### 测试/上线视角

1. `NOTICE_CMS_TEST_MATRIX.md`
2. `NOTICE_CMS_CLOUDKIT_SCHEMA_CHECKLIST.md`
3. `NOTICE_CMS_MODAL_DEBUG_CHECKLIST.md`
4. `NOTICE_CMS_RELEASE_SOP.md`
5. `NOTICE_CMS_RELEASE_ACCEPTANCE.md`

---

## 8. 维护规则

1. 若产品规则发生变化，优先更新 PRD 和 A 组文档。
2. 若数据实现发生变化，优先更新 B 组文档。
3. 若上线流程变化，优先更新 SOP 与验收总表。
4. 本索引页仅负责导航，不承载规则本体。
