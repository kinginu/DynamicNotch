# DynamicNotchApp — DynamicNotch アプリ本体

DynamicNotch のアプリ本体（XcodeGen プロジェクト + Command Line Tools ハーネス）。Fan Control は
`../FanControl/`（サブモジュール）のパッケージを使い、アプリ側のグルーは `Sources/FanControlGlue/`
（[`docs/fan-control-integration.md`](docs/fan-control-integration.md)）。経過は [`BUILD-LOG.md`](BUILD-LOG.md)。
このアプリは独自実装です。

> **License**: MIT ([`../LICENSE`](../LICENSE); dependencies in [`../THIRD-PARTY-NOTICES.md`](../THIRD-PARTY-NOTICES.md)).

## 構成

| パス | 内容 |
|---|---|
| `project.yml` | XcodeGen スペック（**正**。`.xcodeproj` は生成物で git 管理外） |
| `Package.swift` | Command Line Tools（CLT）だけでビルドできる SwiftPM ハーネス。`Sources/` をライブラリ `DynamicNotchApp` としてコンパイルし、`Tests/` 全体をテストターゲット `DynamicNotchAppTests` にする |
| `Tests/` | 単体テスト（Swift Testing）。Xcode の `DynamicNotchAppTests` と CLT ハーネスが同じファイルをコンパイルする（下記「テストとチェック」） |
| `Sources/` | アプリのソース（`FanControlGlue/` は Fan Control のグルー。`Package.swift` のハーネスでは除外） |
| `Sources/Support/SharedDeclarations.swift` | 共通の宣言（設定プロトコル `Preferences` / `WidgetPrefs` / `MetaInfo`、`interpolatorBuilder`、`Color.nonShockingWhite`、`AnyTransition.scaleAndBlur`） |
| `Sources/Support/EnvironmentValues+Notch.swift` | ノッチ UI の `EnvironmentValues` アクセサ（`\.generalSettings` など） |
| `Sources/Support/Ext-*.swift` | ファイル群ごとの補助拡張（並行修正時の所有単位: A/A1/A2/B/C/C2/D/E。空になった Ext-F は 2026-10-21 に削除） |
| `App/DynamicNotchApp.swift` | `@main`。Xcode ターゲットのみがコンパイルする |
| `Sources/WindowsManager.swift` 末尾 | ノッチウィンドウ（`updateWindows` → `setupDisplayKitForScreen` → `DisplayKit.dynamicnotchWindow: BetterWindow`） |
| `Sources/NookModelContainer.swift`, `Sources/SettingsWindowOpener.swift`, `Sources/NSScreen+Notch.swift` | 起動配線（2026-10-21 に分割）: SwiftData コンテナ `NookModelContainer`（`Application Support/<bundle id>/Nook.store`）、設定ウィンドウを開く `SettingsWindowOpener`（ペイン一覧と固定サイズは `SettingsRootView`）、`NSScreen.hardwareNotchSize` |
| `Sources/Support/NookWidgetGrid.swift` | Nook のウィジェット行（`NookWidget` → View の振り分け。50 pt グリッド、区切り線、横スクロール。FanControl の `fanControl` / `temperature`（2026-10-20）を含む）。F9: ページ（`NookSettings.pages`、2 本指スワイプ・←/→・ドット）と長押しドラッグでの並べ替え・ページ間移動（`NookWidgetPager.swift`、純モデル `NookWidgetPagesModel.swift`、DEBUG `DebugHooks-WidgetPages.swift`） |
| `Sources/Batter{yDevicesManager,iesWidget*}.swift` | Batteries ウィジェット（`NookWidget.batteries`、tag 12。この Mac・Magic アクセサリ・AirPods・BLE 機器の電池。公開 API のみ: IOPS / IOKit レジストリ / `system_profiler` / CoreBluetooth 電池サービス。BUILD-LOG 2026-10-20） |
| `Sources/Usage{Accounting,Store,Tracker,Widget*}.swift` | Usage ウィジェット（`NookWidget.usage`、tag 28。自前収集のスクリーンタイム風統計: 前面アプリの時間・無操作の除外・スリープ/ロック・ピックアップ。既定 OFF、SwiftData `Usage.store`、90 日保持。集計は純粋型 `UsageAccountant`、テスト `Tests/DynamicNotchAppTests/UsageAccountingTests.swift`。BUILD-LOG 2026-10-20） |
| `Sources/LiveActivities/` | 閉じたノッチのライブアクティビティ（2026-10-21 に 1 ファイルから分割）: `LiveActivity` と `LiveActivityDescriptor`（id・優先度・幅・設定ゲートを 1 か所に）、`LiveActivityCenter`、`ClosedNotchActivitiesView`（カメラ左右の行）、電池/カレンダー/タイマーの各 Activity |
| `Sources/{DDCPacket,DDCTransport,DisplayHardware,DisplayControlService,DisplaysWidget*}.swift` | Displays ウィジェット（`NookWidget.displays`、tag 29。内蔵の輝度（DisplayServices、IORegistry は概算フォールバック）と外部モニターの輝度・コントラスト・音量（DDC/CI over IOAVService）、入力は表示のみ。[`docs/displays.md`](docs/displays.md)） |
| `Sources/Support/NotchDrop.swift` | ノッチへのファイルドロップ（`NotchDropModifier` / `NotchDropController`） |
| `Sources/Support/Ext-A.swift`, `Ext-C2.swift` | ウィジェット側・トレイ側の補助（ノート編集窓、設定タブ遷移、サムネイル、トレイのメニュー） |
| `Sources/Support/FanControl-Patches.swift` | [`docs/fan-control-integration.md`](docs/fan-control-integration.md) の (d)(e)。`#if canImport(FanControlKit)` で Xcode ターゲットのみ |
| `Sources/NotchHover.swift`, `NotchHover+Debug.swift`, `NotchWindowGeometry.swift` | ノッチのホバー開閉（ホバーで開く・閉じる前の猶予とホバー帯・メニュー/ポップオーバー/シート/テキスト編集中は閉じない）と画面ごとの窓サイズ `NotchWindowGeometry` |
| `Sources/Support/DebugHooks*.swift` | DEBUG ビルドのみ: 分散通知による検証用リモート操作（スナップショット・クリック・ペイン表示。コマンド表は `DebugHooks-Registry.swift`、ウィジェット別は `DebugHooks-<Widget>.swift`。下記） |
| `Localization/en.lproj/Localizable.strings` | `Support/merge-strings.py` の生成物（アプリのキー一覧 + FanControl en 文字列。英語のみ。下記） |
| `Support/Info.plist`, `Support/DynamicNotch.entitlements` | `xcodegen generate` が `project.yml` から生成（コミット対象） |
| `BUILD-LOG.md` | 作業ログ（変更内容と検証結果） |

