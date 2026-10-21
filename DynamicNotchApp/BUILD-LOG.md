# BUILD-LOG — DynamicNotch（作業ログ）

このアプリは独自実装です。このログは作業パスごとの変更内容と検証結果の記録（日本語）。最初は Command Line Tools だけでビルドできる
SwiftPM ハーネス（`Package.swift`）で `swift build` がエラー 0 になるまで整え、その後 Xcode ビルド（下記）へ移った。

> パスについて: 2026-10-21 以前の記録に出てくる `FanControl/DynamicNotchIntegration/…`（Fan Control のグルーと文字列）は現在
> `Sources/FanControlGlue/` と `Support/strings/fan-control.json` に、`FanControl/Tools/IntegrationTypeCheck`（グルーの型検査）は
> アプリのビルドと `FanControlUITests` に置き換わった。`PATCHES.md` は [`docs/fan-control-integration.md`](docs/fan-control-integration.md)。

## Xcode ビルド（2026-10-20、Xcode 26.6、`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`）

コマンド: `xcodegen generate && xcodebuild -project DynamicNotch.xcodeproj -scheme DynamicNotch -configuration Debug -derivedDataPath .derivedData build CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES`

| Pass | 結果 | 変更内容 |
|---|---|---|
| X1 | 失敗（`NativeGlassPill.swift` 20 件） | `ENABLE_DEBUG_DYLIB: NO`、`OTHER_CODE_SIGN_FLAGS: $(inherited) --options=runtime` を追加しただけの初回。`#if canImport(DynamicNotch)` が Xcode ターゲット内では真（自モジュール）で、無効化していたコードがコンパイルされた |
| X2 | **成功** | 上記を `#if false` に。本物の `@Model`（Note / TodoItem）、`@Query`、`#Preview` 入り RichTextKit 1.2.0、`@main` はエラー無し。ハーネスとの差はこの 1 件のみ |
| X3 | 成功・**起動** | 起動配線（`WindowsManager.swift`: `NotchPanel`、`setupSettingsWindow()`、ペイン 8 つ）、`RootView(screenNotchSize:)`、Nook 設定に Widgets タブ、ホバー。main actor 隔離エラー 4 件を `MainActor.assumeIsolated` で解消。起動後クラッシュ無し、ノッチは「Welcome」カードのまま（`intro` 既定 true、終了手段なし） |
| X4 | 成功 | `DebugHooks`（DEBUG のみ）。`IntroView` をクリックで閉じる。`NookView` をウィジェット行に（`NookWidgetGrid.swift`）、開いた幅を保存済み `nookSettings` から |
| X5 | 成功・**クラッシュ** → 修正 | ウィジェットに Calendar を入れると SwiftData の `@Query` がトラップ（`modelContainer` 未設定）。`.modelContainer(for:)` だけでもトラップ → `NSAttributedStringTransformer` を先に登録する `NookModelContainer`（失敗時はインメモリ→nil）で解消 |
| X6 | 成功 | FanControl 統合: パッケージ・ヘルパーターゲット・Copy Files・ドロップイン 8 ファイル・PATCHES (a)〜(f)・`Localization/`。エラー 1 件（`FanControlWidgetSettings` が `Preferences` の `init()` を満たさない）→ PATCHES (a) の拡張に `init()` を追加。`group: Packages` 無しではドロップインがターゲットから落ちた（「member of multiple groups」警告と未定義エラー） |
| L1 | 成功（`-derivedDataPath .derivedData-lic`） | 全設定ペインを固定 760×640 pt に（Fan Control も同じヘルパーで作成）。CLT ハーネスも Build complete |

CLT ハーネス（`swift build --skip-update`、CLT のみ）は各段階後も **Build complete**（FanControl 関連は `#if canImport(FanControlKit)` で除外）。

起動確認（DEBUG フック経由のアプリ内スナップショット。画面収録権限が無いため `screencapture` は「could not create image from display」）:
ノッチパネル 3 枚（画面 3 つ）、閉状態は透明、`open` で黒いノッチ（Calendar + Timer、Fan Control + Timer）、設定ウィンドウ（General / Nook ▸ Widgets / Fan Control ほか）。
`osascript -e 'quit app "DynamicNotch"'` で正常終了。

## 設定 ▸ About ペイン（2026-10-20）
`Sources/AboutSettingsView.swift` を実装: アイコン・版・説明文、機種/チップ/macOS/手動ヘルパー有無（FileManager で plist とバイナリの存在確認）、診断コピー、OSS ライセンス一覧（mediaremote-adapter はチェックアウトに LICENSE が無く「リポジトリ参照」）。文字列 9 件は `Support/merge-strings.py` の `APP_EXTRA_*` に追加（en/ja 再生成）。

## ノッチウィンドウ（N1、2026-10-20、`-derivedDataPath .derivedData-notch`、開発用 bundle id `…DynamicNotch.dev`）

ユーザー報告: (1) 閉じるときノッチは上へ消えるが Fan Control ウィジェットのグラフ線がついてこない、(2) アニメーションがカクカクする、
(3) Fan 以外の要素が出ない。ユーザー決定により、初回の独自 `NotchPanel` / パネル生成 / `.onHover` 開閉を捨て、`WindowsManager` → `DisplayKit` の経路で組み直した。

**経路**: `WindowsManager`（`updateWindows` → `setupDisplayKitForScreen` → `DisplayKit`）、`DisplayKit.dynamicnotchWindow: BetterWindow?`、
`AcceptingFirstClickHostingView`、`NotchViewModel` のホバー状態機械（`setPointerOver(notch:band:)` → main キューで合流 → `hovering`、
`hoveringWillSet` の触覚）、`NotchView` の `.onContinuousHover(coordinateSpace: .local)` と枠高さ 250 pt。ノッチウィンドウの生成は
`DisplayKit.setupDynamicNotchWindow()`（新規）が行う。ウィジェット行は `NookWidgetGrid.swift`。

| 変更 | 内容 |
|---|---|
| 削除 | `WindowsManager.swift` の `NotchPanel`（NSPanel）と `DisplayKit.setupNotchWindow()`、`DisplayKit.notchPanel`、`NotchShape` の旧パス |
| 経路 | `setupDisplayKitForScreen` が `DisplayKit.setupDynamicNotchWindow()`（`WindowsManager.swift` 末尾、新規）を呼び、画面ごとに **`BetterWindow`** を `dynamicnotchWindow` に格納。ボーダーレス・透明・`mainMenu+3`・全 Space・固定 900×360、`AcceptingFirstClickHostingView(RootView)`、`sizingOptions = []`。**開閉中にウィンドウを一切リサイズしない**。`BetterWindow` に `isNotchWindow`（canBecomeKey）を追加 |
| ホバー | `.onHover { hovering = $0 }` → `.onContinuousHover(coordinateSpace: .local)` → `NotchViewModel.setPointerOver(notch:band:)`。`hovering` は値が変わるときだけ書く（毎マウス移動の @Observable 通知を防止）、変化時に `hoveringWillSet`（触覚）。`NotchViewModel` の「Non-@Observable」欄の格納プロパティを `@ObservationIgnored` に、`endScrub()` の書込を変化時のみに |
| 形状 | `NotchShape`: 旧版は「rect 中央に置いた角丸矩形、幅だけ animatable」で、高さがアニメせず枠の中央に置かれるため、閉じるとき黒い形が最終サイズに跳んで上へ滑っていた。新版は上辺に吊り下げ、上角の外向きの耳 + 下角の丸み、幅・高さ・半径すべて animatable |
| レイアウト | `NotchView.body`: 固定キャンバス（ウィンドウサイズ）に、固定サイズ（開いたサイズ）の中身を置き、**背景と同じ animatable `NotchShape` でマスク** + footprint の矩形 `.clipped()`（AppKit 製の子ビュー—カレンダーのスクローラ、`Menu`、テキスト欄—は SwiftUI のマスク/不透明度を無視するが矩形クリップには従う）。中身は開いている間フレームが変わらないので毎フレームの再レイアウトが無い。上段（ノッチ高）は開: `TopBarView`、閉: `ClosedNotchActivitiesView`（ライブアクティビティ）。背景形状は常に階層に残し、閉じた後 0.5 s で不透明度 0（旧版は `if shouldRender` で閉じた瞬間に消え、開くときは最終サイズで出現していた） |
| アニメーション | 開閉はモード変化 1 つ（`AnimationsModifier`: 開 `.notchOpen` = spring 0.42/0.82、閉 `.notchClose` = spring 0.36/1.0、ホバーの膨らみ `.notchHover`）。旧版は呼出元ごとに `.smooth` / `.defaultTransition` / **減衰 0.45 の spring**（閉じた大きさを行き過ぎて画面上端の外へ跳ねる）が混在。中身の blur は 10→4 pt、scale 0.9→0.94 |
| フック | 他パス用の差込口: `LiveActivities/`（`ClosedNotchActivityLayout.sideWidth` / `ClosedNotchActivitiesView` / `LiveActivitiesStartup.start()`、AppDelegate から呼ぶ）、`Support/NotchDrop.swift`（`NotchDropModifier`、footprint 大のヒット層に付く）、`Support/DebugHooks-{A,B,C}.swift` |
| DEBUG | `DN_DEBUG_CHANNEL=<名>`（通知名 `com.example.dynamicnotch.debug.<名>`。ユーザーの稼働インスタンスと混線しない）、`DN_DEBUG_OFFSCREEN=1`（ノッチ窓を画面外へ）、`DN_DEBUG_GHOST=1`（画面上・不透明度 2 %・マウス無視。計測用）、`animperf:<n>`（下記） |

**計測**（`animperf:6`、Mac14,9、メイン画面 100 Hz、3 画面、ウィジェット Fan Control（ダブルワイド）+ Timer + Calendar、開発用 bundle id の別ドメイン、`DN_DEBUG_GHOST=1`）。
メイン画面の `CADisplayLink`（main ランループ）のコールバック間隔を各遷移 0.9 s 記録。遅れたコールバック = フレーム期限に main スレッドが塞がっていた。
`bodyEvals` は遷移ごとの `NotchView.body` 評価回数（3 画面合計）。

| 版 | 遷移 | フレーム間隔 平均 / p95 / 最大 | ヒッチ（>15 ms）/遷移 | bodyEvals |
|---|---|---|---|---|
| 旧（HEAD、`NotchPanel`） | 開 ×6 | 10.06–10.12 / 10.03 / 13.7–17.7 ms | 0–1 | 3 |
| 旧 | 閉 ×6 | 9.96–10.28 / ≤10.05 / 10.0–30.0 ms | 0–2 | 3 |
| 新（N1） | 開 ×6 | 10.03–10.29 / ≤10.07 / 12.3–30.0 ms | 0–2 | 3 |
| 新 | 閉 ×6 | 9.99–10.23 / ≤10.07 / 20.0 ms | 1–2 | 3 |

結論: **main スレッドのフレーム落ちは新旧とも遷移あたり 0〜2 回で、カクつきの主因ではない**（2 秒ごとのファンのポーリングや body の再評価も遷移中は起きていない: 3 画面で 3 回）。
主因は幾何: 旧版の背景形状は `NotchShape.path(in:)` が 1 遷移あたり 3 回（3 画面で各 1 回）しか評価されず＝補間されずに最終サイズで出入りし、
高さが animatable でなく中央配置のため上へ滑り、中身はマスクされずその場でフェードしていた（グラフ線が残って見えた）。新版では背景とマスクが同じ形状値で補間される
（DEBUG の形状プローブ `NotchShape(probe:)` で、閉じる際の高さ 250→… の段階的変化を確認。SwiftUI は形状の補間を一部レンダーサーバ側で行うため、main スレッドでの `path(in:)` 呼出は毎フレームではない）。
実画面の見た目は画面収録権限が無く未確認（ユーザー確認待ち）。

**挙動差（要確認）**: ノッチ窓が `NSPanel(.nonactivatingPanel)` から `BetterWindow`（NSWindow）になったため、ノッチ内をクリックすると DynamicNotch がアクティブになり、
前面アプリのキーフォーカスが外れる可能性がある（`ForceFocusableWindow` はテキスト欄クリック時に明示的にアクティブ化する）。問題なら非アクティブ化パネルに戻す。

FanControl PATCHES.md (b-2)（e47c4e8 で追加されたホスト用フック）: `NotchView` に `.onChange(of: nookState.mode, initial: true)` →
`FanControlNookVisibility.nookVisibilityChanged(isVisible: mode == .nook)` を `#if canImport(FanControlKit)` で追加（ノッチ窓ごとに呼ばれるが冪等）。
Nook が閉じる／Tray に切り替わると「Nook 非表示中は一時停止」設定に従ってファンのポーリングが止まり、Nook を開くと再開する。
`NotchView.body` は型検査時間超過（"unable to type-check this expression in reasonable time"）になったため中身を `notchContent(...)` に分割。

### 機能の実装（N1 後半、並行 3 パス + 統合）

ファイル所有を分けて並行作業（各自 `.derivedData-{a,b,c}` / bundle id `…dev-{a,b,c}` / `.build-{a,b,c}`、画面外の開発用インスタンス）。

| パス | 結果 |
|---|---|
| A ウィジェット | 全 `NookWidget` を設定 ▸ Nook ▸ Widgets で追加・削除・並べ替え（「In the Nook」/「Available」、右に各ウィジェット設定）、Nook ▸ General に一覧・「Choose Widgets…」・間隔スライダ。ウィジェット行は 50 pt グリッド（Calendar 220、Media 250、Shortcuts/Mirror/Quick Apps 150、Notes/To-dos 200、Timer 170、Fan 100/250）+ 区切り線、820 pt 超は横スクロール。上段に Nook/Tray タブ（カメラの左）と設定ボタン（右）。Calendar（週ストリップ + 当日の予定、アクセス要求）、Timer（プリセット・進捗リング・ノッチを閉じても継続、`NookTimersStore.shared`）、To-dos、Notes（一覧 + 編集窓）、Mirror（表示中だけカメラ）、Shortcuts（`shortcuts list/run`）、Quick Apps（新規）。**ノート保存時のクラッシュ修正**（`NSAttributedStringTransformer.transformedValueClass` が `NSData` を返していた）。Mirror のアイコン名 `webcam.filled`（SF Symbol に無い）→ `web.camera.fill` |
| B ライブアクティビティ・メディア | `LiveActivities/`: カメラ左右の行、`LiveActivityCenter`（設定の写し・変化時のみ書込）、優先度選択、電池（充電開始 5 s / 20 % 以下）、カレンダー（N 分前〜開始 5 分後、`minutesBefore` 追加）、タイマー終了（4 s）、トレイ、`.fanAlert`（設定に関係なく常に表示）。`MediaManager` の修正（10 s ごとのリセット、誤キャストによるクラッシュの恐れ、操作をアダプタ経由に、`seek(to:)`）、Media Player ウィジェット（アートワーク・マーキー・シーク・操作・未再生時のアプリ起動）、設定 ▸ Live Activities の General/Customize。`PowerMonitor` の電源情報なしでのクラッシュ、`LiveActivityIconView` のサイズ 0 フォント、`BatteryIconView` の二重描画を修正 |
| C トレイ・ドロップ | `NotchDropModifier` / `NotchDropController`（AppKit のドロップビュー + 閉じたノッチ付近でのドラッグを検知するグローバルモニタ、ドラッグ中は Tray/AirDrop ターゲット）、ファイル・ファイルプロミス・画像・リンク・テキストの受理、トレイ（`Caches/<bundle>/TrayFiles/<UUID>/<元の名前>` にコピー、スタック、`trayState.json` で永続化、キーボード操作、QuickLook サムネイル、右クリックメニュー、ドラッグで取り出し）、`.tray` ライブアクティビティ、設定 ▸ Tray / Nook ▸ Drop Area。起動時の `Tray.shared` 再入クラッシュを修正 |
| 統合（リード） | `NotchView` の未使用ドロップ処理を削除、閉じたノッチの形状を完全透明にしない（不透明度 0.012。完全透明な画素はウィンドウサーバがクリック・ドラッグを素通しする）、`NookTimersStore.shared` を起動時に生成、SwiftData を `Application Support/<bundle id>/Nook.store` に（既定の `default.store` は全アプリ・全開発インスタンスで共有。旧ストアは 0 件だったため移行なし）、`project.yml` で MediaRemoteAdapter.framework を埋め込み（`embed: true`。従来は DerivedData の絶対パスから読込）、`NookWidgetGrid` に `import Settings`、新規 UI 文字列約 130 件を `merge-strings.py` の `NOTCH_EXTRA_JA`（最低優先）に追加 |

最終ビルド: Xcode（`.derivedData-notch`、`…dev`）**BUILD SUCCEEDED**、`codesign --verify --deep --strict` 成功、`Contents/Frameworks` に Lottie / MediaRemoteAdapter / Sparkle。
CLT ハーネス（`swift build --skip-update --scratch-path .build-lead`）**Build complete**。
起動確認（画面外インスタンス、すぐ終了）: 開いた Nook（Media Player に実際の再生中トラック、Fan Control ダブルワイド、Timer、To-dos）、Tray タブ（空）、閉じたノッチのメディアのライブアクティビティ。

統合後の計測（`animperf:4`、ウィジェット Media + Fan + Timer + To-dos）: 開 平均 10.06–10.32 ms・ヒッチ 1–2、閉 平均 10.22–10.66 ms・ヒッチ 1–2、
**閉じ始めに 30–60 ms の停止が 1 回**（ウィジェットのビュー木の破棄）。閉じ終わるまで中身を残す案を試したが、閉じる間ずっと AppKit ビューの更新が走り
（ヒッチ 15–18/遷移、p95 22–24 ms）悪化したため戻した。

## ノッチ N2: 可変幅・画面ごとの開閉・ホバー猶予・メニュー中は閉じない（2026-10-20、`-derivedDataPath .derivedData-notch2`、`…DynamicNotch.dev`）

ユーザー報告: (1) Fan Control（ダブルワイド）+ Timer + Calendar + Media で開いた中身が固定 900 pt の窓より広く両端が見切れる、(2) 開いたノッチの幅をウィジェット構成に合わせたい、
(3) 3 画面すべてのノッチが同時に開く、(4) ノッチ内の `Menu`（Fan Control のプロファイル選択など）を開くとポインタがメニュー窓へ移ってホバーアウト扱いになり、ノッチが閉じてメニューも消える。
追加目標（理想動作のデモ動画）: ホバーで開く、開いたパネル幅＝中身の幅、画面幅の約 80 % を超えるときはその幅で止めて行を横スクロール、ドロップでトレイへ直行。

| 項目 | 変更 |
|---|---|
| 幅の式 | `NookWidgetLayout.openWidth = min(max(rowWidth, 320), maxOpenWidth)`、`rowWidth = Σ width(widget) + (n−1) × (8 + 2 × separatorSpacing) + 2 × 12`（`width = cells × 50`。`widgetsWidthInPoints` と同じ 50 pt グリッド）、`maxOpenWidth = floor(画面幅 × 0.8)`。窓は `min(openWidth + 2 × 40, 画面幅)` × 360、画面の上端中央。例: Fan 250 + Timer 170 + Calendar 220 + Media 250、間隔 4 → 行 962 pt、窓 1042 pt（従来は 820 にクランプされ見切れ） |
| 窓のリサイズ | `NotchWindowGeometry`（`NotchHover.swift`、画面ごと、`DisplayKit.notchGeometry`）。`NotchView` が `@Default(.nookSettings)` と `@Default(.fanControlWidgetSettings)` を観測し、開いたサイズが変わったときだけ `.onChange(of: openFootprint)` → `geometry.fit(openWidth:)`（`setFrame` + アニメーション無効のトランザクションでキャンバス更新）。開閉の各フレームではリサイズしない。`WindowsManager.DisplayKit.notchWindowSize` / `notchWindowFrame` は削除 |
| 横スクロール | 行が開いた幅より広いときだけ `ScrollView(.horizontal)`（判定は環境値 `\.nookRowAvailableWidth` = 開いた幅。従来は固定 820） |
| 画面ごとの開閉 | `DynamicNotchState` を画面ごとに 1 つ（`DisplayKit.notchState`、`DynamicNotchState.perScreen[displayID]`）。`RootView` が `\.dynamicNotchState` に注入、`NotchView` の各 modifier（Shape/Gestures/Animations/Environments/LockedIndicator）は注入された state を使う。`TopBarTabsView` / `TopBarContentView` / `TrayView` / `MiniAlbumCoverView` も環境値へ。`NotchDropController` は `viewModel.screenNotchState`。`DynamicNotchState.shared` は計算プロパティになり「開いている画面 → ポインタ下の画面 → メイン画面」の state を返す（トレイのキー監視、DebugHooks 用。`_mode` を直接読み、他画面の Observation 依存を作らない）。FanControl の Nook 表示通知は `DynamicNotchState.anyScreen(in: .nook)` |
| ホバー | 閉じたノッチにホバー → 0.12 s 留まれば**その画面だけ**開く（デモどおり。タップは即時）。ホバーアウトは即閉じず、20 Hz のガード（閉じる保留中だけ動く）が「開いたノッチ + 左右 24 pt・下 56 pt の帯」の外に 0.32 s 居続けたら閉じる。帯の中・角の透明部分を横切る・クリックで窓がキーになる瞬間の `.ended` では閉じない |
| メニュー等 | ガードは次の間は閉じない: `NSMenu.didBeginTracking`〜`didEndTracking`（`NotchInteractionMonitor` が深さを数える。SwiftUI `Menu`・ポップアップ・コンテキストメニュー）、ノッチ窓の可視の子窓（ポップオーバー）・`attachedSheet`・ノッチ窓を parent に持つ可視窓、ノッチ窓がキーで first responder が `NSText`（テキスト編集中）、左ボタン押下中（トレイのファイルを Finder へドラッグ中・スクラブ中など）、`NotchInteractionMonitor.begin()/end()`（ウィジェットが明示する用。現状未使用） |
| ドロップ | `.dragging` → `.tray` へ移ったとき（ドロップ完了）ホバー中でなければガードを起動（ドラッグ中はホバーが報告されないため、従来はポインタが離れても開いたままだった）。ドラッグ検知・トレイ直行の流れ自体は N1 のまま（画面ごとの state になったので近い画面だけが開く） |
| DEBUG | `open` / `open:tray` はポインタ下の画面だけ、`open:all` / `open:tray,all`、`close` は全画面。`notchstate`、`hovertest`、`menutest:<x>,<y>`、`DN_DEBUG_MAX_OPEN=<pt>` |

