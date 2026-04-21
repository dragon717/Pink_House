import { AppTheme } from '../../core/theme/AppTheme';
import { AppSymbol, AppSymbolName } from '../../core/theme/AppSymbols';
import { GlassCard } from '../../core/theme/GlassComponents';

class PetChatMessage {
  id: string = '';
  text: string = '';
  isUser: boolean = false;
  timeText: string = '';

  constructor(id: string, text: string, isUser: boolean, timeText: string) {
    this.id = id;
    this.text = text;
    this.isUser = isUser;
    this.timeText = timeText;
  }
}

const QUICK_PROMPTS: string[] = ['今天穿什么好', '奶茶饿了吗', '去衣橱看看', '给我打气'];
const LOCAL_REPLIES: string[] = [
  '我先用本地小脑袋陪你，今天也要慢慢变漂亮。',
  '听到啦。先把心愿衣橱整理一下，灵感很快就会冒出来。',
  '主人可以从衣橱挑一件给我看，我会用固定规则认真点评。',
  '今天适合温柔一点，粉白和浅金都很合拍。',
  '我在这里陪着你，先完成一个小目标就很好。'
];

@Component
export struct PetPage {
  @State private inputText: string = '';
  @State private messages: PetChatMessage[] = [
    new PetChatMessage('welcome', '早上好，我是奶茶。这里先保留聊天入口、历史气泡和固定回复，后续再接宠物状态与序列帧动画。', false, '刚刚')
  ];
  @State private moodText: string = '开心';
  @State private fullness: number = 76;
  @State private energy: number = 64;
  onOpenWardrobe: () => void = () => {};

  private nextReply(seed: string): string {
    const index = (this.messages.length + seed.length) % LOCAL_REPLIES.length;
    return LOCAL_REPLIES[index];
  }

  private appendMessage(text: string, isUser: boolean): void {
    const safeText = text.trim();
    if (safeText.length === 0) {
      return;
    }
    const id = `${isUser ? 'u' : 'p'}-${Date.now()}-${this.messages.length}`;
    this.messages = [...this.messages, new PetChatMessage(id, safeText, isUser, '刚刚')];
  }

  private sendText(text: string): void {
    const safeText = text.trim();
    if (safeText.length === 0) {
      return;
    }

    this.appendMessage(safeText, true);
    this.appendMessage(this.nextReply(safeText), false);
    this.inputText = '';
  }

  private handlePetAction(kind: string): void {
    if (kind === 'feed') {
      this.fullness = Math.min(100, this.fullness + 8);
      this.moodText = '满足';
      this.appendMessage('小鱼干很好吃，我有精神继续陪你啦。', false);
    } else if (kind === 'drink') {
      this.energy = Math.min(100, this.energy + 6);
      this.moodText = '清爽';
      this.appendMessage('喝到水了，尾巴都变轻快了。', false);
    } else if (kind === 'work') {
      this.energy = Math.max(12, this.energy - 10);
      this.moodText = '努力';
      this.appendMessage('我去打工一会儿，回来给你带喵币。', false);
    } else {
      this.moodText = '撒娇';
      this.appendMessage('被摸摸了，今天的心情直接加满。', false);
    }
  }

  @Builder
  private Header() {
    Row() {
      Column({ space: 3 }) {
        Text('萌宠对话')
          .fontSize(AppTheme.font.displayMedium)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.color.textPrimary)
        Text('奶茶在线 · 本地规则回复')
          .fontSize(AppTheme.font.caption)
          .fontColor(AppTheme.color.textSecondary)
      }
      .alignItems(HorizontalAlign.Start)

      Blank()
        .layoutWeight(1)

      Text('衣橱')
        .fontSize(AppTheme.font.caption)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.color.primary)
        .padding({ left: 16, right: 16, top: 10, bottom: 10 })
        .backgroundColor(AppTheme.color.overlayGlassStrong)
        .backgroundBlurStyle(BlurStyle.Thin)
        .borderRadius(AppTheme.radius.pill)
        .border({ width: 1, color: AppTheme.color.border })
        .onClick(() => {
          this.onOpenWardrobe();
        })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private StatusChip(title: string, value: string, tintColor: string) {
    Column({ space: 3 }) {
      Text(value)
        .fontSize(AppTheme.font.titleMedium)
        .fontWeight(FontWeight.Bold)
        .fontColor(tintColor)
      Text(title)
        .fontSize(AppTheme.font.tiny)
        .fontColor(AppTheme.color.textSecondary)
    }
    .layoutWeight(1)
    .height(58)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(AppTheme.color.surfaceTint)
    .borderRadius(AppTheme.radius.tile)
  }

