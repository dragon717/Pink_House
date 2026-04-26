import relationalStore from '@ohos.data.relationalStore';
import common from '@ohos.app.ability.common';
import { DatabaseSchema } from './DatabaseSchema';
import { AppLogger } from '../../core/utils/AppLogger';

interface DesiredColumn {
  name: string;
  ddl: string;
}

const WARDROBE_ITEM_COLUMNS: DesiredColumn[] = [
  { name: 'id', ddl: 'id TEXT' },
  { name: 'name', ddl: "name TEXT NOT NULL DEFAULT ''" },
  { name: 'category', ddl: "category TEXT NOT NULL DEFAULT ''" },
  { name: 'image_uri', ddl: 'image_uri TEXT' },
  { name: 'price', ddl: 'price REAL DEFAULT 0' },
  { name: 'brand_name', ddl: "brand_name TEXT DEFAULT ''" },
  { name: 'types', ddl: "types TEXT DEFAULT ''" },
  { name: 'colors', ddl: "colors TEXT DEFAULT ''" },
  { name: 'sizes', ddl: "sizes TEXT DEFAULT ''" },
  { name: 'length', ddl: "length TEXT DEFAULT ''" },
  { name: 'condition', ddl: "condition TEXT DEFAULT '全新'" },
  { name: 'note', ddl: "note TEXT DEFAULT ''" },
  { name: 'original_price', ddl: 'original_price REAL DEFAULT 0' },
  { name: 'deposit', ddl: 'deposit REAL DEFAULT 0' },
  { name: 'balance', ddl: 'balance REAL DEFAULT 0' },
  { name: 'accessories_price', ddl: 'accessories_price REAL DEFAULT 0' },
  { name: 'stock', ddl: 'stock INTEGER DEFAULT 1' },
  { name: 'purchased_at', ddl: 'purchased_at INTEGER' },
  { name: 'deposit_date', ddl: 'deposit_date INTEGER' },
  { name: 'is_deposit_plan', ddl: 'is_deposit_plan INTEGER DEFAULT 0' },
  { name: 'final_payment_date', ddl: 'final_payment_date INTEGER' },
  { name: 'final_payment_end_date', ddl: 'final_payment_end_date INTEGER' },
  { name: 'created_at', ddl: 'created_at INTEGER NOT NULL DEFAULT 0' },
  { name: 'updated_at', ddl: 'updated_at INTEGER NOT NULL DEFAULT 0' },
  { name: 'is_deleted', ddl: 'is_deleted INTEGER DEFAULT 0' },
  { name: 'sort_index', ddl: 'sort_index INTEGER DEFAULT 0' }
];

const TAG_COLUMNS: DesiredColumn[] = [
  { name: 'id', ddl: 'id TEXT' },
  { name: 'name', ddl: "name TEXT NOT NULL DEFAULT ''" },
  { name: 'sort_index', ddl: 'sort_index INTEGER DEFAULT 0' },
  { name: 'created_at', ddl: 'created_at INTEGER NOT NULL DEFAULT 0' }
];

export class RdbStoreProvider {
  private storePromises: Map<string, Promise<relationalStore.RdbStore>> =
    new Map<string, Promise<relationalStore.RdbStore>>();

  async getStore(context: common.Context): Promise<relationalStore.RdbStore> {
    const key = this.cacheKey(context);
    const cached = this.storePromises.get(key);
    if (cached) {
      return cached;
    }

    const promise = this.openStore(context);
    this.storePromises.set(key, promise);
    try {
      return await promise;
    } catch (err) {
      this.storePromises.delete(key);
      const message = err instanceof Error ? err.message : String(err);
      throw new Error('[RDB] openStore failed: ' + message);
    }
  }

