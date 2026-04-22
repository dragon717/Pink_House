import { AppConstants } from "@bundle:com.pinkhouse.harmony/entry/ets/core/constants/AppConstants";
interface DatabaseDdlConfig {
    wardrobeItems: string;
    tags: string;
    wardrobeItemTags: string;
    petStates: string;
    walletTransactions: string;
    iapOrders: string;
}
interface DatabaseSchemaConfig {
    name: string;
    version: number;
    ddl: DatabaseDdlConfig;
}
export const DatabaseSchema: DatabaseSchemaConfig = {
    name: AppConstants.databaseName,
    version: AppConstants.databaseVersion,
    ddl: {
        wardrobeItems: `CREATE TABLE IF NOT EXISTS wardrobe_items (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      category TEXT NOT NULL,
      image_uri TEXT,
      price REAL DEFAULT 0,
      brand_name TEXT DEFAULT '',
      types TEXT DEFAULT '',
      colors TEXT DEFAULT '',
      sizes TEXT DEFAULT '',
      length TEXT DEFAULT '',
      condition TEXT DEFAULT '全新',
      note TEXT DEFAULT '',
      original_price REAL DEFAULT 0,
      deposit REAL DEFAULT 0,
      balance REAL DEFAULT 0,
      accessories_price REAL DEFAULT 0,
      stock INTEGER DEFAULT 1,
      purchased_at INTEGER,
      deposit_date INTEGER,
      is_deposit_plan INTEGER DEFAULT 0,
      final_payment_date INTEGER,
      final_payment_end_date INTEGER,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      is_deleted INTEGER DEFAULT 0,
      sort_index INTEGER DEFAULT 0
    )`,
        tags: `CREATE TABLE IF NOT EXISTS tags (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      sort_index INTEGER DEFAULT 0,
      created_at INTEGER NOT NULL
    )`,
        wardrobeItemTags: `CREATE TABLE IF NOT EXISTS wardrobe_item_tags (
      item_id TEXT NOT NULL,
      tag_id TEXT NOT NULL,
      PRIMARY KEY (item_id, tag_id)
    )`,
        petStates: `CREATE TABLE IF NOT EXISTS pet_states (
      id TEXT PRIMARY KEY,
      pet_key TEXT NOT NULL,
      fullness INTEGER DEFAULT 0,
      mood INTEGER DEFAULT 0,
      updated_at INTEGER NOT NULL
    )`,
        walletTransactions: `CREATE TABLE IF NOT EXISTS wallet_transactions (
      id TEXT PRIMARY KEY,
      type TEXT NOT NULL,
      amount INTEGER NOT NULL,
      source TEXT NOT NULL,
      created_at INTEGER NOT NULL
    )`,
        iapOrders: `CREATE TABLE IF NOT EXISTS iap_orders (
      order_id TEXT PRIMARY KEY,
      product_id TEXT NOT NULL,
      purchase_data TEXT NOT NULL,
      signature TEXT NOT NULL,
      status TEXT NOT NULL,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    )`
    }
};
