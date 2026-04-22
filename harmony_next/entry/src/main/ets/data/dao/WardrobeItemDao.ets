import relationalStore from '@ohos.data.relationalStore';
import { NewWardrobeItem, WardrobeCategory, WardrobeItem } from '../../domain/model/WardrobeItem';

const TABLE_NAME = 'wardrobe_items';

const SELECT_COLUMNS = `id, name, category,
    COALESCE(image_uri, '') AS image_uri,
    COALESCE(price, 0) AS price,
    COALESCE(brand_name, '') AS brand_name,
    COALESCE(types, '') AS types,
    COALESCE(colors, '') AS colors,
    COALESCE(sizes, '') AS sizes,
    COALESCE(length, '') AS length,
    COALESCE(condition, '全新') AS condition,
    COALESCE(note, '') AS note,
    COALESCE(original_price, 0) AS original_price,
    COALESCE(deposit, 0) AS deposit,
    COALESCE(balance, 0) AS balance,
    COALESCE(accessories_price, 0) AS accessories_price,
    COALESCE(stock, 1) AS stock,
    COALESCE(purchased_at, 0) AS purchased_at,
    deposit_date,
    COALESCE(is_deposit_plan, 0) AS is_deposit_plan,
    final_payment_date,
    final_payment_end_date,
    created_at, updated_at,
    COALESCE(is_deleted, 0) AS is_deleted`;

