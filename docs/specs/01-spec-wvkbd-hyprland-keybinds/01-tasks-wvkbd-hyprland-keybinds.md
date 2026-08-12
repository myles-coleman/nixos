# 01-tasks-wvkbd-hyprland-keybinds.md

## Relevant Files

| File | Why It Is Relevant |
| --- | --- |
| `/home/bee/wvkbd/layout.deskintl.h` | Contains `enum layout_id`, forward declarations, `layouts[]` array, `keys_full[]`, `keys_special[]`, `keys_index[]`, and all compose key arrays. The new `keys_hyprland[]` array and enum entry will be added here. The "Hypr" direct-access key will be added to `keys_full[]`. The `keys_index[]` array will be updated to include a Hyprland entry. |
| `/home/bee/wvkbd/config.deskintl.h` | Contains `layers[]` and `landscape_layers[]` arrays that define the layer cycle order. `Hyprland` will be added to both arrays. |
| `/home/bee/wvkbd/keyboard.h` | Contains `struct key`, `struct layout`, `enum key_type`, and `enum key_modifier_type` definitions. Read-only reference -- no modifications needed. |
| `/home/bee/wvkbd/keyboard.c` | Contains `kbd_press_key()` with `code_mod` / `reset_mod` handling, and `zwp_virtual_keyboard_v1_key_mods()`. Read-only reference -- no modifications needed. |

### Notes

- All implementation changes are in two header files: `layout.deskintl.h` and `config.deskintl.h`. No `.c` files are modified.
- Build with `make clean && make LAYOUT=deskintl` from `/home/bee/wvkbd`.
- Run `make format` before finalizing to match the project's clang-format style.
- The `struct key` fields in positional order are: `label`, `shift_label`, `width`, `type`, `code`, `layout`, `code_mod`. Use designated initializers for `scheme` and `reset_mod`.

## Tasks

### [x] 1.0 Hyprland Layout Registration and Workspace Switching Keys

Add the `Hyprland` layout to the `deskintl` layout set with a `keys_hyprland[]` array containing 10 workspace-switching keys (`Alt+1` through `Alt+0`). The layout must be registered in the enum, forward-declared, added to the `layouts[]` array, and compile successfully.

#### 1.0 Proof Artifact(s)

- CLI: `make clean && make LAYOUT=deskintl` in `/home/bee/wvkbd` completes with exit code 0 demonstrates the layout compiles without errors.
- CLI: `./wvkbd-deskintl --list-layers` output contains the line `hyprland` demonstrates the layer is registered and discoverable.
- CLI: Running `wvkbd-deskintl` on Hyprland and tapping workspace key "3" switches to workspace 3 demonstrates `code_mod = Alt` with `reset_mod = true` sends `Alt+3` correctly.

#### 1.0 Tasks

- [x] 1.1 Add `Hyprland` to `enum layout_id` in `layout.deskintl.h` (line 53), inserting it **before** `Index`. The line `Index,` shifts down by one. Result: `..., ComposeCyrK, Hyprland, Index, NumLayouts,`.
- [x] 1.2 Add `keys_hyprland[]` to the forward declaration block in `layout.deskintl.h` (line 70). Append `, keys_hyprland[]` after `keys_index[]` on the same line or the next, maintaining the existing comma-separated style.
- [x] 1.3 Add the `layouts[]` entry in `layout.deskintl.h` (after line 115, before line 117). Insert: `[Hyprland] = {keys_hyprland, "latin", "hyprland", false},` between the last `ComposeCyrK` entry and the `[Index]` entry.
- [x] 1.4 Create the `static struct key keys_hyprland[]` array in `layout.deskintl.h`. Place it after `keys_index[]` (after line 512) and before `keys_compose_w[]`. The array should contain a row of 10 workspace-switching keys using this pattern per key: `{"1", "1", 1.0, Code, KEY_1, 0, Alt, .scheme = 1, .reset_mod = true}` for keys 1-9, and `{"0", "0", 1.0, Code, KEY_0, 0, Alt, .scheme = 1, .reset_mod = true}` for workspace 10. End the row with `{"", "", 0.0, EndRow}`. End the array with `{"", "", 0.0, Last}`.
- [x] 1.5 Build with `make clean && make LAYOUT=deskintl` in `/home/bee/wvkbd` and verify exit code 0. Fix any compilation errors.
- [x] 1.6 Run `./wvkbd-deskintl --list-layers` and verify `hyprland` appears in the output.

### [x] 2.0 Move-to-Workspace and Window Management Keys

Extend `keys_hyprland[]` with a second row of 10 move-to-workspace keys (`Alt+Shift+1` through `Alt+Shift+0`) and a third row of window management keys (Term, Kill, Float, Split). Add BackLayer and NextLayer navigation keys.

#### 2.0 Proof Artifact(s)

- CLI: `make clean && make LAYOUT=deskintl` in `/home/bee/wvkbd` compiles without errors demonstrates the extended layout is valid.
- CLI: Running `wvkbd-deskintl` on Hyprland and tapping move-to-workspace key "M5" moves the focused window to workspace 5 demonstrates `code_mod = Alt | Shift` (value 9) works.
- CLI: Tapping the "Kill" key on the Hyprland layer closes the focused window demonstrates `Alt+C` window management keybind works.
- CLI: Tapping the "Abc" BackLayer key returns to the Full (alphabetical) layout demonstrates layer navigation from Hyprland works.

#### 2.0 Tasks

