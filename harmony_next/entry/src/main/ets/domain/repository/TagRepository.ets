import { NewTag, Tag } from '../model/Tag';
import { TagUsageCount } from '../../data/dao/WardrobeItemTagDao';

export interface TagRepository {
  getAllTags(): Promise<Tag[]>;
  getTagsByIds(ids: string[]): Promise<Tag[]>;
  createTag(tag: NewTag): Promise<Tag>;
  renameTag(id: string, name: string): Promise<void>;
  deleteTag(id: string): Promise<void>;

  // 关联
  getTagIdsForItem(itemId: string): Promise<string[]>;
  setTagsForItem(itemId: string, tagIds: string[]): Promise<void>;
  getItemIdsByTagIds(tagIds: string[]): Promise<string[]>;
  getTagUsageCounts(): Promise<TagUsageCount[]>;
}
