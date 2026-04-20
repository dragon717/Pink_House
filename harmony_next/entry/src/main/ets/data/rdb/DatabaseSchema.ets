import { AppConstants } from '../../core/constants/AppConstants';

interface DatabaseDdlConfig {
  wardrobeItems: string;
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
      purchased_at INTEGER,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      is_deleted INTEGER DEFAULT 0
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