アプリの `Contents/Resources` に入るのは次の 3 つだけ（他アプリの資産は一切同梱しない）:

- `DynamicNotchAppIcon.icns` — `swift Support/make-app-icon.swift` が生成する自作アイコン（プレビュー `docs/app-icon/preview.png`）。
- `en.lproj/Localizable.strings` — `Support/merge-strings.py` の生成物。アプリは**英語のみ**（`CFBundleDevelopmentRegion` en、
  `CFBundleLocalizations` [en]）。
- `MediaRemoteAdapter_MediaRemoteAdapter.bundle` — SwiftPM が MediaRemoteAdapter パッケージから生成する（ライセンスは
  `../THIRD-PARTY-NOTICES.md`）。

カタログ色の代わりに `Color` リテラル（`Sources/Support/Ext-C.swift`）を使い、メディアライブアクティビティ「Custom GIF」は
ユーザーが選んだ GIF が無いとき SwiftUI 描画のイコライザ（`AudioBarsView`）を表示する。

## ビルド方法

### Command Line Tools のみ（ハーネス）

```sh
cd DynamicNotchApp
swift package resolve          # 初回のみ（GitHub へのアクセスが必要）
swift build                    # 2 回目以降はネットワーク無しなら --skip-update
```

CLT 固有の回避策（Xcode ビルドには不要・無関係）:

1. **SwiftData `@Model`**: CLT には SwiftDataMacros が無い。ハーネスは `DN_CLT_HARNESS` を定義し、`Note.swift` などは
   型検査専用の手書き `PersistentModel` 準拠に切り替わる（**動作しない**。Xcode ビルドは `#else` 側の本物の `@Model`）。