interface WardrobeItemRow {
  id: string;
  name: string;
  category: string;
  image_uri: string;
  price: number;
  brand_name: string;
  types: string;
  colors: string;
  sizes: string;
  length: string;
  condition: string;
  note: string;
  original_price: number;
  deposit: number;
  balance: number;
  accessories_price: number;
  stock: number;
  purchased_at: number;
  deposit_date: number | null;
  is_deposit_plan: number;
  final_payment_date: number | null;
  final_payment_end_date: number | null;
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
    const sql = `SELECT ${SELECT_COLUMNS}
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

    const sql = `SELECT ${SELECT_COLUMNS}
      FROM ${TABLE_NAME}
      WHERE is_deleted = 0 AND name LIKE ?
      ORDER BY created_at DESC`;
    return this.queryItems(sql, [`%${normalizedKeyword}%`]);
  }

  async queryDepositPlans(): Promise<WardrobeItem[]> {
    const sql = `SELECT ${SELECT_COLUMNS}
      FROM ${TABLE_NAME}
      WHERE is_deleted = 0 AND is_deposit_plan = 1
      ORDER BY (final_payment_date IS NULL), final_payment_date ASC, created_at DESC`;
    return this.queryItems(sql);
  }

  async queryDepositPlansByYear(year: number): Promise<WardrobeItem[]> {
    const start = new Date(year, 0, 1).getTime();
    const end = new Date(year + 1, 0, 1).getTime();
    const sql = `SELECT ${SELECT_COLUMNS}
      FROM ${TABLE_NAME}
      WHERE is_deleted = 0 AND is_deposit_plan = 1
        AND final_payment_date IS NOT NULL
        AND final_payment_date >= ? AND final_payment_date < ?
      ORDER BY final_payment_date ASC, created_at DESC`;
    return this.queryItems(sql, [start, end]);
  }

  async insertItem(item: NewWardrobeItem): Promise<WardrobeItem> {
    const now = Date.now();
    const wardrobeItem: WardrobeItem = {
      id: this.createId(now),
      name: item.name,
      category: item.category,
      imageUri: item.imageUri ?? '',
      price: item.price ?? 0,
      brandName: item.brandName ?? '',
      types: item.types ?? '',
      colors: item.colors ?? '',
      sizes: item.sizes ?? '',
      length: item.length ?? '',
      condition: item.condition ?? '全新',
      note: item.note ?? '',
      originalPrice: item.originalPrice ?? 0,
      deposit: item.deposit ?? 0,
      balance: item.balance ?? 0,
      accessoriesPrice: item.accessoriesPrice ?? 0,
      stock: item.stock ?? 1,
      purchasedAt: item.purchasedAt ?? now,
      depositDate: item.depositDate ?? null,
      isDepositPlan: item.isDepositPlan ?? false,
      finalPaymentDate: item.finalPaymentDate ?? null,
      finalPaymentEndDate: item.finalPaymentEndDate ?? null,
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
      brand_name: resultSet.getString(resultSet.getColumnIndex('brand_name')),
      types: resultSet.getString(resultSet.getColumnIndex('types')),
      colors: resultSet.getString(resultSet.getColumnIndex('colors')),
      sizes: resultSet.getString(resultSet.getColumnIndex('sizes')),
      length: resultSet.getString(resultSet.getColumnIndex('length')),
      condition: resultSet.getString(resultSet.getColumnIndex('condition')),
      note: resultSet.getString(resultSet.getColumnIndex('note')),
      original_price: resultSet.getDouble(resultSet.getColumnIndex('original_price')),
      deposit: resultSet.getDouble(resultSet.getColumnIndex('deposit')),
      balance: resultSet.getDouble(resultSet.getColumnIndex('balance')),
      accessories_price: resultSet.getDouble(resultSet.getColumnIndex('accessories_price')),
      stock: resultSet.getLong(resultSet.getColumnIndex('stock')),
      purchased_at: resultSet.getLong(resultSet.getColumnIndex('purchased_at')),
      deposit_date: this.readLongOrNull(resultSet, 'deposit_date'),
      is_deposit_plan: resultSet.getLong(resultSet.getColumnIndex('is_deposit_plan')),
      final_payment_date: this.readLongOrNull(resultSet, 'final_payment_date'),
      final_payment_end_date: this.readLongOrNull(resultSet, 'final_payment_end_date'),
      created_at: resultSet.getLong(resultSet.getColumnIndex('created_at')),
      updated_at: resultSet.getLong(resultSet.getColumnIndex('updated_at')),
      is_deleted: resultSet.getLong(resultSet.getColumnIndex('is_deleted'))
    };
  }

  private readLongOrNull(resultSet: relationalStore.ResultSet, column: string): number | null {
    const idx = resultSet.getColumnIndex(column);
    if (resultSet.isColumnNull(idx)) {
      return null;
    }
    return resultSet.getLong(idx);
  }

  private toDomain(row: WardrobeItemRow): WardrobeItem {
    return {
      id: row.id,
      name: row.name,
      category: row.category,
      imageUri: row.image_uri,
      price: row.price,
      brandName: row.brand_name,
      types: row.types,
      colors: row.colors,
      sizes: row.sizes,
      length: row.length,
      condition: row.condition,
      note: row.note,
      originalPrice: row.original_price,
      deposit: row.deposit,
      balance: row.balance,
      accessoriesPrice: row.accessories_price,
      stock: row.stock,
      purchasedAt: row.purchased_at,
      depositDate: row.deposit_date,
      isDepositPlan: row.is_deposit_plan === 1,
      finalPaymentDate: row.final_payment_date,
      finalPaymentEndDate: row.final_payment_end_date,
      createdAt: row.created_at,
      updatedAt: row.updated_at,
      isDeleted: row.is_deleted === 1
    };
  }

  private toValuesBucket(item: WardrobeItem): relationalStore.ValuesBucket {
    const bucket: relationalStore.ValuesBucket = {
      id: item.id,
      name: item.name,
      category: item.category,
      image_uri: item.imageUri,
      price: item.price,
      brand_name: item.brandName,
      types: item.types,
      colors: item.colors,
      sizes: item.sizes,
      length: item.length,
      condition: item.condition,
      note: item.note,
      original_price: item.originalPrice,
      deposit: item.deposit,
      balance: item.balance,
      accessories_price: item.accessoriesPrice,
      stock: item.stock,
      purchased_at: item.purchasedAt,
      deposit_date: item.depositDate,
      is_deposit_plan: item.isDepositPlan ? 1 : 0,
      final_payment_date: item.finalPaymentDate,
      final_payment_end_date: item.finalPaymentEndDate,
      created_at: item.createdAt,
      updated_at: item.updatedAt,
      is_deleted: item.isDeleted ? 1 : 0
    };
    return bucket;
  }

  private createId(now: number): string {
    const randomPart = Math.floor(Math.random() * 1000000).toString();
    return `wardrobe_${now}_${randomPart}`;
  }
}
