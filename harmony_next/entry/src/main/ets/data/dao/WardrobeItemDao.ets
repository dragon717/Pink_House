import relationalStore from '@ohos.data.relationalStore';
import { NewWardrobeItem, WardrobeCategory, WardrobeItem } from '../../domain/model/WardrobeItem';

const TABLE_NAME = 'wardrobe_items';

interface WardrobeItemRow {
  id: string;
  name: string;
  category: string;
  image_uri: string;
  price: number;
  purchased_at: number;
  created_at: number;
  updated_at: number;
  is_deleted: number;
}

export class WardrobeItemDao {
  private readonly store: relationalStore.RdbStore;

  constructor(store: relationalStore.RdbStore) {
    this.store = store;
  }

  async queryActiveItems(): Promise<WardrobeItem[]> {
    const sql = `SELECT id, name, category, COALESCE(image_uri, '') AS image_uri,
        COALESCE(price, 0) AS price, COALESCE(purchased_at, 0) AS purchased_at,
        created_at, updated_at, COALESCE(is_deleted, 0) AS is_deleted
      FROM ${TABLE_NAME}
      WHERE is_deleted = 0
      ORDER BY created_at DESC`;
    return this.queryItems(sql);
  }

  async searchActiveItems(keyword: string): Promise<WardrobeItem[]> {
    const normalizedKeyword = keyword.trim();
    if (normalizedKeyword.length === 0) {
      return this.queryActiveItems();
    }

    const sql = `SELECT id, name, category, COALESCE(image_uri, '') AS image_uri,
        COALESCE(price, 0) AS price, COALESCE(purchased_at, 0) AS purchased_at,
        created_at, updated_at, COALESCE(is_deleted, 0) AS is_deleted
      FROM ${TABLE_NAME}
      WHERE is_deleted = 0 AND name LIKE ?
      ORDER BY created_at DESC`;
    return this.queryItems(sql, [`%${normalizedKeyword}%`]);
  }

  async insertItem(item: NewWardrobeItem): Promise<WardrobeItem> {
    const now = Date.now();
    const wardrobeItem: WardrobeItem = {
      id: this.createId(now),
      name: item.name,
      category: item.category,
      imageUri: item.imageUri ?? '',
      price: item.price ?? 0,
      purchasedAt: item.purchasedAt ?? now,
      createdAt: now,
      updatedAt: now,
      isDeleted: false
    };
    const values: relationalStore.ValuesBucket = this.toValuesBucket(wardrobeItem);
    await this.store.insert(TABLE_NAME, values);
    return wardrobeItem;
  }

  async insertSampleItem(): Promise<WardrobeItem> {
    const sampleNames: string[] = ['奶油针织开衫', '樱桃格纹半裙', '通勤玛丽珍鞋', '珍珠蝴蝶结发夹'];
    const sampleCategories: string[] = [
      WardrobeCategory.Tops,
      WardrobeCategory.Bottoms,
      WardrobeCategory.Shoes,
      WardrobeCategory.Accessory
    ];
    const index = Date.now() % sampleNames.length;
    return this.insertItem({
      name: sampleNames[index],
      category: sampleCategories[index],
      price: 129 + index * 30,
      purchasedAt: Date.now()
    });
  }

  async softDeleteItem(id: string): Promise<void> {
    const sql = `UPDATE ${TABLE_NAME} SET is_deleted = 1, updated_at = ? WHERE id = ?`;
    await this.store.executeSql(sql, [Date.now(), id]);
  }

  private async queryItems(sql: string, bindArgs: relationalStore.ValueType[] = []): Promise<WardrobeItem[]> {
    const resultSet = await this.store.querySql(sql, bindArgs);
    const items: WardrobeItem[] = [];

    try {
      while (resultSet.goToNextRow()) {
        const row = this.readRow(resultSet);
        items.push(this.toDomain(row));
      }
    } finally {
      resultSet.close();
    }

    return items;
  }

  private readRow(resultSet: relationalStore.ResultSet): WardrobeItemRow {
    return {
      id: resultSet.getString(resultSet.getColumnIndex('id')),
      name: resultSet.getString(resultSet.getColumnIndex('name')),
      category: resultSet.getString(resultSet.getColumnIndex('category')),
      image_uri: resultSet.getString(resultSet.getColumnIndex('image_uri')),
      price: resultSet.getDouble(resultSet.getColumnIndex('price')),
      purchased_at: resultSet.getLong(resultSet.getColumnIndex('purchased_at')),
      created_at: resultSet.getLong(resultSet.getColumnIndex('created_at')),
      updated_at: resultSet.getLong(resultSet.getColumnIndex('updated_at')),
      is_deleted: resultSet.getLong(resultSet.getColumnIndex('is_deleted'))
    };
  }

  private toDomain(row: WardrobeItemRow): WardrobeItem {
    return {
      id: row.id,
      name: row.name,
      category: row.category,
      imageUri: row.image_uri,
      price: row.price,
      purchasedAt: row.purchased_at,
      createdAt: row.created_at,
      updatedAt: row.updated_at,
      isDeleted: row.is_deleted === 1
    };
  }

  private toValuesBucket(item: WardrobeItem): relationalStore.ValuesBucket {
    return {
      id: item.id,
      name: item.name,
      category: item.category,
      image_uri: item.imageUri,
      price: item.price,
      purchased_at: item.purchasedAt,
      created_at: item.createdAt,
      updated_at: item.updatedAt,
      is_deleted: item.isDeleted ? 1 : 0
    };
  }

  private createId(now: number): string {
    const randomPart = Math.floor(Math.random() * 1000000).toString();
    return `wardrobe_${now}_${randomPart}`;
  }
}