**確認**（開発用インスタンス、`DN_DEBUG_CHANNEL=n2`、確認ごとに終了）:
- `open` → `notchstate`: 開いたのは 1 画面だけ（他の 2 画面は `closed`）。窓 1042×360（上記の 4 ウィジェット）。スナップショットで両端とも見切れなし。8 ウィジェット（Fan/Timer/Calendar/Media/Notes/To-dos/Mirror/Shortcuts）では行 1726 pt・窓 1806 pt（3840 pt 幅の画面）で全部表示。`DN_DEBUG_MAX_OPEN=700` では開いた幅 700・窓 780 で行が先頭から表示され右側が横スクロール。
- `hovertest`: ホバーアウト 0.2 s 後は `nook`、0.6 s 後は `closed`（猶予どおり）。
- `menutest:230,231`（Fan Control の「Automatic」プロファイルメニューをクリック）: メニュー表示中 1.5 s 時点で `mode=nook menuDepth=1 busy=1`（開いたまま）、メニューを閉じた 1 s 後に `closed`。
- `animperf:5`（`DN_DEBUG_GHOST=1`、1 画面のみ開閉）: 開 平均 9.98–10.22 ms・ヒッチ 0–1、閉 平均 10.00 ms・ヒッチ 0、**bodyEvals = 1/遷移**（従来は 3 画面ぶんの 3）。中身は従来どおり背景と同じ `NotchShape` でマスク（変更なし）。
- 実ポインタでのホバー（開く・角の横断・帯）とカレンダーの月送り矢印は、画面収録・アクセシビリティ権限が無く未確認（ユーザー確認待ち）。月送り矢印のクリックで閉じていた原因は、クリックで窓がキーになる際の一瞬の `.ended` と推定（猶予で吸収される）。

**デモ動画との対応**: 一致 — ホバーで開く・ポインタ下の画面だけ、物理ノッチから左右対称に広がる 1 つの形状のモーフ（N1 の animatable `NotchShape` + 中身のマスク・ぼかし・縮小）、開いた幅＝中身の幅、上限超過時は横スクロール、上段左に Nook/Tray・右に歯車、ドラッグでトレイ直行。
相違（残り） — パネルの高さ（デモは約 100 pt の低い行、こちらは 250 pt 固定でウィジェットが 218 pt 前提）、ウィジェットの見た目とセル幅（別エージェント W の担当）、開くときの「わずかに膨らんでから横へ」はホバー時の拡大（1.25 倍）→ 開くスプリングの 2 段で近似しているだけ。

## 設定ウィンドウを SwiftUI 標準の `Settings` シーンへ（2026-10-20、`-derivedDataPath .derivedData-settings`、開発用 bundle id `…DynamicNotch.dev-settings`）

ユーザー決定（UI は可能な限り Apple 純正風）により sindresorhus/Settings を撤去し、SwiftUI 標準の `Settings` シーンへ移行した。

| 項目 | 変更 |
|---|---|
| シーン | `App/DynamicNotchApp.swift`: `Settings { SettingsRootView() }`（以前は空の `SwiftUI.Settings { EmptyView() }` + `SettingsWindowController`） |
| 中身 | `Sources/SettingsRootView.swift`（新規）: `TabView(selection:)` に 8 タブ（General / Nook / Live Activities / Tray / Liquid Glass / Gestures / Fan Control / About、SF Symbols は従来どおり）。各タブを `.frame(width: 760, height: 640, alignment: .top)`（`SettingsRootView.contentSize`）で包むので切替で窓が伸縮しない（実測: 全タブで窓 760×728 = 内容 640 + タイトル/ツールバー 88） |
| タブ選択 | `SettingsNavigation.shared.pane`（`@Observable`、UserDefaults `settingsSelectedPane` に保存して次回も同じタブで開く）。ID 型 `AppSettings.PaneIdentifier`（旧パッケージと同じ綴り・`init(_:)`）を自前で定義したので、`showSettings(pane: AppSettings.PaneIdentifier("nook"))` の呼び出し側（Ext-A / NookWidgetGrid / DebugHooks）は `import Settings` 行の削除だけで済んだ |
| 開き方 | `WindowsManager.showSettings(pane:)` → 選択を設定 → `SettingsWindowOpener.open()`（`WindowsManager.swift`）。既存の可視ウィンドウ（identifier `com_apple_SwiftUI_Settings_window`）があれば前面へ、無ければアプリメニューの「Settings…」（⌘,、SwiftUI が `Settings` シーンに対して作る項目。LSUIElement でも存在）を `performActionForItem`。macOS 14 以降 `showSettingsWindow:` セレクタは無効、SwiftUI の `@Environment(\.openSettings)` はモジュール内の同名の `EnvironmentValues.openSettings: () -> Void` に隠されて取れない（型注釈でも解決不可）ため。`setupSettingsWindow()` は空（AppDelegate の呼び出しは残す） |
| サブタブ | **入れ子の `TabView` は `Settings` シーン内でツールバーへ吸い上げられる**（Nook の General/Widgets/Drop Area、Fan Control の General/Profiles/Sensors がトップのツールバーに並び、窓タイトルも内側のタブ名「General」になった）。そのため中央寄せのセグメンテッドコントロールに変更: ホスト側は `SettingsSubTabs`（SettingsRootView.swift）を Nook / Live Activities / Liquid Glass（Basic/Advanced。従来の BasicGlassTab/AdvancedGlassTab ボタンから置換）で使用、`FanControlSettingsView` は同等の `Picker(.segmented)` を内蔵。Live Activities と Fan Control のサブタブ選択は `@AppStorage`（`liveActivitiesSettingsTab` / `fanControlSettingsTab`）で記憶 |
| フォーム | sindresorhus の `Settings.Container` / `Settings.Section` を使っていた `LiquidSettingsView`、`MediaLiveAcitivitySettingsView`、`PipelinesSettingsTabView`（未使用）、FanControl の `FanControlGeneralTabView` / `FanControlWidgetSettingsView` を `Form` + `Section` + `.formStyle(.grouped)` に。FanControl 側は「ラベル + Spacer + ラベル無しコントロール」の HStack 行を標準のラベル付き `Toggle` / `Picker` / `LabeledContent` に置換（文字列キーは同じ）。ウィジェット設定のセンサー一覧は最大 220 pt の内側 ScrollView をやめ、フォームの行として並べる |
| 依存 | `project.yml` / `Package.swift`（harness）/ `FanControl/Tools/IntegrationTypeCheck/Package.swift` から Settings を削除（Package.resolved も更新）。About の OSS 一覧から Settings を削除 |
| 文字列 | `Support/merge-strings.py` に `SETTINGS_EXTRA_JA`（Liquid Glass / Basic / Advanced / Animation Effect）。en/ja とも再生成 |

**確認**（開発用インスタンス、`DN_DEBUG_CHANNEL=settings DN_DEBUG_OFFSCREEN=1`、確認ごとに終了）: `settings:<paneId>` で 8 タブすべて + Nook の Widgets / Drop Area、
Fan Control の Profiles / Sensors（`defaults write …dev-settings fanControlSettingsTab -int 1|2`）、Live Activities の Customize をスナップショット。
窓は常に 760×728、ツールバーは 8 項目のみ、タイトルは選択タブ名、クリップなし。DebugHooks の `click:` でセグメンテッドコントロールを押すと
（合成イベントのトラッキングループで）以後のコマンドが処理されなかったため、サブタブ切替の確認は defaults 経由にした。

追加（同日、アプリレビュー指摘への対応）: 「ログイン時に開く」が保存されるだけで何もしていなかったため、`GeneralSettingsView` のトグルを
`SMAppService.mainApp.register()` / `unregister()` に接続し、表示時に `SMAppService.mainApp.status`（enabled / requiresApproval をオン扱い）を反映。
設定ペインの日本語訳が無かった 32 キー（General / Gestures / Liquid Glass / Battery・Calendar・Media のライブアクティビティ設定など）を
`SETTINGS_EXTRA_JA` に追加し、ウィジェット名（`NookWidget.name`）は Settings ▸ Nook で `LocalizedStringKey` / `String(localized:)` 経由で表示。
`-AppleLanguages "(ja)"` のスナップショットでタブ名・一般タブ・ウィジェット一覧が日本語になることを確認（ログイン項目の登録自体は副作用を避けて未実行）。

## ウィジェットの Apple ネイティブ化（W1、2026-10-20、`-derivedDataPath .derivedData-widgets`、開発用 bundle id `…DynamicNotch.dev-w`）

ユーザー決定: ウィジェットを「できるだけ Apple 純正 UI に近く、かつ理想デモに合わせる」。共通部品は新規
`Sources/Support/NookWidgetChrome.swift`（`NookWidgetMetrics` 8/12 pt、`nookGlass(in:tint:interactive:)` = macOS 26 は Liquid Glass
`glassEffect`、14/15 は `.ultraThinMaterial`、`nookButtonStyle` = `.glass`/`.glassProminent` ↔ `.bordered`/`.borderedProminent`、
`NookRoundIconButton`、`NookChip`、`NookWidgetEmptyState`）。色は固定の白＋不透明度をやめ `.primary/.secondary/.tertiary` と
`.quinary/.quaternary` の塗りに、文字はシステムのテキストスタイル（タイマーの数字のみ rounded）に統一、各ウィジェットにアクセシビリティラベル。

| ウィジェット | 変更 |
|---|---|
| Media | 64 pt・角丸 12 のアートワーク（アプリアイコンのバッジ）、曲名 headline / アーティスト subheadline の 2 行、スクラバー 4→8 pt（ホバー/ドラッグ）+ 経過 / 残り（VoiceOver で ±10 s）、前・再生/一時停止・次。未再生は「Not Playing」タイル + アプリアイコン |
| Mirror | 暗い円（quaternary + 細い縁）に `web.camera` と「Mirror」、クリックで円形ライブプレビュー（ボタンとしてアクセシブル） |
| Calendar | 「Oct」（title3 bold）+ 選択日を中心に 5 日の 1 行（今日 = アクセント塗りの円、選択日 = quaternary の円、予定ドット、クリックで再センタリング、横ドラッグで 5 日送り）、「Today/明日/日付」見出し + Today チップ、予定行（カレンダー色のバー）または「Nothing for today」 |
| Notes | 選択中のメモをその場で編集（新規 `NoteInlineEditor`: RichTextKit、ダーク外観に追従）+ 書式バー（ウインドウで開く / A = 大きく・小さく / B / I / U、選択範囲の状態を反映）、右に最近のメモ 4 件の切替（頭文字のガラス円）と「+」 |
| Timer | `TimerCreatorView` を書き直し: h:m:s ホイール（スクロール・ドラッグ・前後値クリック・VoiceOver、`TimerHaptics`）+ 1m/3m/5m/10m チップ + 「…」メニュー（12h〜15m）+ 丸いアクセントの再生ボタン（前回の長さを記憶）。1 件実行中は進捗リング内に大きなカウントダウン + ×/一時停止/＋、複数は行リスト |
| To-dos | 「New task…」欄（フォーカスでアクセントの枠）+ リマインダー風の行（circle / checkmark.circle.fill）、未完了件数、ホバーでスター/削除 |
| Shortcuts / Quick Apps | 3 列のアイコングリッド（ショートカットは名前から決まる色タイル、実行中スピナー/チェック）、最後のセルに「+」タイル |
| Tray | Finder 風タイル（48 pt アイコン、選択時は名前がアクセントのカプセル）、ヘッダの操作を丸いガラスボタンに、空表示 `tray.and.arrow.down` |
| Fan Control | レイアウトは維持。上下 8 pt、見出し subheadline semibold secondary、RPM バー 4 pt + quaternary、空表示の書体、アクセシビリティ値、プロファイルメニュー `.controlSize(.small)`。レビュー指摘（low）対応: `onDisappear` の一時停止は表示中の Fan ウィジェットが 0 個のときだけ（`FanControlWidgetPresence`。PATCHES.md (b-2)） |

**スナップショット**（DEBUG、新規 `Support/WidgetGallery-Debug.swift`、コマンド `widgetgallery:<dir>`。DebugHooks と同じ通知名を自前で購読し、
最初にウィジェットが表示された時点で登録されるので先に `open` する）: 各ウィジェットをグリッド幅 × 行の高さ 202 pt でダーク（黒背景）/
ライト（ウインドウ背景）描画、Fan Control は 2x1 / 5x1、Tray、デモ順の 1 行。`cacheDisplay` は Liquid Glass を取り込めない（ガラスのボタンは
消え、大きなガラスは白くなる）ため、ギャラリー描画中は `NookGlass.forceFallback`（`DN_DEBUG_NOGLASS=1` でも可）で macOS 14/15 の
マテリアル表示にする。結果は `docs/widget-gallery/`（26 枚。`row-demo-dark{,-idle}.png`、`widget-<name>-<cells>x1-<dark|light>.png`、
タイマーは `-creator` / `-running` / `-list`）。実画面でのガラスの見た目は画面収録権限が無く未確認。

ビルド: IntegrationTypeCheck は Swift 5 / 6 とも Build complete、CLT ハーネス（`--scratch-path .build-widgets`）Build complete、Xcode は
自分の変更では成功（BUILD SUCCEEDED）。作業終盤に別作業の `FanControl/Package.swift` が `.macOS("26.0")` に上がり、`project.yml` が 14.6 の
ままのため素の Xcode ビルドは `FanControlHelper` で「module 'FanControlCore' has a minimum deployment target of macOS 26.0」で失敗する
（本作業とは無関係）。確認用には `MACOSX_DEPLOYMENT_TARGET=26.0` をコマンドラインで上書きしてビルドした（ファイルは変更していない）。

## レビュー指摘の修正（サービス・ウィンドウ・トレイ、2026-10-20、隔離ワークツリー `/tmp/dn-fix-r`）

`docs/adversarial-review-2026-10-20.md` の確定指摘のうち、ウィジェット View／設定 View／ローカライズ以外の 16 件を修正。

- Tray: 範囲選択の基点インデックスが削除後に古いまま `_files[min...max]` でトラップ → 範囲外を検証、`removeFile` / `updateFiles` / `unstack` / `removeSelectedFiles` で基点をリセット。クリックは Finder 準拠（素 = 単一、⇧ = 範囲、⌘ = トグル）
- TrayFile: キャンセルハンドラが weak self で fd を閉じられず漏れていた → fd を値で捕捉、`O_EVTONLY`
- CameraManager: グローバル並行キューからの setup/stop 競合 → 専用シリアルキューで直列化（`sessions` 読取も）
- AppDelegate: メニューバーを SF Symbol テンプレート画像に、「Settings…」(⌘,) /「Quit DynamicNotch」(⌘Q) をローカライズ。起動時に `LoginItemManager.syncSetting()` と AirDrop 一時ファイル掃除
- SliderPlusNegative: `EmptyView` → −／Slider／＋と値表示
- IntroView: ライト配色で可読化、「Get Started」と ✕ で閉じ `Defaults[.intro] = false` を保存（HelloView のダミーリンクは不使用）
- Note 編集ウインドウ: `ModelContext.didSave` で削除されたメモのウインドウを閉じる＋書込前に `isDeleted` 確認、willClose オブザーバを解除
- タイマー終了ライブアクティビティ: ストアの tick が先に expired にしても、期限直後に running から消えた項目を通知
- MediaKeyTap: 回らない GCD スレッドの run loop → 専用スレッドで `CFRunLoopRun()`
- VolumeAndBrightnessListener: `start()` を冪等に、繰り返しタイマーとウェイク監視の多重登録を解消
- MediaManager: TIFF 2 回エンコード比較 → ペイロードの base64 一致で旧 NSImage を再利用
- CalendarManager: EventKit 取得を専用キューへ、`events(on:)` は週単位キャッシュ（ミス時 1 クエリ／週、前後週と起動・ストア変更後にバックグラウンド先読み）、ストア変更通知を 300 ms で合流
- NotchDrop: AirDrop 用 `$TMPDIR/DynamicNotchTemp/<UUID>` を共有完了／失敗で削除、起動時に残骸を削除
- WindowsManager: 画面スケーリング変更でノッチ寸法が変わったら RootView を作り直す。画面が外れたら `FanControlNookVisibility.nookVisibilityChanged` を再評価
- 新規 `Support/LoginItemManager.swift`（`LoginItemManager`: SMAppService.mainApp の登録／解除／状態）
- FullscreenMonitor: 壁紙ウインドウが一致して常に全画面扱い → `.excludeDesktopElements`・レイヤー 0・自プロセス除外、CG 座標を Cocoa 座標に変換

ビルド: 作業ツリー全体のスナップショット（HEAD + 未コミット変更）で `xcodebuild`（`-derivedDataPath /tmp/dn-fix-r/.derivedData`、ad-hoc）BUILD SUCCEEDED、
`swift build --scratch-path /tmp/dn-fix-r/.build` Build complete。変更ファイルの新規警告 0（CalendarManager の既存の非推奨警告は残存）。実行時確認は未実施。

## ミラーの非円形化・アスペクト追従とウィジェット間隔の既定値（2026-10-20、隔離ワークツリー `/tmp/dn-A`）

ユーザー指示 (1)(3)。

- `MirrorWidgetView`: 円形をやめ、角丸長方形（`NookWidgetMetrics.cornerRadius` 12、continuous、`.quaternary` + 細線）。プレビューは
  `videoGravity = .resizeAspect`（トリミング無し）。映像欄はカメラのアスペクト比で、セル内に aspect-fit（高さ = 行 202 − 余白 2×8 = 186 pt が上限、
  幅はアスペクトに追従）。新設 `MirrorWidgetLayout`（`@Observable`、`shared.aspect`）: 起動前は選択カメラの `activeFormat` の寸法、無ければ 16:9。
  セッション開始後に `CameraManager.videoDimensions(for:)`（セッションキュー上で入力デバイスの `activeFormat` を読む）で実寸に更新。9:16〜21:9 にクランプ。
- **グリッド幅の要求（`NookWidgetGrid.swift` の所有者向け、未変更）**: 映像が行の高さいっぱいになるセル幅は
  `(186 × aspect + 16)` pt = 16:9 で 347 pt（6.94 セル）、4:3 で 264 pt（5.28 セル）。`NookWidgetLayout.cells(of:)` の `.mirror` を
  `MirrorWidgetLayout.shared.preferredCells()` にすれば追従する（`NookWidget.gridSizeType` の .medium=2 は幅に使われていないので変更不要）。
  現状の 150 pt のままでも縦横比は保たれ、16:9 なら 134×75 pt に縮小表示される。
- `CameraManager`: 上記 API の追加と、既存の「常に成功する条件付きキャスト」「未使用の `error`」警告 3 種を解消。
- `NookSettings.separatorSpacing` の既定値 0 → 24（設定スライダー `0...24` の最大値。範囲は変更なし）。保存済みの `nookSettings` がある環境には影響しない
  （`defaultProvider` の 0 は未使用のため未変更）。
- DEBUG: `mirrorpreview:<dir>`（`MirrorWidgetView.swift` 内のリスナー、先に `open`）で 16:9 / 4:3 × 推奨幅 / 現行幅の非アクティブ表示を PNG 化。

ビルド: `xcodebuild`（`-derivedDataPath /tmp/dn-A/.derivedData`、ad-hoc）BUILD SUCCEEDED、`swift build --scratch-path /tmp/dn-A/.build` Build complete。
変更ファイルの警告 0。dev バンドル ID・`DN_DEBUG_CHANNEL=a`・`DN_DEBUG_OFFSCREEN=1` で起動し `/tmp/dn-A-shots/` に撮影（カメラは起動していない。
ライブ映像のアスペクト更新は実機未確認）。

## トレイ右側の AirDrop 領域（UI 要件 (5)、2026-10-20、隔離ワークツリー `/tmp/dn-C`、開発用 bundle id `…DynamicNotch.dev-c`）

ユーザー決定: 開いたノッチの Tray タブの右側を AirDrop 専用のドロップ領域にする（理想デモの Tray / AirDrop 配置）。

| 項目 | 変更 |
|---|---|
| レイアウト | `TrayView` を 1 行の HStack に: 左（可変幅）= `.tray` ではファイル列 `TrayFilesScrollView`（空なら `TrayEmptyView`）、`.dragging` では Tray ターゲット（`DropAreaTrayTargetView`）。右（`TrayLayout.airDropZoneWidth` = 150 pt）= AirDrop 領域 `TrayAirDropZone`。両モードで同じ位置・大きさ（例: 幅 1126 の窓で tray (52,35,864×204) / airdrop (924,35,150×204)）。余白 `TrayLayout.insets`（上 4・左右 12・下 12）、間隔 8 |
| 見た目 | `DropAreaTargetView` を共通カードに作り直し: 角丸 16、通常は `.quinary` + 破線 `.tertiary`、ドラッグが乗るとアクセント 22 % + 実線アクセント 2 pt + アイコン 1.12 倍、ポインタのホバーは `.quaternary`。AirDrop のアイコンはシステムの `NSSharingService(.sendViaAirDrop).image`（無ければ SF Symbol）。文言は「AirDrop / Drop to send」「Tray / Drop files here」 |
| 開いたトレイでのドロップ | AirDrop 領域の前面に AppKit の受け口 `AirDropZoneDropView`（`DropArea.swift`）。ノッチ全体の受け口（`NotchDropController`）はアプリ内ドラッグを無視するため、**トレイのファイル／スタックをドラッグして領域に落とす**と、そのまま AirDrop 共有（`NotchDropTempFiles.airDrop(pasteboard:)`、新設）。Finder からのドラッグを領域に直接落とした場合も同じ。ファイル約束・画像・リンク・テキストは `$TMPDIR/DynamicNotchTemp/<UUID>` に実体化して送り、共有の完了／失敗で削除（既存の後始末を再利用。トレイのコピーと Finder の元ファイルは削除しない）。領域をクリックすると選択中（無ければ全部）のトレイファイルを送信。ツールチップ「Click or drop files to send via AirDrop」 |
| ドラッグ中（閉じた／開きかけのノッチ） | 従来どおり 2 ターゲット（Tray / AirDrop）。`.dragging` では AirDrop 領域は描画だけで、ドロップは `NotchDropController` が `hoveredDropTargetID` で振り分ける（ターゲット間・外は Tray）。フレームの収集（`DropAreaCoordPreferenceKey` → `targetsCoords`）は `TrayView` に移した |
| 「ドラッグで取り出したら削除」 | AirDrop 領域に落としたトレイファイルは送信中に消さない（`AirDropZoneDrops.record/consume`、`TrayFileView` / `TrayStackView` の `onDropCompleted`） |
| ヘッダー | AirDrop 領域を表示中はヘッダーの AirDrop ボタンを出さない（`TrayFilesScrollView(showsAirDropButton:)`）。設定 ▸ Nook ▸ Drop Area ▸ AirDrop を OFF にすると領域が消えボタンが戻る。トグルの下に説明文を追加 |
| 文字列 | `Support/merge-strings.py` に `TRAY_EXTRA_EN/JA`（Drop to send / Click or drop files to send via AirDrop / Drop Area の説明文）。en/ja 再生成（再生成で他作業の FanControl 文字列 6 件も反映された） |

変更ファイル: `TrayView`、`TrayFilesScrollView`、`TrayFileView`、`TrayStackView`、`DropArea`、`DropAreaTargetView`、`DropAreaTrayTargetView`、`DropAreaGeneralSettingsTabView`、
`Support/NotchDrop.swift`（`receivePromises` / `destinationDirectory` を static 化、`NotchDropTempFiles.airDrop(pasteboard:)`）、`Support/merge-strings.py`、`Localization/{en,ja}`。

ビルド: `/tmp/dn-C`（HEAD + 上記ファイル）で `xcodebuild`（ad-hoc）BUILD SUCCEEDED、`swift build --scratch-path /tmp/dn-C/.build` Build complete。変更ファイルの警告 0。
確認（`DN_DEBUG_CHANNEL=c`、`DN_DEBUG_OFFSCREEN=1`、確認後に終了。`/tmp/dn-C/shots/`）: `1-tray-open`（ファイル 10 件 + 右の AirDrop 領域）、`2-drag-tray` / `2-drag-airdrop`
（`traydrag:` で Tray / AirDrop がそれぞれ強調、`hoveredDropTargetID` も一致）、`3-tray-empty` と `4-drag-narrow`（最小幅 320 pt）、`5-airdrop-off`（設定 OFF でヘッダーのボタン復帰）。
未確認: 実ポインタでのドラッグ（トレイ → 領域、Finder → 領域）と AirDrop 共有シートの表示は、アクセシビリティ権限が無く合成できないためユーザー確認待ち。