2. `@Observable`（ObservationMacros）は CLT にもあるのでそのまま使える。SwiftUI の `@Entry` は無いので使っていない。

### Xcode（2026-10-20、Xcode 26.6 で成功）

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer   # xcode-select が CLT を指している場合
cd DynamicNotchApp
xcodegen generate
xcodebuild -project DynamicNotch.xcodeproj -scheme DynamicNotch -configuration Debug \
  -derivedDataPath .derivedData build CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES
open .derivedData/Build/Products/Debug/DynamicNotch.app
```

- ターゲットは `DynamicNotch`（アプリ）と `FanControlHelper`（Command Line Tool）。成果物は
  `Contents/MacOS/{DynamicNotch,FanControlHelper}`、`Contents/Library/LaunchDaemons/com.example.dynamicnotch.DynamicNotch.fanfi.plist`、
  `Contents/Frameworks/MediaRemoteAdapter.framework`（2026-10-20 の依存削減以降。当初は Lottie / Sparkle）。両方 `flags=0x10002(adhoc,runtime)`、`codesign --verify --deep --strict` 成功。
- アドホック署名の Debug を起動できるよう `ENABLE_DEBUG_DYLIB = NO` と `OTHER_CODE_SIGN_FLAGS = $(inherited) --options=runtime`
  （HelperSmokeApp と同じ理由。FanControl/docs/integration.md §4）。
- **バンドル ID の共有に注意**: `com.example.dynamicnotch.DynamicNotch` は `FanControl/Tools/HelperSmokeApp` と同じなので、
  UserDefaults（`fanControl.profileStore` など）を共有する。スモークアプリで作ったプロファイル（例「Custom」）がこのアプリにも出る。

- `xcodegen` 自体は Xcode のライセンス無しで動く（`xcodegen generate` 成功を確認済み）。
- `#if canImport(DynamicNotch)` は Xcode ターゲット内では自モジュール名で真になるので、無効化したいコードには `#if false` を使う。
- 署名: `project.yml` の `DEVELOPMENT_TEAM` は空で、`CODE_SIGN_IDENTITY = "-"`（ローカル実行用アドホック署名）。
  ヘルパーは手動インストール（`../FanControl/Support/manual-install/`）で使う。SMAppService で登録する場合だけ
  Team ID をここ（または Xcode の Signing & Capabilities）に入れる（アドホック署名では登録できない）。
- 設定値: macOS 26.0（2026-10-20 に 14.6 から引き上げ）、Swift 5 モード、`SWIFT_STRICT_CONCURRENCY = minimal`、App Sandbox なし、Hardened Runtime あり、
  `LSUIElement = YES`、プライバシー文言 7 種（汎用文）、entitlements（apple-events / camera / audio-input /
  calendars / disable-library-validation）。
- 独自ドキュメント型（`CFBundleDocumentTypes` / `UTExportedTypeDeclarations`）は未設定。

## テストとチェック（2026-10-20）

### 一括チェック `../scripts/check.sh`

リポジトリ全体の検査をまとめたスクリプト。システムには触れない（インストール・sudo・SMC 書込・アプリ起動なし）。

```sh
scripts/check.sh               # 全ステップ（Xcode ビルドを含む。初回は数分〜十数分）
scripts/check.sh --fast        # Xcode の 3 ステップと Swift 6 型検査を省く（CLT ハーネス・FanControl・型検査 Swift 5・文字列・shellcheck）
scripts/check.sh app-test harness-test   # 指定ステップだけ（名前は --list）
scripts/check.sh --keep-going  # 失敗しても残りを続ける（既定は最初の失敗で停止）
```

