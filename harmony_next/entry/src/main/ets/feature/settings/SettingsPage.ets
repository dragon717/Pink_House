import { FeatureShell } from '../FeatureShell';

@Component
export struct SettingsPage {
  build() {
    FeatureShell({
      title: '设置',
      badge: 'M7',
      description: '隐私协议、备份导入导出、分享、字体注册和调试工具的集中入口。',
      checklist: ['隐私弹窗', 'filePicker JSON 导入', 'systemShare 分享', 'rawfile/fonts 字体注册']
    });
  }
}
