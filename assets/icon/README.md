# App Icon

Place a 1024x1024 PNG image here named `icon.png` with Millie's face design:

**Design Specs:**
- Size: 1024x1024 pixels
- Background: #101316 (dark gray/black - AppColors.faceBackground)
- Two white rounded square eyes:
  - Each eye: ~358x358 pixels (35% of icon size)
  - Border radius: ~72 pixels (20% of eye size)
  - Gap between eyes: ~102 pixels (10% of icon size)
  - Position: Horizontally centered, slightly above center
- One white rounded rectangle mouth:
  - Width: ~410 pixels (40% of icon size)
  - Height: ~82 pixels (8% of icon size)
  - Border radius: ~41 pixels (half of height)
  - Position: Below eyes, horizontally centered

**After placing the icon file, run:**
```bash
flutter pub get
dart run flutter_launcher_icons
```

This will generate all the required Android icon sizes automatically.

