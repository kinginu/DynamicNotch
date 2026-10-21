# Menu bar item hiding — technique reference (Menu Bar widget, 2026-10-20)

Background for `DynamicNotchApp/Sources/MenuBarItems*.swift`: how a third-party app can hide other
apps' menu bar items and show them somewhere else, using only public macOS APIs. The notes come from
Apple's API documentation, from measurements on this Mac (MacBook Pro Mac14,9, macOS 26.5.2, three
displays), and from looking at how Ice works.

> **Attribution / provenance.** Ice (<https://github.com/jordanbaird/Ice>, MIT, © Jordan Baird) was
> consulted **for technique only**, after the user allowed it: the 10 000 pt length of the
> "hidden" control item (`ControlItem.swift`), and the fact that its synthetic mouse events set the
> window-under-pointer event fields to the item's window (`MenuBarItemManager.swift`). No Ice code,
> identifiers or structure were copied. Ice also uses private CGS/SkyLight functions (window lists,
> spaces, connection properties). This implementation does not use them. Everything below is
> written independently.

## 1. Hiding: a separator status item with a huge length

- The status area is laid out from the right edge leftwards, in the user's order. Our own
  `NSStatusItem` (the *separator*, `autosaveName` "DynamicNotchMenuBarSeparator") sits somewhere in
  that row.
- **Hidden** = `separator.length = 10_000`. Every item to its left is pushed past the left edge
  of the screen. The separator's button has no image then, so its visible part looks like empty
  menu bar, and clicking it shows the hidden items again.
- **Shown** = `NSStatusItem.variableLength` with a `chevron.compact.left` template image.
- Arranging is done by the system: **⌘-drag** moves status items, including across the
  separator. `behavior = []` stops the separator itself from being dragged out of the menu bar.
- Quitting the app removes the separator, so every item comes back. This is the escape hatch.
- Measured: `button.window.frame` follows the length (3 000 pt length → frame x = −55, width
  3016 on a 3840 pt display). The width of a variable-length item is the image plus about 16 pt
  of padding (20 pt length → 36 pt window).

## 2. Finding the items: `CGWindowListCopyWindowInfo`

- Status item windows are at layer `kCGStatusWindowLevel` (25), one window per item **per
  display** (each display has its own menu bar copy).
- **macOS 26: every status item window is owned by Control Center** (`kCGWindowOwnerPID`
  = Control Center for all apps' items, in both CGWindowList and ScreenCaptureKit
  `SCWindow.owningApplication`). The owning app therefore can't come from the window owner.
- `NSStatusItem.button.window.windowNumber` is a placeholder (4294967296) on macOS 26 and does
  not match any window server window. The **frame** is correct, so the separator is located by
  its frame.
- Window titles (`kCGWindowName`, readable only with Screen Recording) are the item's autosave
  name on the active menu bar ("Item-0", "Clock", "WiFi", "BentoBox-0", "raycastIcon") and the
  owning app's **bundle identifier** on the other displays' copies.
- Separator row = windows whose top equals the separator's top (CG global coordinates, origin at
  the top-left of the primary display; `y_CG = primaryHeight − maxY_AppKit`). Hidden items are
  the row windows left of the separator:
  - while shown, those on the separator's display;
  - while hidden (pushed off-screen), those whose nearest separator-sized copy to their right
    is ours. Displays at the same y also have a pushed-off copy of the separator, and this rule
    keeps their items out.
- Our own status windows (app icon, separator) are excluded by frame (`NSApp.windows` of class
  `NSStatusBarWindow`).

### Owning app (best effort, in order)

1. **Accessibility**: `AXUIElementCreateApplication(pid)` → attribute `AXExtrasMenuBar` →
   children with `AXPosition` / `AXSize`. Measured: this still reports the real app for each
   item on macOS 26, with positions inside the item windows. Some apps don't respond, and a
   full scan took **12.9 s** with a 0.2 s timeout, so it runs on a background queue with a 0.1 s
   per-app timeout, at most every 10 s, and only while an item is unresolved.
2. The window title when it is a bundle identifier of a running or installed app.
3. The same item's copy on another display: same offset from that display's right edge and
   same width, with a bundle-id title.
4. Control Center's own titles ("Clock", "WiFi", "Sound", "Bluetooth", "BentoBox" …).
5. Otherwise "Menu Bar Item".

## 3. Images: ScreenCaptureKit

- `SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)` → the `SCWindow`
  with the item's window ID → `SCScreenshotManager.captureImage(contentFilter:
  SCContentFilter(desktopIndependentWindow:), configuration:)`, at the display's backing scale.
  It runs about once a second, and only while the widget is on screen.
- `CGWindowListCreateImage` is obsoleted in the macOS 15 SDK, and this target is macOS 26, so
  only ScreenCaptureKit is used.
- Requires **Screen Recording** (`CGPreflightScreenCaptureAccess` / `CGRequestScreenCaptureAccess`).
  Without it the widget lists app names and icons (and window titles are empty too).
- Items rendered for a light menu bar are dark. The widget puts dark images (mean luminance
  < 0.35) on a light tile so they stay visible in the dark notch.
- Fully transparent captures are dropped and the last good image is kept. Items pushed off-screen
  may not be drawn by the window server.

## 4. Clicking an item: un-hide, post `CGEvent`s, re-hide

1. Close the notch. If hidden, set the separator to its shown length and wait about 0.45 s for
   the layout to settle.
2. Read the item's frame again by window ID, and require it to be on a screen.
3. Post `leftMouseDown/Up` (or `rightMouseDown/Up`) at its centre with
   `CGEvent(mouseEventSource:mouseType:mouseCursorPosition:mouseButton:)` to `.cghidEventTap`.
   Set `.mouseEventWindowUnderMousePointer` and
   `.mouseEventWindowUnderMousePointerThatCanHandleThisEvent` to the item's window. Then warp the
   cursor back with `CGWarpMouseCursorPosition`.
4. Re-hide after at least 1.5 s, once no pop-up-menu-level window (`kCGPopUpMenuWindowLevel`) is
   on screen and the pointer is not in the menu bar (two checks in a row, 0.5 s apart), and at the
   latest after 60 s.

- Posting events requires **Accessibility** (`AXIsProcessTrusted` /
  `AXIsProcessTrustedWithOptions(prompt)`). Without it, a click in the widget only shows the
  hidden items for at least 8 s so the user can click the real item.
- **Move to Menu Bar** (an app in the "Always show in menu bar" list that ended up hidden): an
  explicit button posts a ⌘-drag (`leftMouseDown` / `leftMouseDragged` ×12 / `leftMouseUp`, all with
  `.maskCommand`) from the item to 4 pt right of the separator. It never runs automatically.

## 5. Onboarding

There's no API to reorder other apps' items. The user does it with ⌘-drag. The widget and
settings say: show the separator (‹), then hold ⌘ and drag items to its left to hide them.
