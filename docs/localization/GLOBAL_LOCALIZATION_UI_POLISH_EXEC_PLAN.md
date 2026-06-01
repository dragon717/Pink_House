# Global Localization And UI Polish Execution Plan

> Updated: 2026-06-01
> Scope: Pink_House iOS app in `/Users/muniao/Library/Mobile Documents/com~apple~CloudDocs/游戏/github/Pink_House`.
> Status: living execution plan for the current multi-agent goal.

## Current Baseline

- App localization resources now exist under `ItemManager/Resources/Localization/Localizable.xcstrings`.
- Current app locales are `en`, `zh-Hans`, and `zh-Hant`.
- `LanguageManager` supports system, Simplified Chinese, Traditional Chinese, English, Japanese, Korean, French, German, Spanish, and Brazilian Portuguese.
- `ItemManager.xcodeproj/project.pbxproj` known regions list `en`, `ja`, `ko`, `fr`, `de`, `es`, `pt-BR`, `zh-Hans`, and `zh-Hant`.
- `Localizable.xcstrings` contains 2403 string entries. The existing three locales cover 2393 entries each; 9 recently added final-payment/detail strings are missing translations.
- Main target `InfoPlist.strings` exists for `en`, `zh-Hans`, `zh-Hant`, `ja`, `ko`, `fr`, `de`, `es`, and `pt-BR`; the six new locales currently use English permission-copy fallback.
- Older research docs from 2026-05-25 predate the current String Catalog and should be treated as historical baseline unless this file or a newer localization doc supersedes them.

## Apple Source Check

Checked on 2026-06-01 against Apple official pages:

- Apple says the App Store is available in 175 regions and 50 languages: [Localization - Apple Developer](https://developer.apple.com/localization/).
- App Store Connect added 11 metadata languages on 2026-03-31: Bangla, Gujarati, Kannada, Malayalam, Marathi, Odia, Punjabi, Slovenian, Tamil, Telugu, and Urdu: [App Store expands support to 11 new languages](https://developer.apple.com/news/?id=97t4mt64).
- App Store metadata localization is different from Xcode binary localization; metadata may fall back to the primary language when no matching localization exists: [Localize app information](https://developer.apple.com/help/app-store-connect/manage-app-information/localize-app-information).
- The storefront-language table is maintained here: [App Store localizations](https://developer.apple.com/help/app-store-connect/reference/app-information/app-store-localizations/).

## Workstreams

### A. Global Language Expansion

Goal: support global release without pretending every storefront needs a separate binary language.

Stage A1:

- Confirm the first expansion locale list against current Apple docs. Completed 2026-06-01.
- Update `AppLanguage`, project known regions, and InfoPlist localization folders. Completed 2026-06-01.
- Keep String Catalog translations source-controlled per language batch; `String.appLocalized` falls back to English for new non-source locales when a translation is not present.
- Verify language picker, bundle lookup, and build output.

Confirmed first-batch app binary locale candidates:

- `ja` Japanese
- `ko` Korean
- `fr` French
- `de` German
- `es` Spanish
- `pt-BR` Brazilian Portuguese

Recommended matching App Store metadata locales:

- `ja`
- `ko`
- `fr-FR`
- `de-DE`
- `es-MX`
- `es-ES`
- `pt-BR`

Reasoning:

- These languages cover high-value App Store markets and broad multi-country discovery without requiring RTL validation in the first UI pass.
- `es-MX` plus `es-ES` covers Latin America and Spain better than a single generic Spanish metadata entry.
- `pt-BR` should come before `pt-PT` because Brazil is the larger App Store opportunity.
- App availability can still be set globally; a binary language is not required per country or region.

Stage A2 candidates:

- `nl` Dutch
- `it` Italian
- `id` Indonesian
- `vi` Vietnamese
- `th` Thai
- `tr` Turkish
- `pl` Polish
- `hi` Hindi

Stage A3 / long tail:

- `ar` Arabic after RTL layout and screenshot QA.
- `ru`, `pt-PT`, `fr-CA`, `ms`, `sv`, `uk`, `ro`, `cs`, `da`, `fi`, `el`.
- India metadata languages from Apple's 2026 expansion: `bn-BD`, `gu-IN`, `kn-IN`, `ml-IN`, `mr-IN`, `or-IN`, `pa-IN`, `sl-SI`, `ta-IN`, `te-IN`, `ur-PK`.

### B. View Localization Coverage

Goal: migrate user-facing View text in small, reviewable batches.

Stage B1 target files:

- `ItemManager/Views/BookHouseSmallWorldView.swift`
- `ItemManager/Views/ClothingDetailView.swift`
- `ItemManager/Views/ClothingEditSections.swift`
- `ItemManager/Views/WardrobeView.swift`
- `ItemManager/Views/ClothingFilterMenu.swift`
- `ItemManager/Views/ClothingCard.swift`

Rules:

- Use existing `String.appLocalized` for strings that must be resolved before entering SwiftUI `Text`.
- Keep user-created content, clothing names, brand names, tag names, pet names, and journal titles untranslated.
- Use whole-sentence localization for interpolated strings.
- Prefer stable keys for legal, IAP, permission, notification, and business-state text; short low-risk UI labels may temporarily use source text keys.

Audit command:

```bash
python3 tools/localization/audit_swift_literals.py ItemManager/Views/BookHouseSmallWorldView.swift ItemManager/Views/ClothingDetailView.swift ItemManager/Views/ClothingEditSections.swift ItemManager/Views/WardrobeView.swift ItemManager/Views/ClothingFilterMenu.swift ItemManager/Views/ClothingCard.swift --show candidate
```

### C. House And Wardrobe UI Polish

Goal: improve the house, wardrobe, edit, and detail surfaces without breaking ThemeSkin compatibility.

Stage C1 low-risk polish:

- House: improve placement hint/control legibility and room depth in `BookHouseSmallWorldView.swift`.
- Wardrobe: refine stats/actions hierarchy, filter affordance, empty states, and card shell consistency.
- Edit: improve section grouping, inline help, price/reservation hierarchy, and chart image affordances.
- Detail: improve hero overlap, metadata, action visibility, and price/detail card hierarchy.

Rules:

- Do not change `ThemeSkinSlot.rawValue` or the 18-slot contract.
- Keep user clothing images visually unfiltered.
- Reuse `LiquidBackground`, `ThemeSkinPrimaryButtonStyle`, `ThemeSkinSectionCardContainer`, wardrobe card tokens, and `ThemeManager` palette APIs before adding new UI primitives.
- Any generated asset must go through Asset Catalog under an appropriate namespace; do not use loose bundle image paths.

## Stage Gates

Each small stage must pass before commit:

1. `git diff --check`
2. Targeted audit command for the files touched
3. `xcodebuild -scheme ItemManager -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -derivedDataPath /private/tmp/pink-house-build-<stage> -clonedSourcePackagesDirPath build/SourcePackages -quiet build`
4. Simulator install/terminate/launch for UI stages when visual validation is required
5. Screenshot or explicit manual observation summary for UI stages

Commit cadence:

- Commit research/tooling separately from code changes.
- Commit each localization batch separately from UI polish.
- Commit generated image assets separately from Swift integration when possible.
