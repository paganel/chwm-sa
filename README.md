## Description

CHWMInjector.osax is our scripting addition.

The main executable in `CHWMInjector.osax` is `sa_core`, placed in `CHWMInjector.osax/Contents/MacOS/`.

The payload is `payload_test` and is placed in `CHWMInjector.osax/Contents/Resources/`.

Use `inject_test` to remotely load our scripting addition into a target application.

## Build

Build `CHWMInjector.osax` by running the `build.sh` script in the root folder.

## Test

Copy the generated `CHWMInjector.osax` to `/Library/ScriptingAdditions/`.

Build and run `inject_test` to load the scripting addition bundle into an application.

`inject_test` is currently hardcoded to 'Dock' for testing purposes.
