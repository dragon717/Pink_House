import common from '@ohos.app.ability.common';
import { NewTag, Tag } from '../../domain/model/Tag';
import { TagRepository } from '../../domain/repository/TagRepository';
import { TagDao } from '../dao/TagDao';
import { TagUsageCount, WardrobeItemTagDao } from '../dao/WardrobeItemTagDao';
import { rdbStoreProvider } from '../rdb/RdbStoreProvider';

export class RdbTagRepository implements TagRepository {
  private readonly context: common.Context;

  constructor(context: common.Context) {
    this.context = context;
  }

  async getAllTags(): Promise<Tag[]> {
    const dao = await this.getTagDao();
    return dao.queryAllTags();
  }

  async getTagsByIds(ids: string[]): Promise<Tag[]> {
    const dao = await this.getTagDao();
    return dao.queryTagsByIds(ids);
  }

  async createTag(tag: NewTag): Promise<Tag> {
    const dao = await this.getTagDao();
    return dao.insertTag(tag);
  }

  async renameTag(id: string, name: string): Promise<void> {
    const dao = await this.getTagDao();
    await dao.renameTag(id, name);
  }

  async deleteTag(id: string): Promise<void> {
    const tagDao = await this.getTagDao();
    const relationDao = await this.getRelationDao();
    await relationDao.deleteAllForTag(id);
    await tagDao.deleteTag(id);
  }

  async getTagIdsForItem(itemId: string): Promise<string[]> {
    const dao = await this.getRelationDao();
    return dao.getTagIdsForItem(itemId);
  }

  async setTagsForItem(itemId: string, tagIds: string[]): Promise<void> {
    const dao = await this.getRelationDao();
    await dao.setTagsForItem(itemId, tagIds);
  }

  async getItemIdsByTagIds(tagIds: string[]): Promise<string[]> {
    const dao = await this.getRelationDao();
    return dao.getItemIdsByTagIds(tagIds);
  }

  async getTagUsageCounts(): Promise<TagUsageCount[]> {
    const dao = await this.getRelationDao();
    return dao.getTagUsageCounts();
  }

  private async getTagDao(): Promise<TagDao> {
    const store = await rdbStoreProvider.getStore(this.context);
    return new TagDao(store);
  }

  private async getRelationDao(): Promise<WardrobeItemTagDao> {
    const store = await rdbStoreProvider.getStore(this.context);
    return new WardrobeItemTagDao(store);
  }
}
