# Displays ウィジェット — 輝度・DDC/CI の調査と設計（2026-10-20）

`NookWidget.displays`（tag 29、raw `displays`、アイコン `display`、5 セル = 250 pt、設定キー `displaysWidgetSettings`）。
接続中のディスプレイを一覧し、内蔵ディスプレイの輝度と、外部モニターの輝度・コントラスト・音量（DDC/CI）をスライダーで変更する。
入力ソース（VCP 0x60）は**表示のみ**（ノッチから入力を切り替えると画面が消えるため）。

> **安全上の注意（この調査の範囲）**: 実機ではディスプレイの値を一切変更していない。内蔵・外部とも **読み取りのみ**
> （DisplayServices の getter、IORegistry の読取、DDC/CI の Get VCP Feature 0x01 と Capabilities Request 0xF3 のみ。
> プローブは送信前に opcode を検査し、それ以外を拒否）。書込経路（Set VCP 0x03 / `DisplayServicesSetBrightness`）は
> `FakeDDCMonitor` / テスト用 `FakeDisplayHardware` に対してのみ動作確認した。実モニターへの書込は未検証。

## 1. 検証環境

- MacBook Pro Mac14,9（M2 Pro）、macOS 26.5.2、Xcode 26.6
- 接続ディスプレイ（`NSScreen` + `CGDirectDisplayID`）:

| CGDirectDisplayID | NSScreen.localizedName | builtin | main | vendor | model | serial |
|---|---|---|---|---|---|---|
| 1 | Built-in Display | yes | no | 1552 | 41038 | 4251086178 |
| 3 | DELL P3225QE (1) | no | yes | 4268 | 17277 | 1093753164 |
| 2 | DELL P3225QE (2) | no | no | 4268 | 17277 | 1093817932 |

（ブリーフィングでは「内蔵のみ」とされていたが、調査時点では DELL P3225QE が 2 台 USB-C で接続されていた。）

## 2. 内蔵ディスプレイの輝度（Apple Silicon、macOS 26）

| 経路 | 種別 | 結果 |
|---|---|---|
| `IOServiceGetMatchingServices("IODisplayConnect")` + `IODisplayGetFloatParameter(kIODisplayBrightnessKey)` | 公開 IOKit | **使えない**: Apple Silicon には `IODisplayConnect` が無い（0 件） |
| `IODisplayGetFloatParameter` を `AppleARMBacklight` サービスに直接 | 公開 IOKit | **使えない**: `0xE00002C7`（`kIOReturnUnsupported`） |
| `AppleARMBacklight` の `IODisplayParameters` を IORegistry から読む | 公開 IOKit | 読めるが**ユーザー設定に追従しない**: `brightness = {min 0, max 65536, value 32768}`（= 0.5）で固定。同時に `BrightnessMilliNits.value = 381794`（381.8 nit）、`rawBrightness = 1488/2047`、`BrightnessMicroAmps = 3199` |
| `DisplayServicesGetBrightness(displayID, &float)`（`/System/Library/PrivateFrameworks/DisplayServices.framework`、dlsym） | 非公開 | **正しい**: `0.42540225`（コントロールセンターのスライダー値）。外部 DELL には `1000`（エラー）を返す。`DisplayServicesCanChangeBrightness`: 内蔵 true / 外部 false |
| `CoreDisplay_Display_GetUserBrightness` | 非公開 | 使えない: 全ディスプレイで 1.0 |

方針（`Sources/DisplayHardware.swift`）:

- 読取: `DisplayServicesBacklight.brightness` → 失敗時のみ `RegistryBacklight`（IORegistry の `brightness`）。後者を使ったときは
  ウィジェットに「≈」を付けて概算と示す（`DisplayControlState.brightnessApproximate`）。
- 書込: `DisplayServicesSetBrightness`（dlsym。無ければ書込不可でスライダーを無効化）。公開 API の書込経路
  （`IODisplaySetFloatParameter`）は読取と同じ理由で使えないと判断し実装していない（**実機で未検証**）。
- 内蔵の輝度はキー操作・自動輝度で変わるので 2 秒ごとに読む（DisplayServices の getter は軽い）。

`BrightnessMilliNits` が追従するかは、輝度を変えられない制約のため未確認（将来の公開 API フォールバック候補）。

## 3. 外部モニター: DDC/CI over IOAVService（Apple Silicon）

### 3.1 サービスの発見と対応付け

IORegistry（IOService plane）の構造（Mac14,9）:

```
dispext0@88000000 (AppleARMIODevice)
  └ IOMobileFramebufferShim   external = Yes, DisplayAttributes.ProductAttributes = {LegacyManufacturerID 4268, ProductID 17277, SerialNumber 1093817932, ProductName "DELL P3225QE", …}
…
dispext0:dcpav-service-epic:0 (AFKEPInterfaceKextV2)
  └ DCPAVServiceProxy          Location = External
```

