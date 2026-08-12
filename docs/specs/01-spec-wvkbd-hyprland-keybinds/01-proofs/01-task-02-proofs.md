# Task 02 Proofs - Move-to-Workspace and Window Management Keys

## Task Summary

This task proves the Hyprland layer has been extended with a second row of move-to-workspace keys (`Alt+Shift+1` through `Alt+Shift+0`) and a third row with window management keys (Term, Kill, Float, Split) plus navigation keys (BackLayer, NextLayer). The extended layout compiles successfully.

## What This Task Proves

- The `keys_hyprland[]` array contains a second row of 10 move-to-workspace keys with `code_mod = 9` (Alt | Shift).
- The move-to-workspace keys use scheme 0 (default) for visual distinction from workspace-switch keys (scheme 1).
- A third row contains window management keys (Term/Kill/Float/Split) with `code_mod = Alt`.
- Navigation keys (BackLayer, NextLayer) are present for layer switching.
- The extended layout compiles without errors.

## Evidence Summary

- The build succeeds after adding the second and third rows to `keys_hyprland[]`.
- Code inspection confirms 10 move-to-workspace keys with `code_mod = 9` and no `.scheme` designation (defaults to 0).
- Code inspection confirms 4 window management keys with `code_mod = Alt` and `.scheme = 1`.
- BackLayer ("Abc") and NextLayer (⌨) keys are present.

## Artifact: Successful compilation with extended layout

**What it proves:** The extended `keys_hyprland[]` array with all three rows compiles successfully.

**Why it matters:** Confirms the move-to-workspace row (using `code_mod = 9` for Alt+Shift), window management row, and navigation keys are syntactically correct.

**Command:**

```bash
cd /home/bee/wvkbd
nix-shell -p wayland wayland-scanner wayland-protocols cairo pango libxkbcommon pkg-config --run "make clean && make LAYOUT=deskintl"
```

**Result summary:** Build completed successfully with no errors. The linker output confirms all object files compiled correctly.

```
gcc -o wvkbd-deskintl build-deskintl/./drw.o build-deskintl/./keyboard.o build-deskintl/./main.o build-deskintl/./os-compatibility.o build-deskintl/./shm_open.o proto/fractional-scale-v1-client-protocol.o proto/input-method-unstable-v2-client-protocol.o proto/viewporter-client-protocol.o proto/virtual-keyboard-unstable-v1-client-protocol.o proto/wlr-layer-shell-unstable-v1-client-protocol.o proto/xdg-shell-client-protocol.o [libraries...]
```

## Artifact: Extended keys_hyprland array structure

**What it proves:** All three rows are present with correct key definitions, modifier values, and scheme assignments.

**Why it matters:** Demonstrates the implementation matches the task specification for move-to-workspace keys (scheme 0, `code_mod = 9`) and window management keys (scheme 1, `code_mod = Alt`).

**File:** `/home/bee/wvkbd/layout.deskintl.h` (lines ~517-545)

**Row 1 - Workspace switching (Alt+N):**
```c
static struct key keys_hyprland[] = {
  {"1", "1", 1.0, Code, KEY_1, 0, Alt, .scheme = 1, .reset_mod = true},
  {"2", "2", 1.0, Code, KEY_2, 0, Alt, .scheme = 1, .reset_mod = true},
  // ... keys 3-9 ...
  {"0", "0", 1.0, Code, KEY_0, 0, Alt, .scheme = 1, .reset_mod = true},
  {"", "", 0.0, EndRow},
```

**Row 2 - Move-to-workspace (Alt+Shift+N, code_mod = 9):**
```c
  {"M1", "M1", 1.0, Code, KEY_1, 0, 9, .reset_mod = true},
  {"M2", "M2", 1.0, Code, KEY_2, 0, 9, .reset_mod = true},
  {"M3", "M3", 1.0, Code, KEY_3, 0, 9, .reset_mod = true},
  {"M4", "M4", 1.0, Code, KEY_4, 0, 9, .reset_mod = true},
  {"M5", "M5", 1.0, Code, KEY_5, 0, 9, .reset_mod = true},
  {"M6", "M6", 1.0, Code, KEY_6, 0, 9, .reset_mod = true},
  {"M7", "M7", 1.0, Code, KEY_7, 0, 9, .reset_mod = true},
  {"M8", "M8", 1.0, Code, KEY_8, 0, 9, .reset_mod = true},
  {"M9", "M9", 1.0, Code, KEY_9, 0, 9, .reset_mod = true},
  {"M0", "M0", 1.0, Code, KEY_0, 0, 9, .reset_mod = true},
  {"", "", 0.0, EndRow},
```

**Row 3 - Window management and navigation:**
```c
  {"Abc", "Abc", 1.5, BackLayer, .scheme = 1},
  {"Term", "Term", 1.0, Code, KEY_Q, 0, Alt, .scheme = 1, .reset_mod = true},
  {"Kill", "Kill", 1.0, Code, KEY_C, 0, Alt, .scheme = 1, .reset_mod = true},
  {"Float", "Float", 1.0, Code, KEY_V, 0, Alt, .scheme = 1, .reset_mod = true},
  {"Split", "Split", 1.0, Code, KEY_J, 0, Alt, .scheme = 1, .reset_mod = true},
  {"", "", 3.0, Pad},
  {"⌨͕", "⌨͔", 1.5, NextLayer, .scheme = 1},
  {"", "", 0.0, Last},
};
```

**Key observations:**
- Move-to-workspace keys use `code_mod = 9` (the literal value of `Alt | Shift`).
- Move-to-workspace keys omit `.scheme`, defaulting to scheme 0 for visual distinction.
- Window management keys use `code_mod = Alt` and `.scheme = 1`.
- BackLayer ("Abc") and NextLayer (⌨) provide navigation.

## Reviewer Conclusion

The extended Hyprland layer includes all required keys: 10 move-to-workspace keys with Alt+Shift modifier (code_mod = 9), 4 window management keys with Alt modifier, and proper navigation keys. The layout compiles successfully and follows the visual distinction pattern (scheme 0 for move-to-workspace, scheme 1 for workspace-switch and window management).
