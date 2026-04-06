# 公告系统埋点事件字典

> 更新时间：2026-04-06  
> 用途：为 Notice CMS 提供统一事件定义，方便前端、数据和后续看板统计使用。

## 1. 设计目标

- 统一事件名
- 统一字段名
- 支持用户侧、管理侧、发布侧核心行为分析
- 避免埋点口径分裂

---

## 2. 通用字段

建议所有公告相关事件默认带以下公共字段：

| 字段 | 说明 |
|---|---|
| `notice_id` | 公告 ID |
| `record_name` | CloudKit 记录标识 |
| `status` | 公告状态 |
| `channel` | 渠道 |
| `severity` | 严重等级 |
| `environment` | 当前环境 |
| `app_version` | App 版本 |
| `user_state` | 用户当前公告状态 |
| `timestamp` | 事件时间 |

---

## 3. 用户侧事件

| 事件名 | 触发时机 | 关键字段 |
|---|---|---|
| `notice_center_viewed` | 打开公告中心 | `unread_count` |
| `notice_list_item_exposed` | 列表项曝光 | `position` |
| `notice_detail_opened` | 打开详情 | `entry_source` |
| `notice_marked_read` | 标记已读 | `from_state` |
| `notice_acknowledged` | 点击“我已知晓” | `from_state` |
| `notice_banner_exposed` | banner 曝光 | `position` |
| `notice_banner_clicked` | 点击 banner | `entry_source=banner` |
| `notice_banner_dismissed` | 关闭 banner | `from_state` |
| `notice_modal_exposed` | modal 曝光 | `presentation_count` |
| `notice_modal_primary_clicked` | 点击 modal 主按钮 | `entry_source=modal` |
| `notice_modal_dismissed` | 关闭 modal | `from_state` |
| `notice_action_clicked` | 点击公告动作按钮 | `action_type`, `action_target` |

---

## 4. 管理侧事件

| 事件名 | 触发时机 | 关键字段 |
|---|---|---|
| `notice_draft_created` | 新建草稿 | `operator_role` |
| `notice_draft_updated` | 编辑草稿 | `operator_role`, `revision` |
| `notice_preview_opened` | 打开预览 | `preview_channel` |
| `notice_publish_clicked` | 点击发布 | `operator_role` |
| `notice_published` | 发布成功 | `operator_role`, `publish_type` |
| `notice_scheduled` | 定时发布设置成功 | `publish_at` |
| `notice_archived` | 归档成功 | `operator_role` |
| `notice_unpublished` | 下线成功 | `operator_role` |
| `notice_rollback_started` | 发起回滚 | `operator_role`, `target_revision` |
| `notice_rollback_completed` | 回滚完成 | `operator_role`, `target_revision` |

---

## 5. 诊断与同步事件

| 事件名 | 触发时机 | 关键字段 |
|---|---|---|
| `notice_sync_started` | 发起同步 | `sync_type` |
| `notice_sync_completed` | 同步完成 | `sync_type`, `count` |
| `notice_sync_failed` | 同步失败 | `sync_type`, `error_code` |
| `notice_user_state_sync_completed` | 用户状态同步完成 | `count` |
| `notice_environment_checked` | 诊断页查看环境 | `environment` |
| `notice_permission_checked` | 诊断页查看权限 | `operator_role` |

---

## 6. 字段说明补充

### `entry_source`

可选值：

- `notice_center`
- `banner`
- `modal`
- `deep_link`

### `publish_type`

可选值：

- `immediate`
- `scheduled`

### `sync_type`

可选值：

- `notice_data`
- `user_state`
- `manual_refresh`
- `foreground_refresh`

### `operator_role`

可选值：

- `editor`
- `publisher`
- `admin`

---

## 7. 统计目标建议

可基于埋点计算：

- 公告中心访问率
- 公告详情打开率
- banner 点击率
- modal 打开后详情进入率
- 公告确认率
- 发布成功率
- 回滚次数
- 同步失败率

---

## 8. 禁止项

以下做法禁止：

1. 同一行为定义多个事件名
2. 不带公共字段导致事件不可关联
3. 在不同页面用不同字段表达同一语义

---

## 9. 冻结结论

本字典冻结以下共识：

1. 公告系统埋点必须区分用户消费行为和管理操作行为。
2. 所有埋点必须能关联到具体公告。
3. 事件名一旦落地，应避免随意改名。
