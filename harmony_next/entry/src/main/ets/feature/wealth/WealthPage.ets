import { FeatureShell } from '../FeatureShell';

@Component
export struct WealthPage {
  build() {
    FeatureShell({
      title: '财富',
      badge: 'M5',
      description: '喵币流水、账本、尾款提醒、拼豆和 OOTD 统计能力的占位入口。',
      checklist: ['RDB: wallet_transactions', '尾款 Calendar 提醒', '资产趋势统计', 'Service Card 2x4 数据源']
    });
  }
}