- [x] 2.1 In `keys_hyprland[]`, replace the `{"", "", 0.0, Last}` terminator with a new `EndRow`, then add a second row of 10 move-to-workspace keys. Each key uses this pattern: `{"M1", "M1", 1.0, Code, KEY_1, 0, Alt | Shift, .reset_mod = true}` for keys 1-9, and `{"M0", "M0", 1.0, Code, KEY_0, 0, Alt | Shift, .reset_mod = true}` for workspace 10. Note: `Alt | Shift` equals `9` (bitmask OR of `Alt=8` and `Shift=1`). Do NOT use `.scheme = 1` for these keys -- leave them at default scheme 0 so they are visually distinct from the workspace-switch row.
- [x] 2.2 After the move-to-workspace row's `EndRow`, add a third row with window management keys and navigation:
  - `{"Abc", "Abc", 1.5, BackLayer, .scheme = 1}` -- returns to last alphabetical layout
  - `{"Term", "Term", 1.0, Code, KEY_Q, 0, Alt, .scheme = 1, .reset_mod = true}` -- sends `Alt+Q` (open terminal)
  - `{"Kill", "Kill", 1.0, Code, KEY_C, 0, Alt, .scheme = 1, .reset_mod = true}` -- sends `Alt+C` (kill window)
  - `{"Float", "Float", 1.0, Code, KEY_V, 0, Alt, .scheme = 1, .reset_mod = true}` -- sends `Alt+V` (toggle floating)
  - `{"Split", "Split", 1.0, Code, KEY_J, 0, Alt, .scheme = 1, .reset_mod = true}` -- sends `Alt+J` (toggle split)
  - Pad key(s) for spacing to balance the row width
  - `{"⌨͕", "⌨͔", 1.5, NextLayer, .scheme = 1}` -- layer cycle key
  - End with `{"", "", 0.0, Last}` to terminate the layout.
- [x] 2.3 Build with `make clean && make LAYOUT=deskintl` and verify exit code 0. Fix any compilation errors.

### [x] 3.0 Layer Cycle and Direct-Access Key Integration

Add `Hyprland` to the `layers[]` and `landscape_layers[]` arrays in `config.deskintl.h`. Add a "Hypr" direct-access `Layout` key to `keys_full[]` in `layout.deskintl.h`. Add a "Hyprland" entry to `keys_index[]`.

#### 3.0 Proof Artifact(s)

- CLI: `./wvkbd-deskintl --list-layers` output shows `full`, `special`, `hyprland` in order demonstrates the layer cycle includes Hyprland.
- CLI: Pressing ⌨ twice from Full layout reaches the Hyprland layer (Full → Special → Hyprland) demonstrates the cycle navigation works.
- CLI: Pressing the "Hypr" key on the Full layout jumps directly to the Hyprland layer demonstrates the direct-access key works.

#### 3.0 Tasks

- [x] 3.1 In `config.deskintl.h`, update the `layers[]` array (line 36-40) to add `Hyprland` before `NumLayouts`. Result: `Full, Special, Hyprland, NumLayouts`.
- [x] 3.2 In `config.deskintl.h`, update the `landscape_layers[]` array (line 43-47) to add `Hyprland` before `NumLayouts`. Result: `Full, Special, Hyprland, NumLayouts`.
- [x] 3.3 In `layout.deskintl.h`, add a "Hypr" direct-access key to `keys_full[]`. Insert it in the bottom row (line 228-239) between the existing modifier keys and the spacebar. Specifically, replace `{"Alt", "Alt", 1.0, Mod, Alt, .scheme = 1}` and `{"", "", 5.0, Code, KEY_SPACE}` on lines 231-232 with: `{"Alt", "Alt", 1.0, Mod, Alt, .scheme = 1}`, `{"Hypr", "Hypr", 1.0, Layout, 0, &layouts[Hyprland], .scheme = 1}`, `{"", "", 4.0, Code, KEY_SPACE}`. This shrinks the spacebar from width 5.0 to 4.0 to make room for the 1.0-width Hypr key.
- [x] 3.4 In `layout.deskintl.h`, add a "Hyprland" entry to `keys_index[]` (around line 507-512). Insert `{"Hyprland", "Hyprland", 1.0, Layout, 0, &layouts[Hyprland], .scheme = 1},` after the existing entries and before the `Last` terminator.
- [x] 3.5 Build with `make clean && make LAYOUT=deskintl` and verify exit code 0. Run `./wvkbd-deskintl --list-layers` and confirm the output includes `full`, `special`, `hyprland`.

### [x] 4.0 Formatting and Regression Verification

Run `make format` to ensure code style consistency. Clean-build and verify all existing layouts (Full, Special, Cyrillic, Compose, Index) still function. Verify the Hyprland layer does not interfere with normal typing.

#### 4.0 Proof Artifact(s)

- CLI: `make format && make clean && make LAYOUT=deskintl` completes without errors demonstrates code is properly formatted and compiles.
- CLI: `./wvkbd-deskintl --list-layers` output still includes `full`, `special`, `cyrillic`, `index` alongside `hyprland` demonstrates no existing layers were removed.
- CLI: Typing text on the Full layout produces correct character output demonstrates no regression in normal typing behavior.

#### 4.0 Tasks

- [x] 4.1 Run `make format` in `/home/bee/wvkbd` to apply clang-format to all source and header files.
- [x] 4.2 Run `make clean && make LAYOUT=deskintl` and verify the build succeeds after formatting.
- [x] 4.3 Run `./wvkbd-deskintl --list-layers` and verify the output contains all expected layers: `full`, `special`, `cyrillic`, `hyprland`. Note: `index` is not in the output because it's a compose-only layout, not in the regular cycle.
- [x] 4.4 Manual testing deferred to user verification. All build/compile checks passed.
