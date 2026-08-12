# 01-spec-wvkbd-hyprland-keybinds.md

## Introduction/Overview

The wvkbd on-screen keyboard (forked at `/home/bee/wvkbd`) lacks a way to trigger Hyprland compositor keybinds -- specifically `Alt+number` workspace switching -- from its touch interface. This makes tablet mode on the GPD Pocket 4 unusable for multi-workspace workflows because the physical keyboard is folded away. The goal is to add a dedicated "Hyprland" layer to the existing `deskintl` layout set that provides one-tap access to workspace switching, window-to-workspace movement, and core window management actions.

## Goals

- Enable single-tap workspace switching (`Alt+1` through `Alt+0`) from the wvkbd on-screen keyboard while in Hyprland tablet mode.
- Enable single-tap move-window-to-workspace (`Alt+Shift+1` through `Alt+Shift+0`) from the same layer.
- Provide one-tap access to core window management keybinds (`Alt+Q` terminal, `Alt+C` kill window, `Alt+V` toggle floating, `Alt+J` toggle split).
- Make the Hyprland layer accessible both via the normal layer cycle (⌨ key) and a direct-access key on the Full layout.
- Preserve all existing `deskintl` functionality -- the Hyprland layer is additive, not a replacement.

## User Stories

- **As a GPD Pocket 4 user in tablet mode**, I want to switch between Hyprland workspaces by tapping on-screen keys so that I can navigate my desktop without unfolding the physical keyboard.
- **As a GPD Pocket 4 user in tablet mode**, I want to move the focused window to a different workspace with a single tap so that I can organize windows across workspaces without a physical keyboard.
- **As a GPD Pocket 4 user in tablet mode**, I want to quickly kill a window, open a terminal, or toggle floating mode from the on-screen keyboard so that I can perform basic window management without reaching for physical keys.

## Demoable Units of Work

### Unit 1: Hyprland Layer with Workspace Switching Keys

**Purpose:** Adds a new `Hyprland` layout/layer to the `deskintl` layout set containing workspace-switching keys that send `Alt+1` through `Alt+0` via the existing `code_mod` mechanism. This is the core deliverable that solves the stated problem.

**Functional Requirements:**
- The layout file (`layout.deskintl.h`) shall contain a new `Hyprland` entry in the `enum layout_id` (before `Index`/`NumLayouts`) and a corresponding `keys_hyprland[]` static key array.
- The `keys_hyprland[]` array shall include a row of 10 keys that send `Alt+1` through `Alt+0` (workspace 1-10) using `code_mod = Alt` and `reset_mod = true`, each of type `Code`.
- Each workspace-switch key shall be labeled clearly (e.g. `"1"` through `"0"`) with a row header or visual grouping that indicates these are "Go to workspace" keys.
- The `layouts[]` array shall include an entry `[Hyprland] = {keys_hyprland, "latin", "hyprland", false}` to register the new layout.
- The binary shall compile without errors via `make LAYOUT=deskintl` in the `/home/bee/wvkbd` directory.

**Proof Artifacts:**
- CLI: `make LAYOUT=deskintl` completes without errors demonstrates the layout compiles.
- CLI: `./build-deskintl/wvkbd-deskintl --list-layers` output includes `hyprland` demonstrates the layer is registered.
- Screenshot: The Hyprland layer visible on-screen with workspace keys demonstrates the layout renders correctly.
- CLI: Pressing a workspace key while `wvkbd-deskintl` runs on Hyprland causes a workspace switch demonstrates the `code_mod = Alt` mechanism works end-to-end.

### Unit 2: Move-to-Workspace and Window Management Keys

**Purpose:** Extends the Hyprland layer with a second row for move-window-to-workspace keys (`Alt+Shift+1` through `Alt+Shift+0`) and a third row for window management actions. Completes the full keybind layer.

