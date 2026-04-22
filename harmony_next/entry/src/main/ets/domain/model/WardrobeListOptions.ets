export enum WardrobeSortOption {
  CreatedAtDesc = 'createdAtDesc',
  PriceAsc = 'priceAsc',
  PriceDesc = 'priceDesc',
  PurchaseDateAsc = 'purchaseDateAsc',
  PurchaseDateDesc = 'purchaseDateDesc',
  NameAsc = 'nameAsc',
  NameDesc = 'nameDesc',
  Custom = 'custom'
}

export enum WardrobeViewLayout {
  ListBrief = 'listBrief',
  ListDetailed = 'listDetailed',
  Grid2 = 'grid2',
  Grid3 = 'grid3',
  Grid6 = 'grid6'
}

export enum DepositStatusFilter {
  All = 'all',
  Owned = 'owned',
  DepositPlan = 'depositPlan'
}

export const DefaultSortOption: WardrobeSortOption = WardrobeSortOption.CreatedAtDesc;
export const DefaultViewLayout: WardrobeViewLayout = WardrobeViewLayout.Grid2;

export interface WardrobeFilterState {
  tagIds: string[];
  brandNames: string[];
  types: string[];
  colors: string[];
  sizes: string[];
  lengths: string[];
  conditions: string[];
  depositStatus: DepositStatusFilter;
}

export function createDefaultFilter(): WardrobeFilterState {
  const filter: WardrobeFilterState = {
    tagIds: [],
    brandNames: [],
    types: [],
    colors: [],
    sizes: [],
    lengths: [],
    conditions: [],
    depositStatus: DepositStatusFilter.All
  };
  return filter;
}

export function isFilterActive(filter: WardrobeFilterState): boolean {
  return filter.tagIds.length > 0 ||
    filter.brandNames.length > 0 ||
    filter.types.length > 0 ||
    filter.colors.length > 0 ||
    filter.sizes.length > 0 ||
    filter.lengths.length > 0 ||
    filter.conditions.length > 0 ||
    filter.depositStatus !== DepositStatusFilter.All;
}

export function countActiveFilters(filter: WardrobeFilterState): number {
  return filter.tagIds.length +
    filter.brandNames.length +
    filter.types.length +
    filter.colors.length +
    filter.sizes.length +
    filter.lengths.length +
    filter.conditions.length +
    (filter.depositStatus !== DepositStatusFilter.All ? 1 : 0);
}

export function sortOptionLabel(opt: WardrobeSortOption): string {
  switch (opt) {
    case WardrobeSortOption.CreatedAtDesc: return '添加时间从晚到早';
    case WardrobeSortOption.PriceAsc: return '价格从低到高';
    case WardrobeSortOption.PriceDesc: return '价格从高到低';
    case WardrobeSortOption.PurchaseDateAsc: return '购买时间从早到晚';
    case WardrobeSortOption.PurchaseDateDesc: return '购买时间从晚到早';
    case WardrobeSortOption.NameAsc: return '名称从A到Z';
    case WardrobeSortOption.NameDesc: return '名称从Z到A';
    case WardrobeSortOption.Custom: return '自定义顺序';
    default: return '添加时间从晚到早';
  }
}

export function sortOptionSymbol(opt: WardrobeSortOption): string {
  switch (opt) {
    case WardrobeSortOption.CreatedAtDesc: return 'sys.symbol.clock';
    case WardrobeSortOption.PriceAsc: return 'sys.symbol.arrow_up_arrow_down';
    case WardrobeSortOption.PriceDesc: return 'sys.symbol.arrow_up_arrow_down';
    case WardrobeSortOption.PurchaseDateAsc: return 'sys.symbol.calendar';
    case WardrobeSortOption.PurchaseDateDesc: return 'sys.symbol.calendar';
    case WardrobeSortOption.NameAsc: return 'sys.symbol.textformat';
    case WardrobeSortOption.NameDesc: return 'sys.symbol.textformat';
    case WardrobeSortOption.Custom: return 'sys.symbol.hand_draw';
    default: return 'sys.symbol.clock';
  }
}

