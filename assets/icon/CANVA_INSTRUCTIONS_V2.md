# Canva App Icon Instructions (Updated for Safe Zone)

**IMPORTANT:** Android adaptive icons crop the edges! Only the center 66% is safe.

Create a 1024x1024 pixel design with **smaller, more centered** facial features:

## Canvas Setup
- **Size:** 1024 x 1024 pixels (square)
- **Background Color:** #101316 (dark gray/black)
- **Rounded corners:** 154 pixels (15% border radius)

## Elements (SIZED FOR SAFE ZONE):

### 1. Background (the whole canvas)
- Color: #101316
- Rounded corners: 154 pixels

### 2. Left Eye (White Rounded Square) - SMALLER & CENTERED
- Size: **280 x 280 pixels** (27% of canvas, was 35%)
- Color: #FFFFFF (white)
- Border radius: 56 pixels (20% of eye size)
- Position: 
  - X: 308 pixels from left (centered in safe zone)
  - Y: 385 pixels from top (centered vertically in safe zone)

### 3. Right Eye (White Rounded Square) - SMALLER & CENTERED
- Size: **280 x 280 pixels** (same as left)
- Color: #FFFFFF (white)
- Border radius: 56 pixels
- Position:
  - X: 636 pixels from left (centered with gap)
  - Y: 385 pixels from top (same as left eye)

### 4. Mouth (White Rounded Rectangle) - SMALLER & CENTERED
- Width: **320 pixels** (31% of canvas, was 40%)
- Height: **64 pixels** (6% of canvas, was 8%)
- Color: #FFFFFF (white)
- Border radius: 32 pixels (half of height - pill shape)
- Position:
  - X: 352 pixels from left (horizontally centered in safe zone)
  - Y: 575 pixels from top (centered in safe zone)

## Quick Reference (NEW SAFE ZONE SIZES):
- Canvas: 1024x1024, #101316 background, 154px rounded corners
- Each Eye: **280x280px** (was 358px), white, 56px rounded corners
- Gap between eyes: ~76 pixels (centered)
- Mouth: **320x64px** (was 410x82px), white, 32px rounded corners
- Everything is centered in the safe zone (center 66% of canvas)

## Why Smaller?
- Android applies circular/square masks that crop the edges
- Only the center ~66% (about 680x680 pixels) is guaranteed visible
- Smaller features ensure nothing gets cut off!

## Visual Layout (Safe Zone):
```
     ┌─────────────────────────┐
     │      (CROPPED AREA)     │ ← Can be masked
     │  ┌───────────────────┐  │
     │  │                   │  │
     │  │   [Eye]  [Eye]    │  │ ← Safe Zone (center 66%)
     │  │   280px  280px    │  │
     │  │                   │  │
     │  │    [ Mouth ]      │  │
     │  │    320x64px       │  │
     │  │                   │  │
     │  └───────────────────┘  │
     │      (CROPPED AREA)     │ ← Can be masked
     └─────────────────────────┘
```

After creating in Canva:
1. Download as PNG (1024x1024)
2. Save to: `assets/icon/icon.png` (overwrite existing)
3. Run: `dart run flutter_launcher_icons`
4. Rebuild app

