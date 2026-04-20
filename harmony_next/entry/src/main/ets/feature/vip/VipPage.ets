import { FeatureShell } from '../FeatureShell';

@Component
export struct VipPage {
  build() {
    FeatureShell({
      title: 'VIP',
      badge: 'M6',
      description: 'HMS IAP 仅用于喵币充值，VIP 通过喵币兑换，和 iOS/Android 产品规则保持一致。',
      checklist: ['HMS 商品 ID', '订单验签', '幂等发币', '恢复购买']
    });
  }
}