## ToDo → Apple リマインダー連携（UI 要件 (6)、2026-10-20、隔離ワークツリー `/tmp/dn-E`、開発用 bundle id `…DynamicNotch.dev-e`）

ユーザー決定: ToDo はアプリ内に閉じ込めない。アプリ内 SwiftData の ToDo 実装とデータを**移行なしで破棄**し、EventKit の `EKReminder` で
リマインダー App のリストを閲覧・追加・完了する。

- 削除: `TodoItem.swift`、`TodoWidgetView.swift`、`TodoCreatorView.swift`、`TodoRowView.swift`、`TodoListWidgetSettings{,Key,View}.swift`。
  SwiftData のスキーマは `Schema([Note.self])`（`WindowsManager.swift`）。既存ストアの `ZTODOITEM` は SwiftData の自動軽量移行で
  落ち、`Note` は残ることを、同じ形の v1（Note + TodoItem）→ v2（Note のみ）の小さな実験で確認（CoreData が「Persistent History has to be
  truncated」をログに出すのみ）。Todo 専用の付随コード（`sampletodo:` デバッグコマンドと `deletesample:` の TodoItem 部分、
  `\.todoListWidgetSettings` 環境値とその RootView 注入）も削除。ギャラリーの `.todos` は `.reminders` に。
- 新規 `RemindersManager`（`@MainActor @Observable`、`shared`）: 起動時は要求せず状態のみ読む。ウィジェット／設定の「Allow Access」で
  `requestFullAccessToReminders()`、拒否・制限・書込のみは「Open System Settings」（`Privacy_Reminders`）。表示時に毎回状態を再読込。
  表示リスト = `RemindersWidgetSettings.listIdentifiers`（空 = `defaultCalendarForNewReminders()`）、`predicateForIncompleteReminders` を
  EventKit のキューで値型 `ReminderRow` に写して期日昇順（期日なしは後）→ 作成日昇順。`.EKEventStoreChanged` で 250 ms 合流の再読込。
  完了は丸をタップ → リスト色で塗り、0.9 s 後に `isCompleted = true` を `save(commit:)`（その間の再タップで取り消し、リマインダー App 準拠）。
  追加は `newReminderListIdentifier`（表示中のリストのみ有効、既定は先頭）へ `EKReminder` を保存。保存失敗は赤い caption。
  オフラインでもローカルストアに読み書き（iCloud 同期は後で）。DEBUG の `DN_DEBUG_REMINDERS_SAMPLE=1` は EventKit に触れずサンプル行を出す。
- `RemindersWidgetView`: リスト名（リスト色、複数リストなら「Reminders」）+ 件数、「New reminder…」欄（Return で追加しフォーカス維持、Esc で消去）、
  行 = 丸（複数リスト時はリスト色）・タイトル 2 行・期日（「今日」「明日, 15:00」「10月18日」、期限切れは赤、1 分ごとに再評価）。
  空は「No Reminders」。アクセス無しは `checklist` + 文言 + ボタンのコンパクト表示。
- `RemindersWidgetSettings`（`listIdentifiers`、`newReminderListIdentifier`、`showDueDates`。未知キーに寛容なデコード）、`RemindersWidgetSettingsKey`、
  `RemindersWidgetSettingsView`（アクセス状態、リストのトグル（未選択 = デフォルトのリスト）、複数時の追加先 Picker、期日表示）。
- `project.yml` の info に `NSRemindersFullAccessUsageDescription`（`Support/Info.plist` にも同文を反映）。entitlements は既存の
  `com.apple.security.personal-information.calendars`（リマインダーも同じ資源）で、変更なし。
- 文字列: `merge-strings.py` に `REMINDERS_EXTRA_EN/JA`（17 キー）、ToDo 専用の 11 キー（`Nothing to do`、`New to-do...`、`New task…` 等、
  `Star`/`Remove Star`/`Starred`、ToDo 設定 2 件）を削除して再生成。
- レジストリ（`NookWidget.reminders`、グリッド、追加リスト、`Defaults` キー）は別作業。隔離ビルドではその差分と Clipboard のスタブを当てた。

ビルド（HEAD + 本作業 + レジストリ差分）: `xcodebuild` BUILD SUCCEEDED、`swift build --scratch-path /tmp/dn-E/.build` Build complete、
本作業のファイルの警告 0。スナップショット（`DN_DEBUG_CHANNEL=e` / `DN_DEBUG_OFFSCREEN=1`、`widgetgallery:` と `snapshot:`）: サンプル行の
ダーク／ライト、未許可（ja、「ここにリマインダーを表示」+「アクセスを許可」）、設定ペイン（未許可 ja／サンプル en）。
未確認: 実際のアクセス許可ダイアログ・実リマインダーでの取得／追加／完了（TCC の許可はユーザー操作が必要なため未実施）。

## クリップボード履歴ウィジェットとウィジェット登録の更新（UI 要件 (4)(6)、2026-10-20、隔離ワークツリー `/tmp/dn-D`、開発用 bundle id `…DynamicNotch.dev-d`）

- 新規 `Sources/ClipboardHistoryManager.swift`: `NSPasteboard.general.changeCount` を 0.5 秒ごとにメイン run loop でポーリング（変化時のみ読取）。
  テキスト（最大 10 万字）、設定で画像（PNG、5 MB 以下）とファイル参照を、時刻と前面アプリ（推定の取得元）付きで記録。連続する同一内容は 1 件に統合。
  `org.nspasteboard.ConcealedType/TransientType/AutoGeneratedType` 等（パスワード管理アプリ）と除外アプリ前面時のコピーは記録しない。
  ポーリングは Clipboard ウィジェットが Nook にあり記録オンのときだけ（アプリ非表示での一時停止はしない: エージェントアプリはほぼ隠れず、他アプリでのコピーを取りこぼすため）。
  `copy(_:)`（自分の書込は履歴に二重登録せず、項目を先頭へ）/ `delete(_:)` / `clear()`。保存先 `~/Library/Application Support/<bundle id>/ClipboardHistory.json`（0600）と
  `…/ClipboardImages/<uuid>.png`、0.5 秒デバウンスでバックグラウンド書込、起動時に孤立画像を掃除。
- 新規 `ClipboardWidgetView`（見出し + 「消去」→「すべて消去」の 2 段確認、行 = 種類アイコン／画像サムネイル・2 行まで・相対時刻、クリックで再コピー＋チェック表示、ホバーで削除、空表示）、
  `ClipboardWidgetSettings`（`isRecording`、`historyLimit` 既定 50（10/25/50/100/200）、`captureImages`、`captureFiles`、`excludedBundleIDs`。欠損フィールド許容のデコード）+ `…Key`、
  `ClipboardWidgetSettingsView`（Form: 記録・件数・画像・ファイル、除外アプリ（NSOpenPanel で .app 追加）、履歴件数と「履歴を消去…」確認ダイアログ）。
- 登録: `NookWidget` から `case todos`（tag 6）を削除し、`case clipboard`（tag 9、`doc.on.clipboard`、4 セル = 200 pt）と `case reminders`（tag 10、`checklist`、4 セル）を末尾に追加
  （fanControl tag 8 は不変）。保存済みの `"todos"` は `.reminders` としてデコード（Nook の位置を引き継ぐ）。`NookWidgetGrid` の振り分け、`WidgetsSettingsTabView` の設定、
  `Ext-C.swift` に Defaults キー `.clipboardWidgetSettings` / `.remindersWidgetSettings`（`.todoListWidgetSettings` は削除）。`NookWidgetLayout.cells(of: .mirror)` は
  `MirrorWidgetLayout.shared.preferredCells()` に。`WidgetGallery-Debug` に `.clipboard` を追加。文字列は `merge-strings.py` の `CLIPBOARD_EXTRA_EN/JA`（31 キー）。
- ビルド（main d28e0c8 系 + 本作業 + Todo* 削除・Reminders 型の一時スタブ（ワークツリーのみ））: `xcodebuild` BUILD SUCCEEDED（本作業ファイルの警告 0）、
  `swift build --skip-update --scratch-path /tmp/dn-D/.build` Build complete。スナップショット（`DN_DEBUG_OFFSCREEN=1`、サンプル履歴を開発用 bundle id の Application Support に置いて記録オフ）:
  ギャラリーのダーク／ライト、開いた Nook の行（Clipboard / Reminders（`"todos"` から移行）/ Timer）、設定ペイン。確認後に開発用データと defaults は削除。
- 未確認: 実際のクリップボード監視（ユーザーのクリップボードを読み書きしないため実行時の取得は未試験）。**起動時に記録を始めるには `AppDelegate.applicationDidFinishLaunching` に
  `MainActor.assumeIsolated { ClipboardHistoryManager.shared.start() }` が必要**（現状はウィジェット／設定の表示時に開始。AppDelegate は本作業の所有外）。

## タイマーを iOS の Dynamic Island 方式に（2026-10-20、隔離ワークツリー `/tmp/dn-T`、開発用 bundle id `…DynamicNotch.dev-t`）

ユーザー指示 (6b)。調査メモは [`../docs/ios-timer-reference.md`](../docs/ios-timer-reference.md)（iOS 17〜26 の Clock／Dynamic Island と、2026-09 公開の
iOS 27 のコントロールセンターのスライダー。Apple の公式ページは本文取得不可のため第三者記事＋未検証の記憶を明記）。

| iOS | DynamicNotch |
|---|---|
| Clock のホイール + ラベル + 開始、Recents | ウィジェットの作成画面: h:m:s ホイール、チップ = 最近使った長さ（`NookTimersStore.recents`、最大 6 件、`nook_timers_recents`）→ プリセットの順で 4 個、「…」= Recents（即開始）+ プリセット、ラベル欄、緑の開始ボタン |
| Expanded（大きな残り時間・リング・一時停止・✕・ラベル） | 1 件: リング内にラベル／オレンジの大きな残り時間／終了時刻（🔔 16:37）、✕・一時停止（オレンジ）／再開（緑）・＋。複数: ロック画面風の行 |
| Compact | 閉じたノッチ: 左 = オレンジの進捗リング + `timer`（一時停止中 `pause.fill`）、右 = オレンジの残り時間（1 時間以上で幅 76 pt） |
| Minimal | 他のアクティビティ（メディア等）がある間は相手が compact、タイマーは右端の小さなリング（左右に 24 pt 追加して中央を維持） |
| 終了アラート（停止・繰り返し） | 閉じたノッチ: ベル + ラベル │ オレンジの「停止」（各側 104 pt、他の通常アクティビティより優先）。開いたノッチのウィジェット: ベル・ラベル・「繰り返す」・「停止」。音は「タイマー終了時」の設定で 2.5 秒ごとに反復し、「通知を表示する時間」（既定 1 分、10 秒〜5 分／停止するまで）で自動的に消える |
| タイマー終了時（サウンド／再生停止） | 設定: システムサウンド 14 種（既定 Glass、選択時に試聴）／再生停止（再生中のメディアを一時停止）／なし。「実行中のタイマーを閉じたノッチに表示」 |

- `NookTimersStore`: `alertingIDs`・`recents`・`islandEntry`（最も早く終わる実行中、なければ最後に一時停止したもの）・`stop` / `repeatTimer` / `stopAllAlerts` /
  `checkNow` / `onActivityChange`。残り秒は ceil（従来は round で最後の 0.5 秒が 0:00）。一時停止時に正確な残りを保存。毎秒の保存をやめ状態変化時のみ保存。
  起動時に 60 秒以上前に終わっていた実行中タイマーは鳴らさず終了扱い。永続化（`nook_timers_snap`）の形式は不変で、再起動後も実行中タイマーが閉じたノッチに出ることを確認。
  `init(persistent:)` はギャラリー用（読み書きしない）。
- `LiveActivities/` のタイマー部: `.timerExpired` を「タイマー」アクティビティとして、実行中／一時停止中（設定オン時）とアラート中に要求。
  `currentActivity` はアラート以外のタイマーを他のアクティビティに譲る、`timerIsMinimal`、`sideWidth` に minimal 分を加算、`syncTimerActivity()`。
  本日の別作業の期限監視（`NookTimerExpiryMonitor`）はそのまま残し、発火時に `checkNow()` で終了を即時反映（4 秒で消す処理は撤去）。
- `TimerWidgetSettings` に `soundName` / `alertSeconds` / `showInClosedNotch`（旧データを読めるよう `decodeIfPresent` の手書き `init(from:)`）。
- 共通部品（`TimerRowView.swift`）: `TimerProgressRing`、`TimerRoundButton`（記号はガラスの上に重ねる。ガラスの中に入れると着色ガラスで記号が消える／
  `cacheDisplay` に写らないため）、`TimerCapsuleButton`。色は iOS に合わせオレンジ（残り時間・リング・一時停止・停止）、緑（開始・再開）、グレー（✕・＋）。
- 文字列: `Support/merge-strings.py` に `TIMER_EXTRA_JA` / `TIMER_EXTRA_EN`（15 キー）を追加して再生成。
- 制約: 閉じたノッチはホバーで開くため、閉じたノッチの「停止」は押せる UI ではなく表示（停止はノッチを開いたウィジェットで行う）。タイマーウィジェットを
  Nook に置いていない場合はアラートの時間切れで消える。iOS 27 のスライダー型の作成 UI は未採用（ホイールのまま）。
- ビルド: HEAD c7a8349 + 本作業で `xcodebuild` BUILD SUCCEEDED（本作業ファイルの新規警告 0。`LiveActivityCenter.start()` の電池監視の既存警告 1 件は残存）、
  `swift build --skip-update --scratch-path /tmp/dn-T/.build` Build complete。
- 確認（自分のインスタンス、`DN_DEBUG_CHANNEL=t`・`DN_DEBUG_OFFSCREEN=1`、音は `soundName=""`）: 5 秒タイマー → 閉じたノッチの compact → アラート → 10 秒で自動消去、
  メディアと同時の minimal、再起動後の継続、開いたノッチの実行中／アラート表示。DEBUG コマンド `timergallery:<dir>`（`TimerWidgetView.swift`、
  一時ストアで描画）を追加。スナップショットは [`../docs/widget-gallery/ios-timer/`](../docs/widget-gallery/ios-timer/)（`timer-<状態>-<dark|light>.png`、
  `timer-notch-*.png`、実ウィンドウの `live-*.png`）。ガラスは `cacheDisplay` に写らないため実画面の見た目は未確認。


## 外部依存の削減（2026-10-20、Sparkle / SmoothGradient / Lottie / RichTextKit / CodeEditor+Highlightr）

ユーザー決定（CLAUDE.md「外部依存の削減」）の第 1 段。Defaults → `@AppStorage` は対象外（後続）。残る SwiftPM 依存は **Defaults と mediaremote-adapter のみ**
（`swift package show-dependencies` で確認、`Package.resolved` も 2 件に更新）。

| 依存 | 置換 | ファイル |
|---|---|---|
| Sparkle | 削除（ローカルビルドは自己更新しない）。`SparkleManager` / `SparkleManagerKey` / `\.sparkleManager` を削除、`RootView` の注入を撤去。`UpdateAppIconView` は Sparkle 参照のみ除去、`UpdateButtonIconView`（update.lottie）は `EmptyView`（MockTopBar の呼出しは不変） | 削除 2、変更 4 |
| SmoothGradient | 実使用は無く import のみ（`ShadowedNotchShapeView`、`NoteCodeEditor`）。置換として `EasedGradient`（`UnitCurve` に沿って 16 段の stop を置く SwiftUI `Gradient`）を `NoteCodeEditor.swift` に追加し、コードエディタ上下のフェードマスクに使用 | 変更 2 |
| Lottie | イントロの hello.lottie → `IntroWaveSymbol`（`hand.wave.fill` + `.symbolEffect(.wiggle.byLayer, .repeat(.periodic(delay: 1.6)))`、アクセント色）。`HelloView`（未使用）も同じ記号に。`project.yml` で `*.lottie`（6 個）をリソースから除外 | 変更 3 |
| RichTextKit | macOS 26 の `TextEditor(text: Binding<AttributedString>, selection:)` に置換（`NoteRichEditor.swift` に集約）。`NoteTextFormatting`（RichTextContext の代替: B/I/U/S・文字サイズ・選択位置のスタイル）、`NoteRichText`（NSAttributedString ↔ AttributedString。フォント・非無彩色の色・下線・取り消し線・リンク）、`NativeRichTextEditor`、`NoteRichEditor`、`NoteInlineEditor`（W1 のウィジェット内エディタ、API から RichTextKit とスクロール位置を除去）。`CRichTextEditor` / `CRichTextCoordinator` は削除。保存形式は不変（`NSAttributedStringTransformer` / `NoteDocument` は RichTextKit と同じ AppKit の RTF 読み書きを直接呼ぶ） | 削除 2、変更 9 |
| CodeEditor + Highlightr | `MonospacedTextView`（`NSTextView`、等幅 `monospacedSystemFont`、リッチテキスト・スマート引用符/ダッシュ/置換/スペル無効、Undo・検索バー有効）。`NoteCodeEditor` は `note.codeText` に直接バインド（以前の版は空のローカル状態で保存されなかった）。`LanguageDetector` は削除（ハイライト用途のみ）。`NotesWidgetSettings.codeEditorLanguage` は `String`（旧値は文字列で保存されているのでデコード互換）。`NoteMiniatureView` は等幅 `Text` | 削除 1、変更 4 |

- ノートのウィンドウ（`Support/Ext-A.swift` の `NoteEditorWindowContent`）: 従来の平文 `TextEditor`（初回編集で書式が消えていた）を `NativeRichTextEditor` +
  書式バー（太字 ⌘B／斜体 ⌘I／下線 ⌘U／取り消し線 ⇧⌘X／小さく ⌘-／大きく ⌘+）に、コードモードは `NoteCodeEditor` に。ウィジェットの B/I/U にも ⌘B/⌘I/⌘U。
- 範囲選択への書式適用は run ごと（`transformAttributes(in:)` は選択全体に 1 つのコンテナを渡し、斜体・下線が消えた）。文字オフセットで適用し選択を復元
  （`transform(updating:)` では選択が末尾に飛んだ）。状態表示は「選択中の全 run が持つスタイル」（TextEdit と同じ）。
- 保存（SwiftData の save）で `note.richText` が RTF から再生成され別オブジェクトになる（システムフォントは Helvetica Neue として読み戻される。RichTextKit 時代と同じ
  バイト列なので既存の挙動）。エディタは文字列が変わったときだけ再読込し、保存のたびにキャレットが飛ぶのを防いだ。
- 制約: 段落スタイル（配置・リスト・タブ）は SwiftUI のリッチテキストモデルに無く、旧ノートを**編集した時点で**落ちる（開くだけでは書き換えない）。無彩色（黒・白・灰）の
  文字色は読み込み時に外し外観に追従させる（旧エディタの `usesAdaptiveColorMappingForDarkAppearance` 相当）。`Note.scrollPos` は使われなくなった（モデルには残置）。
- About のライセンス一覧は Defaults と mediaremote-adapter のみ。文字列: `merge-strings.py` に `DEP_EXTRA_JA/EN`（「Strikethrough」= 取り消し線）を追加して再生成。
- 未対応（担当外ファイル）: `README.md` の `Support/clt-prepare.sh`・`strip-previews.py` の記述と両スクリプト自体（RichTextKit の #Preview 除去用。不要になった）、`.gitignore` の `Packages/` 行。
  ローカルの `Packages/RichTextKit`（git 管理外）は残置、`Package.swift` はもう参照しない。
- ビルド（HEAD 6909af2 のワークツリー + 本作業ファイル）: `xcodebuild` BUILD SUCCEEDED（本作業ファイルの新規警告 0。`NoteDocument` の既存 Sendable 警告 1 件は残存）、
  `swift build --skip-update` Build complete（エラー 0）。アプリ同梱物: Frameworks は MediaRemoteAdapter のみ、`.lottie` 0 個、Sparkle/Lottie へのリンク無し。
- 確認（自分のインスタンス、`DN_DEBUG_CHANNEL=dep`・`DN_DEBUG_OFFSCREEN=1`、bundle id `.dev`。ワークツリー限定の一時 DEBUG フックで検証し、フックは破棄）:
  イントロの手の記号、ウィジェット内エディタの太字/斜体/下線/赤/18 pt の表示（黒文字はノッチ上で白に追従）、ノートウィンドウの書式バーと選択位置の B 強調、
  範囲選択への太字・斜体・下線・取り消し線・拡大の適用と SwiftData への書き戻し（保存後も書式保持・再読込なし）、NSAttributedString→AttributedString→NSAttributedString→RTF
  の往復、等幅コードエディタ（直引用符のまま）。テストノート・Defaults は元に戻した。

## 閉じたノッチのタイマーアラート中はホバーで開かない（2026-10-20、隔離ワークツリー `/tmp/dn-S`、`DN_DEBUG_CHANNEL=s`）

不具合: タイマー終了のオレンジの「停止」カプセルが閉じたノッチに出るが、ホバー 0.12 秒でノッチが開き、ポインタが停止に届かなかった。

- 抑止条件: `NotchViewModel.hoverOpenSuppressed` = `NookTimersStore.shared.alertingIDs` が空でない **かつ** `LiveActivityCenter.shared.currentActivity == .timerExpired`
  （アラートが閉じたノッチに実際に出ている間だけ。カウント中／一時停止の compact・minimal は抑止しない）。`scheduleHoverOpen` が開始時と 0.12 秒後の発火時の両方で確認する。
  ホバー状態機械（画面ごと・猶予・メニュー追跡）は無変更。アラートが終わると次のホバーインから従来どおり開く（停止を押した時点で既にポインタが載っていても、その場では開かない）。
- 「停止」を実ボタンに（`TimerLiveActivityView`）: `store.stopAllAlerts()`。`ClosedNotchActivitiesView` は従来全体 `allowsHitTesting(false)` だったが、アラート中だけ有効にし、
  左側（ベル + ラベル）と中央の `Color.clear` は無効のまま（そこのクリックは従来どおりノッチを開く）。
- DEBUG: `hoverprobe:in|out|stop|state`（`NotchHover.swift`、`NotchInteractionMonitor.install()` が登録）。
- 確認（`DN_DEBUG_OFFSCREEN=1`）: 実行中ホバーイン → open、5 秒タイマー（4 秒）カウント中のホバーイン → nook に開く、アラート中 `suppressed=1 alerting=1` で 1.5 秒ホバーしても closed のまま、
  停止後のホバーイン → nook に開く。ボタンの実クリックはオフスクリーンのため未確認。
- ビルド: `xcodebuild` BUILD SUCCEEDED（本作業ファイルの新規警告 0）、`swift build` Build complete。

## Defaults → SettingsStore（2026-10-20、外部依存の削減の最後の項目）

sindresorhus/Defaults を撤去し、純正の設定保存層 `SettingsStore` に置換した。残るリモート依存は mediaremote-adapter のみ。

