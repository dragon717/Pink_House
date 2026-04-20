import { FeatureShell } from '../FeatureShell';

@Component
export struct PetPage {
  build() {
    FeatureShell({
      title: '宠物',
      badge: 'M3',
      description: '宠物状态、喂食、互动、提醒和序列帧动画的 HarmonyOS Next 原生实现入口。',
      checklist: ['RDB: pet_states', 'reminderAgent 定时提醒', 'PNG 序列帧动画', 'Service Card 2x2 数据源']
    });
  }
}
