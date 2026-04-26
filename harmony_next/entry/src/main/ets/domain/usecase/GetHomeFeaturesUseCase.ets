import { AppRoute } from '../../core/navigation/AppRoute';
import { FeatureDescriptor } from '../model/FeatureDescriptor';

export class GetHomeFeaturesUseCase {
  execute(): FeatureDescriptor[] {
    return [
      {
        route: AppRoute.Wardrobe,
        title: '衣橱',
        description: '预留 F-01 到 F-10：服饰建模、图片、分类、搭配与资产统计。',
        milestone: 'M2',
        status: 'scaffolded'
      },
      {
        route: AppRoute.Pet,
        title: '宠物',
        description: '预留 F-11 到 F-25：宠物状态、互动、提醒和序列帧动画。',
        milestone: 'M3',
        status: 'scaffolded'
      },
      {
        route: AppRoute.SmallWorld,
        title: '小世界',
        description: '预留天气、签到、场景和服务卡片跳转入口。',
        milestone: 'M3/M4',
        status: 'scaffolded'
      },
      {
        route: AppRoute.Wealth,
        title: '财富',
        description: '预留账本、尾款、喵币流水和统计面板。',
        milestone: 'M5',
        status: 'scaffolded'
      },
      {
        route: AppRoute.Vip,
        title: 'VIP',
        description: '预留 HMS IAP 购买、验签、恢复购买和会员权益。',
        milestone: 'M6',
        status: 'scaffolded'
      },
      {
        route: AppRoute.Settings,
        title: '设置',
        description: '预留隐私协议、JSON 备份导入导出、分享和调试入口。',
        milestone: 'M7',
        status: 'scaffolded'
      }
    ];
  }
}