- 実装: `../FanControl/DynamicNotchIntegration/FanControlSettingsStorage.swift`（ドロップイン。アプリ・CLT ハーネス（シンボリックリンク
  `Sources/Support/SettingsStorage.swift`、`project.yml` は除外）・IntegrationTypeCheck（シンボリックリンク）で同じファイルを使う）。
  - `enum SettingKey`: 全キー名の文字列定数（旧 `Defaults.Keys` 名と同一。28 個）。
  - `StoredKeys` / `StoredKey<Value>`（`extension StoredKeys { static let x = Key<T>(SettingKey.x, default: …) }`、Defaults と同じクラス継承の仕掛けで `.x` 記法が使える）。
  - `StoredValue`（`storedObject` / `fromStoredObject`、`SendableMetatype`）。`CodableStoredValue` = JSON 文字列、`RawStoredValue` = 生値、Bool/Int/Double/Float/String/Data/Date はネイティブ、
    Array・`[String: V]`・Optional は要素ごと。
  - `SettingsStore`（`shared` = `UserDefaults.standard`、`init(defaults:)` でテスト用 suite）: `SettingsStore[.x]`（static / instance）、`value/set/reset/isDefault`、
    `observedValue(_:)`（キー単位の Observation 依存を登録。`Observable` に手書き準拠、`ObservationRegistrar` + キーパス `\.[revisionOf: name]`）、
    `SettingsStore.updates(.x, initial:)` → `AsyncStream<Value>`、`SettingsStore.updates([.a, .b], initial:)` → `AsyncStream<Void>`。
    変更検知は UserDefaults の KVO（Defaults と同じ）なので、ストア外の書込（`UserDefaults.standard.set`、DebugHooks の `defaults:`、`defaults write`）も届く。
    Observation の通知はメインスレッドで出す。`@MainActor` にはしていない（非ビューのコード・バックグラウンドからも同期で読むため。UserDefaults はスレッド安全）。
  - `@StoredSetting(.x) var x`（`DynamicProperty`。ビューは Observation で再描画、`$x` は Binding、`reset()`、`isDefaultValue`）。`@StoredSetting(SettingKey.x) var x = 既定値` も可。
- 保存形式（Defaults 8.2 の `CodableBridge` / ネイティブ型と同一）: Codable は `JSONEncoder` + `.sortedKeys` の UTF-8 **文字列**、読みは素の `JSONDecoder`。
  文字列でない／デコード不能な値は既定値として読む。Bool・数値・String・`[String]` はネイティブの plist オブジェクト。トップレベルの enum キーは無い
  （入れ子の enum は親構造体の Codable のまま）。
- 機械的置換（402 ファイル、うち実使用 約 95）: `import Defaults` 削除、`@Default(` → `@StoredSetting(`、`Defaults[` → `SettingsStore[`、
  `Defaults.updates(` → `SettingsStore.updates(`、`extension Defaults.Keys` → `extension StoredKeys` + キー名を `SettingKey.x` に、
  設定構造体・ドロップインの `Defaults.Serializable` → `Preferences` が含む／`CodableStoredValue`、入れ子 enum の `Defaults.Serializable` は削除。
  `Ext-C.swift` の `DefaultsKeyConvertible`（`Defaults[XSettingsKey()]` ブリッジ）は未使用なので削除。About のライセンス一覧から Defaults を削除。
- **一時シム**: 別セッションが編集中だった `Sources/LiveActivities/`（`Defaults[.x]`・`Defaults.Key`・`Defaults.Serializable`・
  `Defaults.updates`）と `Sources/NotchViewModel.swift`（`import Defaults` のみ）は未変更（`Sources/NotchHover.swift` は Defaults 未使用）。
  空のローカルパッケージ `Shims/Defaults`（モジュール名 `Defaults`）と `Sources/Support/DefaultsCompatShim.swift`（アプリ内 `enum Defaults`、型エイリアスと転送のみ）で
  コンパイルを通している。両ファイル移行後にシム一式を削除する（README.md「設定の保存」）。
- 互換性の証拠: `Tests/SettingsStorageTests`（ハーネスの `swift test`、5 tests）。ユーザーの実ドメインを `defaults export` で写し（読取のみ）、設定キーだけを
  `Fixtures/settings-2026-10-20.plist` に保存。存在する 8 キーすべてがフォールバック無しでデコードされ、`generalSettings`・`liquidBasicSettings` は再エンコードが
  **バイト一致**、`intro`・`quickAppsPaths`・`shortcutsWidgetSelection` はネイティブで一致。`nookSettings` は保存済みの "todos" を `NookWidget.init(rawValue:)` が
  "reminders" に読み替えるため（意図した値の移行）不一致、他のフィールドは一致。ハーネスには `case fanControl` が無いので写しから "fanControl" を除いて検査
  （Xcode ターゲットでは有る）。写しの全体（`DN_SETTINGS_PLIST`）でも同じ結果。Fan Control の 3 キーは `FanControl/Tools/IntegrationTypeCheck` の `swift test`
  （2 tests）: `fanControlGeneralSettings`・`fanControlWidgetSettings` はデコードされ、保存済みの全フィールドが一致（後から追加したフィールド
  `slowPollingOnBattery` / `showFanCurve` が再エンコードに加わるだけ）。書込形式 `{"alertHysteresis":5,"emergencyTemperature":95,"highTemperatureAlert":85}` も確認。
  KVO 経由の Observation 無効化と `updates` ストリームもテスト済み。
- マニフェスト: `Package.swift`・`project.yml`・`../FanControl/Tools/IntegrationTypeCheck/Package.swift` から Defaults を削除（IntegrationTypeCheck の
  `Package.resolved` はリモート依存が無くなり削除、`DynamicNotchApp/Package.resolved` は mediaremote-adapter のみ）。

## ショートカット／クイックアプリのウィジェットを行・列レイアウトに（ユーザー指摘「Start 1…」「Bitwar…」、2026-10-20、隔離ワークツリー `/tmp/dn-Q`、`DN_DEBUG_CHANNEL=q`、bundle id `…DynamicNotch.dev-q`）

- 各項目を 1 行に: 30 pt のアイコン（ショートカットは名前由来の色タイル、実行中／完了／失敗の記号は従来どおり）+ 右にフルネーム（`.callout`、1 行、本当に長いときだけ末尾省略、`.help` で全文）。
  行高 36 pt・行間 1 pt で 202 pt のセルに **1 列 5 行**（`NookRowColumnsMetrics.rowsPerColumn()`）。あふれた項目は右に新しい列。列幅は列内の最長名に合わせ 134〜220 pt、
  名前非表示（Quick Apps の「Show app names」オフ）や「+」だけの列はアイコン幅 38 pt。最後の列の末尾に小さな「+」行（ガラスの丸 + 「Add Shortcut」/「Add Apps…」、既存文字列）。
  ホバーは行全体の quaternary 塗り + アイコン 1.06 倍、押下は `ShrinkOnClick(0.96)`、アクセシビリティラベル・ヒント・コンテキストメニューは維持。
- 固有幅: `ShortcutsWidgetLayout.shared.preferredCells()` / `QuickAppsWidgetLayout.shared.preferredCells()`（`@Observable`、`UserDefaults.didChangeNotification` で
  選択・アプリ一覧・名前表示を追従。空のときは 3 セル）。グリッドが狭い間は列が横スクロールする（潰れない）。共通部品 `NookRowColumnsPlan` / `NookRowColumnsView` /
  `NookIconRow` / `NookAddRow` は `ShortcutsWidgetView.swift` に置き、`NookGridAddTile` は廃止。
- **グリッド側への依頼（未適用、`Support/NookWidgetGrid.swift`）**: `case .shortcuts: return ShortcutsWidgetLayout.shared.preferredCells()`、
  `case .quickApps: return QuickAppsWidgetLayout.shared.preferredCells()`。検証はワークツリー内でのみこの 2 行を当てた。
- 幅の実測（サンプル名）: ショートカット 3 件 218 pt（4.36 セル）、5 件 262 pt（「+」が 2 列目）、8 件 378 pt、12 件 543 pt（3 列）。クイックアプリ 3 件 150 pt、8 件 296 pt、12 件 436 pt。
- ビルド（HEAD 4d8c34c のワークツリー。移行前の HEAD なので `SettingsStore`/`@StoredSetting` を `Defaults`/`@Default` に置換して投入）: `xcodebuild` BUILD SUCCEEDED（本作業ファイルの警告 0）、
  `swift build --skip-update --scratch-path /tmp/dn-Q/.build` Build complete。
- DEBUG コマンド `rowwidgets:<dir>`（`ShortcutsWidgetView.swift`。ショートカット／クイックアプリのウィジェットが一度表示されると登録）: サンプルデータで 3/5/8/12 件の
  `shortcuts-<n>-<dark|light>.png` / `quickApps-<n>-…png`、旧 150 pt 幅の `shortcuts-8-at150-dark.png`、名前非表示の `quickApps-8-nonames-dark.png`。
  撮影は `/tmp/dn-Q-shots/`（実ノッチの `snap/1-BetterWindow.png` で可変幅を確認）。ガラスは `cacheDisplay` に写らないため素材フォールバックで描画。
- 未対応: 実行状態のアクセシビリティ値（「Running」「Failed」の文字列が未登録のため見送り）。

## カレンダーの選択日を常に中央に／内蔵ディスプレイで開いたノッチが見切れる（2026-10-20、隔離ワークツリー `/tmp/dn-CAL`、`DN_DEBUG_CHANNEL=cal`、開発用 bundle id `…DynamicNotch.dev-cal`）

ユーザー報告: (1) カレンダーで選択中の日が分かりにくい、選択日を常に中央に、(2) 4K 外部ディスプレイでは見切れないが MacBook 内蔵ディスプレイでは開いたノッチの中身が見切れる。

- **(2) 原因**: 内蔵ディスプレイは「スペースを拡大」最大（3024×1964 pt、倍率 1.0）で、`safeAreaInsets.top` = **64 pt**。開いたノッチの高さは
  `max(ノッチ高, 250)` = 250 固定だったため、ウィジェット行（218 pt 前提 = 250 − 既定スケールのノッチ 32）が 186 pt しか取れず、各ウィジェットの**下端が 32 pt 切れていた**
  （録画の Fan Control の CPU 行、ノートのツールバー、ミラーの枠）。幅は 0.8 × 3024 = 2419 ≥ 行 2409 pt なので横には収まっていた（窓 2489、左右の角も録画で見えている）。
- **修正**: `NotchView.expectedOpenFootprint` の高さを `max(ノッチ高 + NookWidgetLayout.rowHeight(218), 250)`（内蔵 64 pt → 282、外部 4K は従来どおり 250）。
  `NotchWindowGeometry.update` の上限を `min(画面幅 × 0.8, 画面幅 − 2 × 40)` に（窓が画面を超えない保証）。横スクロール時は `onScrollGeometryChange` で
  左右の隠れ量を取り、隠れている側だけ 28 pt のフェード（静止時の先頭はフェードなし）。窓の再計算は従来どおり画面ごとの `onChange(of: openFootprint)` → `geometry.fit`。
- コーディネーター依頼: `NookWidgetLayout.cells(of:)` の `.shortcuts` / `.quickApps` を `ShortcutsWidgetLayout.shared.preferredCells()` / `QuickAppsWidgetLayout.shared.preferredCells()` に。
- **(1) カレンダー**: 日付ストリップは常に選択日が中央（選択日 ±4 の 9 日を日付キーで並べ、中央 5 日を表示。クリック・‹ ›・「今日」チップ・横ドラッグ
  （指に追従、予測終点で日数を決定、最大 ±7）で選択が変わると `.snappy` でスライドして再センタリング）。選択日 = 塗りのアクセント円・白太字、今日（非選択時）=
  アクセントのリングと文字。見出し行に選択日（「今日 · 10月20日(火)」形式、入らなければ日付のみ）、右に「今日」チップと ‹ ›（新規文字列 "Previous Day" / "Next Day"、
  `merge-strings.py` の `CALENDAR_EXTRA_JA` で再生成）。下は選択日の予定一覧（従来どおり）。
- ビルド: `xcodebuild` BUILD SUCCEEDED（本作業ファイルの新規警告 0。`NotchHover.swift:104` の既存 Sendable 警告は残存）、`swift build --skip-update` Build complete。
- 確認（自分のインスタンス、`DN_DEBUG_OFFSCREEN=1`、ユーザーの nookSettings を複製、Fan Control は無効化）: 内蔵ディスプレイの窓 2489×360・開いたノッチ 2409×282 で
  ノートのツールバー等の下端まで表示。`DN_DEBUG_MAX_OPEN=1209`（既定スケール 1512 pt 相当）で窓 1289、行は横スクロールし右端にフェード。カレンダーは
  ワークツリー限定の一時フック（破棄済み）で +2 日（遷移途中のスライドを撮影）・−1 日・ドラッグ −40 pt・+5 日・今日 を確認。チップはガラスが写らないため `DN_DEBUG_NOGLASS=1` で確認。
- 未確認: 実ポインタでのドラッグ・スクロール時の先頭側フェード、予定のある日の表示（開発用 bundle id にカレンダー権限が無い）。

2026-10-20: Defaults → SettingsStore 移行完了。`NotchViewModel.swift` / `LiveActivities/` を移行し、互換シム（`Shims/Defaults`、`DefaultsCompatShim.swift`、project.yml / Package.swift の参照）を削除。

## アイコンをネイティブ化・新アプリアイコン・「ミラー」→「カメラ」（2026-10-20、隔離ワークツリー `/tmp/dn-ICON`）

- **監査**: `Image("…")` / `NSImage(named:)` によるカスタム画像グリフは `UpdateAppIconView` の `internalAppIconPaddingless`（旧アイコン画像）のみ
  → `NSApp.applicationIconImage`（新アイコン）に。`Ext-C.swift` の `ImageResource` 宣言は未使用のまま残置（設定移行中のファイルのため）。写真・アートワーク・GIF・ファイル/アプリのアイコンは対象外。
  ソース中の SF Symbol 名を `NSImage(systemSymbolName:)` で全数検査し、実在しない 4 件を修正（いずれも空白表示になっていた）: `magickeyboard.fill` → `keyboard`、
  `trackpad.fill` → `rectangle.and.hand.point.up.left`（`BluetoothManager`）、`chevron.left.forwards.slash.chevron.right` → `chevron.left.forwardslash.chevron.right`（`NoteView`）、
  ウィジェットのカメラ `web.camera.fill` → `web.camera`（他のウィジェットと同じ輪郭形）。`NookWidgetPlaceholder` を `.hierarchical` に（`NookWidgetEmptyState` と統一）。
  設定タブ（輪郭形、Nook のみノッチを表す塗り）、ウィジェット見出し（10 pt semibold・単色）、ライブアクティビティ（12 pt semibold・単色）は一貫しており変更なし。
- **アプリアイコン**: `Support/make-app-icon.swift`（`swift` で実行、出力は決定的）が CoreGraphics で 16〜1024 px（@2x 含む）を描画 → `iconutil` →
  `Support/DynamicNotchAppIcon.icns`、2× プレビュー `docs/app-icon/preview.png`。macOS アイコングリッド（1024 キャンバス、824 の連続角丸 r=185.4、グリッドの影）に
  グラファイトの 2 トーングラデーション＋上部の淡い光、白い単一グリフ（上辺にノッチの付いたディスプレイの輪郭＋中央に 3 枚羽根のファン）。SF Symbols はライセンス上アイコンに使わない。
  - 超楕円で近似した形は macOS 26 の Finder/Dock で灰色の「旧形式」プレートに入れられた（`NSWorkspace.icon(forFile:)` で確認）。SwiftUI の `.continuous` 角丸ではプレート無し。
  - `CFBundleIconFile: DynamicNotchAppIcon`（`Support/Info.plist` も同値）。
  - Icon Composer の `.icon` 形式は actool で `Assets.car` に焼く必要があるため見送り。
  - 同じパスで旧ビルドのアイコンがキャッシュされていることがある（Dock/Finder の表示が古い場合は `touch` してから `killall Dock`）。
- **メニューバー**: `rectangle.topthird.inset.filled`（テンプレート）を維持。上辺に帯のある画面 = 新アイコンの「上辺にノッチのある画面」と同じ読み。
- **「ミラー」→「カメラ」**（ユーザー依頼）: ウィジェット名・プレースホルダー・アクセシビリティラベルを "Camera"/「カメラ」に（既存キー）。設定の説明文を
  "…Click the preview to start or stop it."（`merge-strings.py` の `ICON_EXTRA_JA` で再生成）。enum `.mirror`・raw value・設定キーは不変、「映像を左右反転」も不変。
- ビルド（HEAD のワークツリー＋本作業ファイル）: `xcodebuild` BUILD SUCCEEDED、本作業による新規警告 0。バンドルに `DynamicNotchAppIcon.icns`、`CFBundleIconFile` = `DynamicNotchAppIcon`、
  `Bundle.image(forResource:)` と `NSWorkspace.icon(forFile:)`（新しいパスにコピーして確認）の両方が新アイコン。About 画面の実表示は未確認（ユーザーのインスタンスを起動しないため）。

## 開いたノッチの中身が全画面で下端見切れ（ユーザー報告、ビルド 8d7c18f、2026-10-20、隔離ワークツリー `/tmp/dn-CLIP`、`DN_DEBUG_CHANNEL=clip`、開発用 bundle id `…DynamicNotch.dev-clip`）

- **原因**（DEBUG `notchgeom` で実測、ユーザーのウィジェット 10 個を複製）: 幅・窓は正しかった（4K: 行 2685 = 開いた幅 2685、窓 2765、スクロールなし。内蔵: 行 2685 > 上限 2419 → スクロール、窓 2499。カメラのアスペクトを 4:3 に変えると両 4K の窓が 2682 に追従）。
  見切れは**縦**: Fan Control ウィジェット（ダブルワイド）の中身が最小 230 pt を要求し（プロファイルが Max 追加で 7 行 + センサー行）、セルの `.frame(maxHeight: .infinity)` は子の超過をそのまま通すので HStack（= 全セル）が 230 pt、行が 246 pt に伸び、218〜220 pt の枠で**全ウィジェットの下端**が約 26 pt 切れていた（ノートのツールバー、区切り線が枠の下端まで届く）。
- **修正**（`Support/NookWidgetGrid.swift`）: 各セルを `NookWidgetLayout.cellHeight`（218 − 4 − 12 = 202 pt）固定・上揃えでクリップし、行も 202 pt 固定。超過するウィジェットは自分のセル内でだけ下が切れ、他のウィジェットと行の高さには影響しない。
- **残り（FanControl ドロップインの担当へ）**: Fan Control ウィジェットの中身は 202 pt に収める必要がある（HEAD で 230 pt。センサー行の下が切れる）。新しい Temperature ウィジェットも同様。`notchgeom` の `OVERFLOWS` で確認できる。
- DEBUG `notchgeom`（`NotchHover.swift`）: 画面ごとの画面枠・ノッチ寸法・行幅・上限・開いた幅・フットプリント・窓・キャンバス・`scrolls`・`windowFits`、AppKit コントロールの位置と可視域、ウィジェットごとの幅と要求高さ（`OVERFLOWS`）。`notchgeom:aspect=<w/h>` でカメラのアスペクトを変えて 0.5 s 後に記録（窓の追従確認）。
- 内蔵ディスプレイのスナップショットでタイマーのホイール・チップ・ラベル欄が写らないのはガラスの描画が `cacheDisplay` に写らないため（`DN_DEBUG_NOGLASS=1` では全部写る。AppKit コントロールは可視域内）。
- ビルド: `xcodebuild` BUILD SUCCEEDED（新規警告 0。`NotchHover.swift:104` の既存警告のみ）。

## Shortcuts / Quick Apps のアイコンサイズ統一（2026-10-20、隔離ワークツリー `/tmp/dn-ICN`、`DN_DEBUG_CHANNEL=icn`）

- アプリアイコンは透明余白があり 30 pt 描画だと見た目が小さいため、`NookRowColumnsMetrics.appIconDrawSize = 34`（30 pt スロット内で中央に溢れ描画）に変更。
  ショートカットのタイルは 30 pt のまま角丸 7.5 → 7（`iconCornerRadius`、squircle 22% 相当）。「+」の円は 22 → 24 pt。行高 36・左インセット 4 は共通のまま。
- 実測（`rowwidgets:` 出力、1x）: Calendar アイコン／ショートカットタイルとも可視 30×30 px（36 pt 描画では 32 px だった）。
- ファイル: `ShortcutsWidgetView.swift`、`QuickAppsWidgetView.swift`。ビルド BUILD SUCCEEDED。スナップショット `/tmp/dn-ICN-shots/`（`shortcuts-*` / `quickApps-*` の dark/light）。

## Fan Control UI: 新エンジン・カーブ編集・選択の強調・温度ウィジェット（2026-10-20、隔離ワークツリー `/tmp/dn-FC2`、`DN_DEBUG_CHANNEL=fc2`、開発用 bundle id `…DynamicNotch.dev-fc2`）

- **エンジンの採用**: `FanCurveView` と目標表示を `FanProfile.curve(for:)`（`sample(count: 48…)`、PCHIP）/ `FanControlEngine.targetRPM(for: profile…)` に。動作点は `controlTemperature(for:)`。
  ブーストが 5 点の実カーブで描かれる。「最大」（`BuiltInID.max`）は一覧と設定の説明に入り、プリセットの説明がカーブに触れる（ブーストはアイドルでも約 5,500 RPM 以上になる旨と現在値を表示）。
- **カーブ編集**（`FanControlCurveEditorView.swift`、カスタム 1/2 のセンサー連動）: Swift Charts のライブカーブ・制御点・緊急温度の破線・動作点、点のドラッグ、10 °C グリッドの温度ピッカー＋RPM スライダ／ステッパー、
  点の追加／削除、「プリセットを使用」、検証メッセージ（エラーで保存・適用を無効化）。旧「開始温度／最大温度」ステッパーは撤去。
- **選択の強調**: ウィジェットの選択行 = アクセントのチェック＋太字の白文字＋ガラスのカプセル、他は淡色。7 行（最大を含む）が 2x1 / ダブルワイドとも 202 pt に収まる（`notchgeom`: 2x1 minHeight 194、ダブルワイド 175）。
- **温度ウィジェット**（新規 `NookWidget.temperature`、tag 11、`thermometer.medium`、5 セル）: `FanControlTemperatureWidget{View,Settings,SettingsView}.swift`。CPU / GPU / SSD の現在値・期間内の最高／最低・
  `temperatureHistory` の折れ線（1 / 5（既定）/ 15 / 30 分のチップ）・警告しきい値の赤破線。`notchgeom` minHeight 93。Fan Control ウィジェットから CPU / GPU / SSD の欄を削除（設定 ▸ センサーの主要温度は残す）。
  レジストリ: `NookWidget.swift`（case・icon・name・gridSizeType・prefs・rawValue、`WidgetPrefs` 準拠）、`NookWidgetGrid.swift`（`cells` = 5、振り分け。`cellHeight` 修正は維持）、
  `WidgetsSettingsTabView.swift`、`SettingKey.fanControlTemperatureWidgetSettings`。DEBUG: `fanpreview:` に温度ウィジェット（ライブ・合成履歴）・最大・カスタム 1（縦長）を追加、`widgetgallery:` に温度ウィジェット。