| ステップ | 内容 |
|---|---|
| `xcodegen` | `xcodegen generate`（`project.yml` → `.xcodeproj`、`Support/Info.plist`） |
| `app-build` | `xcodebuild -scheme DynamicNotch build`（アプリ + ヘルパー、アドホック署名） |
| `app-test` | `xcodebuild -scheme DynamicNotch test -only-testing:DynamicNotchAppTests` |
| `harness-build` / `harness-test` | CLT ハーネス（`Package.swift`）の `swift build` / `swift test` |
| `fancontrol-build` / `fancontrol-test` | `FanControl/` の `swift build` / `swift test` |
| `strings-lint` | `Support/lint-strings.py`（または `.sh`、`scripts/lint-strings.sh`）があれば実行。無ければ `Localizable.strings` の `plutil -lint` と `merge-strings.py` の構文確認 |
| `shellcheck` | リポジトリの全 `*.sh`（`shellcheck -x`） |

- 成果物とログは `CHECK_BUILD_DIR`（既定 `<repo>/.build-check/`、git 管理外。ログは `logs/<step>.log`）。2 回目以降は差分ビルド。
  失敗時はログのエラー・テスト結果の要約を表示する。
- `DEVELOPER_DIR` が未設定なら `/Applications/Xcode.app/Contents/Developer` を使う（`xcode-select` が CLT のままでも可）。
- 警告: FanControl は警告 1 件でも失敗（0 件を維持している）。アプリとハーネスには既知の警告が数件あるので件数の表示だけ
  （`CHECK_STRICT_WARNINGS=1` で失敗扱い）。差分ビルドでは再コンパイルしたファイルの警告しか出ないので、全件を見るには `CHECK_BUILD_DIR` を空にする。

### 単体テスト `DynamicNotchAppTests`

- **Xcode**: `project.yml` のターゲット 2 つ。
  - `DynamicNotchApp`（`library.static`）: アプリと同じ `Sources/`（`FanControlGlue/` を含む）を、`App/`（`@main`）とリソース抜きでコンパイルするテスト専用ライブラリ
    （出荷しない。モジュール名は CLT ハーネスと同じ `DynamicNotchApp`、`ENABLE_TESTABILITY = YES`）。
  - `DynamicNotchAppTests`（`bundle.unit-test`）: `Tests/**`（`Fixtures/` を除く）を **ホスト無し**（`TEST_HOST` 無し）でコンパイルし、上のライブラリにリンクする。
    アプリは起動しない（ホスト付きテストは稼働中のインスタンスの隣に 2 つ目の DynamicNotch を起動し、ノッチ窓・SMC 読取・ヘルパー接続まで動いてしまうため）。
    `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES`（テストコードのみ。Xcode には Swift のファイル単位フラグが無いので、アプリ側の新ウィジェットだけに付けることはできない）。
  - スキーム `DynamicNotch` のテストアクションに入っている:
    `xcodebuild -project DynamicNotch.xcodeproj -scheme DynamicNotch -derivedDataPath .derivedData test -only-testing:DynamicNotchAppTests`
- **CLT ハーネス**: `Package.swift` のテストターゲット `DynamicNotchAppTests`（パス `Tests`、`SettingsStorageTests/Fixtures` を除外）。`swift test`。
  ハーネスは `FanControlKit` を持たないので `#if canImport(FanControlKit)` の部分（`NookWidget.fanControl` など）はテストされない。
- テストファイルはどちらでも `@testable import DynamicNotchApp` で書く。`Tests/` の下に置けば両方に自動で入る（`project.yml` / `Package.swift` の編集不要）。
  フィクスチャは `Fixtures/` ディレクトリに置き、`#filePath` からの相対パスで読む（バンドルにはコピーしない）。
- 現在のスイート（2026-10-21、Xcode・ハーネスとも 101 tests / 9 suites）: `Tests/DynamicNotchAppTests/` の `Smoke`（ウィジェット ID の一意性、
  テストプロセスがアプリでないこと）、`NextUp meeting links`（サービス判定・偽ドメイン拒否・末尾の句読点）、`World clock hour format`、
  `Tests/EngineTests/` の計算機エンジン・計算機ストア・クリップボード履歴・カラーピッカー・ポモドーロ、
  `Tests/SettingsStorageTests/` の `SettingsStore compatibility with Defaults 8.2 data`。

## 依存パッケージ（SwiftPM で解決確認済み）