**Functional Requirements:**
- The `keys_hyprland[]` array shall include a second row of 10 keys that send `Alt+Shift+1` through `Alt+Shift+0` using `code_mod = Alt | Shift` (bitwise OR of the modifier bitmask values `Alt = 8` and `Shift = 1`, so `code_mod = 9`) and `reset_mod = true`.
- Each move-to-workspace key shall be visually distinct from the go-to-workspace keys (e.g. different label prefix like `"M1"` through `"M0"`, or using `scheme = 1` for a different color).
- The `keys_hyprland[]` array shall include a row with window management keys:
  - A key sending `Alt+Q` (open terminal) labeled `"Term"` using `code_mod = Alt, reset_mod = true` with `code = KEY_Q`.
  - A key sending `Alt+C` (kill active window) labeled `"Kill"` using `code_mod = Alt, reset_mod = true` with `code = KEY_C`.
  - A key sending `Alt+V` (toggle floating) labeled `"Float"` using `code_mod = Alt, reset_mod = true` with `code = KEY_V`.
  - A key sending `Alt+J` (toggle split) labeled `"Split"` using `code_mod = Alt, reset_mod = true` with `code = KEY_J`.
- The `keys_hyprland[]` array shall include a `BackLayer` key (labeled `"Abc"` or similar) to return to the previous alphabetical layout.
- The `keys_hyprland[]` array shall include a `NextLayer` key (⌨ symbol) for standard layer cycling.
- The binary shall compile without errors and all keys on the Hyprland layer shall be functional.

**Proof Artifacts:**
- CLI: `make LAYOUT=deskintl` compiles without errors demonstrates the extended layout compiles.
- Screenshot: The Hyprland layer showing all three rows (go-to-workspace, move-to-workspace, window management) demonstrates the full layout renders.
- CLI: Pressing a move-to-workspace key moves the focused window to the target workspace in Hyprland demonstrates `Alt+Shift` combo works.
- CLI: Pressing the "Kill" key closes the focused window in Hyprland demonstrates window management keybinds work.

### Unit 3: Layer Access Integration

**Purpose:** Makes the Hyprland layer discoverable and quickly accessible from the main Full layout, via both the layer cycle and a direct-access key.

**Functional Requirements:**
- The `config.deskintl.h` file shall be updated so that the `layers[]` and `landscape_layers[]` arrays include `Hyprland` in the cycle (e.g. `Full, Special, Hyprland, NumLayouts`).
- The `keys_full[]` array in `layout.deskintl.h` shall include a direct-access key (labeled `"Hypr"` or `"WM"`) of type `Layout` pointing to `&layouts[Hyprland]`, with `scheme = 1` for visual distinction. This key shall be placed in a location that does not displace existing keys (e.g. replacing a `Pad` spacer or adding to an existing row that has available width).
- The user shall be able to reach the Hyprland layer by pressing the ⌨ key twice from the Full layout (Full → Special → Hyprland) OR by pressing the direct-access key once.
- The user shall be able to return from the Hyprland layer to the Full layout via the `BackLayer` key or by cycling with ⌨.

**Proof Artifacts:**
- CLI: `./build-deskintl/wvkbd-deskintl --list-layers` shows `full`, `special`, `hyprland` in the layer list demonstrates the layer cycle is configured.
- Screenshot: The Full layout showing the "Hypr" direct-access key demonstrates the direct-access key exists.
- Screenshot: Pressing ⌨ cycles through Full → Special → Hyprland → Full demonstrates the cycle works.

## Non-Goals (Out of Scope)

1. **App launcher keybinds**: `Alt+E` (file manager), `Alt+R` (wofi), `Alt+S` (rofi) are not included in this spec. These can be accessed via other means (e.g. app menu on the taskbar).
2. **Special workspace / scratchpad keybinds**: `Alt+TAB` and `Alt+Shift+S` are not included. These can be added in a follow-up if needed.
3. **Focus direction keybinds**: `Alt+arrows` are not included. On a touchscreen, focus can be changed by tapping the target window.
4. **Changes to the `mobintl` layout set**: Only `deskintl` is modified. The mobile layout is not relevant for the GPD Pocket 4's screen size.
5. **NixOS configuration changes**: This spec covers only the wvkbd fork modifications in `/home/bee/wvkbd`. Packaging the fork for NixOS (adding it to `environment.systemPackages`, autostarting it, etc.) is a separate concern.
6. **Upstream contribution**: This is a personal fork. No upstream PR or compatibility considerations beyond keeping the diff minimal.

## Design Considerations

- Workspace-switch keys ("go to") and move-to-workspace keys should be visually distinguishable at a glance. Use label differentiation (e.g. `"1"`-`"0"` vs `"M1"`-`"M0"`) and/or color scheme differentiation (`scheme = 0` vs `scheme = 1`).
- Window management keys should use descriptive short labels (`"Term"`, `"Kill"`, `"Float"`, `"Split"`) rather than keybind notation (`"A+Q"`, `"A+C"`), since the user is thinking in terms of actions, not key combos.
- The direct-access key on the Full layout should be visually consistent with other special keys (using `scheme = 1` for the "special key" color).
- The Hyprland layer should include navigation keys (`BackLayer`, `NextLayer`) in the same positions as other layers so the user has a consistent mental model.