- 文字列: FanControl `Localizable/{en,ja}.strings` に 51 キー追加・旧 8 キー削除（en/ja とも 180 キーで一致）→ `merge-strings.py` で再生成。時計の「Now」（開始）と衝突しないようグラフの「now」は小文字キー。
- ビルド: `xcodebuild` BUILD SUCCEEDED（本作業ファイルの警告 0）、`swift build --skip-update --scratch-path /tmp/dn-FC2/.build` Build complete、IntegrationTypeCheck Swift 5 / 6 とも警告・エラー 0。
- スナップショット `/tmp/dn-FC2-shots/{fan,fan5,gallery}/`（`DN_DEBUG_NOGLASS=1`。ガラスは `cacheDisplay` に写らない）。分散通知が途中から届かなくなったため、後半はワークツリー限定の一時フック（`DN_DEBUG_RUN`、破棄）でコマンドを起動時に流した。
- 未確認: 実ノッチ表示、カーブ編集の操作（ドラッグ・保存・適用）、日本語・°F 表示。SMC 書込なし。

## バンドルの整理・英語のみ化（2026-10-20 夕方、隔離ワークツリー `/tmp/dn-STRIP`）

- **リソース**: `project.yml` から外部のリソースフォルダの参照を削除。`Contents/Resources` は `DynamicNotchAppIcon.icns`、`en.lproj/`、
  `MediaRemoteAdapter_MediaRemoteAdapter.bundle`（SwiftPM 生成）の 3 つだけ。
  Debug アプリ: **217,028 KB（212 MB）→ 25,796 KB（25 MB）**、`Contents/Resources` 187 MB → 820 KB。
- **生きていた 2 参照の置換**: カタログ色 `fineTuningBG` → `Color(.displayP3, 0.0902, 0.0588, 0.1020)`（`Support/Ext-C.swift`。
  `Height/WidthFineTuningView` は `Color.fineTuningBG`、`import DeveloperToolsSupport` 2 箇所と `ImageResource.internalAppIconPaddingless` を削除）。
  「Custom GIF」効果はユーザーが選んだ GIF を引き続き再生し、未選択・ファイル無しのときは SwiftUI 描画のイコライザ `AudioBarsView` を出す
  （GIF オプション自体を消すより変更が小さいのでこちらを採用）。同梱 GIF の選択 `PredefinedGIF` / `selectedGIF` は削除（保存済みの値はデコード時に無視）。
- **デッドコード削除（28 ファイル）**: 動画（`SlabVideoBackdrop`、`ShadowedNotchShapeView`、`AnimatablePoseVideo`、`VerticalAlignedVideoView`、
  `VerticalAlignedPlayerNSView`、`VPlayer`、`AVLooperPlayer`、`VideoFeatureView`、`ActualSizeCurrentWallpaperView`、`CurrentWallpaperManager`）、
  Metal（`LiquidGlassRenderer`、`LiquidLensView`、`LiquidLensRenderDelegate`、`LiquidLensPill`、`LiquidLensShadowView`、`ZeroCopyBridge`、`ContourSDFBaker`、
  `SDFScratch`、`LiquidGlass`。`import Metal` は残っていない）、Sparkle／変更履歴（`DynamicNotchUpdateFeedDelegate`、`UpdateButtonIconView`、`UpdateAppIconView`、
  `ChangelogView`、`ShowChangelogKey` + `EnvironmentValues.showChangelog`、`WindowsManager.showChangelogViewWindow()`、一般設定の
  「Show changelog after updates」トグル。`GeneralSettings.showChangelog` は保存形式維持のため未使用のまま残す）、`HelloView`（存在しないドメインへのリンク）、
  呼び出し元の無い `MockLiveAcitivitiesView` / `MockTopBar`、空の `PredefinedGIF.swift`。
- **英語のみ**: `Support/merge-strings.py` を en 専用に書き直し（ja 入力・全 `*_EXTRA_JA` を削除し、キー一覧 + FanControl `en.strings` から
  identity の `en.lproj` を生成。438 件 = 従来 439 件から削除したトグルの 1 件減）。`Localization/ja.lproj` と `FanControl/DynamicNotchIntegration/Localizable/ja.strings` を削除。
  Info.plist に `CFBundleDevelopmentRegion` en / `CFBundleLocalizations` [en]。
- **識別情報**: `CFBundleShortVersionString` 0.9.0 / `CFBundleVersion` 1。ドロップ領域設定の説明文を置換
  （ "Drop files on the notch to keep them in the tray or send them with AirDrop." に、未実装の「Customize pipelines」節を削除）。
  使用者の無い `com.apple.security.device.audio-input` entitlement と `NSAppleMusicUsageDescription` を削除。bundle id とアプリ名は変更なし。
- ビルド: `xcodebuild` BUILD SUCCEEDED（警告は既存のみ、ベースライン 49 → 46 種）、`codesign --verify --deep --strict` 成功、
  `swift build --skip-update --scratch-path /tmp/dn-STRIP/.build` Build complete、IntegrationTypeCheck Swift 5 / 6 とも Build complete。
  ビルド済みアプリに更新／パイプライン関連の識別文字列（`Customize pipelines`、`Sparkle` など）が無いことを確認。
- 未確認: 起動しての表示確認（Custom GIF 未選択時のイコライザ、微調整 UI の色）。

## Batteries ウィジェット（2026-10-20、隔離ワークツリー `/tmp/dn-BAT`、`DN_DEBUG_CHANNEL=bat`、開発用 bundle id `…DynamicNotch.dev-bat`）

- Notification Center の「バッテリー」ウィジェット相当。新規 `NookWidget.batteries`（tag 12、raw `batteries`、`battery.100percent`、設定キー `batteriesWidgetSettings`）。
  幅は `BatteriesWidgetLayout.preferredCells()`: 表示 5 台以下は 4 セル（200 pt、1 列）、6 台以上は 8 セル（400 pt、2 列）、10 台超は列内スクロール。
- データ源（公開 API・公開ツールのみ。`BatteryDevicesManager`、30 s（設定）ごと＋IOPS 通知＋Bluetooth 接続/切断（IOBluetooth、許可時）＋スリープ復帰 5 s 後）:
  1. この Mac: `IOPSCopyPowerSourcesInfo` / `IOPSGetPowerSourceDescription`（容量 %、充電中、AC/電池。名前はコンピュータ名から製品名 "MacBook Pro"）。
  2. HID アクセサリ: IOKit レジストリ `AppleDeviceManagementHIDEventService` ＋ `BatteryPercent` を持つ `IOHIDDevice`（`ioreg -r -k BatteryPercent` 相当）。
  3. `/Library/Preferences/com.apple.Bluetooth.plist` ▸ `DeviceCache`（**macOS 26 では DeviceCache 自体が無い**。旧 macOS 用に残し、無ければ 0 件）。
  4. `system_profiler SPBluetoothDataType -json`（約 0.5 s、バックグラウンド）: 接続中機器の名前・アドレス・種別と `device_batteryLevel{Left,Right,Case,Main}`。**macOS 26 の AirPods の残量はここにしか無い**。権限不要。
  5. CoreBluetooth 電池サービス（0x180F / 0x2A19）: システムが接続済みの BLE 機器（サードパーティ製キーボード等）。Bluetooth 許可済みのときだけ（ウィジェットから許可ダイアログは出さず、設定に「Allow Bluetooth Access」）。
  同一機器は Bluetooth アドレス（LE は名前）で統合。並びはこの Mac → 名前順。AirPods は左右の低い方を 1 行、ケースを別行（"… Case"）。Apple 製品は "<owner>’s AirPods Pro" → "AirPods Pro"。
- この Mac（Mac14,9、macOS 26）での実測（`batlog`）: MacBook Pro 50 %（AC・充電保留）＝IOPS、Magic Trackpad 15 %（低残量で赤）＝IOKit、AirPods Pro 74 %・AirPods Pro Case 47 %＝system_profiler、
  Cornix 67 %＝CoreBluetooth（開発インスタンスの Bluetooth 許可は 2 回目の起動時点で allowedAlways だった）。Bluetooth plist は 0 件。
- 設定: この Mac の表示、指定 % 未満のアクセサリを隠す（なし / 5 / 10 / 20 / 50）、更新間隔（15 s / 30 s / 1 分 / 5 分）、Bluetooth 許可、検出中の機器一覧。
- ファイル: 新規 `Sources/BatteryDevicesManager.swift`、`BatteriesWidgetView.swift`、`BatteriesWidgetSettings.swift`（`StoredKeys.batteriesWidgetSettings` もここ）、`BatteriesWidgetSettingsView.swift`、
  `Support/DebugHooks-Batteries.swift`（DEBUG: `batlog`、`batpreview:<dir>`）。最小差分: `NookWidget.swift`、`Support/NookWidgetGrid.swift`、`WidgetsSettingsTabView.swift`、
  `Support/DebugHooks.swift`（`handleBatteries` 1 行）、`Support/merge-strings.py`（`BATTERY_EXTRA_EN`、英語のみ）→ `en.lproj` 再生成（+24 キー）。PATCHES.md は不変。
- ビルド: `xcodebuild` BUILD SUCCEEDED（本作業ファイルの警告 0）。スナップショット `/tmp/dn-BAT-shots/`（`batteries-{live,sample,many,empty}-{dark,light}.png`、`settings-*.png`、`notch/1-BetterWindow.png` = 実ノッチ行）。
- 制約: `BatteryStatusFlags`（HID の充電中判定）のビット意味は非公開で推定。AirPods の充電中は system_profiler に無く表示不可。Magic 機器の種別は名前・通知種別名・Apple の ProductID 表で推定。

## World Clock ウィジェット（2026-10-20、隔離ワークツリー `/tmp/dn-W16`、`DN_DEBUG_CHANNEL=w16`）

- `NookWidget.worldClocks`（tag 16、raw `worldClocks`、アイコン `globe`、設定キー `worldClocksWidgetSettings`）。macOS の World Clock ウィジェット風の都市タイル列: 短縮ラベル（4 文字以下の上書きはそのまま、複数語は頭文字 NY、他は先頭 3 文字 TOK/CUP）、大きな時刻（12/24 時間: システム / 12 / 24 を選択、システムは `j` テンプレートで判定）、日付（Today/Yesterday/Tomorrow）とこの Mac との時差（`−16h`、`+5:30h`）、現地 6:00–17:59 は明るいタイル・夜は暗いタイル、任意のアナログミニ文字盤（秒表示時は秒針）。更新は分境界ごと（秒表示時は毎秒）の `TimelineSchedule`。
- 幅: 1 時計 84 pt（秒表示 104 pt）+ 間隔 6 pt + 余白。`WorldClockWidgetLayout.preferredCells()` が `SettingsStore.shared.observedValue` で設定を追跡し、時計の追加・削除で行幅が変わる。既定はこの Mac + 東京・Cupertino（America/Los_Angeles）・New York・London（この Mac と同じゾーンは省く）。最大 8 個。
- 設定: 時計一覧（ラベル上書き、上下移動、削除、`onMove`）、`TimeZone.knownTimeZoneIdentifiers` の検索（都市名前方一致 → 識別子・ローカライズ名の部分一致、30 件）と追加、「この Mac のタイムゾーンを追加」、秒表示・時刻形式・アナログ文字盤・昼夜の色分け。
- ファイル: 新規 `Sources/WorldClockWidgetSettings.swift`（`WorldClock`、設定、`StoredKeys.worldClocksWidgetSettings`、`WorldClockWidgetLayout`）、`WorldClockWidgetView.swift`、`WorldClockWidgetSettingsView.swift`、`Support/DebugHooks-WorldClock.swift`（DEBUG: `worldclockpreview:<dir>`。ウィジェット表示時に自前のリスナーを入れる。`handleWorldClocks` は DebugHooks の default 分岐に連結も可だが本体には未追加）。最小差分: `NookWidget.swift`（7 行）、`Support/NookWidgetGrid.swift`（2 行）、`WidgetsSettingsTabView.swift`（2 行）、`Support/merge-strings.py`（`CLOCKS_EXTRA_EN`、英語のみ。`Localization/` は再生成していない）。
- ビルド: `xcodebuild` BUILD SUCCEEDED（本作業ファイルの警告 0。他エージェントの作業中ファイル Pomodoro/Network/Bluetooth/SystemStats/Weather/NextUp/Capture/Calculator はワークツリーから外して確認）。スナップショット（固定時刻 2026-10-20 09:23 UTC = 東京 18:23）: `worldclock-{live,sample,sample12h,seconds-dial,many,empty}-{dark,light}.png`、`settings-{dark,light}.png`。

## Focus（Pomodoro）ウィジェット（2026-10-20、隔離ワークツリー `/tmp/dn-W22`、`DN_DEBUG_CHANNEL=w22`）

- **新規** `NookWidget.pomodoro`（tag 22、raw "pomodoro"、`brain.head.profile`、表示名 "Focus"、4 セル = 200 pt）。設定キー `pomodoroWidgetSettings`（`PomodoroWidgetSettings.swift` 内で宣言）。
  集中／短い休憩／長い休憩（既定 25 / 5 / 15 分、4 回ごとに長い休憩、選択肢付き）、開始・一時停止・スキップ・リセット、サイクル内のセッションドット、今日の完了数、任意のタスク名（すべて UserDefaults `nook_pomodoro_state` に永続化。実行中は再起動後も継続、起動前 60 秒超に終わった区間は鳴らさず進める）。
  「休憩／集中を自動で開始」（音を 1 回）、「閉じたノッチに表示」。
- 終了アラート: タイマーの「When Timer Ends」の音（Stop Playing / None を含む）を 2.5 s ごとに繰り返し、Stop・次の区間の開始・タイマーの「Alert Duration」で止まる。ウィジェットはベル + "Focus Done" / "Break Over" + 次の区間 + Stop / Start Break・Start Focus。
- 閉じたノッチ: 新しい `LiveActivity.pomodoro`（タイマーの compact と同じ寸法: 緑（集中）／青（休憩）の進捗リング + 記号 | 残り時間、アラート中はベル + タイトル | 次の区間の記号と長さ。表示のみ、操作はウィジェットで）。優先度は `timerExpired` の直後。タイマーが同時に動くとタイマーが minimal 側に回る（既存のロジック）。
- タイマーのファイルは変更せず、`TimerProgressRing` / `TimerRoundButton` / `TimerCapsuleButton` / `TimerRowView.countdownText` / `TimerInsets` を再利用。
- ファイル（新規）: `Sources/PomodoroWidgetSettings.swift`、`PomodoroStore.swift`、`PomodoroWidgetView.swift`（ウィジェット、ライブアクティビティ、`PomodoroInsets`、DEBUG `pomodorogallery:<dir>`）、`PomodoroWidgetSettingsView.swift`。
  レジストリの追加行: `NookWidget.swift`（case・icon・name・gridSizeType・prefs・rawValue・init）、`NookWidgetGrid.swift`（cells 4・振り分け）、`WidgetsSettingsTabView.swift`、`LiveActivity.swift`（case・icon・id・name・init）、
  `LiveActivitySelectionManager.swift`（優先度 1 行）、`LiveActivityView.swift`（`case (.pomodoro, _)`）、`LiveActivities/`（幅の case と `PomodoroStore.shared.start()`）、`Support/merge-strings.py`（`POMODORO_EXTRA_EN`。Localization は未再生成）。
- ビルド: `xcodebuild` BUILD SUCCEEDED、`swift build --skip-update --scratch-path /tmp/dn-W22/.build` Build complete（Pomodoro ファイルの警告 0。ワークツリーでは他エージェント作業中の NextUp / SystemStats / DebugHooks-Capture を除外してビルド）。
- スナップショット `/tmp/dn-W22-shots/`（`pomodoro-{idle,running,paused-break,long-break,alert}-{dark,light}.png`、`pomodoro-settings-*.png`、`pomodoro-notch-{compact,paused,break,alert}.png`。`DN_DEBUG_NOGLASS=1`）。
- 未確認: 実ノッチでの表示・実時間での区間終了と音・設定 ▸ Live Activities の一覧への追加（`LiveActivitiesGeneralSettingsTabView.configurable` は未変更）。

## Menu Bar ウィジェット（隠したメニューバー項目、2026-10-20、隔離ワークツリー `/tmp/dn-W26`、`DN_DEBUG_CHANNEL=w26`、開発用 bundle id `…DynamicNotch.dev-w26`）

- **新規** `NookWidget.menuBarItems`（tag 26、raw "menuBarItems"、`menubar.rectangle`、5 セル = 250 pt、設定キー `menuBarItemsWidgetSettings`）。ファイル: `MenuBarItemsManager.swift`、`MenuBarItemsWidget{Settings,View,SettingsView}.swift`、`Support/DebugHooks-MenuBar.swift`（独自の observer。`DebugHooks.swift` は未変更）、技法メモ `../docs/menubar-items-reference.md`（Ice（MIT）は技法の参照のみ。コードは流用していない）。
- 仕組み（公開 API のみ）: 自前の区切り NSStatusItem（`autosaveName` "DynamicNotchMenuBarSeparator"）を長さ 10 000 にすると左側の項目が画面外へ押し出される（実測では長さが 5016 に丸められたが、押し出しは有効）。表示中は `chevron.compact.left`。項目の列挙は `CGWindowListCopyWindowInfo`（layer 25、区切りと同じ行）。画像は ScreenCaptureKit `SCScreenshotManager`（画面外へ押し出した項目も撮れた）。クリックは一時的に表示 → 項目の中心へ `CGEvent` 左/右クリック（window-under-pointer フィールド付き）→ メニューが閉じたら隠し直す。「常に表示」アプリは明示ボタンで ⌘ ドラッグ。
- **macOS 26 の実測**: すべての項目ウィンドウの所有者は Control Center（CGWindowList・SCK とも）。`button.window.windowNumber` はダミー値で、frame だけが正しい。タイトルは表示中のメニューバーでは autosave 名、他ディスプレイのコピーでは bundle id。所有アプリは AX の `AXExtrasMenuBar`（位置 → アプリ。全走査 12.9 s のためバックグラウンドで実行）、bundle id のタイトル、他ディスプレイの対応コピー、Control Center 名の順で解決。
- 権限: 画面収録（無い場合は名前とアイコンの一覧に縮退）とアクセシビリティ（無い場合はクリックで 8 s 以上表示するだけ）。シェルから起動した開発用インスタンスは両方とも許可済みだった（責任プロセスであるターミナルの権限）。
- 確認: 区切りの配置と行の判定（3 ディスプレイ構成で隣接ディスプレイの項目を除外できた）、テスト項目の非表示と画像取得（35×30）、**左右クリックの転送が `[MenuBar] test item clicked` で届いた**、プレビュー各状態と実ノッチのスナップショット。
  注意: 縮める（隠す）テスト中に、後から起動した別エージェント（W18）の項目が区切りの左端に置かれ、約 10 秒隠れた（すぐに戻した）。新しく起動したアプリの項目は左端に入るため、既定では隠れる。
- レジストリ: `NookWidget.swift`（7 行）、`NookWidgetGrid.swift`（cells 5・振り分け）、`WidgetsSettingsTabView.swift`、`AppDelegate.swift`（`MenuBarItemsManager.shared.start()`）、`Support/merge-strings.py`（`MENUBAR_EXTRA_EN`。Localization は未再生成）。
- ビルド: `xcodebuild` BUILD SUCCEEDED（本ファイルの警告 0）、`swift build --skip-update --scratch-path /tmp/dn-W26/.build` Build complete（ワークツリーのみ、HEAD の `Color.fineTuningBG` 欠落をスタブで補完）。スナップショット `/tmp/dn-W26-shots/`（`menubar-{live,sample,sample-noscreen,sample-noax,empty,off}-{dark,light}.png`、`settings-*.png`、`notch/1-BetterWindow.png`）。
- 未確認: 画面収録／アクセシビリティが無い状態での実動作（プレビューのみ）、隠した状態からの一時表示 → クリック → 自動で隠し直す流れ（他アプリの項目を隠さないよう未実施）、「Move to Menu Bar」の ⌘ ドラッグ（未実施）、ノッチのある内蔵ディスプレイを主にした構成。

## System ウィジェット（CPU / GPU / メモリ / ディスク、2026-10-20、隔離ワークツリー `/tmp/dn-W15`、`DN_DEBUG_CHANNEL=w15`、開発用 bundle id `…DynamicNotch.dev`）

- **新規** `NookWidget.systemStats`（tag 15、raw "systemStats"、`gauge.with.dots.needle.33percent`、5 セル = 250 pt、設定キー `systemStatsWidgetSettings`）。ファイル: `SystemStatsMonitor.swift`（サンプラ）、`SystemStatsWidget{Settings,View,SettingsView}.swift`、`Support/DebugHooks-SystemStats.swift`（独自の observer。`DebugHooks.swift` は未変更）。`SettingKey.systemStatsWidgetSettings` は `SystemStatsWidgetSettings.swift` の extension（FanControl 側の `SettingKey` は未変更）。
- 情報源（公開 API・読取のみ）: CPU = `host_processor_info(PROCESSOR_CPU_LOAD_INFO)` の差分（E/P の区別は IODeviceTree `cpus/*` の `cluster-type` を `logical-cpu-id` で一度だけ読む。Mac14,9 は cpu0–3 = E、4–9 = P）、メモリ = `host_statistics64(HOST_VM_INFO64)`（使用 = app(internal − purgeable) + wired + compressed）・`hw.memsize`・`vm.swapusage`・`kern.memorystatus_vm_pressure_level`、ディスク = IOBlockStorageDriver `Statistics` の Bytes (Read)/(Write) 合計の差分、GPU = IOAccelerator `PerformanceStatistics`。**この Mac（M2 Pro、macOS 26.5）のキーは `"Device Utilization %"`**（ほかに `"Renderer Utilization %"`、`"Tiler Utilization %"`。`"GPU Activity(%)"` は無し）。熱状態 `ProcessInfo.thermalState`、`getloadavg`、`kern.boottime`。上位プロセスは省略（コスト対効果）。
- 2 秒周期（utility キュー、leeway 250 ms）、履歴 5 分。ウィジェットが初めて表示されたときに開始し、Nook に入っている間はノッチを閉じても継続（スパークラインに履歴を残すため）、Nook から外すと約 30 秒以内に停止。表示: CPU（合計 + E/P）、GPU、メモリ（使用/総量、スワップ・圧縮、圧迫度の色 緑/黄/赤）、ディスク（読み/書き 2 本）の Swift Charts スパークライン + 熱状態・ロードアベレージ・稼働時間のフッター。設定: 表示する行、E/P 表示、履歴 1/2/5 分。
- **CPU コスト**: 1 サンプル 0.17–0.22 ms（`sysstats` の 50 回計測、ロードアベレージ 65 の高負荷下）→ 2 秒周期で約 0.01 %。プロセス全体の CPU はウィジェット有り/無しで 11.5 % / 11.2 %（差は測定誤差内。ベースラインは別要因）。
- Swift Charts の 1 つの `Chart { ForEach … if … AreaMark … LineMark }` が型検査タイムアウトになったため、点を平坦化して `ChartContent` 構造体（`SparklineMark`）に分けた。
- レジストリ: `NookWidget.swift`（7 行）、`NookWidgetGrid.swift`（cells・振り分け）、`WidgetsSettingsTabView.swift`（2 行）、`Support/Ext-C.swift`（StoredKeys 1 行）、`Support/merge-strings.py`（`SYSTEM_EXTRA_EN`。Localization は未再生成）。
- ビルド: `xcodebuild` BUILD SUCCEEDED（本ファイル群の警告 0）、`swift build --skip-update --scratch-path /tmp/dn-W15/.build` Build complete（ワークツリー = HEAD + 本ファイル、HEAD の `Color.fineTuningBG` 欠落をワークツリー内で補完）。スナップショット `/tmp/dn-W15-shots/`（`system-{live,sample,compact}-{dark,light}.png`、`settings-{dark,light}.png`、`notch-open-live.png`）。
- 未確認: Intel Mac（IOAccelerator のキー名・クラスタ無し表示）、メモリ圧迫度 4（critical）の表示、スリープ復帰後のスパークラインの切れ目（5 秒超の間隔で線を切る実装）。