  async close(context?: common.Context): Promise<void> {
    if (context) {
      const key = this.cacheKey(context);
      const promise = this.storePromises.get(key);
      if (!promise) {
        return;
      }
      this.storePromises.delete(key);
      const store = await promise;
      await store.close();
      AppLogger.info('[RDB] closed store for ' + key);
      return;
    }

    const promises: Promise<relationalStore.RdbStore>[] = [];
    this.storePromises.forEach((promise: Promise<relationalStore.RdbStore>) => {
      promises.push(promise);
    });
    this.storePromises.clear();
    for (const promise of promises) {
      const store = await promise;
      await store.close();
    }
    AppLogger.info('[RDB] closed all stores');
  }

  private async openStore(context: common.Context): Promise<relationalStore.RdbStore> {
    const config: relationalStore.StoreConfig = {
      name: DatabaseSchema.name,
      securityLevel: relationalStore.SecurityLevel.S1
    };
    AppLogger.info(`[RDB] opening ${DatabaseSchema.name}, databaseDir=${context.databaseDir}`);
    const store = await relationalStore.getRdbStore(context, config);
    await this.ensureSchema(store);
    return store;
  }

  private cacheKey(context: common.Context): string {
    return context.databaseDir;
  }

  private async ensureSchema(store: relationalStore.RdbStore): Promise<void> {
    const currentVersion = store.version;
    const targetVersion = DatabaseSchema.version;

    const statements: string[] = [
      DatabaseSchema.ddl.wardrobeItems,
      DatabaseSchema.ddl.tags,
      DatabaseSchema.ddl.wardrobeItemTags,
      DatabaseSchema.ddl.petStates,
      DatabaseSchema.ddl.walletTransactions,
      DatabaseSchema.ddl.iapOrders
    ];

    for (const statement of statements) {
      await store.executeSql(statement);
    }

    if (currentVersion !== targetVersion) {
      await this.migrate(store, currentVersion, targetVersion);
      store.version = targetVersion;
    }
    AppLogger.info('RDB schema ensured');
  }

  private async migrate(store: relationalStore.RdbStore, from: number, to: number): Promise<void> {
    for (let version = from; version < to; version++) {
      const nextVersion = version + 1;
      AppLogger.info('[RDB] migrate ' + version + ' -> ' + nextVersion);
      switch (version) {
        case 0:
          await this.addCurrentSchemaMissingColumns(store);
          break;
        case 1:
          await this.addCurrentSchemaMissingColumns(store);
          break;
        case 2:
          await this.addCurrentSchemaMissingColumns(store);
          break;
        case 3:
          await this.addCurrentSchemaMissingColumns(store);
          break;
        default:
          await this.addCurrentSchemaMissingColumns(store);
          break;
      }
      AppLogger.info('[RDB] migrate ' + version + ' -> ' + nextVersion + ' done');
    }
  }

  private async addCurrentSchemaMissingColumns(store: relationalStore.RdbStore): Promise<void> {
    await this.addMissingColumns(store, 'wardrobe_items', WARDROBE_ITEM_COLUMNS);
    await this.addMissingColumns(store, 'tags', TAG_COLUMNS);
  }

  private async tableColumns(store: relationalStore.RdbStore, table: string): Promise<Set<string>> {
    const rs = await store.querySql('PRAGMA table_info(' + table + ')');
    const cols = new Set<string>();
    try {
      while (rs.goToNextRow()) {
        cols.add(rs.getString(rs.getColumnIndex('name')));
      }
    } finally {
      rs.close();
    }
    return cols;
  }

  private async addMissingColumns(
    store: relationalStore.RdbStore,
    table: string,
    desired: Array<DesiredColumn>
  ): Promise<void> {
    const cols = await this.tableColumns(store, table);
    for (const col of desired) {
      if (!cols.has(col.name)) {
        AppLogger.info('[RDB] add column ' + table + '.' + col.name);
        await store.executeSql('ALTER TABLE ' + table + ' ADD COLUMN ' + col.ddl);
      }
    }
  }
}

export const rdbStoreProvider = new RdbStoreProvider();