  @Builder
  private PetStage() {
    GlassCard({ innerPadding: 16, cornerRadius: AppTheme.radius.cardLarge }) {
      Column({ space: 14 }) {
        Row({ space: 16 }) {
          Stack() {
            Circle({ width: 148, height: 148 })
              .fill(AppTheme.color.primaryPale)
            Image($r('app.media.pet_cat_peek'))
              .width(172)
              .height(104)
              .objectFit(ImageFit.Contain)
              .margin({ top: 24 })
          }
          .width(164)
          .height(156)

          Column({ space: 10 }) {
            Text('今天也在衣橱旁边等你')
              .fontSize(AppTheme.font.titleMedium)
              .fontWeight(FontWeight.Bold)
              .fontColor(AppTheme.color.textPrimary)
              .width('100%')
            Text('当前先用固定文案、状态条和入口骨架完成复刻；投喂、喝水、打工会即时更新页面状态。')
              .fontSize(AppTheme.font.caption)
              .lineHeight(20)
              .fontColor(AppTheme.color.textSecondary)
              .width('100%')
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')

        Row({ space: 10 }) {
          this.StatusChip('饱食度', `${this.fullness}%`, AppTheme.color.petOrange);
          this.StatusChip('心情', this.moodText, AppTheme.color.primary);
          this.StatusChip('体力', `${this.energy}%`, AppTheme.color.houseBlue);
        }
        .width('100%')
      }
      .width('100%')
    }
  }

  @Builder
  private ActionButton(label: string, symbolName: string, onTap: () => void) {
    Column({ space: 6 }) {
      AppSymbol({
        name: symbolName,
        iconSize: 25,
        color: AppTheme.color.primary
      })
      Text(label)
        .fontSize(AppTheme.font.caption)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.color.textPrimary)
    }
    .layoutWeight(1)
    .height(78)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(AppTheme.color.overlayGlassStrong)
    .backgroundBlurStyle(BlurStyle.Thin)
    .borderRadius(AppTheme.radius.tile)
    .border({ width: 1, color: AppTheme.color.border })
    .onClick(onTap)
  }

  @Builder
  private ActionRow() {
    Row({ space: 10 }) {
      this.ActionButton('投喂', AppSymbolName.Feed, () => {
        this.handlePetAction('feed');
      });
      this.ActionButton('喝水', AppSymbolName.Drink, () => {
        this.handlePetAction('drink');
      });
      this.ActionButton('打工', AppSymbolName.Work, () => {
        this.handlePetAction('work');
      });
      this.ActionButton('摸摸', AppSymbolName.Touch, () => {
        this.handlePetAction('touch');
      });
    }
    .width('100%')
  }

  @Builder
  private ChatBubble(message: PetChatMessage) {
    Row() {
      if (message.isUser) {
        Blank()
          .layoutWeight(1)
      }

      Column({ space: 4 }) {
        Text(message.text)
          .fontSize(AppTheme.font.body)
          .lineHeight(22)
          .fontColor(message.isUser ? AppTheme.color.textOnPrimary : AppTheme.color.textPrimary)
        Text(message.timeText)
          .fontSize(AppTheme.font.tiny)
          .fontColor(message.isUser ? 'rgba(255, 255, 255, 0.70)' : AppTheme.color.textTertiary)
      }
      .padding({ left: 14, right: 14, top: 10, bottom: 10 })
      .backgroundColor(message.isUser ? AppTheme.color.primary : AppTheme.color.surfaceTint)
      .borderRadius(AppTheme.radius.card)
      .constraintSize({ maxWidth: '78%' })

      if (!message.isUser) {
        Blank()
          .layoutWeight(1)
      }
    }
    .width('100%')
  }

  @Builder
  private ChatPanel() {
    GlassCard({ innerPadding: 14, cornerRadius: AppTheme.radius.cardLarge }) {
      Column({ space: 12 }) {
        Row() {
          Text('对话记录')
            .fontSize(AppTheme.font.titleMedium)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppTheme.color.textPrimary)
          Blank()
          Text('固定回复')
            .fontSize(AppTheme.font.tiny)
            .fontColor(AppTheme.color.primary)
            .padding({ left: 10, right: 10, top: 5, bottom: 5 })
            .backgroundColor(AppTheme.color.primaryPale)
            .borderRadius(AppTheme.radius.pill)
        }
        .width('100%')

        Column({ space: 10 }) {
          ForEach(this.messages, (message: PetChatMessage) => {
            this.ChatBubble(message);
          }, (message: PetChatMessage) => message.id)
        }
        .width('100%')
      }
      .width('100%')
    }
  }

  @Builder
  private QuickPrompts() {
    Row({ space: 8 }) {
      ForEach(QUICK_PROMPTS, (prompt: string) => {
        Text(prompt)
          .fontSize(AppTheme.font.tiny)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.color.primary)
          .padding({ left: 11, right: 11, top: 7, bottom: 7 })
          .backgroundColor(AppTheme.color.primaryPale)
          .borderRadius(AppTheme.radius.pill)
          .onClick(() => {
            this.sendText(prompt);
          })
      }, (prompt: string) => prompt)
    }
    .width('100%')
  }

  @Builder
  private Composer() {
    Column({ space: 10 }) {
      this.QuickPrompts();

      Row({ space: 10 }) {
        TextInput({ placeholder: '和奶茶说点什么...', text: this.inputText })
          .height(48)
          .fontSize(AppTheme.font.body)
          .fontColor(AppTheme.color.textPrimary)
          .placeholderColor(AppTheme.color.textTertiary)
          .backgroundColor(AppTheme.color.overlayGlassStrong)
          .backgroundBlurStyle(BlurStyle.Thin)
          .borderRadius(AppTheme.radius.pill)
          .layoutWeight(1)
          .onChange((value: string) => {
            this.inputText = value;
          })

        Text('发送')
          .fontSize(AppTheme.font.body)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.color.textOnPrimary)
          .padding({ left: 18, right: 18, top: 13, bottom: 13 })
          .backgroundColor(this.inputText.trim().length > 0 ? AppTheme.color.primary : AppTheme.color.primarySoft)
          .borderRadius(AppTheme.radius.pill)
          .onClick(() => {
            this.sendText(this.inputText);
          })
      }
      .width('100%')
    }
    .width('100%')
  }

  build() {
    Scroll() {
      Column({ space: 16 }) {
        this.Header();
        this.PetStage();
        this.ActionRow();
        this.ChatPanel();
        this.Composer();
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({
        left: AppTheme.spacing.page,
        right: AppTheme.spacing.page,
        top: 18,
        bottom: 150
      })
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .backgroundColor(Color.Transparent)
  }
}
