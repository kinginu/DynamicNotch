# iOS タイマー（Clock／コントロールセンター／Dynamic Island）参照メモ

> **Historical note (2026-10-20).** In Japanese; this is research notes for the notch timer. The timer code may have moved on since.

調査日 2026-10-20。DynamicNotch のタイマー（`DynamicNotchApp/Sources/Timer*.swift`、閉じたノッチのライブアクティビティ）を
iPhone の Dynamic Island に寄せるための参照。Apple のサポート／HIG ページは JavaScript 描画で本文を取得できなかったため、
下記は第三者記事と、記事で裏付けの取れない点は「記憶（未検証）」と明記した一般知識に基づく。

> **版について**: ユーザー指示は「iOS 26」だが、調査時点（2026-10）の最新は **iOS 27**（2026-09 公開）で、コントロールセンターの
> タイマーが作り直されている。iOS 26 までの形（Clock アプリのホイール）と iOS 27 の差分を両方記す。

## 1. タイマーの開始

| 項目 | iOS 17〜26 | iOS 27 |
|---|---|---|
| コントロールセンターのタイマー | タップで Clock アプリの「タイマー」タブを開く。長押しで 1 分〜2 時間の固定刻みの縦スライダー（カスタム時間不可）[1][2] | タップで画面上部（Dynamic Island から垂れ下がる）にオレンジのスライダー帯が出て、左右にスワイプで長さを決めてその場で開始。既定は 1 分刻み、押し続けると 15 秒刻み（別記事は 25 秒刻みと記述、未確定）。帯は右下→左上のスワイプで閉じる。長押しでタイマー／ストップウォッチ／アラームのクイックメニュー [3][4][5] |
| Clock アプリのタイマー | 時・分・秒の 3 列ホイール、「ラベル」欄、「タイマー終了時」（サウンド選択。末尾に「再生停止」= 音楽・Podcast を止めるスリープタイマー）、丸い「キャンセル」「開始」ボタン [6][7] | 同左（Recents 付き） |
| 最近使った項目 | iOS 17 で「最近使った項目（Recents）」が追加。過去に開始したタイマーが長さ＋ラベルで並び、行の再生ボタンで即開始 [7][8] | 同左 |
| 複数タイマー | iOS 17 から同時に複数実行可。実行中に「＋」で追加、各タイマーを個別に一時停止・再開・キャンセル [7][8][9] | 同左 |

## 2. Dynamic Island / Live Activity の表示

ActivityKit の 3 表示（compact / minimal / expanded）に従う（記憶・未検証の細部あり）。

- **Compact（アクティビティが 1 つ）**: カメラ部の左右に付く。Clock のタイマーは **左 = オレンジのタイマー記号（進捗リング）**、
  **右 = オレンジの残り時間（等幅数字）**。一時停止中は数字が止まり淡くなる。
- **Minimal（他のアクティビティと同時）**: 一方が compact、もう一方は本体から離れた小さな円（タイマーはオレンジの進捗リング／記号のみ）。
- **Expanded（長押し）**: 左に丸ボタン 2 つ（**一時停止／再開 = オレンジ**、**キャンセル ✕ = グレー**）、右にラベル（未設定なら「タイマー」）と
  大きなオレンジの残り時間。ロック画面／通知センターの Live Activity も同じ構成で、ここからも一時停止・再開・停止できる [8][9]。
- 複数タイマー時は最後に開始した（または最も早く終わる）タイマーが Island に出て、他はロック画面にそれぞれの Live Activity が並ぶ [8][9]。
- iOS 27 ではスライダーで開始したタイマーが滑らかなアニメーションで Island に吸い込まれ、Island をタップで変更できる [3][4]。

## 3. 終了時

- 「タイマー終了時」に選んだサウンドが鳴る（どのタイマーが終わっても鳴る）[9]。「再生停止」を選ぶと音は鳴らず再生中のメディアを止める [6]。
- 使用中（ロック解除中）は Dynamic Island が大きく展開して **ラベル＋「停止」（大きいボタン）＋「繰り返し」** の通知になり、
  停止するまで音が繰り返し鳴る（記憶・未検証。iOS 26 の AlarmKit の alert 表示＝停止ボタン＋任意の副ボタンと同じ型）。ロック中は
  アラームと同様の全画面。止めるとアクティビティは消え、タイマーは Recents に残る。

## 4. DynamicNotch での対応（実装方針）

| iOS | DynamicNotch（macOS ノッチ） |
|---|---|
| Clock のホイール + ラベル + 開始 | ウィジェットの作成画面: h:m:s ホイール、最近使った項目のチップ（なければプリセット）+「…」メニュー、ラベル欄、丸い開始ボタン |
| Recents | `NookTimersStore.recents`（長さ＋ラベル、最大 6 件、UserDefaults 永続） |
| タイマー終了時（サウンド／再生停止） | タイマー設定の「タイマー終了時」（システムサウンド 14 種／再生停止／なし） |
| Expanded（大きな残り時間・リング・一時停止・✕・ラベル） | 開いたノッチのウィジェット（1 件: リング内に大きな残り時間＋ラベル、✕／一時停止・再開／＋。複数: 行リスト） |
| Compact | 閉じたノッチ: カメラ左 = オレンジの進捗リング＋`timer`、右 = オレンジの残り時間 |
| Minimal | 他のライブアクティビティ（メディア等）が表示中は、それを compact に、タイマーは外側の小さな進捗リングに |
| 終了アラート（停止・繰り返し・音の反復） | 閉じたノッチが広がり、ベル＋ラベル＋「停止」表示。音は「アラートの長さ」まで繰り返し、停止（ウィジェット）または時間切れで消えて Recents に残る。ウィジェットには「停止」「繰り返し」 |

## 出典

1. How-To Geek — How to Quickly Set a Timer on Your iPhone or iPad: https://www.howtogeek.com/724914/how-to-quickly-set-a-timer-on-your-iphone-or-ipad/
2. Gadget Hacks — Use These Tricks to Set Timers Faster on Your iPhone: https://ios.gadgethacks.com/how-to/use-these-tricks-set-timers-faster-your-iphone-0312928/
3. Gear Patrol — Apple Is Quietly Making an Essential iPhone Feature Way Cooler (iOS 27 timer): https://www.gearpatrol.com/?p=1024916
4. iPhoned — Timer op je iPhone werkt in iOS 27 helemaal anders: https://www.iphoned.nl/tips/timer-iphone-ios-27/
5. iGeeksBlog — Hidden iOS 27 features: https://www.igeeksblog.com/ios-27-hidden-features/
6. Apple iPhone User Guide — Set timers in Clock on iPhone（本文は取得不可。「When Timer Ends」「Stop Playing」の記述は検索結果の抜粋）: https://support.apple.com/guide/iphone/set-timers-iph8241d6b2a/ios
7. MacRumors — How to Use and Label Multiple Timers in iOS: https://www.macrumors.com/how-to/use-label-multiple-timers-ios
8. Trusted Reviews — How to set and label multiple timers in iOS 17: https://www.trustedreviews.com/how-to/set-and-label-multiple-timers-ios-17-4371593
9. iGeeksBlog — How to set up and use multiple timers on iPhone in iOS 17: https://www.igeeksblog.com/how-to-set-up-multiple-timers-on-iphone/
10. Apple HIG — Live Activities（compact / minimal / expanded の定義。本文取得不可）: https://developer.apple.com/design/human-interface-guidelines/live-activities
