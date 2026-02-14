# App Icon Generation

To generate the app icon with Millie's face (black background, white rounded square eyes and mouth):

## Quick Method (Recommended)

1. Create a 1024x1024 PNG image with:
   - Background: #101316 (black)
   - Two white rounded square eyes (35% of icon size each, with 10% gap)
   - One white rounded rectangle mouth (40% width, 8% height)
   - All corners rounded (15% border radius)

2. Save it as `assets/icon/icon.png`

3. Run:
   ```bash
   flutter pub get
   dart run flutter_launcher_icons
   ```

## Manual Icon Creation

If you need to create the icon manually, use any image editor:

**Specs:**
- Size: 1024x1024 pixels
- Background: #101316 (dark gray/black)
- Eyes: White rounded squares (approximately 358x358 pixels each)
  - Border radius: ~72 pixels (20% of eye size)
  - Position: Centered horizontally, slightly above center
  - Gap between eyes: ~102 pixels (10% of icon size)
- Mouth: White rounded rectangle
  - Width: ~410 pixels (40% of icon size)
  - Height: ~82 pixels (8% of icon size)
  - Border radius: ~41 pixels (half of height)
  - Position: Below eyes, centered horizontally