| パッケージ | URL | 版 |
|---|---|---|
| MediaRemoteAdapter | https://github.com/ejbills/mediaremote-adapter | revision `5b6afde`（タグ無し。`MediaController`/`TrackInfo` と `run.pl` リソースを使う。ungive/mediaremote-adapter には Package.swift が無い） |

2026-10-20 に Sparkle・SmoothGradient・Lottie・RichTextKit・CodeEditor（+ Highlightr）を純正 API に置換し（BUILD-LOG.md）、
最後に sindresorhus/Defaults を撤去した。残るリモート依存は MediaRemoteAdapter のみ（About ペインのライセンス一覧も同じ）。

### 設定の保存（`SettingsStore`、2026-10-20 に Defaults から移行）

- 実装は `../FanControl/Sources/FanControlUI/Storage/SettingsStore.swift`（FanControlUI の internal なストア。アプリは
  シンボリックリンク `Sources/Support/SettingsStorage.swift` 経由で自モジュールにもう 1 部コンパイルする。キー名は `Sources/Support/SettingKey.swift`）。
- API: キー名 `SettingKey.x`（文字列。旧 `Defaults.Keys` 名のまま）、型付きキー `extension StoredKeys { static let x = Key<T>(SettingKey.x, default: …) }`
  （アプリの分は `Support/Ext-A/A2/B/C/D.swift`）、読み書き `SettingsStore[.x]`、ビュー／プロパティ `@StoredSetting(.x) var x`（`$x` は Binding、
  変更で再描画）、変更ストリーム `SettingsStore.updates(.x, initial:)` / `SettingsStore.updates([.a, .b])`。設定構造体は `Preferences`
  （= `CodableStoredValue & Hashable` + `init()`）または `CodableStoredValue` に準拠する。
- 保存形式は Defaults 8.2 と同一（Codable はソート済みキーの JSON **文字列**、Bool/数値/String/配列はネイティブ）なので既存の設定はそのまま読める。
  互換性テスト: `swift test --filter SettingsStorage`（`Tests/SettingsStorageTests`、Xcode では `DynamicNotchAppTests` の一部。ユーザー設定の写し `Fixtures/settings-2026-10-20.plist`、`DN_SETTINGS_PLIST=<export>` で差し替え可）。
- 移行完了（2026-10-20）: `import Defaults` / 互換シム（`Shims/Defaults`、`DefaultsCompatShim.swift`）は撤去済み。

## 共通の宣言と補助

共通（`Sources/Support/`）:
- `SharedDeclarations.swift`: `Preferences`（`CodableStoredValue & Hashable` + `init()`、`X.defaultValue`。2026-10-20 まで `Defaults.Serializable`）、
  `WidgetPrefs`（`gridSizeType` のみ要求。`docs/fan-control-integration.md` (a) と整合）、`MetaInfo`、`interpolatorBuilder`、
  `Color.nonShockingWhite`、`AnyTransition.scaleAndBlur`。
- `EnvironmentValues+Notch.swift`: ノッチ UI の `*Key`（EnvironmentKey）と環境値・既定値。
- `Ext-A`〜`Ext-E`: 並行作業時に各グループが足した拡張（`Animation` の各種 spring 値、`vibrate()`、`flexFrame` は
  `Extensions.swift`、`Color.selected` / `weekendPink`、`NSColor.lighter/darkened`、設定キー一式（設定構造体ごとに
  `StoredKeys.<lowerCamel>`。旧 `Defaults.Keys`。`Defaults[XSettingsKey()]` ブリッジは未使用のため 2026-10-20 に削除）など）。

その他:
- **`@main`**: `App/DynamicNotchApp.swift`。
- 状態を持つクラスは `@Observable`、`Note` は `@Model`。
- **Metal**: 呼び出し元の無かった Metal レンダラ一式は 2026-10-20 夕方に削除。ガラス表現は SwiftUI `.glassEffect` / `NativeGlassPill`。
- 動画ローダ／背景も呼び出し元が無く、同日に削除。
  `#if false` / `#if canImport(DynamicNotch)` で無効化した重複定義:
  `TopBarContentView.swift`（private な重複ビュー）、`NativeGlassPill.swift`（全体。型が合わない）。

## 起動配線と検証方法

