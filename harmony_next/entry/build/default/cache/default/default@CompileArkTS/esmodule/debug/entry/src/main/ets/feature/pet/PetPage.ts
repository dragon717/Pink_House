if (!("finalizeConstruction" in ViewPU.prototype)) {
    Reflect.set(ViewPU.prototype, "finalizeConstruction", () => { });
}
interface PetPage_Params {
    inputText?: string;
    messages?: PetChatMessage[];
    moodText?: string;
    fullness?: number;
    energy?: number;
    onOpenWardrobe?: () => void;
}
import { AppTheme } from "@bundle:com.pinkhouse.harmony/entry/ets/core/theme/AppTheme";
import { AppSymbol, AppSymbolName } from "@bundle:com.pinkhouse.harmony/entry/ets/core/theme/AppSymbols";
import { GlassCard } from "@bundle:com.pinkhouse.harmony/entry/ets/core/theme/GlassComponents";
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
export class PetPage extends ViewPU {
    constructor(parent, params, __localStorage, elmtId = -1, paramsLambda = undefined, extraInfo) {
        super(parent, __localStorage, elmtId, extraInfo);
        if (typeof paramsLambda === "function") {
            this.paramsGenerator_ = paramsLambda;
        }
        this.__inputText = new ObservedPropertySimplePU('', this, "inputText");
        this.__messages = new ObservedPropertyObjectPU([
            new PetChatMessage('welcome', '早上好，我是奶茶。这里先保留聊天入口、历史气泡和固定回复，后续再接宠物状态与序列帧动画。', false, '刚刚')
        ], this, "messages");
        this.__moodText = new ObservedPropertySimplePU('开心', this, "moodText");
        this.__fullness = new ObservedPropertySimplePU(76, this, "fullness");
        this.__energy = new ObservedPropertySimplePU(64, this, "energy");
        this.onOpenWardrobe = () => { };
        this.setInitiallyProvidedValue(params);
        this.finalizeConstruction();
    }
    setInitiallyProvidedValue(params: PetPage_Params) {
        if (params.inputText !== undefined) {
            this.inputText = params.inputText;
        }
        if (params.messages !== undefined) {
            this.messages = params.messages;
        }
        if (params.moodText !== undefined) {
            this.moodText = params.moodText;
        }
        if (params.fullness !== undefined) {
            this.fullness = params.fullness;
        }
        if (params.energy !== undefined) {
            this.energy = params.energy;
        }
        if (params.onOpenWardrobe !== undefined) {
            this.onOpenWardrobe = params.onOpenWardrobe;
        }
    }
    updateStateVars(params: PetPage_Params) {
    }
    purgeVariableDependenciesOnElmtId(rmElmtId) {
        this.__inputText.purgeDependencyOnElmtId(rmElmtId);
        this.__messages.purgeDependencyOnElmtId(rmElmtId);
        this.__moodText.purgeDependencyOnElmtId(rmElmtId);
        this.__fullness.purgeDependencyOnElmtId(rmElmtId);
        this.__energy.purgeDependencyOnElmtId(rmElmtId);
    }
    aboutToBeDeleted() {
        this.__inputText.aboutToBeDeleted();
        this.__messages.aboutToBeDeleted();
        this.__moodText.aboutToBeDeleted();
        this.__fullness.aboutToBeDeleted();
        this.__energy.aboutToBeDeleted();
        SubscriberManager.Get().delete(this.id__());
        this.aboutToBeDeletedInternal();
    }
    private __inputText: ObservedPropertySimplePU<string>;
    get inputText() {
        return this.__inputText.get();
    }
    set inputText(newValue: string) {
        this.__inputText.set(newValue);
    }
    private __messages: ObservedPropertyObjectPU<PetChatMessage[]>;
    get messages() {
        return this.__messages.get();
    }
    set messages(newValue: PetChatMessage[]) {
        this.__messages.set(newValue);
    }
    private __moodText: ObservedPropertySimplePU<string>;
    get moodText() {
        return this.__moodText.get();
    }
    set moodText(newValue: string) {
        this.__moodText.set(newValue);
    }
    private __fullness: ObservedPropertySimplePU<number>;
    get fullness() {
        return this.__fullness.get();
    }
    set fullness(newValue: number) {
        this.__fullness.set(newValue);
    }
    private __energy: ObservedPropertySimplePU<number>;
    get energy() {
        return this.__energy.get();
    }
    set energy(newValue: number) {
        this.__energy.set(newValue);
    }
    private onOpenWardrobe: () => void;
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
        }
        else if (kind === 'drink') {
            this.energy = Math.min(100, this.energy + 6);
            this.moodText = '清爽';
            this.appendMessage('喝到水了，尾巴都变轻快了。', false);
        }
        else if (kind === 'work') {
            this.energy = Math.max(12, this.energy - 10);
            this.moodText = '努力';
            this.appendMessage('我去打工一会儿，回来给你带喵币。', false);
        }
        else {
            this.moodText = '撒娇';
            this.appendMessage('被摸摸了，今天的心情直接加满。', false);
        }
    }
    private Header(parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Row.create();
            Row.width('100%');
            Row.alignItems(VerticalAlign.Center);
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create({ space: 3 });
            Column.alignItems(HorizontalAlign.Start);
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create('萌宠对话');
            Text.fontSize(AppTheme.font.displayMedium);
            Text.fontWeight(FontWeight.Bold);
            Text.fontColor(AppTheme.color.textPrimary);
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create('奶茶在线 · 本地规则回复');
            Text.fontSize(AppTheme.font.caption);
            Text.fontColor(AppTheme.color.textSecondary);
        }, Text);
        Text.pop();
        Column.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Blank.create();
            Blank.layoutWeight(1);
        }, Blank);
        Blank.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create('衣橱');
            Text.fontSize(AppTheme.font.caption);
            Text.fontWeight(FontWeight.Bold);
            Text.fontColor(AppTheme.color.primary);
            Text.padding({ left: 16, right: 16, top: 10, bottom: 10 });
            Text.backgroundColor(AppTheme.color.overlayGlassStrong);
            Text.backgroundBlurStyle(BlurStyle.Thin);
            Text.borderRadius(AppTheme.radius.pill);
            Text.border({ width: 1, color: AppTheme.color.border });
            Text.onClick(() => {
                this.onOpenWardrobe();
            });
        }, Text);
        Text.pop();
        Row.pop();
    }
    private StatusChip(title: string, value: string, tintColor: string, parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create({ space: 3 });
            Column.layoutWeight(1);
            Column.height(58);
            Column.justifyContent(FlexAlign.Center);
            Column.backgroundColor(AppTheme.color.surfaceTint);
            Column.borderRadius(AppTheme.radius.tile);
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(value);
            Text.fontSize(AppTheme.font.titleMedium);
            Text.fontWeight(FontWeight.Bold);
            Text.fontColor(tintColor);
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(title);
            Text.fontSize(AppTheme.font.tiny);
            Text.fontColor(AppTheme.color.textSecondary);
        }, Text);
        Text.pop();
        Column.pop();
    }
    private PetStage(parent = null) {
        {
            this.observeComponentCreation2((elmtId, isInitialRender) => {
                if (isInitialRender) {
                    let componentCall = new GlassCard(this, {
                        innerPadding: 16, cornerRadius: AppTheme.radius.cardLarge,
                        content: () => {
                            this.observeComponentCreation2((elmtId, isInitialRender) => {
                                Column.create({ space: 14 });
                                Column.width('100%');
                            }, Column);
                            this.observeComponentCreation2((elmtId, isInitialRender) => {
                                Row.create({ space: 16 });
                                Row.width('100%');
                            }, Row);
                            this.observeComponentCreation2((elmtId, isInitialRender) => {
                                Stack.create();
                                Stack.width(164);
                                Stack.height(156);
                            }, Stack);
                            this.observeComponentCreation2((elmtId, isInitialRender) => {
                                Circle.create({ width: 148, height: 148 });
                                Circle.fill(AppTheme.color.primaryPale);
                            }, Circle);
                            this.observeComponentCreation2((elmtId, isInitialRender) => {
                                Image.create({ "id": 16777227, "type": 20000, params: [], "bundleName": "com.pinkhouse.harmony", "moduleName": "entry" });
                                Image.width(172);
                                Image.height(104);
                                Image.objectFit(ImageFit.Contain);
                                Image.margin({ top: 24 });
                            }, Image);
                            Stack.pop();
                            this.observeComponentCreation2((elmtId, isInitialRender) => {
                                Column.create({ space: 10 });
                                Column.layoutWeight(1);
                                Column.alignItems(HorizontalAlign.Start);
                            }, Column);
                            this.observeComponentCreation2((elmtId, isInitialRender) => {
                                Text.create('今天也在衣橱旁边等你');
                                Text.fontSize(AppTheme.font.titleMedium);
                                Text.fontWeight(FontWeight.Bold);
                                Text.fontColor(AppTheme.color.textPrimary);
                                Text.width('100%');
                            }, Text);
                            Text.pop();
                            this.observeComponentCreation2((elmtId, isInitialRender) => {
                                Text.create('当前先用固定文案、状态条和入口骨架完成复刻；投喂、喝水、打工会即时更新页面状态。');
                                Text.fontSize(AppTheme.font.caption);
                                Text.lineHeight(20);
                                Text.fontColor(AppTheme.color.textSecondary);
                                Text.width('100%');
                            }, Text);
                            Text.pop();
                            Column.pop();
                            Row.pop();
                            this.observeComponentCreation2((elmtId, isInitialRender) => {
                                Row.create({ space: 10 });
                                Row.width('100%');
                            }, Row);
                            this.StatusChip.bind(this)('饱食度', `${this.fullness}%`, AppTheme.color.petOrange);
                            this.StatusChip.bind(this)('心情', this.moodText, AppTheme.color.primary);
                            this.StatusChip.bind(this)('体力', `${this.energy}%`, AppTheme.color.houseBlue);
                            Row.pop();
                            Column.pop();
                        }
                    }, undefined, elmtId, () => { }, { page: "entry/src/main/ets/feature/pet/PetPage.ets", line: 137, col: 5 });
                    ViewPU.create(componentCall);
                    let paramsLambda = () => {
                        return {
                            innerPadding: 16,
                            cornerRadius: AppTheme.radius.cardLarge,
                            content: () => {
                                this.observeComponentCreation2((elmtId, isInitialRender) => {
                                    Column.create({ space: 14 });
                                    Column.width('100%');
                                }, Column);
                                this.observeComponentCreation2((elmtId, isInitialRender) => {
                                    Row.create({ space: 16 });
                                    Row.width('100%');
                                }, Row);
                                this.observeComponentCreation2((elmtId, isInitialRender) => {
                                    Stack.create();
                                    Stack.width(164);
                                    Stack.height(156);
                                }, Stack);
                                this.observeComponentCreation2((elmtId, isInitialRender) => {
                                    Circle.create({ width: 148, height: 148 });
                                    Circle.fill(AppTheme.color.primaryPale);
                                }, Circle);
                                this.observeComponentCreation2((elmtId, isInitialRender) => {
                                    Image.create({ "id": 16777227, "type": 20000, params: [], "bundleName": "com.pinkhouse.harmony", "moduleName": "entry" });
                                    Image.width(172);
                                    Image.height(104);
                                    Image.objectFit(ImageFit.Contain);
                                    Image.margin({ top: 24 });
                                }, Image);
                                Stack.pop();
                                this.observeComponentCreation2((elmtId, isInitialRender) => {
                                    Column.create({ space: 10 });
                                    Column.layoutWeight(1);
                                    Column.alignItems(HorizontalAlign.Start);
                                }, Column);
                                this.observeComponentCreation2((elmtId, isInitialRender) => {
                                    Text.create('今天也在衣橱旁边等你');
                                    Text.fontSize(AppTheme.font.titleMedium);
                                    Text.fontWeight(FontWeight.Bold);
                                    Text.fontColor(AppTheme.color.textPrimary);
                                    Text.width('100%');
                                }, Text);
                                Text.pop();
                                this.observeComponentCreation2((elmtId, isInitialRender) => {
                                    Text.create('当前先用固定文案、状态条和入口骨架完成复刻；投喂、喝水、打工会即时更新页面状态。');
                                    Text.fontSize(AppTheme.font.caption);
                                    Text.lineHeight(20);
                                    Text.fontColor(AppTheme.color.textSecondary);
                                    Text.width('100%');
                                }, Text);
                                Text.pop();
                                Column.pop();
                                Row.pop();
                                this.observeComponentCreation2((elmtId, isInitialRender) => {
                                    Row.create({ space: 10 });
                                    Row.width('100%');
                                }, Row);
                                this.StatusChip.bind(this)('饱食度', `${this.fullness}%`, AppTheme.color.petOrange);
                                this.StatusChip.bind(this)('心情', this.moodText, AppTheme.color.primary);
                                this.StatusChip.bind(this)('体力', `${this.energy}%`, AppTheme.color.houseBlue);
                                Row.pop();
                                Column.pop();
                            }
                        };
                    };
                    componentCall.paramsGenerator_ = paramsLambda;
                }
                else {
                    this.updateStateVarsOfChildByElmtId(elmtId, {
                        innerPadding: 16, cornerRadius: AppTheme.radius.cardLarge
                    });
                }
            }, { name: "GlassCard" });
        }
    }
    private ActionButton(label: string, symbolName: string, onTap: () => void, parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create({ space: 6 });
            Column.layoutWeight(1);
            Column.height(78);
            Column.justifyContent(FlexAlign.Center);
            Column.backgroundColor(AppTheme.color.overlayGlassStrong);
            Column.backgroundBlurStyle(BlurStyle.Thin);
            Column.borderRadius(AppTheme.radius.tile);
            Column.border({ width: 1, color: AppTheme.color.border });
            Column.onClick(onTap);
        }, Column);
        {
            this.observeComponentCreation2((elmtId, isInitialRender) => {
                if (isInitialRender) {
                    let componentCall = new AppSymbol(this, {
                        name: symbolName,
                        iconSize: 25,
                        color: AppTheme.color.primary
                    }, undefined, elmtId, () => { }, { page: "entry/src/main/ets/feature/pet/PetPage.ets", line: 183, col: 7 });
                    ViewPU.create(componentCall);
                    let paramsLambda = () => {
                        return {
                            name: symbolName,
                            iconSize: 25,
                            color: AppTheme.color.primary
                        };
                    };
                    componentCall.paramsGenerator_ = paramsLambda;
                }
                else {
                    this.updateStateVarsOfChildByElmtId(elmtId, {
                        name: symbolName,
                        iconSize: 25,
                        color: AppTheme.color.primary
                    });
                }
            }, { name: "AppSymbol" });
        }
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(label);
            Text.fontSize(AppTheme.font.caption);
            Text.fontWeight(FontWeight.Bold);
            Text.fontColor(AppTheme.color.textPrimary);
        }, Text);
        Text.pop();
        Column.pop();
    }
    private ActionRow(parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Row.create({ space: 10 });
            Row.width('100%');
        }, Row);
        this.ActionButton.bind(this)('投喂', AppSymbolName.Feed, () => {
            this.handlePetAction('feed');
        });
        this.ActionButton.bind(this)('喝水', AppSymbolName.Drink, () => {
            this.handlePetAction('drink');
        });
        this.ActionButton.bind(this)('打工', AppSymbolName.Work, () => {
            this.handlePetAction('work');
        });
        this.ActionButton.bind(this)('摸摸', AppSymbolName.Touch, () => {
            this.handlePetAction('touch');
        });
        Row.pop();
    }
    private ChatBubble(message: PetChatMessage, parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Row.create();
            Row.width('100%');
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            If.create();
            if (message.isUser) {
                this.ifElseBranchUpdateFunction(0, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Blank.create();
                        Blank.layoutWeight(1);
                    }, Blank);
                    Blank.pop();
                });
            }
            else {
                this.ifElseBranchUpdateFunction(1, () => {
                });
            }
        }, If);
        If.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create({ space: 4 });
            Column.padding({ left: 14, right: 14, top: 10, bottom: 10 });
            Column.backgroundColor(message.isUser ? AppTheme.color.primary : AppTheme.color.surfaceTint);
            Column.borderRadius(AppTheme.radius.card);
            Column.constraintSize({ maxWidth: '78%' });
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(message.text);
            Text.fontSize(AppTheme.font.body);
            Text.lineHeight(22);
            Text.fontColor(message.isUser ? AppTheme.color.textOnPrimary : AppTheme.color.textPrimary);
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(message.timeText);
            Text.fontSize(AppTheme.font.tiny);
            Text.fontColor(message.isUser ? 'rgba(255, 255, 255, 0.70)' : AppTheme.color.textTertiary);
        }, Text);
        Text.pop();
        Column.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            If.create();
            if (!message.isUser) {
                this.ifElseBranchUpdateFunction(0, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Blank.create();
                        Blank.layoutWeight(1);
                    }, Blank);
                    Blank.pop();
                });
            }
            else {
                this.ifElseBranchUpdateFunction(1, () => {
                });
            }
        }, If);
        If.pop();
        Row.pop();
    }
    private ChatPanel(parent = null) {
        {
            this.observeComponentCreation2((elmtId, isInitialRender) => {
                if (isInitialRender) {
                    let componentCall = new GlassCard(this, {
                        innerPadding: 14, cornerRadius: AppTheme.radius.cardLarge,
                        content: () => {
                            this.observeComponentCreation2((elmtId, isInitialRender) => {
                                Column.create({ space: 12 });
                                Column.width('100%');
                            }, Column);
                            this.observeComponentCreation2((elmtId, isInitialRender) => {
                                Row.create();
                                Row.width('100%');
                            }, Row);
                            this.observeComponentCreation2((elmtId, isInitialRender) => {
                                Text.create('对话记录');
                                Text.fontSize(AppTheme.font.titleMedium);
                                Text.fontWeight(FontWeight.Bold);
                                Text.fontColor(AppTheme.color.textPrimary);
                            }, Text);
                            Text.pop();
                            this.observeComponentCreation2((elmtId, isInitialRender) => {
                                Blank.create();
                            }, Blank);
                            Blank.pop();
                            this.observeComponentCreation2((elmtId, isInitialRender) => {
                                Text.create('固定回复');
                                Text.fontSize(AppTheme.font.tiny);
                                Text.fontColor(AppTheme.color.primary);
                                Text.padding({ left: 10, right: 10, top: 5, bottom: 5 });
                                Text.backgroundColor(AppTheme.color.primaryPale);
                                Text.borderRadius(AppTheme.radius.pill);
                            }, Text);
                            Text.pop();
                            Row.pop();
                            this.observeComponentCreation2((elmtId, isInitialRender) => {
                                Column.create({ space: 10 });
                                Column.width('100%');
                            }, Column);
                            this.observeComponentCreation2((elmtId, isInitialRender) => {
                                ForEach.create();
                                const forEachItemGenFunction = _item => {
                                    const message = _item;
                                    this.ChatBubble.bind(this)(message);
                                };
                                this.forEachUpdateFunction(elmtId, this.messages, forEachItemGenFunction, (message: PetChatMessage) => message.id, false, false);
                            }, ForEach);
                            ForEach.pop();
                            Column.pop();
                            Column.pop();
                        }
                    }, undefined, elmtId, () => { }, { page: "entry/src/main/ets/feature/pet/PetPage.ets", line: 254, col: 5 });
                    ViewPU.create(componentCall);
                    let paramsLambda = () => {
                        return {
                            innerPadding: 14,
                            cornerRadius: AppTheme.radius.cardLarge,
                            content: () => {
                                this.observeComponentCreation2((elmtId, isInitialRender) => {
                                    Column.create({ space: 12 });
                                    Column.width('100%');
                                }, Column);
                                this.observeComponentCreation2((elmtId, isInitialRender) => {
                                    Row.create();
                                    Row.width('100%');
                                }, Row);
                                this.observeComponentCreation2((elmtId, isInitialRender) => {
                                    Text.create('对话记录');
                                    Text.fontSize(AppTheme.font.titleMedium);
                                    Text.fontWeight(FontWeight.Bold);
                                    Text.fontColor(AppTheme.color.textPrimary);
                                }, Text);
                                Text.pop();
                                this.observeComponentCreation2((elmtId, isInitialRender) => {
                                    Blank.create();
                                }, Blank);
                                Blank.pop();
                                this.observeComponentCreation2((elmtId, isInitialRender) => {
                                    Text.create('固定回复');
                                    Text.fontSize(AppTheme.font.tiny);
                                    Text.fontColor(AppTheme.color.primary);
                                    Text.padding({ left: 10, right: 10, top: 5, bottom: 5 });
                                    Text.backgroundColor(AppTheme.color.primaryPale);
                                    Text.borderRadius(AppTheme.radius.pill);
                                }, Text);
                                Text.pop();
                                Row.pop();
                                this.observeComponentCreation2((elmtId, isInitialRender) => {
                                    Column.create({ space: 10 });
                                    Column.width('100%');
                                }, Column);
                                this.observeComponentCreation2((elmtId, isInitialRender) => {
                                    ForEach.create();
                                    const forEachItemGenFunction = _item => {
                                        const message = _item;
                                        this.ChatBubble.bind(this)(message);
                                    };
                                    this.forEachUpdateFunction(elmtId, this.messages, forEachItemGenFunction, (message: PetChatMessage) => message.id, false, false);
                                }, ForEach);
                                ForEach.pop();
                                Column.pop();
                                Column.pop();
                            }
                        };
                    };
                    componentCall.paramsGenerator_ = paramsLambda;
                }
                else {
                    this.updateStateVarsOfChildByElmtId(elmtId, {
                        innerPadding: 14, cornerRadius: AppTheme.radius.cardLarge
                    });
                }
            }, { name: "GlassCard" });
        }
    }
    private QuickPrompts(parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Row.create({ space: 8 });
            Row.width('100%');
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            ForEach.create();
            const forEachItemGenFunction = _item => {
                const prompt = _item;
                this.observeComponentCreation2((elmtId, isInitialRender) => {
                    Text.create(prompt);
                    Text.fontSize(AppTheme.font.tiny);
                    Text.fontWeight(FontWeight.Medium);
                    Text.fontColor(AppTheme.color.primary);
                    Text.padding({ left: 11, right: 11, top: 7, bottom: 7 });
                    Text.backgroundColor(AppTheme.color.primaryPale);
                    Text.borderRadius(AppTheme.radius.pill);
                    Text.onClick(() => {
                        this.sendText(prompt);
                    });
                }, Text);
                Text.pop();
            };
            this.forEachUpdateFunction(elmtId, QUICK_PROMPTS, forEachItemGenFunction, (prompt: string) => prompt, false, false);
        }, ForEach);
        ForEach.pop();
        Row.pop();
    }
    private Composer(parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create({ space: 10 });
            Column.width('100%');
        }, Column);
        this.QuickPrompts.bind(this)();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Row.create({ space: 10 });
            Row.width('100%');
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            TextInput.create({ placeholder: '和奶茶说点什么...', text: this.inputText });
            TextInput.height(48);
            TextInput.fontSize(AppTheme.font.body);
            TextInput.fontColor(AppTheme.color.textPrimary);
            TextInput.placeholderColor(AppTheme.color.textTertiary);
            TextInput.backgroundColor(AppTheme.color.overlayGlassStrong);
            TextInput.backgroundBlurStyle(BlurStyle.Thin);
            TextInput.borderRadius(AppTheme.radius.pill);
            TextInput.layoutWeight(1);
            TextInput.onChange((value: string) => {
                this.inputText = value;
            });
        }, TextInput);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create('发送');
            Text.fontSize(AppTheme.font.body);
            Text.fontWeight(FontWeight.Bold);
            Text.fontColor(AppTheme.color.textOnPrimary);
            Text.padding({ left: 18, right: 18, top: 13, bottom: 13 });
            Text.backgroundColor(this.inputText.trim().length > 0 ? AppTheme.color.primary : AppTheme.color.primarySoft);
            Text.borderRadius(AppTheme.radius.pill);
            Text.onClick(() => {
                this.sendText(this.inputText);
            });
        }, Text);
        Text.pop();
        Row.pop();
        Column.pop();
    }
    initialRender() {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Scroll.create();
            Scroll.width('100%');
            Scroll.height('100%');
            Scroll.scrollBar(BarState.Off);
            Scroll.backgroundColor(Color.Transparent);
        }, Scroll);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create({ space: 16 });
            Column.width('100%');
            Column.alignItems(HorizontalAlign.Start);
            Column.padding({
                left: AppTheme.spacing.page,
                right: AppTheme.spacing.page,
                top: 18,
                bottom: 150
            });
        }, Column);
        this.Header.bind(this)();
        this.PetStage.bind(this)();
        this.ActionRow.bind(this)();
        this.ChatPanel.bind(this)();
        this.Composer.bind(this)();
        Column.pop();
        Scroll.pop();
    }
    rerender() {
        this.updateDirtyElements();
    }
}