- `DCPAVServiceProxy`（`Location` = `External`）の親ノード名 `dispextN:…` と、フレームバッファ（`IOMobileFramebufferShim`、
  他機種では `AppleCLCD2`）の親ノード名 `dispextN@…` の **`dispextN` 部分**で組にする（`DDCServiceLocator`）。
  内蔵（`disp0`）のシムには `DisplayAttributes` が無く、内蔵用の `DCPAVServiceProxy` は無い。
- フレームバッファの `ProductAttributes` の `LegacyManufacturerID` / `ProductID` / `SerialNumber` が
  `CGDisplayVendorNumber` / `CGDisplayModelNumber` / `CGDisplaySerialNumber` と一致する（上表の 2 台で確認）ので、
  これで `CGDirectDisplayID` と対応付ける（`DisplayMatcher`。シリアル 0 の同型機は順番で）。
  なお `EDID UUID` は同型 2 台で同一（`10AC7D43-0000-0000-3323-0104B5462778`）なので識別に使えない。
- I2C は IOKit.framework がエクスポートするがヘッダに無い `IOAVServiceCreateWithService` / `IOAVServiceReadI2C` /
  `IOAVServiceWriteI2C` を dlsym で解決（3 つとも存在を確認）。手法は MonitorControl / BetterDisplay（MIT）と同じだが、
  コードは DDC/CI 仕様から独自に書いた（逐語的転記なし）。

### 3.2 パケット（`Sources/DDCPacket.swift`）

- チップアドレス 0x37（書込アドレス 0x6E）、サブアドレス = ホストの送信元アドレス 0x51。
- 要求: `[0x80|n][payload…][chk]`、chk = 0x6E ^ 0x51 ^ 以降全バイトの XOR。
  - Get VCP: `82 01 <code> <chk>`（例: 輝度 `82 01 10 AC`）
  - Set VCP: `84 03 <code> <hi> <lo> <chk>`
  - Capabilities: `83 F3 <ofs hi> <ofs lo> <chk>`（例: `83 F3 00 00 4F`）
- 応答: `[0x6E][0x80|n][payload…][chk]`、chk = 0x50（仮想ホストアドレス）^ 0x6E 以降の XOR。
  - Get VCP 応答: `6E 88 02 <result> <code> <type> <max hi> <max lo> <cur hi> <cur lo> <chk>`（result 0x01 = 非対応）
  - `6E 80 BE` は null message（ビジー／非対応）。バス待機時は全 0x00。
- タイミング: 要求→応答の読取まで 50 ms（仕様 40 ms）、Set 後 50 ms、失敗時 30 ms 待って最大 3 回（`DDCChannel.Timing`）。

### 3.3 読取結果（両 DELL とも 1 回目で成功、読み取りのみ）

| VCP | 意味 | dispext1（ID 3） | dispext0（ID 2） | 生バイト（dispext1） |
|---|---|---|---|---|
| 0x10 | 輝度 | 74 / 100 | 72 / 100 | `6E 88 02 00 10 00 00 64 00 4A 8A` |
| 0x12 | コントラスト | 75 / 100 | 75 / 100 | `6E 88 02 00 12 00 00 64 00 4B 89` |
| 0x62 | 音量 | 50 / 100 | 50 / 100 | `6E 88 02 00 62 00 00 64 00 32 80` |
| 0x60 | 入力 | 0x1B1B（max 14） | 0x1B1B | `6E 88 02 00 60 00 00 0E 1B 1B DA` |

Capabilities（両機同一、14 フラグメント）:

```
(prot(monitor)type(lcd)model(P3225QE)cmds(01 02 03 07 0C E3 F3)vcp(02 04 05 08 10 12 14(05 08 0B 0C) 16 18 1A 52 60( 1B 0F 11) 87 AA(00 01 04 02) AC AE B2 B6 C6 C8 C9 CA CC(02 03 04 06 09 0A 0D 0E) D6(01 04 05) DC(00 03 05) DF E0(03) E2(00 02 04 0E 12 14) EA(F800 F801) F1 F2 FE FD)mccs_ver(2.1)mswhql(1))
```

所見:

- **入力ソースは下位バイト**を使う: DELL は 0x1B（USB-C、MCCS 外のベンダー値）を上位バイトにも重ねて 0x1B1B と返す。最大値 14 は無意味。
  対応入力は capabilities の `60( 1B 0F 11)` = USB-C / DisplayPort 1 / HDMI 1。