- `AppDelegate.applicationDidFinishLaunching` → `WindowsManager.updateWindows()`（画面ごとに `DisplayKit` を作り、`DisplayKit.dynamicnotchWindow` に
  `BetterWindow` を作る。幅は開いたノッチ（ウィジェット行の幅ちょうど、画面幅の 80 % まで）+ 80 pt、高さ 360 pt。ウィジェット構成が変わったときだけ
  リサイズし、開閉中はリサイズしない。開閉状態は画面ごと（`DisplayKit.notchState`）。2026-10-20 の N1 パスで独自 `NotchPanel` を廃止。BUILD-LOG「ノッチウィンドウ」「N2」）、
  `LiveActivitiesStartup.start()`、`NookTimersStore.shared`、
  設定ウィンドウ（ノッチ窓の高さ 360 pt・幅は可変、レベル `mainMenu + 3`）。
- **設定ウィンドウ**（2026-10-20 に sindresorhus/Settings から SwiftUI 標準へ移行）: `App/DynamicNotchApp.swift` の `Settings { SettingsRootView() }` シーン。
  `Sources/SettingsRootView.swift` の `TabView`（`.tabItem { Label(…, systemImage:) }` でツールバー型タブ）、タブ順 General / Nook（General・Widgets・Drop Area の
  サブタブ）/ Live Activities / Tray / Liquid Glass / Gestures / Fan Control / About（License ペインは削除）。全タブを同じ固定サイズ 760×640 pt
  （`SettingsRootView.contentSize`、`.frame(alignment: .top)`）で包むのでタブ切替で窓サイズが変わらない。各ペインは `Form` + `.formStyle(.grouped)`。
  選択中のタブは `SettingsNavigation.shared.pane`（`AppSettings.PaneIdentifier`、UserDefaults `settingsSelectedPane` に保存）。
  AppKit 側（ステータスメニュー「Open Settings」、ノッチの「Open Settings」ボタン、DebugHooks `settings:<paneId>`）は
  `WindowsManager.showSettings(pane:)` → 選択を設定 → `SettingsWindowOpener.open()`（`Sources/SettingsWindowOpener.swift`）: 既存の窓があれば前面へ、
  無ければ SwiftUI がアプリメニューに作る「Settings…」（⌘,）項目を `performActionForItem` で実行（macOS 14 以降は
  `showSettingsWindow:` セレクタが無効のため。モジュール内に同名の `EnvironmentValues.openSettings` があり SwiftUI の `OpenSettingsAction` を取れないことも理由）。
- ノッチサイズは `NSScreen.safeAreaInsets` / `auxiliaryTopLeft/RightArea` から（ノッチ無し画面は幅 200 pt・メニューバー高）。
- その他: `IntroView` はクリックで閉じる、`NookView` はウィジェット行、
  ノッチの開いた幅は `NookWidgetLayout.rowWidth`（保存済み `nookSettings` から）を [320, 820] pt に収める、ホバーは
  `.onContinuousHover` → `NotchViewModel.setPointerOver`、開閉は固定キャンバス + animatable `NotchShape` のマスク（BUILD-LOG「ノッチウィンドウ」）、
  `RootView` に SwiftData コンテナ（`NSAttributedStringTransformer` を先に登録しないと `@Query` がトラップする）。
