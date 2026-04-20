import { NewWardrobeItem, WardrobeItem } from '../model/WardrobeItem';

export interface WardrobeRepository {
  getActiveItems(): Promise<WardrobeItem[]>;
  searchActiveItems(keyword: string): Promise<WardrobeItem[]>;
  addItem(item: NewWardrobeItem): Promise<WardrobeItem>;
  addSampleItem(): Promise<WardrobeItem>;
  softDeleteItem(id: string): Promise<void>;
}
