# Canva App Icon Instructions

Create a 1024x1024 pixel square design in Canva with these exact specifications:

## Canvas Setup
- **Size:** 1024 x 1024 pixels (square)
- **Background Color:** #101316 (dark gray/black)

## Elements:

### 1. Background (the whole canvas)
- Color: #101316
- Rounded corners: 154 pixels (15% border radius)

### 2. Left Eye (White Rounded Square)
- Size: 358 x 358 pixels (35% of canvas)
- Color: #FFFFFF (white)
- Border radius: 72 pixels (20% of eye size)
- Position: 
  - X: 283 pixels from left (centered with gap)
  - Y: 333 pixels from top (35% down from top)

### 3. Right Eye (White Rounded Square)
- Size: 358 x 358 pixels (same as left)
- Color: #FFFFFF (white)
- Border radius: 72 pixels
- Position:
  - X: 663 pixels from left (centered with gap)
  - Y: 333 pixels from top (same as left eye)

### 4. Mouth (White Rounded Rectangle)
- Width: 410 pixels (40% of canvas)
- Height: 82 pixels (8% of canvas)
- Color: #FFFFFF (white)
- Border radius: 41 pixels (half of height - fully rounded ends)
- Position:
  - X: 307 pixels from left (horizontally centered)
  - Y: 583 pixels from top (58% down from top)

## Quick Reference:
- Canvas: 1024x1024, #101316 background, 154px rounded corners
- Each Eye: 358x358px, white, 72px rounded corners
- Gap between eyes: ~102 pixels (centered on canvas)
- Mouth: 410x82px, white, 41px rounded corners (pill shape)
- Eyes to mouth spacing: ~123 pixels

## Visual Layout:
```
     [Canvas: 1024x1024, #101316]
     
     ┌─────────────────────────┐
     │                         │
     │     [Eye]   [Eye]       │ ← Eyes at ~35% from top
     │     358px   358px       │
     │                         │
     │      [  Mouth  ]        │ ← Mouth at ~58% from top
     │       410x82px          │
     │                         │
     └─────────────────────────┘
```

After creating in Canva:
1. Download as PNG
2. Make sure it's exactly 1024x1024 pixels
3. Save to: `assets/icon/icon.png`
4. Run: `dart run flutter_launcher_icons`

