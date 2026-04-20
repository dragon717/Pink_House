import { FeatureShell } from '../FeatureShell';

@Component
export struct WardrobePage {
  build() {
    FeatureShell({
      title: '衣橱',
      badge: 'M2',
      description: '服饰建模、图片资源、分类筛选、资产统计与搭配入口将在这里实现。',
      checklist: ['RDB: wardrobe_items', '图片导入/权限', 'JSON 备份字段兼容', '衣物详情路由']
    });
  }
}
