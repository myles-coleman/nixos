# 01 Questions Round 1 - wvkbd Hyprland Keybinds

Please answer each question below (select one or more options, or add your own notes). Feel free to add additional context under any question.

## 1. Base Layout Set

Which existing wvkbd layout set should we use as the starting point?

- [ ] (A) `mobintl` (mobile international) -- compact layout designed for phones/small screens. Fewer keys per row, larger touch targets. Currently the default.
- [X] (B) `deskintl` (desktop international) -- full-sized keyboard layout with F-keys, full navigation row, and more keys per row. Designed for tablets/laptops with larger screens.
- [ ] (C) Other (describe)

**Recommended answer(s):** [(B)]

**Why these are recommended:**

- The GPD Pocket 4 is a handheld *laptop* with a physical keyboard, not a phone. When in tablet mode the screen is larger than a phone (8" class), making `deskintl`'s wider layout more appropriate.
- `deskintl` already has a full number row, F-keys, and all modifier keys (Ctrl, Alt, Super, AltGr) on its `Full` layout, providing a closer match to the physical keyboard the user is familiar with.
- `mobintl` could work but would require more modification to add the full keybind set, and its larger key sizes waste screen real estate on a device this size.

## 2. Implementation Approach

How should the Hyprland keybinds be added?

- [X] (A) **New layer within the existing layout set** -- Add a new "Hyprland" layer/layout (e.g. `keys_hyprland[]`) to the chosen layout set's `layout.*.h` file. This layer would appear alongside existing layers (Full, Special, etc.) and be accessible via the layer-switcher key (⌨).
- [ ] (B) **Entirely new custom layout set** -- Create a new trio of files (`layout.hyprland.h`, `keymap.hyprland.h`, `config.hyprland.h`) and build with `make LAYOUT=hyprland`. This would be a standalone keyboard with its own layers, including the Hyprland keybind layer.
- [ ] (C) **Modify the existing Full/Special layers in-place** -- Add workspace keys directly into the existing layers rather than creating a separate Hyprland layer.
- [ ] (D) Other (describe)

**Recommended answer(s):** [(A)]

**Why these are recommended:**

- `(A)` is the smallest change with the highest value. You get all the existing layouts (typing, special, emoji) plus a new dedicated Hyprland layer. It avoids duplicating the entire layout set.
- `(B)` gives maximum control but requires maintaining a separate fork of *all* layouts. More effort, harder to stay current with upstream changes.
- `(C)` risks cluttering the existing layouts and making normal typing harder.

## 3. Hyprland Keybinds Scope

Which Hyprland keybinds should be accessible from the on-screen keyboard? Select all that apply.

- [X] (A) **Workspace switching** (`Alt+1` through `Alt+0` for workspaces 1-10) -- the core request
- [X] (B) **Move window to workspace** (`Alt+Shift+1` through `Alt+Shift+0`)
- [X] (C) **Window management** (`Alt+Q` terminal, `Alt+C` kill, `Alt+V` toggle floating, `Alt+J` toggle split)
- [ ] (D) **App launchers** (`Alt+E` file manager, `Alt+R`/`Alt+S` rofi/wofi menus)
- [ ] (E) **Special workspace** (`Alt+TAB` toggle scratchpad, `Alt+Shift+S` move to scratchpad)
- [ ] (F) **Focus direction** (`Alt+arrows` for moving focus left/right/up/down)
- [ ] (G) Other (describe)

**Recommended answer(s):** [(A), (B), (C), (E)]

**Why these are recommended:**

- `(A)` is the explicit problem stated -- you can't switch workspaces from the software keyboard. This is essential.
- `(B)` is the natural companion to workspace switching. If you can go to workspace 3, you'll also want to send a window there.
- `(C)` covers the most useful window management actions that are otherwise unreachable without a physical keyboard.
- `(E)` the special workspace/scratchpad is another navigation action that requires keyboard shortcuts.
- `(D)` is lower priority because app launchers can often be accessed other ways (dock, menu, etc.).
- `(F)` is lower priority because focus can typically be changed by tapping the target window on a touchscreen.

## 4. Key Arrangement for Workspace Layer

How should the workspace keys be visually arranged on the Hyprland layer?

- [ ] (A) **Number row with toggle** -- A row of keys labeled `W1`-`W10` (or `1`-`0` with a visual indicator), with a toggle row for "Go to" vs "Move to" mode. Other keybind groups (window management, special workspace) on additional rows below.
- [X] (B) **Two dedicated rows** -- One row for "go to workspace" (`1`-`0`), another row for "move to workspace" (`1`-`0`), plus a row for other Hyprland actions. Each key explicitly labeled (e.g. "Go 1", "Mv 1").
- [ ] (C) **Compact grid** -- Workspace keys arranged in a 2x5 grid to save vertical space, with other actions in a sidebar or bottom row.
- [ ] (D) Other (describe)

**Recommended answer(s):** [(B)]

**Why these are recommended:**

- `(B)` is the most explicit and discoverable. Every action is a single tap with no hidden state or mode switching. On a touchscreen you want to minimize the number of taps per action.
- `(A)` is more compact but introduces a toggle that could lead to accidentally moving windows when you meant to switch workspaces (or vice versa). Extra cognitive load.
- `(C)` saves vertical space but may be harder to target accurately on a small touchscreen.

## 5. Layer Access

How should the user get to the Hyprland keybind layer?

- [ ] (A) **Part of the normal layer cycle** -- The Hyprland layer is included in the layer rotation accessed via the ⌨ key. Pressing ⌨ cycles through: Full → Special → Hyprland → (back to Full).
- [ ] (B) **Direct-access key on the Full layout** -- A dedicated key (e.g. labeled "Hypr" or "WM") on the main Full layout that jumps directly to the Hyprland layer. The Hyprland layer has an "Abc" or "Back" key to return.
- [X] (C) **Both** -- Include it in the layer cycle AND add a direct-access key on the Full layout.
- [ ] (D) Other (describe)

**Recommended answer(s):** [(C)]

**Why these are recommended:**

- `(C)` gives maximum flexibility. Users who prefer cycling get it; users who want instant access get a dedicated key.
- `(A)` alone adds friction when you want to quickly switch workspaces -- you'd have to cycle past Special first.
- `(B)` alone means you can't discover the layer through the normal cycling mechanism.
