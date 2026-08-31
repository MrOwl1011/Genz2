# GenZ+

Flutter IPTV app. One codebase, three shippable artifacts.

## Building

Use `./build.sh` — the three products do not share a command shape, and
guessing wrong fails confusingly (see below).

```bash
./build.sh phone-aab      # Android phone  -> Play Console
./build.sh tv-aab         # Android TV     -> Play Console (Android TV release)
./build.sh ipa            # iOS            -> App Store
./build.sh all-aab        # both Android bundles at once

./build.sh tv-apk --debug # quick sideload build while iterating
./build.sh --help         # all targets
```

## Why the commands differ per platform

**Android ships two products** from this codebase — the phone app and the
Android TV app — as Gradle product flavors (`android/app/build.gradle.kts`):

| | phone | tv |
|---|---|---|
| Entrypoint | `lib/main.dart` | `lib/main_tv.dart` |
| `--dart-define` | — | `IS_TV=true` |
| Manifest | `src/main/` | `src/main/` + `src/tv/` overlay (leanback, TV banner, `LEANBACK_LAUNCHER`) |
| App label | GenZ+ | GenZ+ TV |

Both flavors deliberately share `applicationId` (`com.genzplus.app`) and the
`versionCode`/`versionName` from `pubspec.yaml`. Play treats the TV build as
an *Android TV release inside the existing app listing*, not a separate app —
it rejects both a distinct package name and an independent version sequence.

**iOS ships one product**, so it has no flavor schemes at all. Passing
`--flavor` to an iOS build fails with:

```
You must specify a --flavor option to select one of the available schemes.
```

That is not a missing iOS config — flavors are an Android concept here, and
there is no iOS TV target. `flutter build ipa --release` (no flavor, no `-t`)
is correct and is what CI runs.

## TV vs phone code

`lib/core/build_flavor.dart` exposes `kIsTv`, a `bool.fromEnvironment`
compile-time constant driven by the `IS_TV` define. Because it is `const`,
Dart tree-shakes the unused UI out of each binary — the phone build contains
no TV code and vice versa.

- `lib/tv/` — TV-only screens and widgets
- `kIsTv` branches in shared files — TV-specific sizing/behavior in code both
  flavors run (e.g. D-pad handling, text-field keyboard behavior)

## CI

- `.github/workflows/dart.yml` — `flutter build ios --release --no-codesign`
- `codemagic.yaml` — `flutter build ipa --release`

Neither passes `--flavor`, which is correct for iOS.
