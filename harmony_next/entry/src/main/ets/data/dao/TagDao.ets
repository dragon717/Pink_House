import relationalStore from '@ohos.data.relationalStore';
import { NewTag, Tag } from '../../domain/model/Tag';

const TABLE_NAME = 'tags';

export class TagDao {
  private readonly store: relationalStore.RdbStore;

  constructor(store: relationalStore.RdbStore) {
    this.store = store;
  }

  async queryAllTags(): Promise<Tag[]> {
    const sql = `SELECT id, name,
        COALESCE(sort_index, 0) AS sort_index,
        created_at
      FROM ${TABLE_NAME}
      ORDER BY sort_index ASC, created_at ASC`;
    return this.queryTags(sql);
  }

  async queryTagsByIds(ids: string[]): Promise<Tag[]> {
    if (ids.length === 0) {
      return [];
    }
    const placeholders: string = ids.map(() => '?').join(',');
    const sql = `SELECT id, name,
        COALESCE(sort_index, 0) AS sort_index,
        created_at
      FROM ${TABLE_NAME}
      WHERE id IN (${placeholders})`;
    return this.queryTags(sql, ids);
  }

  async insertTag(tag: NewTag): Promise<Tag> {
    const now = Date.now();
    const record: Tag = {
      id: this.createId(now),
      name: tag.name,
      sortIndex: tag.sortIndex ?? 0,
      createdAt: now
    };
    const bucket: relationalStore.ValuesBucket = {
      id: record.id,
      name: record.name,
      sort_index: record.sortIndex,
      created_at: record.createdAt
    };
    await this.store.insert(TABLE_NAME, bucket);
    return record;
  }

  async renameTag(id: string, name: string): Promise<void> {
    await this.store.executeSql(
      `UPDATE ${TABLE_NAME} SET name = ? WHERE id = ?`,
      [name, id]
    );
  }

  async deleteTag(id: string): Promise<void> {
    await this.store.executeSql(
      `DELETE FROM ${TABLE_NAME} WHERE id = ?`,
      [id]
    );
  }

  private async queryTags(sql: string, bindArgs: relationalStore.ValueType[] = []): Promise<Tag[]> {
    const resultSet = await this.store.querySql(sql, bindArgs);
    const tags: Tag[] = [];

    try {
      while (resultSet.goToNextRow()) {
        const row: Tag = {
          id: resultSet.getString(resultSet.getColumnIndex('id')),
          name: resultSet.getString(resultSet.getColumnIndex('name')),
          sortIndex: resultSet.getLong(resultSet.getColumnIndex('sort_index')),
          createdAt: resultSet.getLong(resultSet.getColumnIndex('created_at'))
        };
        tags.push(row);
      }
    } finally {
      resultSet.close();
    }

    return tags;
  }

  private createId(now: number): string {
    const randomPart = Math.floor(Math.random() * 1000000).toString();
    return `tag_${now}_${randomPart}`;
  }
}