- **検証の制約**: このシェルには画面収録・アクセシビリティ権限が無く `screencapture` / UI スクリプトが使えない。代わりに DEBUG ビルドの
  `DebugHooks`（分散通知 `com.example.dynamicnotch.debug`、object がコマンド文字列）で、アプリ内から各ウィンドウを PNG 化
  （`cacheDisplay`。マテリアル/ぼかしは実画面より平板）し、`NSEvent` を合成してクリックする。コマンド: `snapshot:<dir>`、
  `settings:<paneId>`、`open` / `open:tray` / `close`、`click:<窓タイトル>:<x>,<y>`（窓左上からの pt）、`intro:off`、`defaults:<key>=<json>`。
  `fanpreview:<dir>`（2026-10-20）: Fan Control ウィジェットを固定 6 プロファイル × 2x1 / ダブルワイドでオフスクリーン描画（`widget-<size>-<profile>.png`、
  ウィジェットのプレビュー専用引数 `previewProfile` / `previewGridSize` を使うので適用・設定変更・選択変更は一切しない）し、設定 ▸ プロファイル タブを
  Boost / Custom 1 / Custom 2 選択状態で描画する（`profiles-tab-*.png`、`initialSelection`）。合成クリックでは `List` の行選択が変わらないための代替。
  投稿側は 3 行の Swift（`DistributedNotificationCenter.default().postNotificationName(.init("com.example.dynamicnotch.debug"), object: cmd, userInfo: nil, deliverImmediately: true)`）。
  **開発用の 2 つ目のインスタンス**（2026-10-20）: `PRODUCT_BUNDLE_IDENTIFIER=com.example.dynamicnotch.DynamicNotch.dev` でビルドすると UserDefaults・トレイ・
  SwiftData が別になる。環境変数 `DN_DEBUG_CHANNEL=<名>`（通知名が `com.example.dynamicnotch.debug.<名>` になり、稼働中のインスタンスと混線しない）、
  `DN_DEBUG_OFFSCREEN=1`（ノッチ窓を画面外へ）、`DN_DEBUG_GHOST=1`（画面上・不透明度 2 %・マウス無視。計測用）、`DN_DEBUG_MAX_OPEN=<pt>`
  （開いたノッチの最大幅を狭める。横スクロールの確認用）。確認が済んだら必ず終了する。
  ノッチの開閉状態は画面ごとなので、`open` / `open:tray` はポインタ下の画面（無ければメイン画面）だけを開く。全画面は `open:all` / `open:tray,all`、
  `close` は全画面を閉じる。`notchstate`（画面ごとのモードと窓枠）、`hovertest`（開いたノッチでホバーアウトを模擬し、猶予後に閉じるかをログ）、
  `menutest:<x>,<y>`（同上 + ノッチ窓の (x, y) をクリックしてメニューを開き、メニュー表示中は開いたまま・閉じた後に閉じるかをログ）。
  追加コマンド: `animperf:<n>`（開閉の main スレッドのフレーム間隔と `NotchView.body` 評価回数をログ）、`DebugHooks-A.swift`（`nookwidgets:a,b`、
  `sampletodo:` など）、`DebugHooks-B.swift`（`la:<activity>` / `la:clear` / `la:state`、`media:state|toggle|next|prev`）、
  `DebugHooks-C.swift`（`trayadd:<path>`、`traytext:`、`traydrag[:tray|airdrop]`、`trayenddrag`、`trayclear`、`traystate`）。
- 結果（2026-10-20、Mac14,9、外部 4K ×2 + 内蔵）: 起動・クラッシュ無し、ノッチパネル 3 枚、設定ウィンドウの全ペイン表示、ノッチの開閉、
  Calendar / Timer / Fan Control ウィジェットの描画を確認。スナップショットは `.derivedData/shots/`（git 管理外）。
  最初の起動では Notes/To-dos 用 SwiftData コンテナ未設定によるクラッシュ（`@Query` のトラップ）があり修正済み。

## ウィジェットの見た目（2026-10-20、Apple ネイティブ化）

全ウィジェットを macOS 純正 UI に寄せて作り直した（BUILD-LOG「ウィジェットの Apple ネイティブ化」）。共通部品は `Sources/Support/NookWidgetChrome.swift`
（余白 8/12 pt、macOS 26 は Liquid Glass、14/15 はマテリアル、意味色 `.primary/.secondary` と `.quinary/.quaternary`）。Notes はその場で編集
（`NoteInlineEditor`、A/B/I/U バー）、Timer は h:m:s ホイール + プリセット + 再生ボタン（`TimerCreatorView`）、Calendar は月名 + 5 日の 1 行。
DEBUG の `widgetgallery:<dir>`（`Support/WidgetGallery-Debug.swift`、先に `open`）で全ウィジェットをダーク/ライトで PNG 化できる（ガラスは
`cacheDisplay` に写らないためマテリアルで描画）。最新の結果は `../docs/widget-gallery/`。

## FanControl 統合（2026-10-20 実施）

