import common from '@ohos.app.ability.common';
import { NewWardrobeItem, WardrobeItem } from '../../domain/model/WardrobeItem';
import {
  WardrobeFilterState,
  WardrobeSortOption
} from '../../domain/model/WardrobeListOptions';
import { WardrobeRepository } from '../../domain/repository/WardrobeRepository';
import { WardrobeItemDao } from '../dao/WardrobeItemDao';
import { WardrobeItemTagDao } from '../dao/WardrobeItemTagDao';
import { rdbStoreProvider } from '../rdb/RdbStoreProvider';

export class RdbWardrobeRepository implements WardrobeRepository {
  private readonly context: common.Context;

  constructor(context: common.Context) {
    this.context = context;
  }

  async getActiveItems(): Promise<WardrobeItem[]> {
    const dao = await this.getDao();
    return dao.queryActiveItems();
  }

  async searchActiveItems(keyword: string): Promise<WardrobeItem[]> {
    const dao = await this.getDao();
    return dao.searchActiveItems(keyword);
  }

  async addItem(item: NewWardrobeItem): Promise<WardrobeItem> {
    const dao = await this.getDao();
    return dao.insertItem(item);
  }

  async addSampleItem(): Promise<WardrobeItem> {
    const dao = await this.getDao();
    return dao.insertSampleItem();
  }

  async softDeleteItem(id: string): Promise<void> {
    const dao = await this.getDao();
    await dao.softDeleteItem(id);
  }

  async getDepositPlans(): Promise<WardrobeItem[]> {
    const dao = await this.getDao();
    return dao.queryDepositPlans();
  }

  async getDepositPlansByYear(year: number): Promise<WardrobeItem[]> {
    const dao = await this.getDao();
    return dao.queryDepositPlansByYear(year);
  }

  async queryItems(
    filter: WardrobeFilterState,
    sort: WardrobeSortOption,
    keyword: string
  ): Promise<WardrobeItem[]> {
    let tagItemIds: string[] | null = null;
    if (filter.tagIds.length > 0) {
      const tagRelationDao = await this.getTagRelationDao();
      tagItemIds = await tagRelationDao.getItemIdsByTagIds(filter.tagIds);
      if (tagItemIds.length === 0) {
        return [];
      }
    }
    const dao = await this.getDao();
    return dao.queryItems(filter, sort, keyword, tagItemIds);
  }

  async queryDistinctBrandNames(): Promise<string[]> {
    const dao = await this.getDao();
    return dao.queryDistinctBrandNames();
  }

  async queryDistinctTypes(): Promise<string[]> {
    const dao = await this.getDao();
    return dao.queryDistinctTypes();
  }

  async queryDistinctColors(): Promise<string[]> {
    const dao = await this.getDao();
    return dao.queryDistinctColors();
  }

  async queryDistinctSizes(): Promise<string[]> {
    const dao = await this.getDao();
    return dao.queryDistinctSizes();
  }

  async queryDistinctLengths(): Promise<string[]> {
    const dao = await this.getDao();
    return dao.queryDistinctLengths();
  }

  async queryDistinctConditions(): Promise<string[]> {
    const dao = await this.getDao();
    return dao.queryDistinctConditions();
  }

  private async getDao(): Promise<WardrobeItemDao> {
    const store = await rdbStoreProvider.getStore(this.context);
    return new WardrobeItemDao(store);
  }

  private async getTagRelationDao(): Promise<WardrobeItemTagDao> {
    const store = await rdbStoreProvider.getStore(this.context);
    return new WardrobeItemTagDao(store);
  }
}
