import relationalStore from '@ohos.data.relationalStore';

const TABLE_NAME = 'wardrobe_item_tags';

export interface TagUsageCount {
  tagId: string;
  count: number;
}

export class WardrobeItemTagDao {
  private readonly store: relationalStore.RdbStore;

  constructor(store: relationalStore.RdbStore) {
    this.store = store;
  }

  async getTagIdsForItem(itemId: string): Promise<string[]> {
    const resultSet = await this.store.querySql(
      `SELECT tag_id FROM ${TABLE_NAME} WHERE item_id = ?`,
      [itemId]
    );
    const ids: string[] = [];
    try {
      while (resultSet.goToNextRow()) {
        ids.push(resultSet.getString(resultSet.getColumnIndex('tag_id')));
      }
    } finally {
      resultSet.close();
    }
    return ids;
  }

  async setTagsForItem(itemId: string, tagIds: string[]): Promise<void> {
    await this.store.executeSql(
      `DELETE FROM ${TABLE_NAME} WHERE item_id = ?`,
      [itemId]
    );
    for (const tagId of tagIds) {
      const bucket: relationalStore.ValuesBucket = {
        item_id: itemId,
        tag_id: tagId
      };
      await this.store.insert(TABLE_NAME, bucket);
    }
  }

  async getItemIdsByTagIds(tagIds: string[]): Promise<string[]> {
    if (tagIds.length === 0) {
      return [];
    }
    const placeholders: string = tagIds.map(() => '?').join(',');
    const sql = `SELECT DISTINCT item_id
      FROM ${TABLE_NAME}
      WHERE tag_id IN (${placeholders})`;
    const resultSet = await this.store.querySql(sql, tagIds);
    const ids: string[] = [];
    try {
      while (resultSet.goToNextRow()) {
        ids.push(resultSet.getString(resultSet.getColumnIndex('item_id')));
      }
    } finally {
      resultSet.close();
    }
    return ids;
  }

  async getTagUsageCounts(): Promise<TagUsageCount[]> {
    const sql = `SELECT tag_id, COUNT(*) AS count
      FROM ${TABLE_NAME}
      GROUP BY tag_id`;
    const resultSet = await this.store.querySql(sql);
    const counts: TagUsageCount[] = [];
    try {
      while (resultSet.goToNextRow()) {
        const row: TagUsageCount = {
          tagId: resultSet.getString(resultSet.getColumnIndex('tag_id')),
          count: resultSet.getLong(resultSet.getColumnIndex('count'))
        };
        counts.push(row);
      }
    } finally {
      resultSet.close();
    }
    return counts;
  }

  async deleteAllForItem(itemId: string): Promise<void> {
    await this.store.executeSql(
      `DELETE FROM ${TABLE_NAME} WHERE item_id = ?`,
      [itemId]
    );
  }

  async deleteAllForTag(tagId: string): Promise<void> {
    await this.store.executeSql(
      `DELETE FROM ${TABLE_NAME} WHERE tag_id = ?`,
      [tagId]
    );
  }
}
