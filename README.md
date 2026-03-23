# flutter_flame_doltop_stack

Flutter/Flame games monorepo.

## Structure

```text
apps/
  flutter_flame_stacking_game/
  flutter_flame_suika_game/
```

## Current apps

- `apps/flutter_flame_stacking_game`: 돌쌓기 적층 게임
- `apps/flutter_flame_suika_game`: 수박게임 허브 앱

## Add another Flame project

```bash
flutter create apps/another_game
```

Then add Flame dependencies in `apps/another_game/pubspec.yaml`.

## Common commands

Run the stacking game:

```bash
cd apps/flutter_flame_stacking_game
flutter run
```

Run the suika game hub:

```bash
cd apps/flutter_flame_suika_game
flutter run
```

Analyze the stacking game:

```bash
cd apps/flutter_flame_stacking_game
flutter analyze
```