- **音量は capabilities に無い**（0x62 は vcp リストに無い。P3225QE はスピーカー非搭載）のに Get VCP 0x62 は 50 を返す。
  したがって音量スライダーは capabilities に 0x62 があるモニターだけに出す（`DisplayControlState.isAvailable(.volume)`）。
- 輝度は capabilities 文字列に無い短い文字列のモニターもあるとされるので、輝度だけは capabilities に無くても読みに行く。

### 3.4 サービス（`Sources/DisplayControlService.swift`）

- すべてのハードウェア I/O（DisplayServices、IORegistry、DDC）は 1 本の直列キュー `DisplayControlService.io` で行う
  （DDC メッセージがバス上で重ならず、抜けたモニターが UI を止めない）。
- スライダー: 値は 0…1 にクランプ、`CoalescingRateLimiter` でディスプレイ × コントロールごとに「最新値のみ」・最小間隔
  DDC 100 ms／内蔵 30 ms。書込直後 1.5 秒はその項目を読取結果で上書きしない（モニターがしばらく旧値を返すため）。
- 読取: DDC は設定の間隔（既定 30 秒）と画面構成変更・スリープ復帰 3 秒後。capabilities はディスプレイごと（`DisplayInfo.key`
  = vendor-model-serial）に 1 回だけ読みキャッシュ。ウィジェットが Nook に無く表示中のビューも無ければ停止（Storage と同じ）。
- ライフサイクル: `WidgetPresence`（`.displays`）。必要なとき（表示中のビューがある／Nook にある）だけ DDC タイマー・内蔵 2 秒タイマー・画面構成の監視を入れ、スリープ復帰 3 秒後に再読取（`onWake(after: 3)`）。
- 自動化: `DisplayControlCommand`（Codable、`init?(parsing:)`）。例 `brightness 60%`、`brightness +10% builtin`、
  `contrast 0.5 main`、`volume -5 external`、`brightness 40 id:3`、`brightness 70 name:DELL`。`perform(_:)` で実行。
  入力切替は受け付けない。現時点で URL スキーム／Shortcuts への配線は無い（型のみ）。

## 4. テスト

`Tests/DisplayControlTests/`（Swift Testing。単一のテストターゲット `DynamicNotchAppTests` に含まれる。`swift test --filter "DDC|Displays"`）:

- `DDCPacketTests`（15 テスト + 引数化 4 件）: 要求バイト（ddcutil と同じ `82 01 10 AC` / `83 F3 00 00 4F`）、Set の
  ビッグエンディアンとチェックサム、全要求の XOR = 0、ペイロード長上限、実機応答（輝度・入力）の解析、チェックサム不一致、
  待機バス・切詰め・長さバイト不正、null message、非対応コード・コード不一致・opcode 不一致、応答ビルダの往復、
  capabilities フラグメント、割合→値のクランプと丸め。
- `DDCCapabilitiesTests`: 実機の capabilities 文字列、詰めて書かれたコード、`vcp(` の無い文字列。
- `DDCChannelTests`: `FakeDDCMonitor` での読取・書込、待機バス／チェックサム不良からのリトライ、試行回数上限、非対応は再試行しない、
  複数フラグメントの capabilities、チェックサム不良の要求をモニター側が無視。
- `DisplayControlServiceTests`（`FakeDisplayHardware`）: 読取結果、クランプして書込、連続スライドの合体（最新値のみ）、内蔵への書込、
  無効化したディスプレイは読み書きしない、`perform`。
- `DisplayHelperTests`: レートリミッタ、コマンドの解析と Codable、`DisplayMatcher`、ノード名、IORegistry 値の割合、設定の寛容なデコード。

DEBUG: `displayslog`（全ディスプレイを 1 回読んでログ）、`displayspreview:<dir>`（`WidgetSnapshotter`。live は読取のみ、
sample / one / unavailable / ddc-off / empty は `PreviewDisplayHardware`（`FakeDDCMonitor`）上、設定ペイン）。`Support/DebugHooks-Displays.swift`。

## 5. 未検証・既知の制限

- 実モニター・内蔵への**書込は一度も行っていない**（Set VCP、`DisplayServicesSetBrightness`）。ユーザーの確認を得てから、
  DELL 1 台の輝度を 1 段だけ変えて戻す手順で確認すること。
- Intel Mac の DDC（`IOFramebuffer` 経由の I2C）は対象外（プロジェクトは Apple Silicon のみ）。
- 一部の機種の内蔵 HDMI ポート（M1 Mac mini など）、DisplayLink、多くの USB-C ドック経由では DDC/CI が通らないとされる（コミュニティ情報、未確認）。
- ハードウェアミラーリング中の副ディスプレイは `NSScreen` に出ないので一覧に出ない。
- `AppleCLCD2`（M1 世代のフレームバッファクラス）での `dispextN` 対応付けは本機に無いため未確認。