## Color Picker ウィジェット（2026-10-20、隔離ワークツリー `/tmp/dn-W19`、`DN_DEBUG_CHANNEL=w19`、`DN_DEBUG_OFFSCREEN=1`）

- 新規 `NookWidget.colorPicker`（tag 19、raw `colorPicker`、`eyedropper`、設定キー `colorPickerWidgetSettings`）、4 セル（200 pt）× 202 pt。
  色見本（HEX、スポイトボタン、色の上に白／黒の "Aa" と WCAG コントラスト比・AA/AAA 表示）、選択形式の値（クリックでコピー、右クリックで他形式）、最近の色 2 行×6（クリックで再コピー、右クリックで削除／全消去）。
- 採取は `NSColorSampler().show`（画面収録の許可不要）。ループ表示中は `NotchInteractionMonitor.begin()/end()` でノッチを開いたままにする。値は sRGB（`usingColorSpace(.sRGB)`、P3 の範囲外は 0…1 にクランプ）。
- 形式: HEX `#RRGGBB`（大文字/小文字は設定）、`rgb()`、`hsl()`、SwiftUI `Color(red:green:blue:)`、`NSColor(srgbRed:green:blue:alpha:)`（小数 3 桁、POSIX ロケール）。設定: 形式、採取時に自動コピー、HEX 大文字、履歴数 8/10/12（既定 12）、履歴消去。
- 履歴は `~/Library/Application Support/<bundle id>/ColorPickerHistory.json`（0600、新しい順、8bit 値が同じ色は統合）。
- ファイル: 新規 `Sources/ColorPickerWidgetSettings.swift`（`ColorCopyFormat` も）、`ColorPickerHistory.swift`（`PickedColor`、`ColorPickerHistoryStore`）、`ColorPickerWidgetView.swift`、`ColorPickerWidgetSettingsView.swift`、
  `Support/DebugHooks-ColorPicker.swift`（DEBUG: `colorpreview:<dir>`。DebugHooks.swift は共有のため、リスナーはウィジェット／設定画面の表示時に自前で登録）。
  最小差分: `NookWidget.swift`（case と各 switch 1 行）、`Support/NookWidgetGrid.swift`（4 セル、View）、`WidgetsSettingsTabView.swift`、`Support/Ext-C.swift`（`StoredKeys` と `extension SettingKey` の 1 件）、
  `Support/merge-strings.py`（`COLOR_EXTRA_EN`、英語のみ。`Localization/` は再生成していない）。
- ビルド: `xcodebuild` BUILD SUCCEEDED、`swift build` Build complete（本作業ファイルの警告 0）。ワークツリーでは並行作業中の他ウィジェットの未完成ファイルを外し、`KeepAwakeManager` の `LiveActivity.keepAwake` 参照 2 行をスタブ化して検証。
  形式の出力（#007AFF）: `rgb(0, 122, 255)`、`hsl(211, 100%, 50%)`、白 4.0:1 / 黒 5.2:1。
- 未確認: 実際の採取（スポイト操作は手動が必要）、SwiftUI / NSColor 形式の長い値のウィジェット内表示（2 行・縮小で収まる想定）。

## Storage ウィジェット（W21、2026-10-20）

- 追加: `NookWidget.storage`（tag 21、raw "storage"、アイコン `internaldrive`、4 セル = 200 pt）。新規ファイル `Sources/StorageVolumesManager.swift`（`FileManager.mountedVolumeURLs(.skipHiddenVolumes)` + `URLResourceValues`。空きは `volumeAvailableCapacityForImportantUsage`、無ければ `volumeAvailableCapacity`。種別は DiskArbitration でディスクイメージ／光学メディアを判別、非ローカルはネットワーク。60 秒ごと + `NSWorkspace` の mount / unmount / rename 通知で更新、読取はバックグラウンド。取出しは `NSWorkspace.unmountAndEjectDevice`）、
  `StorageWidgetView.swift`（ボリュームごとのリング。85 % で橙、95 % で赤。1 台なら大きいリング + 「x free of y」、5 台以上は縦スクロール。取り外し可能なボリュームには取出しボタン）、`StorageWidgetSettings.swift`（`storageWidgetSettings`: 非表示ボリューム ID、GB／% 表示、ディスクイメージ表示。キーはこのファイル内で宣言）、
  `StorageWidgetSettingsView.swift`、`Support/DebugHooks-Storage.swift`（DEBUG: `storagelog` / `storagepreview:<dir>`。ウィジェット表示時に自前で通知を待ち受けるので `DebugHooks.swift` は変更なし）。
  最小差分: `NookWidget.swift`（case と各 switch 1 行）、`Support/NookWidgetGrid.swift`（セル数、View）、`WidgetsSettingsTabView.swift`、`Support/merge-strings.py`（`DISK_EXTRA_EN`、英語のみ。`Localization/` は再生成していない）。`Ext-C.swift` は変更なし。
- ビルド: `xcodebuild` BUILD SUCCEEDED、`swift build` Build complete（本作業ファイルの警告 0）。HEAD のワークツリーでは `Color.fineTuningBG`（未コミットの `Ext-C.swift` にある）をスタブ化して検証。
- 実機の読取（Mac14,9）: Macintosh HD 494.38 GB 中 60.72 GB 空き（88 % 使用、`/` のみ）。オフスクリーン描画でサンプル 4 台・1 台・6 台・空・% 表示・設定画面をダーク／ライトで確認。
- 未確認: 実際の外部ディスク／DMG／ネットワークボリュームでの種別判定と取出し（この Mac には `/` のみ）。

## 計算機ウィジェット（2026-10-20、隔離ワークツリー `/tmp/dn-W20`）

- **`NookWidget.calculator`**（tag 20、raw "calculator"、`function`、5 セル = 250 pt、設定キー `calculatorWidgetSettings`）。入力欄 1 つで入力ごとに評価する。
  新規: `CalculatorEngine.swift`（字句解析 + 再帰下降パーサで解析しながら評価。NSExpression は使わない）、`CalculatorStores.swift`（為替レートと履歴）、
  `CalculatorWidget{View,Settings,SettingsView}.swift`、`Support/DebugHooks-Calculator.swift`（DEBUG: `calceval:<式>` / `calcpreview:<dir>`。ウィジェット表示時に自前で通知を待ち受ける）。
  最小差分: `NookWidget.swift`（case と各 switch 1 行）、`Support/NookWidgetGrid.swift`（セル数 5、View）、`WidgetsSettingsTabView.swift`、
  `Support/Ext-C.swift`（`StoredKeys.calculatorWidgetSettings` と `extension SettingKey`）、`Support/merge-strings.py`（`CALC_EXTRA_EN`、Localization は未再生成）。
- 文法: 四則・括弧・`^`/`**`（右結合、`-2^2` = -4）・`%`（`200 + 10%` = 220、`15% of 80`、`10 % 3` は剰余）・`mod`・`!`・暗黙の積（`2pi`、`2(3+4)`）・関数（sqrt cbrt abs ln log log2 exp 三角／双曲線 floor ceil round trunc sign min max）・
  定数（pi e tau）・`ans`（直前の履歴）。単位は Foundation の `Dimension`（長さ・質量・時間・温度・情報量・速度・面積・体積・エネルギー・仕事率・圧力・角度・周波数）+ `UnitConverterLinear` の日／週／年／atm／turn。
  並べた同次元の量は加算（`3 h 20 min`、`5 ft 3 in`）。変換は最後の `in`/`to`/`as`/`->` で右辺が単位・通貨・`hex`/`bin`/`oct`/`dec` のもの（`5 ft 3 in in cm` が通る）。
  通貨は ISO コード・記号（$ € £ ¥）・語（dollar, yen…）、Frankfurter（`https://api.frankfurter.app/latest?from=USD`、キー不要、1 時間キャッシュ、オフラインはキャッシュを使い続ける）で USD 経由換算。
  単独の金額（`100 usd`）は既定の通貨ペアで換算。基数リテラル 0x / 0b / 0o。時刻は `15:00 JST in PST`、`3pm EST to Tokyo`、`9:30 in UTC+5:30`、`now in London`（略語・UTC±・IANA・都市名）。
- UI: 見出し（Clear）、入力欄（⌘K でフォーカス、Esc で消去）、結果行（クリックでコピー＋履歴へ、エラーは同じ位置に橙の警告で表示、詳細行にレートと日付）、直近 10 件の履歴（クリックでコピー、
  コンテキストメニューで式を再利用／削除。`Application Support/<bundle id>/CalculatorHistory.json`）。レートは `CalculatorRates.json`。
  「Nook を開いたら入力欄にフォーカス」（既定オン）は通知窓をキーにし、直前の前面アプリを覚えて、Nook が閉じたとき／空欄のままポインタが離れたときに戻す（空欄でフォーカスを持ち続けると NotchHover が閉じないため）。
  設定: 既定の通貨ペア、小数桁数（0〜10）、上記フォーカス。
- 検証: エンジン単体を swiftc で 66 式（エラー 10 種を含む）確認。`xcodebuild` BUILD SUCCEEDED、`swift build --skip-update --scratch-path /tmp/dn-W20/.build` Build complete（本作業ファイルの警告 0）。
  ワークツリーでは並行作業中の未登録ウィジェット（Capture / NextUp / SystemStats）を外し、`PomodoroStore` の DEBUG 呼出しを `MainActor.assumeIsolated` で包み、`DebugHooks.swift` に `CalculatorDebug.handle` を一時的に追加した（本体には入れていない）。
  スナップショット `/tmp/dn-W20-shots/`（算術・単位・通貨（実レート 1 USD = 158.24 JPY、2026-10-19）・基数・時刻・エラー・空欄・初回・設定、ダーク／ライト）。
- 未確認: 実ノッチでのフォーカス取得と前面アプリへの復帰、⌘K、ホバーで閉じる挙動（オフスクリーン描画のみ）。

## Timer のプリセットチップを設定可能に（ユーザー依頼、2026-10-20、隔離ワークツリー `/tmp/dn-TP`、`DN_DEBUG_CHANNEL=tp`、開発用 bundle id `…DynamicNotch.dev-tp`）

- 仕様（ユーザーの簡略化指示）: プリセットは**固定 5 枠**（追加・削除・並べ替え・表示数設定なし）。各枠は長さ（h/m/s）＋任意のラベル。「Restore Defaults」で 1m / 5m / 10m / 25m / 1h。
  ウィジェットは 5 枠すべてをチップで表示（0 秒の枠は非表示）。「…」メニューは Recents 専用（「Show Recents in the … menu」オン時かつ Recents がある時だけ表示、項目で即開始）。
  チップに Recents は入れない（従来の「Recents → プリセットで計 4 個」と旧 12h〜15m のプリセットメニューは廃止）。チップはホイールを設定し、ラベル付きならラベル欄も設定。
- データ: `TimerWidgetSettings.presets: [TimerPreset]`（常に 5 件）、`showRecents: Bool = true`。`TimerPreset { seconds: Int; label: String }`（`slotCount = 5`、`defaults`、`normalized(_:)`）。
  寛容なデコード: キー無し → 既定、旧い可変長リスト → 先頭 5 件（足りなければ既定で補完）、型不正 → 既定（設定全体は失敗させない）、`seconds` は 0〜23:59:59 に丸め。
- ファイル: `Sources/TimerWidgetSettings.swift`、`TimerWidgetSettingsView.swift`（`TimerWidgetSettingsForm` / `TimerPresetRow`、DEBUG `timerpresets:<dir>`）、`TimerCreatorView.swift`（`@StoredSetting` で設定を随時反映）、
  `Support/merge-strings.py` に `TIMERPRESET_EXTRA_EN`（5 キー、`en` の集合に追加。`Localization/` は未再生成）。
- 検証: `xcodebuild` BUILD SUCCEEDED（本作業ファイルの警告 0）。DEBUG `timerpresets:` でデコード 4 例をログ確認、スナップショット `/tmp/dn-TP-shots/`
  （`timerpresets-settings-{dark,light}.png`、`timerpresets-creator-{defaults,custom,norecents}-{dark,light}.png`）。開発用 defaults とワークツリーは削除済み。
- 未確認: 実設定ウィンドウでのピッカー操作・ラベル入力の保存（オフスクリーン描画は定数バインディング）、「…」メニューの実表示。

## Keep Awake ウィジェット（2026-10-20、隔離ワークツリー `/tmp/dn-W17`、`DN_DEBUG_CHANNEL=w17`、`DN_DEBUG_OFFSCREEN=1`）

- `NookWidget.keepAwake`（tag 17、raw `keepAwake`、アイコン `cup.and.saucer`、設定キー `keepAwakeWidgetSettings`、4 セル = 200 pt）。ヘッダ（タイトル + オン/オフスイッチ）、残り時間で減るリング + カップ、カウントダウン（`14:05` / `1:59:59`、無期限は `∞`）、状態行（"Mac and display awake until 19:52" など）、時間チップ 15m / 1h / 2h / ∞（押すとその長さで開始・再開始）。スイッチは最後に選んだ長さ（設定 `lastDuration`）で開始。
- `KeepAwakeManager`（@MainActor @Observable）: `IOPMAssertionCreateWithDescription` で `PreventUserIdleDisplaySleep`、「Allow display to sleep」オン時は `PreventUserIdleSystemSleep` のみ（実行中に切り替えると新しい assertion を先に作ってから旧を解放）。時間指定ではアサーション自体にも残り秒のタイムアウト（action release）を付け、アプリ側は終了時刻の Timer + スリープ復帰時の再判定で解除。アプリ終了（`willTerminate`）で解放。セッション（長さ・開始・終了時刻）は UserDefaults `keepAwakeSession`（JSON Data）に保存し、「Resume after relaunch」オンなら起動時に同じ終了時刻で再開（期限切れなら破棄）。
- 閉じたノッチのライブアクティビティ: 新規 `LiveActivity.keepAwake`（id `keepAwake`、`cup.and.saucer.fill`、"Keep Awake"）。左 = カップ、右 = 残り時間（無期限は `infinity`）、琥珀色。幅は残り 1 時間以上 66 pt / 未満 54 pt / 無期限 notch 高さ + 8。設定「Show in the closed notch」とライブアクティビティ設定の無効化に従う。優先度は `defaultPriority` の末尾（未列挙ケース扱い）。
- ファイル: 新規 `Sources/KeepAwakeManager.swift`（+ `KeepAwakeFormat`）、`KeepAwakeWidgetSettings.swift`（`KeepAwakeDuration` も）、`KeepAwakeWidgetView.swift`（ウィジェット + `KeepAwakeLiveActivityView`）、`KeepAwakeWidgetSettingsView.swift`、`Support/DebugHooks-KeepAwake.swift`（DEBUG: `kapreview:<dir>`、`katest`、`kalive:<秒>|off`、`kastate`。`KeepAwakeManager.start()` が自前のリスナーを入れるので `DebugHooks.swift` は不変）。
  最小差分: `NookWidget.swift`（7 行）、`Support/NookWidgetGrid.swift`（2 行）、`WidgetsSettingsTabView.swift`（2 行）、`Support/Ext-C.swift`（`StoredKeys.keepAwakeWidgetSettings`、キー名リテラル）、`LiveActivity.swift`（case + icon/id/name/init の 5 行）、`LiveActivities/`（幅の case 2 行 + `LiveActivitiesStartup.start()` で `KeepAwakeManager.shared.start()`）、`LiveActivityView.swift`（case 2 行）、`Support/merge-strings.py`（`AWAKE_EXTRA_EN`、英語のみ。`Localization/` は再生成していない）。
- ビルド: `xcodebuild` BUILD SUCCEEDED（本作業ファイルの警告 0）、`swift build`（CLT ハーネス）Build complete。他エージェントの作業中ファイル（Pomodoro/SystemStats/Bluetooth/AudioDevices/Capture/Network/NextUp/Weather/WorldClock）はワークツリーから外して確認。
- 実機確認（開発インスタンス）: `katest` で両種のアサーションが `pmset -g assertions` に `PreventUserIdleDisplaySleep` / `PreventUserIdleSystemSleep named: "DynamicNotch Keep Awake test"` として出て、解放後に消えることを確認。`kalive:120`（UserDefaults に書かない実セッション）で assertion 保持・`.keepAwake` 要求（visible。fanAlert が優先で current は fanAlert）、2 分後に自動解除され assertion と要求が消えることを確認。`keepAwakeSession` は書かれていない。
- スナップショット（`kapreview`、プレビュー状態で assertion・設定に触れない）: `keepawake-{off,15m,2h,infinite,display}-{dark,light}.png`、`keepawake-notch-{15m,2h,infinite}.png`（モックのノッチ）、`keepawake-settings-{dark,light}.png`。
- 未確認: 実ノッチでの表示（このインスタンスでは fanAlert が常に current）、蓋を閉じたスリープからの復帰後の解除タイミング。

## Capture ウィジェット（2026-10-20、隔離ワークツリー `/tmp/dn-W24`、`DN_DEBUG_CHANNEL=w24`）

- 新規 `NookWidget.capture`（tag 24、raw `capture`、`camera.viewfinder`、4 セル = 200 pt、設定キー `captureWidgetSettings`）。`/usr/sbin/screencapture` を `Process` で起動:
  Area `-i -s`、Window `-i -w`（影なしは `-o`）、Screen `-m`（メインディスプレイ）、録画 `-v`（`-V <秒>` の自動停止、`-k` クリック表示）、共通 `-x`（音なし）・`-t png|jpg|heic`・`-c`（クリップボード、静止画のみ）。
  録画の停止は stdin に 1 文字 → 1.5 s 後 SIGINT → 8 s 後 SIGTERM。保存先: デスクトップ（重複時 `(2)`）／クリップボード（録画はデスクトップに保存しファイルをコピー）／トレイ（`Tray.shared.newItemDirectory()` に直接書いて `adoptFiles`）。
  ファイル名パターン（`{kind} {date} at {time}`）、遅延チップ 0 / 3 / 10 s（ノッチを閉じた状態で待つ、キャンセル可）、録画中は赤点＋経過時間＋停止ボタン。撮影前にウィジェットのノッチを閉じ、静止画の後はポインタがそのノッチ窓上にあれば開き直す（トレイ保存ならトレイタブ）。
  画面収録権限は `CGPreflightScreenCaptureAccess()` で判定し、無ければウィジェット下部と設定にヒント（Allow = `CGRequestScreenCaptureAccess()`、System Settings を開く）。
- ファイル: `CaptureWidgetSettings.swift`（設定・`StoredKeys.captureWidgetSettings`）、`CaptureManager.swift`、`CaptureWidgetView.swift`（ウィジェット＋閉じたノッチの録画表示 `CaptureClosedNotchIndicator`）、`CaptureWidgetSettingsView.swift`、`Support/DebugHooks-Capture.swift`（`capturepreview:<dir>`）。
- レジストリ: `NookWidget.swift`（case・icon・name・gridSizeType・prefs・rawValue・init）、`NookWidgetGrid.swift`（cells 4・振り分け）、`WidgetsSettingsTabView.swift`、`DebugHooks.swift`（`handleCapture`）、`merge-strings.py`（`CAPTURE_EXTRA_EN`、Localization は再生成していない）。
  閉じたノッチの録画表示（他のライブアクティビティが無いときだけ。左に赤点、右に経過時間）: `LiveActivities/` 2 行（`sideWidth` 加算・ビュー）と `NotchView.swift` 2 行（`closedNotchFootprint` と `shouldRender` に `CaptureClosedNotchIndicator.isShown`）。
- ビルド: `xcodebuild` BUILD SUCCEEDED（Capture ファイルの警告 0）、`swift build --skip-update --scratch-path /tmp/dn-W24/.build` Build complete。HEAD 単体では `Color.fineTuningBG` が無くビルドできないため、ワークツリーの `Ext-C.swift` にだけ一時定義を足した。
- スナップショット `/tmp/dn-W24-shots/`（idle / message / countdown / capturing / recording / stopping × dark/light、`capture-closed-indicator.png`、`settings-*.png`。`DN_DEBUG_NOGLASS` 相当のマテリアル描画）。
- 未確認: 実際の撮影・録画（開発インスタンスでの TCC プロンプトとユーザーのデスクトップ／クリップボード／トレイへの書込を避けたため未実行）、`screencapture -v` を stdin パイプ経由で止める挙動、マルチディスプレイ（Screen / 録画はメインディスプレイのみ）、録音なし。

## Audio ウィジェット（2026-10-20、隔離ワークツリー `/tmp/dn-W13`、`DN_DEBUG_CHANNEL=w13`、開発用 bundle id `…DynamicNotch.dev-w13`）

- `NookWidget.audioDevices`（tag 13、raw `audioDevices`、アイコン `speaker.wave.2`、設定キー `audioDevicesWidgetSettings`）。コントロールセンターのサウンド風: 出力デバイス一覧（+ 任意で入力デバイスの 2 列目）、既定デバイスはガラスのカプセル＋アクセントのチェック＋太字（Fan Control のプロファイル一覧と同じ見た目）、行クリックで既定の出力／入力を切替。出力列の下に音量スライダとミュートボタン、入力列の下に既定入力のレベルメータ。幅 8 セル（400 pt、出力｜入力）／入力非表示時 4 セル（200 pt）。
- CoreAudio（`AudioDevicesManager`）: `kAudioHardwarePropertyDevices`（非表示デバイスは除外、ストリームの有無で出力／入力）、名前・UID・トランスポート種別・内蔵出力のデータソース（`hdpn` = ヘッドホン）から SF Symbol（speaker / headphones / airpods / airpodspro / airpodsmax / homepod / hifispeaker / display / airplayaudio / iphone / mic）。既定は `kAudioHardwarePropertyDefaultOutputDevice/DefaultInputDevice` の読み書き。音量は仮想メイン音量（`kAudioHardwareServiceDeviceProperty_VirtualMainVolume`）→ `VolumeScalar`（main → ch1/2）の順、ミュートは `kAudioDevicePropertyMute`。システムオブジェクトと既定出力に `AudioObjectAddPropertyListenerBlock`（メインキュー、既定出力の変更でリスナーを付け替え）。
- 入力レベル: `AVAudioEngine` の入力タップ（RMS → −60…0 dBFS）。ウィジェット表示中（onAppear/onDisappear の参照カウント）かつマイク使用可のときだけ動く。**現ビルドでは常に非表示**: `com.apple.security.device.audio-input` entitlement と `NSMicrophoneUsageDescription` が無い（バンドル整理時に削除済み）ため `microphoneStatus = .unavailable` とし、許可要求もしない（使用説明なしの要求はクラッシュするため）。有効にするには `project.yml` にこの 2 つを戻す。
- 設定: 入力デバイスの表示、出力音量の表示、入力レベルの表示（＋マイク許可の状態・許可ボタン・システム設定を開く）、検出したデバイス一覧。
- ファイル: 新規 `Sources/AudioDevicesManager.swift`、`AudioDevicesWidgetSettings.swift`（`StoredKeys.audioDevicesWidgetSettings` もここ）、`AudioDevicesWidgetView.swift`、`AudioDevicesWidgetSettingsView.swift`、`Support/DebugHooks-Audio.swift`（DEBUG: `audiolog`、`audiopreview:<dir>`。`handleAudio` は DebugHooks.swift の default 分岐に未連結 — ワークツリーでのみ連結して確認）。最小差分: `NookWidget.swift`（7 行）、`Support/NookWidgetGrid.swift`（2 行）、`WidgetsSettingsTabView.swift`（2 行）、`Support/merge-strings.py`（`AUDIO_EXTRA_EN`、英語のみ。`Localization/` は再生成していない）。
- 実機（Mac14,9）: 出力 MacBook Pro Speakers、入力 MacBook Pro Microphone と iPhone（Continuity、トランスポート other → `iphone` アイコン）を検出。音量 0 / ミュート true の読取は `osascript 'get volume settings'` と一致。既定デバイスの切替・音量／ミュートの書込は実行していない（ユーザーの音声環境を変えないため）。
- ビルド: `xcodebuild` BUILD SUCCEEDED、`swift build --skip-update --scratch-path /tmp/dn-W13/.build` Build complete（本作業ファイルの警告 0。他エージェントの作業中ファイル Pomodoro/SystemStats/Bluetooth/NextUp/Capture/Calculator はワークツリーから外して確認）。スナップショット `/tmp/dn-W13-shots/`: `audio-{live,sample,outputs-only,empty}-{dark,light}.png`、`settings-{dark,light}.png`（`DN_DEBUG_NOGLASS=1`）。