export function viewLayoutLabel(layout: WardrobeViewLayout): string {
  switch (layout) {
    case WardrobeViewLayout.ListBrief: return '单行简略';
    case WardrobeViewLayout.ListDetailed: return '单行详细';
    case WardrobeViewLayout.Grid2: return '双列';
    case WardrobeViewLayout.Grid3: return '三列';
    case WardrobeViewLayout.Grid6: return '六列';
    default: return '双列';
  }
}

export function viewLayoutColumnCount(layout: WardrobeViewLayout): number {
  switch (layout) {
    case WardrobeViewLayout.Grid2: return 2;
    case WardrobeViewLayout.Grid3: return 3;
    case WardrobeViewLayout.Grid6: return 6;
    default: return 1;
  }
}

export function isListMode(layout: WardrobeViewLayout): boolean {
  return layout === WardrobeViewLayout.ListBrief || layout === WardrobeViewLayout.ListDetailed;
}

export function depositStatusLabel(status: DepositStatusFilter): string {
  switch (status) {
    case DepositStatusFilter.All: return '全部';
    case DepositStatusFilter.Owned: return '已拥有/全款';
    case DepositStatusFilter.DepositPlan: return '心愿尾款';
    default: return '全部';
  }
}

export function parseSortOption(raw: string): WardrobeSortOption {
  switch (raw) {
    case WardrobeSortOption.CreatedAtDesc: return WardrobeSortOption.CreatedAtDesc;
    case WardrobeSortOption.PriceAsc: return WardrobeSortOption.PriceAsc;
    case WardrobeSortOption.PriceDesc: return WardrobeSortOption.PriceDesc;
    case WardrobeSortOption.PurchaseDateAsc: return WardrobeSortOption.PurchaseDateAsc;
    case WardrobeSortOption.PurchaseDateDesc: return WardrobeSortOption.PurchaseDateDesc;
    case WardrobeSortOption.NameAsc: return WardrobeSortOption.NameAsc;
    case WardrobeSortOption.NameDesc: return WardrobeSortOption.NameDesc;
    case WardrobeSortOption.Custom: return WardrobeSortOption.Custom;
    default: return DefaultSortOption;
  }
}

export function parseViewLayout(raw: string): WardrobeViewLayout {
  switch (raw) {
    case WardrobeViewLayout.ListBrief: return WardrobeViewLayout.ListBrief;
    case WardrobeViewLayout.ListDetailed: return WardrobeViewLayout.ListDetailed;
    case WardrobeViewLayout.Grid2: return WardrobeViewLayout.Grid2;
    case WardrobeViewLayout.Grid3: return WardrobeViewLayout.Grid3;
    case WardrobeViewLayout.Grid6: return WardrobeViewLayout.Grid6;
    default: return DefaultViewLayout;
  }
}

export const AllSortOptions: WardrobeSortOption[] = [
  WardrobeSortOption.CreatedAtDesc,
  WardrobeSortOption.PriceAsc,
  WardrobeSortOption.PriceDesc,
  WardrobeSortOption.PurchaseDateAsc,
  WardrobeSortOption.PurchaseDateDesc,
  WardrobeSortOption.NameAsc,
  WardrobeSortOption.NameDesc,
  WardrobeSortOption.Custom
];

export const AllViewLayouts: WardrobeViewLayout[] = [
  WardrobeViewLayout.ListBrief,
  WardrobeViewLayout.ListDetailed,
  WardrobeViewLayout.Grid2,
  WardrobeViewLayout.Grid3,
  WardrobeViewLayout.Grid6
];

export const AllDepositStatus: DepositStatusFilter[] = [
  DepositStatusFilter.All,
  DepositStatusFilter.Owned,
  DepositStatusFilter.DepositPlan
];
