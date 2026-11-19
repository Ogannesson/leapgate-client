# xterm 4.0.0, patched copy

A copy of [xterm](https://pub.dev/packages/xterm) 4.0.0 (MIT, `LICENSE`), the version upstream's
`flutter/pubspec.yaml` pins. `lib/`, `LICENSE`, `README.md`, `CHANGELOG.md`, `pubspec.yaml` and
`analysis_options.yaml` are taken unchanged from the pub.dev archive; `bin/`, `example/`,
`media/`, `script/` and `test/` are left out. Both `core` and `app` depend on it by path.

The one change, marked `// leapgate:`, is in `lib/src/ui/custom_text_edit.dart`
(`_openInputConnection`): the `TextInputConfiguration` passes
`viewId: View.of(context).viewId`. The Windows engine of Flutter 3.44 and later rejects
`TextInput.setClient` without a view ID (`PlatformException(Bad Arguments, Could not set client,
view ID is null.)`), so the input connection was never made and printable characters and paste
never reached the remote shell; keys with a key mapping (Enter, arrows) still did, since they go
through `onKeyEvent`. This is the package's only `TextInput.attach`.

4.0.0 (2024-02) is the latest release on pub.dev. When a release that passes a view ID comes out,
delete this copy and depend on it from pub.dev again in both `core/pubspec.yaml` and
`app/pubspec.yaml`. Not analyzed or formatted as part of `core` or `app`.