## Bluetooth ウィジェット（2026-10-20、隔離ワークツリー `/tmp/dn-W23`、`DN_DEBUG_CHANNEL=w23`、`DN_DEBUG_OFFSCREEN=1`、開発用 bundle id `…DynamicNotch.dev.w23`）

- `NookWidget.bluetooth`（tag 23、raw `bluetooth`、アイコン `dot.radiowaves.left.and.right`（`bluetooth` という SF Symbol は存在しない）、設定キー `bluetoothWidgetSettings`、4 セル = 200 pt）。
  ヘッダ（タイトル + 電源状態 On/Off、読取のみ）、ペアリング済みデバイスの行（クラス／名前から SF Symbol、名前、Connected / Not Connected、接続中は Batteries の `BatteryDevicesManager` が動いていれば名前一致で % を表示（自分では起動しない））。
  行クリックで接続（`openConnection(_:withPageTimeout:authenticationRequired:)` の非同期版、結果は `connectionComplete(_:status:)`、20 秒の保険タイムアウト）／切断（`closeConnection()`、切れるまで最大 5 秒待つ）。実行中はスピナー、失敗時は下部に 3.5 秒のエラートースト。右クリックで接続／切断・お気に入りの追加／削除。
  並び: 接続中 → お気に入り → 名前。空状態: アクセス未決定（Allow ボタンで `CBCentralManager` を作りシステムの許可ダイアログ）、拒否（プライバシー設定を開く）、電源オフ（Bluetooth 設定を開く）、デバイス無し／お気に入り無し。
- `BluetoothWidgetModel`（@MainActor @Observable、既存の `BluetoothManager` とは別）: `CBManager.authorization == .allowedAlways` のときだけ IOBluetooth のデバイス API に触れる（Batteries と同じ方針）。電源状態は `IOBluetoothHostController.default().powerState`（許可不要）、表示中は 3 秒ごとに再読込、許可済みなら `CBCentralManager` の状態変化でも即時更新。接続／切断通知（`register(forConnectNotifications:)` / `register(forDisconnectNotification:)`）で再読込。電源の切替は private API が要るため表示のみ。
- 設定: 「Show only favourites」「Hide unnamed devices」（既定オン）、お気に入り（正規化アドレスの配列）、状態とアクセス許可、全デバイス一覧（星でお気に入り切替）。
- ファイル: 新規 `Sources/BluetoothWidgetSettings.swift`（`StoredKeys.bluetoothWidgetSettings` もここ。`Ext-C.swift` は触っていない）、`BluetoothWidgetModel.swift`、`BluetoothWidgetView.swift`（`BluetoothWidgetLayout`、行、トースト）、`BluetoothWidgetSettingsView.swift`、
  `BluetoothWidgetDebug.swift`（DEBUG: `btpreview:<dir>`、`btstate[:<file>]`、`btrefresh`。ウィジェット表示時に自前のリスナーを入れる。環境変数 `DN_BT_PREVIEW_DIR=<dir>` なら起動約 4 秒後に通知無しで両方を実行）。
  最小差分: `NookWidget.swift`（7 行）、`Support/NookWidgetGrid.swift`（2 行）、`WidgetsSettingsTabView.swift`（2 行）、`Support/merge-strings.py`（`BT_EXTRA_EN`、英語のみ。`Localization/` は再生成していない）。
- ビルド: `xcodebuild` BUILD SUCCEEDED、`swift build --skip-update --scratch-path /tmp/dn-W23/.build` Build complete（本作業ファイルの警告 0）。ワークツリーでは並行作業中の未登録ウィジェット（NextUp / SystemStats / Capture）を外して確認。
- 実機確認（Mac14,9、開発インスタンス。シェル経由起動のため Bluetooth 許可は既に allowedAlways）: 電源 On、ペアリング済み 9 台を取得（接続中 2〜3 台）。分類は Magic Trackpad（05/25）→ trackpad、AirPods Pro（04/06）→ airpods.pro、WH-1000XM4（04/01）→ headphones、"Bedroom speaker"（04/00）→ speaker、
  HHKB / Apple Watch（名前に no-break space）/ iPhone は名前から。BLE のキーボード／マウス（Cornix、VXE R1SE+）はクラス 00/00 で名前にも手掛かりが無く汎用アイコン。接続中デバイスの % は Batteries の値（AirPods 56%、Cornix 69%）。
  途中から分散通知がこのシェルのどのプロセスにも届かなくなった（単体のリスナーでも受信せず）ため、後半のスナップショットは `DN_BT_PREVIEW_DIR` で取得。
- スナップショット: a scratch directory (`bt-shots/`)（`bluetooth-{live,sample-list,sample-list-notoast,sample-off,sample-access,sample-denied}-{dark,light}.png`、`btstate.txt`、`settings-nook-bluetooth.png`（修正前の分類のまま））。
- 未確認: 実際の接続／切断操作（ユーザーの実デバイスを切り替えるため実行していない）、エラートーストの実発生、実ノッチ上でのクリックと右クリックメニュー、Bluetooth 電源オフ時の表示（サンプルのみ）。

## Weather ウィジェット（2026-10-20、隔離ワークツリー `/tmp/dn-W18`）

- **新規 `NookWidget.weather`**（tag 18、raw `weather`、アイコン `cloud.sun`、4 セル = 200 pt、設定キー `weatherWidgetSettings`）。WeatherKit は有料 Team が要るため、
  キー不要の **Open-Meteo**（`api.open-meteo.com/v1/forecast`: 現在の気温・WMO コード・昼夜、25 時間分の気温／降水確率／コード、当日の最高／最低。常に °C で取得し表示時に換算、`timeformat=unixtime`。
  都市検索は `geocoding-api.open-meteo.com/v1/search`）。Open-Meteo は非商用無料・データ CC BY 4.0 → 設定ペインに「Weather data by Open-Meteo.com」のリンクと注記。
- ファイル: `WeatherWidgetSettings.swift`（`WeatherPlace`、場所モード city/current、°C/°F（既定は地域の計量法）、時間別表示）、`WeatherManager.swift`（Open-Meteo クライアント、
  CoreLocation when-in-use（許可ダイアログは設定で「Current location」を選んだときだけ。未許可・拒否・測位失敗時は設定の都市にフォールバック）、MapKit `MKReverseGeocodingRequest` で地名、
  ディスクキャッシュ `Application Support/<bundle id>/Weather/forecast.json`、15 分ごと・復帰 4 秒後・場所変更時に更新、失敗時 2 分後に再試行）、`WeatherWidgetView.swift`
  （macOS の天気ウィジェット風タイル: 地名、大きな気温、WMO→SF Symbols（multicolor）と状態名、H/L、Now + 5 時間の帯（降水確率 30 % 以上を表示）、昼夜・天候でトーンを変える空色グラデーション、
  30 分以上古い／取得失敗時は右上に経過時間（失敗時は `wifi.slash`）、データ無しは読込中／「Weather unavailable」+ Retry）、`WeatherWidgetSettingsView.swift`（場所、都市検索（350 ms デバウンス）、
  単位、時間別、更新状況 + Refresh Now、帰属表示）、`Support/DebugHooks-Weather.swift`（DEBUG: `weatherlog`、`weatherpreview:<dir>`）。
- 共有ファイルの追加行: `NookWidget.swift`（case・icon・name・gridSizeType・prefs・rawValue・init）、`NookWidgetGrid.swift`（cells = 4、振り分け）、`WidgetsSettingsTabView.swift`（設定行）、
  `Support/Ext-C.swift`（`StoredKeys.weatherWidgetSettings`、キー名リテラル）、`Support/merge-strings.py`（`WEATHER_EXTRA_EN`。Localization/ は再生成していない）、
  `project.yml` / `Support/Info.plist`（`NSLocationWhenInUseUsageDescription`）。
- ビルド: `xcodebuild` BUILD SUCCEEDED、`swift build --skip-update --scratch-path /tmp/dn-W18/.build` Build complete。Weather 関連ファイルの警告・エラー 0。
  （ワークツリーでは作業中だった他エージェントの NextUp / Pomodoro / SystemStats を外してビルド。）
- 実行確認（DEBUG、`DN_DEBUG_CHANNEL=w18`、`DN_DEBUG_OFFSCREEN=1`）: 東京の実データ取得（20.6 °C、Mostly Clear、H 25 / L 16、時間別 6 枠）とキャッシュ書込を確認。
  スナップショット `/tmp/dn-W18-shots/weather/`（live、day、night-rain、snow、thunder-f、hourly-off、offline、loading、error、settings）。
- 未確認・要対応: **Hardened Runtime では位置情報に entitlement `com.apple.security.personal-information.location` が必要**（`project.yml` の entitlements は今回の変更範囲外のため未追加。
  無いと「Current location」の測位は拒否されうる → その場合は都市にフォールバック）。位置情報の許可ダイアログと現在地表示、実ノッチ内表示、スリープ復帰時の更新は未確認。

## Network ウィジェット（2026-10-20、隔離ワークツリー `/tmp/dn-W14`、`DN_DEBUG_CHANNEL=w14`）

- 新規 `NookWidget.network`（tag 14、raw `network`、アイコン `wifi`、4 セル = 200 pt、設定キー `networkWidgetSettings`）。ファイル: `NetworkMonitor.swift`（データ）、
  `NetworkWidgetView.swift`（ウィジェット + `NetworkSparkline` + `NetworkFormatting`）、`NetworkWidgetSettings.swift`（設定構造体と `StoredKeys.networkWidgetSettings`。Batteries と同じく自ファイルで宣言）、
  `NetworkWidgetSettingsView.swift`、`Support/DebugHooks-Network.swift`（DEBUG）。
  レジストリ: `NookWidget.swift`（case・icon・name・gridSizeType・prefs・rawValue・init）、`NookWidgetGrid.swift`（cells = 4、振り分け）、`WidgetsSettingsTabView.swift`、
  `Support/merge-strings.py` の `NETWORK_EXTRA_EN`（Localization は再生成していない）。
- 内容: 表示インターフェイス（Wi‑Fi: SSID・規格・帯域・チャネル・RSSI・送信レート・セキュリティ／Ethernet: アダプタ名・リンク速度・ルーター）、IPv4 / IPv6、任意で公開 IP、
  VPN バッジ（`lock.shield.fill`）、↓/↑ スループットと 60 / 120 秒のスパークライン（Swift Charts）。スループットは sysctl `NET_RT_IFLIST2` の 64 ビットカウンタ
  （getifaddrs の `if_data` は 32 ビットで 4 GB で一巡するため）を、ウィジェットが Nook にある間 1 / 2 / 5 秒ごとに採取（開いた時点で履歴がある）。CoreWLAN・アドレスは表示中のみ 3 秒ごと（非表示時はアドレスのみ 30 秒）、バックグラウンドスレッド。
  VPN 判定: utun/ipsec/ppp/tun/tap/wg が主インターフェイス、または `CFNetworkCopySystemProxySettings` の `__SCOPED__` に出る、またはルーティング可能な IPv4 を持つ。
  主インターフェイスがトンネル（フルトンネル VPN / exit node）のときは、自動選択でサービス順の最初の物理インターフェイスを表示し VPN バッジを付ける。
  公開 IP は既定オフ、オン時のみ `https://api.ipify.org`（ネットワーク変化時と表示中 10 分ごと、設定の「Refresh」）。設定: インターフェイス（自動 + 一覧）、採取間隔、履歴長、公開 IP。
- この Mac での実測（`netlog`）: 主 = `utun11`（Tailscale 系 VPN、100.x）→ 表示は `en11`（USB 10/100/1000 LAN、1 Gb/s、ルーター取得）、VPN = utun11。Wi‑Fi `en0` は
  RSSI −42 dBm、ノイズ −89、ch 37 / 6 GHz、送信 2161 Mb/s、Wi‑Fi 6、WPA3 Personal を取得。**SSID は nil**（位置情報の許可が無いため。ウィジェットは「Wi‑Fi」、設定に説明を表示。
  Info.plist に `NSLocationUsageDescription` が無いのでアプリからは許可を求めない）。公開 IP の取得成功。
- ビルド: `xcodebuild` BUILD SUCCEEDED（Network 関連の警告 0）、`swift build --skip-update --scratch-path /tmp/dn-W14/.build` Build complete。
  （ワークツリーでは作業中だった他エージェントの NextUp / Capture / SystemStats を外してビルド。）
- スナップショット `/tmp/dn-W14-shots/run3/`（`netpreview:`。live dark/light、サンプル wifi / wifi-nossid / ethernet-vpn / vpn-tunnel / offline、設定 dark/light）。
  起動時引数 `-nookSettings` / `-networkWidgetSettings`（引数ドメイン。ユーザー設定には書き込まない）で検証。
- 未確認: 実ノッチ内表示、位置情報を許可した場合の SSID、Wi‑Fi 7（`CWPHYMode` rawValue 7 を仮に「Wi‑Fi 7」）、IPv6 のみの環境、インターフェイス選択の操作。

## Next Up ウィジェット（2026-10-20、隔離ワークツリー `/tmp/dn-W25`、`DN_DEBUG_CHANNEL=w25`、開発用 bundle id `…DynamicNotch.dev-w25`）

- 新規 `NookWidget.nextUp`（tag 25、raw `nextUp`、`clock.badge`、設定キー `nextUpWidgetSettings`、5 セル = 250 pt）。次の 1〜3 件の予定: カレンダー色の点 + タイトル、
  ライブのカウントダウン（"in 12 min" / "in 2 h 5 min" / "tomorrow, 09:00" / 進行中は緑の "now · 23 min left"、5 分以内は橙）、先頭行は時刻範囲・場所、以降は "· 場所"。
  予定の URL → 場所 → メモの順に正規表現で Zoom（`zoom.us/j|my|s|w|wc`、`zoommtg://`）/ Meet / Teams / Webex / FaceTime のリンクを探し、あれば Join ボタン（既定のブラウザで開く。`zoommtg:` はアプリ）。
  キャンセル済み・自分が辞退した予定は除外。アクセス未許可は「Allow Access」/「Open System Settings」（CalendarManager の `requestFullAccess` / `requestAccessFromUser`）。
- データ: `NextUpManager`（`CalendarManager.shared` の `hasReadAccess` / `eventStore` を使用。CalendarManager は無変更）。カレンダー選択が Calendar ウィジェットと独立なので
  日別キャッシュ（`eventsAsync`）は使わず、[現在 − 1 日, 現在 + 先読み] を 1 クエリでバックグラウンド取得（起動時・60 s ごと・`EKEventStoreChanged`（0.4 s 合流）・設定変更時）。
- 閉じたノッチのライブアクティビティ: 新規 `LiveActivity.nextUp`（優先度は battery の次、calendar の前）。予定開始の N 分前（設定、既定 5）から開始 2 分後まで、
  左にカレンダー色の `calendar` 記号、右に "5 min" → "Now"。ウィジェット見出しのベル（`bell.slash`）でその予定の分だけ消せる（次の予定では再表示）。終日予定は対象外。
- 設定: 先読み（1/3/6/12/24/48 h）、表示件数（1〜3）、終日予定、ノッチでの通知のオン/オフと何分前か（1/2/5/10/15/30）、対象カレンダー（除外 ID のリスト。新しいカレンダーは自動で対象）。
- ファイル: 新規 `Sources/NextUpManager.swift`、`NextUpWidgetView.swift`（ライブアクティビティの `NextUpLiveActivityView` も）、`NextUpWidgetSettings.swift`（`StoredKeys.nextUpWidgetSettings` もここ）、
  `NextUpWidgetSettingsView.swift`、`Support/DebugHooks-NextUp.swift`（DEBUG: `nextuplog` / `nextupforce` / `nextupclear` / `nextuppreview:<dir>`。自前のリスナーなので DebugHooks.swift は無変更）。
  最小差分: `NookWidget.swift`（7 行）、`Support/NookWidgetGrid.swift`（2 行）、`WidgetsSettingsTabView.swift`（2 行）、`LiveActivity.swift`（5 行）、
  `LiveActivitySelectionManager.swift`（優先度リストに `.nextUp`）、`LiveActivities/`（幅 `h + 24` と `NextUpManager.shared.start()`）、`LiveActivityView.swift`（1 case）、
  `Support/merge-strings.py`（`NEXTUP_EXTRA_EN`。`Localization/` は再生成していない）。
- ビルド（HEAD bfc3218 + 本作業のみ。HEAD 単体は `Ext-C.swift` の `fineTuningBG` 未コミットで失敗するため、ワークツリーでだけ Color リテラルに差し替え）:
  `xcodebuild` BUILD SUCCEEDED（本作業ファイルの警告 0）、`swift build --skip-update --scratch-path /tmp/dn-W25/.build` Build complete。
- スナップショット `/tmp/dn-W25-shots/`: `nextup-{sample,live,empty}-{dark,light}.png`（live = 開発 bundle id はカレンダー未許可なので許可画面）、`nextup-activity.png`、
  `nextup-settings-{dark,light}.png`、`notch-closed/1-BetterWindow.png`（実ノッチの閉じた状態に `nextupforce` のアクティビティ: 左カレンダー記号 / 右 "5 min"）。
- 未確認: 実カレンダーでの表示（開発インスタンスはカレンダー未許可。許可ダイアログはユーザー操作なので出していない）、Join の実際のブラウザ起動、ベルでの消去のクリック操作。

## 並行作業の統合（2026-10-20 夜）

- 上記ウィジェット 15 種（batteries 12 / audioDevices 13 / network 14 / systemStats 15 / worldClocks 16 / keepAwake 17 / weather 18 / colorPicker 19 / calculator 20 /
  storage 21 / pomodoro 22 / bluetooth 23 / capture 24 / nextUp 25 / menuBarItems 26）と Timer プリセットを main の作業ツリーで統合。`NookWidget` の各 switch
  （icon / name / gridSizeType / prefs / rawValue / init）、`NookWidgetLayout.cells`、`NookWidgetContentView`、`WidgetsSettingsTabView` が全ケースを 1 回ずつ持つことを確認。
  設定キーは重複なし（`SettingKey` 拡張は Ext-C に 1 つへ整理、SystemStats は自ファイル）。
- `DebugHooks.swift` の既定分岐に `handleAudio` を追加（Capture / Batteries は追加済み。他は各ファイルの自前リスナー）。
- 権限: `project.yml` に `NSMicrophoneUsageDescription`（Audio の入力レベル）、`NSLocationUsageDescription`（Weather と Network の SSID）と
  entitlement `com.apple.security.device.audio-input` / `com.apple.security.personal-information.location` を追加（Hardened Runtime 下で必要。ad-hoc 署名のまま）。
  `codesign -d --entitlements -` で組込みを確認。
- `merge-strings.py` で `Localization/en.lproj/Localizable.strings` を再生成（904 項目。各 `*_EXTRA_EN` は恒等表なので値の衝突なし）。
- 検証: `xcodebuild` BUILD SUCCEEDED（新規ファイルの警告 0。既存の警告のみ）、CLT ハーネス `swift build --skip-update` Build complete（新規の警告 0）、
  FanControl `swift build` / `swift test` 319 tests / 52 suites、IntegrationTypeCheck（Swift 5 / 6）緑。

## 新ウィジェットのレビュー修正（2026-10-20 夜）

- 新ウィジェット 15 種のコードレビューで確定した 41 件を 3 系統で修正（未コミットの作業ツリーを統合）。
  - ライフサイクル: Batteries / Storage / Network / Weather / Next Up / System は「ウィジェットが Nook にある間、または表示中のビュー（ウィジェット・設定ペイン）がある間」だけ
    タイマー・通知・クエリを動かし、外されたら停止（`stop()`）。System は再開時に CPU / ディスクの前回カウンタを捨てる（停止期間の平均にならない）。
    Keep Awake はウィジェットを外すとセッション終了、アサーション作成失敗時はセッションを始めずウィジェットに「Could not keep the Mac awake」。
    Pomodoro はウィジェット不在時にリセット（止められない "Until Stopped" アラートを鳴らさない）、スキップした集中は数えない。
  - 権限: Screen Recording / Accessibility は初回はシステムのプロンプトのみ、2 回目以降にプライバシー設定ペインを開く（フラグは UserDefaults で Capture と MenuBarItems が共有）。
    `NSLocationUsageDescription` の文言を Weather 主体に修正。Audio は Bluetooth の既定入力ではレベルメーターを開かない（ヘッドセットが通話品質プロファイルに落ちるため。設定に注記）。
  - Capture: アプリ終了時に screencapture を終わらせる（録画は停止して保存、選択中・カウントダウンは取消）、stdin パイプは SIGPIPE を出さない（`F_SETNOSIGPIPE`）、
    カウントダウン中にホバーで開いたノッチは撮影前に閉じ、`CaptureManager.suppressesNotchHoverOpen` を `NotchViewModel.hoverOpenSuppressed` に接続（撮影中はホバーで開かない）、
    撮影後の再オープンは閉じたノッチ付近にポインタがあるときだけ。
  - その他: Calculator（`ans` を使った結果の確定後は入力を消す、数の並び "2 3" を積にしない、履歴の書込を直列化）、Next Up（Zoom / Webex のホストを接尾辞一致で判定し偽ドメインを除外、
    終日予定の曜日表示 "%@, all day"）、Weather（地点のタイムゾーンで時刻表示、失敗時 2 分後に再試行、現在地が使えないときの代替都市の扱い）、Storage（読取を専用の直列キューへ、
    取り出しエラーの自動消去）、MenuBarItems（AX 走査を同じ未解決項目で繰り返さない）、Batteries（0…100 整数の残量を 1 % と誤読しない）、Bluetooth（AirPods の残量照合）、
    Network（Wi‑Fi オフ時の表示、SSID 取得の取消後に再取得されない問題）、World Clock（引用リテラルを除いて 12/24 時間判定）。
  - 設定 ▸ Live Activities に Next Up のオン/オフを追加。新規文字列 3 件を `merge-strings.py`（AUDIO / AWAKE / NEXTUP）に追加して再生成（907 項目）。
