export interface WardrobeItem {
  id: string;
  name: string;
  category: string;
  imageUri: string;
  price: number;

  // 扩展字段：心愿尾款必需
  brandName: string;
  types: string;
  colors: string;
  sizes: string;
  length: string;
  condition: string;
  note: string;

  originalPrice: number;
  deposit: number;
  balance: number;
  accessoriesPrice: number;
  stock: number;

  purchasedAt: number;
  depositDate: number | null;
  isDepositPlan: boolean;
  finalPaymentDate: number | null;
  finalPaymentEndDate: number | null;

  createdAt: number;
  updatedAt: number;
  isDeleted: boolean;
}

export interface NewWardrobeItem {
  name: string;
  category: string;
  imageUri?: string;
  price?: number;

  brandName?: string;
  types?: string;
  colors?: string;
  sizes?: string;
  length?: string;
  condition?: string;
  note?: string;

  originalPrice?: number;
  deposit?: number;
  balance?: number;
  accessoriesPrice?: number;
  stock?: number;

  purchasedAt?: number;
  depositDate?: number | null;
  isDepositPlan?: boolean;
  finalPaymentDate?: number | null;
  finalPaymentEndDate?: number | null;
}

interface WardrobeCategoryMap {
  Tops: string;
  Bottoms: string;
  Dress: string;
  Shoes: string;
  Accessory: string;
}

export const WardrobeCategory: WardrobeCategoryMap = {
  Tops: '上衣',
  Bottoms: '下装',
  Dress: '连衣裙',
  Shoes: '鞋履',
  Accessory: '配饰'
};

/** 总定金 = (裙装定金) * 库存。iOS 侧还会加上小物明细定金；harmony 精简版仅用主体。 */
export function totalDeposit(item: WardrobeItem): number {
  return item.deposit * item.stock;
}

/** 总尾款 = (裙装尾款) * 库存。 */
export function totalBalance(item: WardrobeItem): number {
  return item.balance * item.stock;
}

/** 单套总价（含小物）。 */
export function unitTotalPrice(item: WardrobeItem): number {
  return item.price + item.accessoriesPrice;
}

/** 库存总价 = 裙装总价 × 库存 + 小物一次。 */
export function inventoryTotalPrice(item: WardrobeItem): number {
  return item.price * item.stock + item.accessoriesPrice;
}
