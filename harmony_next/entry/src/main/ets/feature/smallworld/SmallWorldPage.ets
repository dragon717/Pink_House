import { FeatureShell } from '../FeatureShell';

@Component
export struct SmallWorldPage {
  build() {
    FeatureShell({
      title: '小世界',
      badge: 'M3/M4',
      description: '小世界首页、天气组件、签到入口与未来分布式流转能力的聚合页面。',
      checklist: ['和风天气 JWT', '粗略定位降级', '签到状态', '平板/折叠屏布局预留']
    });
  }
}
