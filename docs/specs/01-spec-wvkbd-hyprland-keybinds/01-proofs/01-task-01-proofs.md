# Task 01 Proofs - Hyprland Layout Registration and Workspace Switching Keys

## Task Summary

This task proves the Hyprland layout infrastructure is correctly registered in the deskintl layout set. The enum entry, forward declaration, layouts array entry, and keys_hyprland array with 10 workspace-switching keys (`Alt+1` through `Alt+0`) are all in place and the layout compiles without errors.

## What This Task Proves

- The Hyprland layout is registered in `enum layout_id`, forward-declared, and added to the `layouts[]` array.
- The `keys_hyprland[]` array exists with 10 workspace-switching keys using `code_mod = Alt` and `reset_mod = true`.
- The layout compiles successfully with `make LAYOUT=deskintl`.
- The `hyprland` layer is discoverable via `--list-layers`.

## Evidence Summary

- The build completes with exit code 0, confirming no compilation errors.
- The `--list-layers` output includes `hyprland`, confirming the layer is registered and discoverable.
- Code inspection confirms the Hyprland enum entry, forward declaration, layouts entry, and keys array are present.

## Artifact: Successful compilation

**What it proves:** The modified layout.deskintl.h compiles without errors, confirming all syntax is correct and the Hyprland layout is properly integrated.

**Why it matters:** A successful build is the first gate - it confirms the layout structure is valid and the C compiler accepts the changes.

**Command:**

```bash
cd /home/bee/wvkbd
nix-shell -p wayland wayland-scanner wayland-protocols cairo pango libxkbcommon pkg-config --run "make clean && make LAYOUT=deskintl"
```

**Result summary:** The build completed successfully, producing the `wvkbd-deskintl` binary without errors. The final linking step confirms all object files compiled correctly.

```
gcc -o wvkbd-deskintl build-deskintl/./drw.o build-deskintl/./keyboard.o build-deskintl/./main.o build-deskintl/./os-compatibility.o build-deskintl/./shm_open.o proto/fractional-scale-v1-client-protocol.o proto/input-method-unstable-v2-client-protocol.o proto/viewporter-client-protocol.o proto/virtual-keyboard-unstable-v1-client-protocol.o proto/wlr-layer-shell-unstable-v1-client-protocol.o proto/xdg-shell-client-protocol.o -L.../lib -lwayland-client -lxkbcommon -lpangocairo-1.0 -lpango-1.0 -lgobject-2.0 -lglib-2.0 -lharfbuzz -lcairo -lm -lutil -lrt
```

Binary verification:
```bash
ls -lh wvkbd-deskintl
-rwxr-xr-x 1 bee users 435K 2026-08-11 21:05 wvkbd-deskintl
```

## Artifact: Layer list output

**What it proves:** The Hyprland layer is registered and discoverable via the `--list-layers` CLI flag.

**Why it matters:** This confirms the runtime layer discovery mechanism recognizes the Hyprland layout, not just the compile-time registration.

**Command:**

```bash
cd /home/bee/wvkbd
./wvkbd-deskintl --list-layers
```

**Result summary:** The output includes `hyprland` in the layer list, confirming the layer is properly registered in the layouts array and config arrays.

```
full
special
cyrillic
hyprland
```

## Artifact: Code structure verification

**What it proves:** The required code elements (enum entry, forward declaration, layouts entry, keys array) are present in layout.deskintl.h.

**Why it matters:** This provides reviewable evidence that the implementation follows the required structure from the task specification.

**File:** `/home/bee/wvkbd/layout.deskintl.h`

**Enum entry (line ~54):**
```c
ComposeCyrK,
Hyprland,
Index,
NumLayouts,
```

**Forward declaration (line ~71):**
```c
keys_compose_cyr_k[], keys_index[], keys_hyprland[];
```

**Layouts array entry (line ~118):**
```c
[Hyprland] = {keys_hyprland, "latin", "hyprland", false},
[Index] = {keys_index,"latin","index", false},
```

**Keys array (lines ~517-529):**
```c
static struct key keys_hyprland[] = {
  {"1", "1", 1.0, Code, KEY_1, 0, Alt, .scheme = 1, .reset_mod = true},
  {"2", "2", 1.0, Code, KEY_2, 0, Alt, .scheme = 1, .reset_mod = true},
  {"3", "3", 1.0, Code, KEY_3, 0, Alt, .scheme = 1, .reset_mod = true},
  {"4", "4", 1.0, Code, KEY_4, 0, Alt, .scheme = 1, .reset_mod = true},
  {"5", "5", 1.0, Code, KEY_5, 0, Alt, .scheme = 1, .reset_mod = true},
  {"6", "6", 1.0, Code, KEY_6, 0, Alt, .scheme = 1, .reset_mod = true},
  {"7", "7", 1.0, Code, KEY_7, 0, Alt, .scheme = 1, .reset_mod = true},
  {"8", "8", 1.0, Code, KEY_8, 0, Alt, .scheme = 1, .reset_mod = true},
  {"9", "9", 1.0, Code, KEY_9, 0, Alt, .scheme = 1, .reset_mod = true},
  {"0", "0", 1.0, Code, KEY_0, 0, Alt, .scheme = 1, .reset_mod = true},
  {"", "", 0.0, EndRow},
  {"", "", 0.0, Last},
};
```

## Reviewer Conclusion

All required code structure elements are in place. The build succeeds, the layer is discoverable, and the workspace-switching keys are defined with the correct `code_mod = Alt` and `reset_mod = true` pattern. Task 1.0 implementation is complete and verified.
