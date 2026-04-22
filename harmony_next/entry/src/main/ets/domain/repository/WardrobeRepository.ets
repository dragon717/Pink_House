import { NewWardrobeItem, WardrobeItem } from '../model/WardrobeItem';
import {
  WardrobeFilterState,
  WardrobeSortOption
} from '../model/WardrobeListOptions';

export interface WardrobeRepository {
  getActiveItems(): Promise<WardrobeItem[]>;
  searchActiveItems(keyword: string): Promise<WardrobeItem[]>;
  addItem(item: NewWardrobeItem): Promise<WardrobeItem>;
  addSampleItem(): Promise<WardrobeItem>;
  softDeleteItem(id: string): Promise<void>;
  softDeleteItems(ids: string[]): Promise<void>;
  reorderItems(orderedIds: string[]): Promise<void>;
  getDepositPlans(): Promise<WardrobeItem[]>;
  getDepositPlansByYear(year: number): Promise<WardrobeItem[]>;

  // R1.5: 顶部导航栏统一查询
  queryItems(
    filter: WardrobeFilterState,
    sort: WardrobeSortOption,
    keyword: string
  ): Promise<WardrobeItem[]>;

  // Filter Sheet 候选值
  queryDistinctBrandNames(): Promise<string[]>;
  queryDistinctTypes(): Promise<string[]>;
  queryDistinctColors(): Promise<string[]>;
  queryDistinctSizes(): Promise<string[]>;
  queryDistinctLengths(): Promise<string[]>;
  queryDistinctConditions(): Promise<string[]>;
}
