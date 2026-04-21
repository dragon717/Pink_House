import { AppTheme } from './AppTheme';

export class AppSymbolName {
  static readonly Wardrobe: string = 'wardrobe';
  static readonly House: string = 'house';
  static readonly Me: string = 'me';
  static readonly Pet: string = 'pet';
  static readonly Deposit: string = 'deposit';
  static readonly Outfit: string = 'outfit';
  static readonly Wealth: string = 'wealth';
  static readonly Calendar: string = 'calendar';
  static readonly Perler: string = 'perler';
  static readonly Sort: string = 'sort';
  static readonly Filter: string = 'filter';
  static readonly Grid: string = 'grid';
  static readonly More: string = 'more';
  static readonly Close: string = 'close';
  static readonly Add: string = 'add';
  static readonly Search: string = 'search';
  static readonly Edit: string = 'edit';
  static readonly Stats: string = 'stats';
  static readonly Import: string = 'import';
  static readonly Spark: string = 'spark';
  static readonly Reminder: string = 'reminder';
  static readonly Series: string = 'series';
  static readonly Share: string = 'share';
  static readonly Back: string = 'back';
  static readonly Info: string = 'info';
  static readonly Color: string = 'color';
  static readonly Size: string = 'symbolSize';
  static readonly Length: string = 'length';
  static readonly State: string = 'state';
  static readonly Feed: string = 'feed';
  static readonly Drink: string = 'drink';
  static readonly Work: string = 'work';
  static readonly Touch: string = 'touch';
}

@Component
export struct AppSymbol {
  @Prop name: string = AppSymbolName.More;
  @Prop iconSize: number = 20;
  @Prop color: ResourceColor = AppTheme.color.textPrimary;

  @Builder
  private NativeGlyph(symbol: Resource) {
    SymbolGlyph(symbol)
      .fontSize(this.iconSize)
      .fontColor([this.color])
      .fontWeight(FontWeight.Medium)
  }

  build() {
    if (this.name === AppSymbolName.Wardrobe) {
      this.NativeGlyph($r('sys.symbol.shirt'));
    } else if (this.name === AppSymbolName.House) {
      this.NativeGlyph($r('sys.symbol.house'));
    } else if (this.name === AppSymbolName.Me) {
      this.NativeGlyph($r('sys.symbol.person_crop_circle_fill_1'));
    } else if (this.name === AppSymbolName.Pet) {
      this.NativeGlyph($r('sys.symbol.face_smiling_plus'));
    } else if (this.name === AppSymbolName.Deposit) {
      this.NativeGlyph($r('sys.symbol.card'));
    } else if (this.name === AppSymbolName.Outfit) {
      this.NativeGlyph($r('sys.symbol.square_and_pencil'));
    } else if (this.name === AppSymbolName.Wealth) {
      this.NativeGlyph($r('sys.symbol.yuansign_moneybag'));
    } else if (this.name === AppSymbolName.Calendar) {
      this.NativeGlyph($r('sys.symbol.calendar_1'));
    } else if (this.name === AppSymbolName.Perler) {
      this.NativeGlyph($r('sys.symbol.puzzle'));
    } else if (this.name === AppSymbolName.Sort) {
      this.NativeGlyph($r('sys.symbol.sort'));
    } else if (this.name === AppSymbolName.Filter) {
      this.NativeGlyph($r('sys.symbol.funnel'));
    } else if (this.name === AppSymbolName.Grid) {
      this.NativeGlyph($r('sys.symbol.square_grid_2x2'));
    } else if (this.name === AppSymbolName.More) {
      this.NativeGlyph($r('sys.symbol.more'));
    } else if (this.name === AppSymbolName.Close) {
      this.NativeGlyph($r('sys.symbol.xmark'));
    } else if (this.name === AppSymbolName.Add) {
      this.NativeGlyph($r('sys.symbol.plus'));
    } else if (this.name === AppSymbolName.Search) {
      this.NativeGlyph($r('sys.symbol.magnifyingglass'));
    } else if (this.name === AppSymbolName.Edit) {
      this.NativeGlyph($r('sys.symbol.square_and_pencil'));
    } else if (this.name === AppSymbolName.Stats) {
      this.NativeGlyph($r('sys.symbol.histogram'));
    } else if (this.name === AppSymbolName.Import) {
      this.NativeGlyph($r('sys.symbol.arrow_left_arrow_right'));
    } else if (this.name === AppSymbolName.Spark) {
      this.NativeGlyph($r('sys.symbol.wand_and_stars'));
    } else if (this.name === AppSymbolName.Reminder) {
      this.NativeGlyph($r('sys.symbol.alarm_1'));
    } else if (this.name === AppSymbolName.Series) {
      this.NativeGlyph($r('sys.symbol.basket'));
    } else if (this.name === AppSymbolName.Share) {
      this.NativeGlyph($r('sys.symbol.share'));
    } else if (this.name === AppSymbolName.Back) {
      this.NativeGlyph($r('sys.symbol.arrow_left_arrow_right'));
    } else if (this.name === AppSymbolName.Info) {
      this.NativeGlyph($r('sys.symbol.shirt'));
    } else if (this.name === AppSymbolName.Color) {
      this.NativeGlyph($r('sys.symbol.paintpalette'));
    } else if (this.name === AppSymbolName.Size) {
      this.NativeGlyph($r('sys.symbol.square'));
    } else if (this.name === AppSymbolName.Length) {
      this.NativeGlyph($r('sys.symbol.arrow_up'));
    } else if (this.name === AppSymbolName.State) {
      this.NativeGlyph($r('sys.symbol.checkmark_circle'));
    } else if (this.name === AppSymbolName.Feed) {
      this.NativeGlyph($r('sys.symbol.basket'));
    } else if (this.name === AppSymbolName.Drink) {
      this.NativeGlyph($r('sys.symbol.drop'));
    } else if (this.name === AppSymbolName.Work) {
      this.NativeGlyph($r('sys.symbol.yuansign_moneybag'));
    } else if (this.name === AppSymbolName.Touch) {
      this.NativeGlyph($r('sys.symbol.hand_stars'));
    } else {
      this.NativeGlyph($r('sys.symbol.more'));
    }
  }
}
