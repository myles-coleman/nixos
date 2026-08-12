# Task 03 Proofs - Layer Cycle and Direct-Access Key Integration

## Task Summary

This task proves the Hyprland layer is integrated into the layer cycle (config.deskintl.h) and accessible via both the ⌨ layer cycle key and a direct-access "Hypr" key on the Full layout (layout.deskintl.h). The layer is also added to the Index layout for manual selection via Cmp+Space.

## What This Task Proves

- The `layers[]` array in config.deskintl.h includes `Hyprland` in the cycle.
- The `landscape_layers[]` array in config.deskintl.h includes `Hyprland` in the landscape cycle.
- The `keys_full[]` array includes a "Hypr" direct-access key that jumps to the Hyprland layout.
- The spacebar width was reduced from 5.0 to 4.0 to accommodate the Hypr key.
- The `keys_index[]` array includes a "Hyprland" entry for manual layout selection.
- The layer list output confirms the integration.

## Evidence Summary

- Config arrays show `Full, Special, Hyprland, NumLayouts` for both portrait and landscape.
- The "Hypr" key is present in keys_full[] with `Layout` type pointing to `&layouts[Hyprland]`.
- The spacebar is reduced to width 4.0.
- The keys_index[] includes a Hyprland entry.
- `--list-layers` confirms `hyprland` is in the layer list.

## Artifact: Layer cycle configuration

**What it proves:** The Hyprland layout is registered in both the portrait and landscape layer cycles.

**Why it matters:** This enables users to reach the Hyprland layer by pressing ⌨ to cycle through layers.

**File:** `/home/bee/wvkbd/config.deskintl.h`

**Portrait layers (lines 36-40):**
```c
static enum layout_id layers[] = {
  Full, // First layout is the default layout on startup
  Special,
  Hyprland,
  NumLayouts // signals the last item, may not be omitted
};
```

**Landscape layers (lines 43-47):**
```c
static enum layout_id landscape_layers[] = {
  Full, // First layout is the default layout on startup
  Special,
  Hyprland,
  NumLayouts // signals the last item, may not be omitted
};
```

## Artifact: Direct-access key in Full layout

**What it proves:** A "Hypr" key exists on the Full layout's bottom row that directly switches to the Hyprland layer.

**Why it matters:** Provides instant access to the Hyprland layer without cycling through other layers.

**File:** `/home/bee/wvkbd/layout.deskintl.h` (lines ~230-235)

**Bottom row of keys_full[]:**
```c
  {"⌨͕", "⌨͔", 1.5, NextLayer, .scheme = 1},
  {"Ctr", "Ctr", 1.0, Mod, Ctrl, .scheme = 1},
  {"Sup", "Sup", 1.0, Mod, Super, .scheme = 1},
  {"Alt", "Alt", 1.0, Mod, Alt, .scheme = 1},
  {"Hypr", "Hypr", 1.0, Layout, 0, &layouts[Hyprland], .scheme = 1},
  {"", "", 4.0, Code, KEY_SPACE},
  {"AGr", "AGr", 1.0, Mod, AltGr, .scheme = 1},
```

**Key observations:**
- The "Hypr" key is type `Layout` pointing to `&layouts[Hyprland]`.
- The spacebar width is 4.0 (reduced from 5.0) to make room for the 1.0-width Hypr key.
- The key uses `.scheme = 1` for visual consistency with other special keys on the row.

## Artifact: Index layout entry

**What it proves:** The Hyprland layout is accessible via the Index layout (triggered by Cmp+Space or Cmp+⌨).

**Why it matters:** Provides another discovery/access path for the Hyprland layer.

**File:** `/home/bee/wvkbd/layout.deskintl.h` (lines ~510-515)

**keys_index[] array:**
```c
static struct key keys_index[] = {
  {"Full", "Full", 1.0, Layout, 0, &layouts[Full], .scheme = 1},
  {"Special", "Special", 1.0, Layout, 0, &layouts[Special], .scheme = 1},
  {"Абв", "Абв", 1.0, Layout, 0, &layouts[Cyrillic], .scheme = 1},
  {"Hyprland", "Hyprland", 1.0, Layout, 0, &layouts[Hyprland], .scheme = 1},
  {"", "", 0.0, Last},
};
```

## Artifact: Layer list verification

**What it proves:** The runtime layer discovery correctly identifies the Hyprland layer in the cycle.

**Why it matters:** Confirms the config changes are effective at runtime, not just at compile time.

**Command:**

```bash
cd /home/bee/wvkbd
./wvkbd-deskintl --list-layers
```

**Result summary:** Output shows `full`, `special`, `cyrillic`, `hyprland` in the layer list.

```
full
special
cyrillic
hyprland
```

**Note:** The `cyrillic` layer appears because it's a primary alphabetical layout (`.abc = true`). The Index layout does not appear because it's a special compose-index layout, not part of the regular layer cycle.

## Reviewer Conclusion

The Hyprland layer is fully integrated into the navigation system. It's accessible via three paths: (1) the ⌨ layer cycle key (Full → Special → Hyprland), (2) the direct-access "Hypr" key on the Full layout, and (3) the Index layout via Cmp+Space. The layer list correctly includes `hyprland`. All integration requirements are met.
