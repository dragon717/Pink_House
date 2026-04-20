export interface WardrobeItem {
  id: string;
  name: string;
  category: string;
  imageUri: string;
  price: number;
  purchasedAt: number;
  createdAt: number;
  updatedAt: number;
  isDeleted: boolean;
}

export interface NewWardrobeItem {
  name: string;
  category: string;
  imageUri?: string;
  price?: number;
  purchasedAt?: number;
}

export const WardrobeCategory = {
  Tops: '上衣',
  Bottoms: '下装',
  Dress: '连衣裙',
  Shoes: '鞋履',
  Accessory: '配饰'
};