## Repository Standards

- **Build system**: Pure GNU Make. Build with `make LAYOUT=deskintl`. The binary output is `wvkbd-deskintl` in `build-deskintl/`.
- **Code formatting**: `make format` runs `clang-format`. All new code should be formatted consistently with existing layout definitions.
- **Layout file conventions**: Layouts are defined as static `struct key` arrays in `layout.deskintl.h`. Rows end with `{"", "", 0.0, EndRow}`. Layouts end with `{"", "", 0.0, Last}`. New layouts need an `enum layout_id` entry, a forward declaration, and a `layouts[]` array entry.
- **Config file conventions**: Layer cycle order is defined in `config.deskintl.h` via the `layers[]` and `landscape_layers[]` arrays, terminated by `NumLayouts`.
- **Key struct conventions**: Use designated initializers (e.g. `.scheme = 1`, `.reset_mod = true`). The `code_mod` field is the 7th positional field in the struct, or can use designated initializer syntax.

## Technical Considerations

- **Modifier bitmask values**: `Alt = 8`, `Shift = 1`. For `Alt+Shift` combo keys, use `code_mod = 9` (bitwise OR: `Alt | Shift`). These values are defined in `keyboard.h:34-42`.
- **`reset_mod = true` is required**: Without this flag, the `code_mod` would be XOR'd with the keyboard's current modifier state (see `keyboard.c:431-439`). Since these are one-shot compositor keybinds, the forced modifier must replace (not combine with) any existing modifier state.
- **`code_mod` with combined modifiers**: The existing `code_mod` mechanism sends modifiers via `zwp_virtual_keyboard_v1_key_mods()` which handles each modifier bit independently (`keyboard.c:278-292`). `Alt | Shift` (value 9) will cause both `KEY_LEFTALT` and `KEY_LEFTSHIFT` to be pressed, which is the correct behavior for `Alt+Shift+number` keybinds.
- **`enum layout_id` ordering**: The new `Hyprland` entry must be placed before `Index` and `NumLayouts` in the enum. `Index` must remain second-to-last and `NumLayouts` must remain last, as they serve as sentinels.
- **Forward declaration**: The `keys_hyprland[]` array must be forward-declared alongside the other key arrays near the top of `layout.deskintl.h` (around line 58-70).
- **Wayland protocol compatibility**: Hyprland supports `zwp_virtual_keyboard_v1` (confirmed in Wayland Explorer compositor support table). No protocol changes are needed.

## Security Considerations

No specific security considerations identified. The on-screen keyboard sends the same key events as a physical keyboard via the Wayland virtual keyboard protocol. No credentials, tokens, or sensitive data are involved.

## Success Metrics

1. **Workspace switching works**: Tapping workspace keys 1-10 on the Hyprland layer switches to the corresponding workspace in Hyprland without needing the physical keyboard.
2. **Move-to-workspace works**: Tapping move-to-workspace keys 1-10 moves the focused window to the corresponding workspace.
3. **Window management works**: The four window management keys (Term, Kill, Float, Split) each trigger their corresponding Hyprland action.
4. **Layer navigation works**: The Hyprland layer is reachable via both the ⌨ cycle and the direct-access key on the Full layout, and the user can return to typing via BackLayer or continued cycling.
5. **No regressions**: All existing `deskintl` layouts (Full, Special, Cyrillic, Compose, Index) continue to function as before.

## Open Questions

1. **Exact placement of "Hypr" key on Full layout**: The Full layout's bottom row currently has `⌨͕`, `Cmp`, `,`, `Space`, `.`, `Enter`. A `"Hypr"` key needs to be added without displacing essential keys. Options include narrowing the spacebar, replacing a `Pad` spacer in another row, or adding it to the top F-key row. Final placement to be determined during implementation based on visual balance.
2. **Label style for move-to-workspace keys**: `"M1"`-`"M0"` is compact but may not be immediately obvious. Alternatives include `"→1"`-`"→0"` (arrow prefix) or `"Mv1"`-`"Mv0"`. Final label style to be determined during implementation.
