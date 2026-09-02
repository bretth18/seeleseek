# Zed setup

## One-time

```sh
brew install xcode-build-server              # feeds compiler flags to sourcekit-lsp
xcode-build-server config -project seeleseek.xcodeproj -scheme seeleseek
```

The second command writes `buildServer.json` (gitignored — it holds absolute
DerivedData paths). Without it sourcekit-lsp only understands
`Packages/SeeleseekCore`; app-target files come up as a sea of red.

Zed also needs the `swift` extension installed.

## When the LSP goes blind

`buildServer.json` points at a DerivedData directory and reads the newest
`.xcactivitylog` there. After a `Clean Build Folder`, a DerivedData wipe, or an
Xcode version change, run the **Regenerate buildServer.json** task and rebuild
once so a fresh build log exists.

Files added to the project since the last build have no compiler flags recorded,
so they resolve poorly until the next build.

## Builds

Tasks build with `CONFIGURATION_BUILD_DIR=$ZED_WORKTREE_ROOT/build/Debug` so
`.zed/debug.json` has a stable binary path. Intermediates still live in the
shared DerivedData, so alternating between Zed and Xcode builds re-links but
does not recompile (~9s).

## Tests

Never run bare `xcodebuild test` — it includes `seeleseekUITests`, which
regenerates the marketing screenshots in `./screenshots/`. Every test task here
pins `-only-testing:seeleseekTests`.

`TEST_RUNNER_CI=true` makes `LiveServerTests` skip; without it they hit
server.slsknet.org and can hang when rate-limited. The "+ live server" task
omits it deliberately.

## Formatting

`format_on_save` is off. swift-format (from the Xcode toolchain, configured by
`.swift-format`) rewraps existing code aggressively, so it is opt-in per file
via the **Format current file** task or `editor: format`.

Package tests are swift-testing only and there is no `/usr/bin/xctest` on this
machine, so there is no Zed debug scenario for them — use the `SeeleseekCore`
Xcode scheme, or the **Package: test SeeleseekCore** task.
