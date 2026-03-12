# flutter_flame_doltop_stack

Flutter/Flame games monorepo.

## Structure

```text
apps/
  flutter_flame_game/
  another_game/
```

## Current app

- `apps/flutter_flame_game`

## Add another Flame project

```bash
flutter create apps/another_game
```

Then add Flame dependencies in `apps/another_game/pubspec.yaml`.

## Common commands

Run the existing game:

```bash
cd apps/flutter_flame_game
flutter run
```

Analyze the existing game:

```bash
cd apps/flutter_flame_game
flutter analyze
```