- 検証: `xcodebuild` BUILD SUCCEEDED（変更ファイルの新規警告 0。既存の 4 件 — NoteDocument / ライブアクティビティ / NotchHover の Timer クロージャ — のみ）、
  CLT ハーネス `swift build --skip-update` Build complete（同じ既存警告のみ）、FanControl `swift build`（警告 0）/ `swift test` 322 tests / 53 suites、IntegrationTypeCheck（Swift 5 / 6）警告 0。

## 単体テストターゲットと一括チェック（R19、2026-10-20 夜）

- `project.yml` を整理（ターゲット一覧の冒頭コメント、`# MARK:` 区切り、設定を Identity / Signing / Sandboxing / Swift / Linking にグループ化、
  アプリとテスト用ライブラリのソース指定を YAML アンカー `&appSources` / `&fanControlDropIns` で共有）。アプリ・ヘルパーのビルド設定は
  `xcodebuild -showBuildSettings` の差分 0、`Support/Info.plist` も不変。参照切れのリソースは無かった（`../resources` 参照は既に撤去済み）。
- 追加ターゲット: `DynamicNotchApp`（`library.static`、アプリのコードを `App/` とリソース抜きでコンパイルするテスト専用ライブラリ。モジュール名は CLT ハーネスと同じ）と
  `DynamicNotchAppTests`（`bundle.unit-test`、`Tests/**`、ホスト無し、`SWIFT_TREAT_WARNINGS_AS_ERRORS = YES`）。スキーム `DynamicNotch` のテストアクションに登録。
  ホスト付きにしなかったのは、テスト実行で 2 つ目の DynamicNotch（ノッチ窓・SMC 読取・ヘルパー接続）が起動するのを避けるため。
  `SWIFT_TREAT_WARNINGS_AS_ERRORS` を新ウィジェットのファイルだけに付ける案は、Xcode に Swift のファイル単位フラグが無いため見送り。
- CLT ハーネス: テストターゲットを `SettingsStorageTests` から `DynamicNotchAppTests`（パス `Tests`、`SettingsStorageTests/Fixtures` 除外）に変更。`Tests/` 下の新しいディレクトリは自動で入る。
- 新規テスト（Swift Testing、`Tests/DynamicNotchAppTests/`）: `Smoke`、`NextUp meeting links`（5 サービス、偽ドメイン拒否、末尾句読点、検索順）、
  `World clock hour format`（明示／システム／寛容なデコード）。計算機エンジンのテストは同時に入った `Tests/EngineTests/`（R20）に任せた
  （SwiftPM はターゲット内のファイル名の重複を許さないので、こちらの `CalculatorEngineTests.swift` は削除）。
  結果: `xcodebuild test -only-testing:DynamicNotchAppTests` TEST SUCCEEDED・ハーネス `swift test` とも 101 tests / 9 suites（EngineTests と SettingsStore 互換を含む）。
  テスト実行中に DynamicNotch は起動しない（ホスト無し）。
- `../scripts/check.sh`（`--fast` / `--list` / ステップ指定 / `--keep-going`）。README「テストとチェック」。ルート `.gitignore` に `/.build-check/` と `__pycache__/`。
  全ステップ実行（2026-10-21 0 時台）: strings-lint 以外は成功（アプリ・ハーネスの既知の警告 各 24 件、FanControl 436 tests / 69 suites、型検査 Swift 5/6 警告 0、shellcheck 0）。
  strings-lint は `Support/lint-strings.py`（R16）が未登録キー 15 件を報告して失敗。

## Displays ウィジェット（F6、2026-10-20〜21、隔離ワークツリー、ブランチ `feature/display-brightness`）

- 新規 `NookWidget.displays`（tag 29、raw `displays`、アイコン `display`、5 セル = 250 pt、設定キー `displaysWidgetSettings`）。接続中のディスプレイごとのカード:
  名前、外部モニターの現在の入力（表示のみ）、輝度スライダー、設定で有効にしたコントラスト、capabilities に 0x62 がある場合の音量。
- 調査（読み取りのみ、`docs/displays.md`）: Apple Silicon / macOS 26.5 には `IODisplayConnect` が無く、`IODisplayGetFloatParameter` は
  `AppleARMBacklight` に対して `kIOReturnUnsupported`、IORegistry の `brightness` は 0.5 から動かない → 内蔵の読書きは DisplayServices（非公開・dlsym）、
  IORegistry は概算フォールバック（「≈」表示）。外部は `DCPAVServiceProxy` + IOAVService I2C（dlsym）で DELL P3225QE 2 台から輝度 74/72・コントラスト 75・
  入力 USB-C（0x1B1B の下位バイト）と capabilities を取得。P3225QE は 0x62 を返すが capabilities に無い（スピーカー無し）。
- 書込は**実機で未実施**（`FakeDDCMonitor` / テスト用 `FakeDisplayHardware` のみ）。
- ファイル: 新規 `Sources/DDCPacket.swift`（パケット・チェックサム・capabilities・入力名）、`DDCTransport.swift`（`DDCTransport`、`DDCChannel`、
  `IOAVServiceDDCTransport`、`FakeDDCMonitor`）、`DisplayHardware.swift`（列挙、内蔵バックライト、DDC サービスの発見と `DisplayMatcher`）、
  `DisplayControlService.swift`（直列 I/O キュー、`CoalescingRateLimiter`、`DisplayControlCommand`）、`DisplaysWidget{View,Settings,SettingsView}.swift`、
  `Support/DebugHooks-Displays.swift`（DEBUG: `displayslog`、`displayspreview:<dir>`）、`Tests/DisplayControlTests/`（Swift Testing、`DynamicNotchAppTests` に含まれる）、
  `Support/strings/displays.json`、`docs/displays.md`。最小差分: `NookWidget.swift`（7 か所 1 行ずつ）、`Support/NookWidgetGrid.swift`（2 行）、
  `WidgetsSettingsTabView.swift`（2 行）、`Support/DebugHooks.swift`（`DisplaysWidgetDebug.install()` 1 行）、`README.md`（1 行）。`en.lproj` 再生成。
- 共通部品: ウィジェットは `NookWidgetHeader` / `.nookWidgetFrame()` / `NookWidgetFootnote`、設定は `SettingsForm` / `SettingsSymbolRow` / `.settingsFootnote()`、
  設定構造体は `static let default` + `decodeSetting`、ライフサイクルは `WidgetPresence`（main d280231 のリファクタリングに合わせて 2026-10-21 にリベース）。
- 検証（リベース後、2026-10-21）: `xcodebuild` BUILD SUCCEEDED（警告 24 件はすべて既存、本作業ファイル 0）、CLT ハーネス `swift build` Build complete（既存 24 件のみ）、
  `swift test` 135 tests / 14 suites 合格（うち Displays の 5 suites / 34 tests: パケット 15（引数化 1 件 × 4 コード）、capabilities 2、チャンネル 5、サービス 6、補助 6）、
  `merge-strings.py --check` 最新（948 項目）、`lint-strings.py` missing 0 / format 0。アプリの起動・目視（`displayspreview` を含む）は未実施。
## F8: Downloads ウィジェット（tag 27、2026-10-21、隔離ワークツリー、開発用 bundle id `…DynamicNotch.dev-f8`）

- 新規: `DownloadsWatcher.swift`（監視・読取・進行中判定・Clear Old）、`DownloadsWidgetView.swift`（行・進捗バー・確認カード・閉じたノッチの
  `DownloadsClosedNotchIndicator`）、`DownloadsWidgetSettings.swift` / `DownloadsWidgetSettingsView.swift`、`Support/DebugHooks-Downloads.swift`（`DebugCommandRegistry` に登録、描画は `WidgetSnapshotter`）。
  ビューは WidgetUI（`NookWidgetHeader` / `nookWidgetFrame` / `NookWidgetFootnote` / `nookListRowBackground`）、設定は SettingsUI（`SettingsForm` / `SettingsChoicePicker` / `settingsFootnote`）。
  幅 5 セル（250 pt）、アイコン `arrow.down.circle`、raw `downloads`。
- 監視: 対象フォルダ（既定 `~/Downloads`、設定で変更可）の DispatchSource（vnode）+ 0.25 s デバウンス、読取は専用の直列キュー。並びは「書込中の進行中ダウンロード → 追加日時の新しい順」。
  進行中: Safari `.download` バンドル（中のファイル + Info.plist のバイト数）、Chromium `.crdownload`、Firefox `.part`（0 バイトの同名プレースホルダは隠す）、
  他アプリが公開する NSProgress（フォルダに `Progress.addSubscriber(forFileURL:)`。ディレクトリ購読で中のファイルの進捗が届くことを実測。
  ファイル URL は `fileURL` ではなく `userInfo[.fileURLKey]` に入る）。進行中は 1 s ごと、止まった部分ファイルだけなら 15 s ごとに再読取（サイズ増加 → 速度）。
  60 s 伸びず進捗公開も無い部分ファイルは「Stopped」（閉じたノッチには出さない）。
- 操作: クリックで開く（進行中は Finder で表示）、ホバーで Quick Look / Finder で表示、コンテキストメニューに Add to Tray（`Tray.addFilesFromURLs`）と Copy、
  行のドラッグアウト（`NSItemProvider(contentsOf:)`）。… メニューに Open Folder / Clear Old Items…（ウィジェット内の確認カード → `NSWorkspace.recycle`）。
  自動クリアは既定オフ、設定でオンにする時に確認、以後 6 時間ごと。隠しファイルと進行中は対象外。
- ライフサイクル: `WidgetPresence(.downloads)`。ウィジェットが Nook にある間（閉じたノッチの進捗表示のため）か表示中のビューがある間だけ動き、外すと即停止（`AppDelegate` の `DownloadsWatcher.shared.activate()` で追従開始）。
- 閉じたノッチ: Capture の録画表示と同じ方式（`// F8:` 行を NotchView 2 か所、`LiveActivities/` 2 か所）。他の Live Activity / 録画表示が無いときだけ、リング | 割合（不定ならバイト数）。
- `NSDownloadsFolderUsageDescription` を project.yml / Info.plist に追加。文字列は `Support/strings/downloads.json`（957 項目に再生成、`lint-strings.py` 合格）。
- 検証: `xcodebuild` BUILD SUCCEEDED（本作業ファイルの警告 0）、CLT ハーネス `swift build` Build complete（同 0）。開発用インスタンス（`DN_DEBUG_CHANNEL=f8`・`DN_DEBUG_OFFSCREEN=1`、
  スクラッチフォルダを監視。ユーザーの `~/Downloads` は読んでいない）で: NSProgress 公開の `.crdownload` が 0.30 の確定進捗、成長する `.part` が不定 + 速度、Safari 風バンドルが 47 %、
  放置 `.crdownload` が Stopped、完了でポーリング停止、閉じたノッチの表示、Clear Old（40 日前の 2 件を確認後にゴミ箱へ）、自動クリア（オン時に 1 件、間隔内の再実行なし）、
  Nook から外すと停止・戻すと再開、実ノッチで Quick Look サムネイル表示。オフスクリーンのプレビュー（`dlpreview:`）ではサムネイルが間に合わずアイコン表示になる。
- 未: アプリ内ドラッグでのトレイへのドロップ（`NotchDropController` が `draggingSource != nil` を無視するため。代わりに Add to Tray）、Quick Look パネル・Finder 表示・ドラッグアウトの実操作、
  `~/Downloads` の TCC プロンプト経路（拒否時の表示はプレビューのみ）。
## Usage ウィジェット（F10、2026-10-20〜21、隔離ワークツリー、ブランチ `feature/usage-widget`、`DN_DEBUG_CHANNEL=f10`、開発用 bundle id `…DynamicNotch.dev-f10`）

- 自前収集のスクリーンタイム風統計。新規 `NookWidget.usage`（tag 28、raw `usage`、`hourglass`、5 セル = 250 pt、設定キー `usageWidgetSettings`）。
  表示: 今日の合計、直近 7 日の棒（今日はアクセント色）、今日のピックアップ数（= ロック解除回数）、今日の上位 5 アプリ（アイコン + 最多アプリ比の棒 + 時間）。
  記録オフ時は `NookWidgetAccessState`「Usage recording is off」＋「Turn On…」（設定を開くだけ。ウィジェットから記録は始めない）。
- 収集（`UsageTracker`、公開 API・許可ダイアログなし）: 前面アプリ `NSWorkspace.didActivateApplicationNotification`（開始時・復帰時・解除時は `frontmostApplication`）、
  無操作 `CGEventSource.secondsSinceLastEventType(.combinedSessionState, kCGAnyInputEventType)` を 5 s ごと（閾値超で最後の入力時刻まで遡って打ち切り、次の入力から再開）、
  `willSleep` / `didWake`、`com.apple.screenIsLocked` / `IsUnlocked`（分散通知）とファストユーザスイッチ（`sessionDidResignActive` / `BecomeActive`）。
  loginwindow / ScreenSaver は数えない。イベント間 600 s 超の空白は数えない（スリープ通知の取りこぼし・プロセス停止対策）。
  記録オンの間は**ウィジェットの有無に関係なく**起動時から動く（`AppDelegate` → `UsageStartup`）。設定変更は `withObservationTracking` で追従（オフで停止）。
- 集計（`UsageAccountant`、純粋型）: 30 s ごとの flush は「最後の入力時刻まで」だけ確定し、残りは開いたまま（後から無操作と判定されたら取り消せる）。日付跨ぎは
  `UsageApportioner` が現地の 0 時で分割（DST の 23/25 時間日も可）。除外アプリの時間は誰にも計上しない。
- 保存: SwiftData の専用コンテナ `~/Library/Application Support/<bundle id>/Usage.store`（Note の `Nook.store` とは別。スキーマ変更がノートに波及しない）。
  `UsageAppDayRecord`（dayKey "yyyy-MM-dd"・bundle id・アプリ名・秒）と `UsageDayRecord`（dayKey・ピックアップ数）。全件をメモリに保持し 30 s ごと／停止時／終了時に保存。
  保持 90 日（今日を含む。起動時・日付変更時・記録開始時に削除）。ハーネスは Note と同じ型検査専用の `PersistentModel` 準拠。
- 設定（SettingsUI: `SettingsForm`、`.settingsFootnote()`、`SettingsChoicePicker`、`SettingsApps` / `SettingsAppIcon` / `SettingsRemoveButton`、`SettingsHistoryRow`）:
  記録のオン/オフ（既定オフ、プライバシー注記）、無操作の閾値（1/2/5/10/15 分、既定 5 分）、除外アプリ（最近使ったアプリのメニュー + 「Choose App…」。除外すると過去分も非表示）、
  記録日数と全データ消去（確認ダイアログ）、CSV 書き出し（NSSavePanel。`date,kind,bundle_id,app_name,seconds,count`、`kind` = app / pickups）。
- ファイル: 新規 `Sources/UsageAccounting.swift`（純粋型）、`UsageStore.swift`、`UsageTracker.swift`（+ `UsageStartup`、`UsageAppIcons`）、`UsageWidgetSettings.swift`（`SettingKey` / `StoredKeys` もここ）、
  `UsageWidgetView.swift`、`UsageWidgetSettingsView.swift`、`Support/DebugHooks-Usage.swift`（`registerUsageCommands`: `usagelog` / `usageflush` / `usagepreview:<dir>`、`WidgetSnapshotter`）、
  `Support/strings/usage.json`、`Tests/DynamicNotchAppTests/UsageAccountingTests.swift`（30 tests / 3 suites）。
  最小差分: `NookWidget.swift`（7 行）、`Support/NookWidgetGrid.swift`（2 行）、`WidgetsSettingsTabView.swift`（2 行）、`AppDelegate.swift`（2 行）、`Support/DebugHooks.swift`（1 行）。
- 検証（main d280231 に載せ替え後）: `xcodebuild` BUILD SUCCEEDED（本作業ファイルの警告 0）、ハーネス `swift build` Build complete・`swift test` 131 tests / 12 suites 合格
  （うち Usage 30）、`merge-strings.py --check` 最新（945 項目）、`lint-strings.py` 合格（missing / format 0）。スナップショットはスクラッチの `F10/shots/usage-*-{dark,light}.png`。初回（934f4dd 上）は開発インスタンスで設定の追従と起動時開始を確認。検証時は画面ロック中・最後の入力 4.4 h 前で
  `locked=true idle=true frontmost=nil` → 0 s（正しい挙動）だが、**実際の計上は未確認**（ユーザー操作が要る）。
- 制約: SIGKILL / クラッシュ時は最大 30 s 分の記録を失う（`willTerminate` でのみ保存）。動画視聴など入力の無い利用は閾値で止まる（電源アサーションでの判定は未実装。
  Keep Awake ウィジェットと区別できないため）。前面アプリ単位なのでサイト別・カテゴリ別は無し。除外は表示から隠すだけで過去データは消さない。

## 機能ブランチ 10 本の統合（2026-10-21、main 7368ed6 まで）

`d280231`（リファクタリング完了）の上に次の 10 本を `--no-ff` でマージした（各マージ後に strings 再生成・`xcodegen generate`・ハーネス／FanControl ビルド、
F2・F3 の後と最後に `scripts/check.sh --keep-going` 全 12 ステップ合格）。

| # | ブランチ | マージ | 内容 |
|---|---|---|---|
| F1 | `feature/charge-limit` | 7ee2b87 | 充電上限 80 %（`CHWA`、ヘルパーの専用要求、protocol v2）。Mac14,9 には `CHWA` が無く「Not supported on this Mac」 |
| F2 | `feature/power-profiles` | c50bf25 | 電源・蓋・時間帯ルールでプロファイルと Low Power Mode を切替（`pmset` 専用要求、エラー 8/9）。`FanProfileArbiter` が優先順位を一元管理 |
| F3 | `feature/app-linked-profile` | 3299ca0 + 4d1eeb8 | アプリ／持続負荷連動プロファイル。4d1eeb8 でアービタの `.workload` 層への claim / release に配線 |
| F4 | `feature/automation-surface` | d3c579e | `dynamicnotch://` URL スキーム、App Intents、`dnctl`。F6 用の `DisplayControlCommand` フックは未配線 |
| F5 | `feature/hud` | ea8cc9d | 音量・輝度・キーボードバックライトの HUD（Live Activity、Input Monitoring 権限） |
| F6 | `feature/display-brightness` | dd6c736 | Displays ウィジェット（tag 29。内蔵・DisplayServices・DDC/CI） |
| F7 | `feature/airpods-noise-control` | 3bf43bd | Audio ウィジェットで AirPods の聴取モード切替（コントロールセンターを AX 操作） |
| F8 | `feature/downloads-widget` | 2d6b880 | Downloads ウィジェット（tag 27）と閉じたノッチの進捗表示 |
| F9 | `feature/widget-pages` | b3fc374 | Nook ウィジェット行のページ化（ページャ、ページ別設定、⌥ 押しで持ち上げて並べ替え） |
| F10 | `feature/usage-widget` | 7368ed6 | 自前集計のアプリ使用時間ウィジェット（tag 28、既定 OFF） |

- 競合の解決: F1/F2 は protocol version 2 を 1 つの契約にまとめた（`setChargeLimitEnabled:reply:` と `setLowPowerMode:reply:`、エラー 8/9 は F2）。
  F2/F3 は起動行を両方残し、kit.md の優先順位節を「Profile precedence and automation」に統合、PATCHES.md は F2 = (h)、F3 = (i)。
  F6/F8/F10 のレジストリ（`NookWidget`、`NookWidgetGrid`（F9 のページャ版）、`WidgetsSettingsTabView`、`DebugHooks`）は全項目をタグ順に残した。
  `Localizable.strings` は毎回 `merge-strings.py` で再生成（手でマージしない）。
- チェック（7368ed6）: アプリ Xcode ビルド + テスト 253 tests / 28 suites、ハーネス 253 tests、FanControl 561 tests / 78 suites（警告 0）、
  IntegrationTypeCheck Swift 5 / 6（警告 0）+ 3 tests、strings lint（missing 0 / format 0、unused 9）、shellcheck。
  `.build-check/typecheck6` の古いキャッシュで新規ファイルが見えず失敗したことがあり、キャッシュ削除で解消。
- ビルド: `.derivedData/Build/Products/Debug/DynamicNotch.app`、アプリ cdhash `4a964029d5798aea439493d2834e0116dce32701`、
  ヘルパー cdhash `9865a807c07e4cb0890d2044c192f113b4c8ef48`（ad-hoc）。ヘルパーは protocol v2 になったので、
  このビルドを使うには `install.sh` の再実行が必要（ユーザーが sudo で行う）。

## 2 回目のレビュー修正（2026-10-21、`docs/review-2026-10-21-features.md` の 44 件）

44 件（high 1 / medium 20 / low 23）をすべて修正。3 グループが個別に修正・検証し、統合後の main で `scripts/check.sh` 全 12 ステップ合格
（アプリ 287 tests / 38 suites、ハーネス 288 tests、FanControl 587 tests / 79 suites・警告 0、IntegrationTypeCheck Swift 5 / 6、strings lint、shellcheck）。

- FanControl（81ac749、ec5e7a6、9738cc0）: Low Power Mode は fan セッションとは別の短命な接続で送り、電源別に設定・復元する。
  XPC のセレクタは `setLowPowerModeWithBattery:ac:reply:`（`setLowPowerMode(battery:ac:)`）に変わったが、未リリースなので
  **protocol v2 のまま**。許可 argv は `-a|-b|-c lowpowermode 0|1` と `pmset -g custom`。充電上限の古い再読込が完了した変更を上書きしない。
  アービタは保留中の決定を適用し、適用中の手動選択を尊重し、ベースラインを保持する。`docs/power-profiles.md` を電源別の復元に合わせて更新。
- Automation / HUD / AirPods（ed673d7、42a7c8f、b0158f7）: タイマーの Int オーバーフローによるクラッシュを修正。URL からの
  `capture/…` は新しい設定 **「Allow automation to take screenshots」**（Capture ウィジェット設定、**既定 OFF**）が ON のときだけ実行。
  HUD は輝度読取の失敗でバックオフ（永久に止めない）、AirPods は Sound メニューを必ず閉じ、要求をキューに入れる。
- Pages / Displays / Downloads / Calendar / Tray（7b96e72、e4879d5、a7432d9）: ウィジェットページは**表示中のページだけを描画**（スワイプ中は隣のページも）
  （マウント・ID・スワイプ・設定を修正）、Displays / Downloads / カレンダー権限・トレイ・Live Activity 選択の修正。
- 統合時の追加: `TimerCreatorView` のスクロールモニタが、列の上を通るスワイプの `.ended` など自分が使わないイベントまで
  消費していた（B2 の部分項目）。縦移動のあるイベントだけを消費し、横スワイプ・縦移動の無いイベント（`.ended` / `.cancelled`・慣性の終了）は通す。