- `project.yml`: ローカルパッケージ `FanControl: { path: ../FanControl, group: Packages }`、アプリに `FanControlCore` / `FanControlKit`、
  `FanControlHelper`（`type: tool`、HelperSmokeApp と同じ設定。`-sectcreate` のパスは `$(SRCROOT)/../FanControl/Support/Helper-Info.plist`）、
  Copy Files（Executables / Wrapper `Contents/Library/LaunchDaemons`）。Fan Control のグルー 6 ファイルは `Sources/FanControlGlue/`
  （2026-10-21 に FanControl リポジトリから移動。以前は `../FanControl/DynamicNotchIntegration` をその場で参照していた）。
  パッケージ参照には `group: Packages` を付ける（付けないとパッケージ参照とソースのグループが衝突する）。
- フック (a)〜(f)（`docs/fan-control-integration.md`）は本ディレクトリのソースに入れ、すべて `#if canImport(FanControlKit)` で囲んだ（CLT ハーネスは FanControl に
  依存しないので従来どおりエラー 0）。(a) `NookWidget.swift`（+ `FanControlWidgetSettings` に `init()` を追加: `Preferences` が要求）、
  (b) `NookWidgetGrid.swift`、(c) `WidgetsSettingsTabView.swift`、(d)(e) `Support/FanControl-Patches.swift`（`AppSettings.*` 表記）、
  (f) `LiveActivity.swift` / `LiveActivityView.swift`。
- **文字列**（2026-10-20 夕方〜、英語のみ）: `Support/merge-strings.py` が `Localization/en.lproj`（`Support/strings/*.json`。Fan Control 分は
  `fan-control.json`。キー＝値）だけを生成する。他の `.lproj` は同梱しない。ja は廃止（ユーザー決定）。
  キー一覧か FanControl の `en.strings` を変えたら `python3 Support/merge-strings.py` を再実行する。
- 読み取り確認（ヘルパー登録・書込・接続なし）の結果は `../FanControl/docs/integration.md` §6「DynamicNotch UI」。

## 現状と残課題

- **CLT ハーネスでは `swift build` がエラー 0**、**Xcode ビルドも成功**し、アドホック署名の Debug ビルドが起動する。
- **機能（2026-10-20、N1 パス）**: 全ウィジェット（Calendar / Media Player / Shortcuts / Mirror / Notes / Quick Apps / To-dos /
  Timer / Fan Control）の選択（設定 ▸ Nook ▸ Widgets）と表示、上段のタブ（Nook / Tray）と設定ボタン、閉じたノッチのライブアクティビティ（メディア、
  電池、カレンダー、タイマー終了、トレイ、ファン警告）、MediaRemoteAdapter による再生中情報と操作、ファイルトレイとノッチへのドロップ（AirDrop 含む）。
  詳細は BUILD-LOG「ノッチウィンドウ」。
- 未実装: アップデート通知のライブアクティビティ（アイコンのみ）、オーディオのスペクトログラム（棒で代用）、パイプライン。
  `X.defaultValue` は `X()` で、`RootView` が環境に配る設定値はユーザー設定を反映しない（ウィジェット・FanControl は
  `@StoredSetting` で直接読むので影響なし）。
- 設定構造体は合成 Codable（キー欠落に備えた `decodeIfPresent` 化は一部の設定のみ）。
- `ArrayPosition` は空 enum のまま（利用側がローカル enum／Optional で回避）。

## 次の作業

1. FanControl Phase 2 以降（ヘルパー）: 手動インストールモードでこのアプリの cdhash を固定し直す必要がある（`sudo install.sh <DynamicNotch.app>`、
   ユーザー操作。現在はスモークアプリの cdhash が固定されている）。書込は CLAUDE.md の確認規則に従う。
2. 実画面での見た目と操作の確認（開閉アニメーション、ドラッグ＆ドロップ、メディア操作。BUILD-LOG「ノッチウィンドウ」の確認手順）。
3. ノッチ窓が `BetterWindow`（NSWindow）になったことでクリック時に前面アプリのフォーカスが外れるかを確認し、問題なら非アクティブ化パネルに戻す。

- 設定 ▸ About: `Sources/AboutSettingsView.swift`（版、システム情報、診断コピー、OSS ライセンス一覧。文字列は `merge-strings.py` の `APP_EXTRA_*`）。
