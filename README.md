## Description

**WARNING**: Use at your own discretion. I take no responsibility if anything should happen to your
machine while testing or otherwise trying to intsall this extension.

I have confirmed this to be working on my machine running MacOS El Capitan (10.11.6) with the below instructions.

CHWMInjector.osax is our scripting addition.

The main executable in `CHWMInjector.osax` is `sa_core`, placed in `CHWMInjector.osax/Contents/MacOS/`.

The payload is `payload_test` and is placed in `CHWMInjector.osax/Contents/Resources/`.

Use `inject_test` to remotely load our scripting addition into a target application.

## Build

Build `CHWMInjector.osax` by running the `build.sh` script in the root folder.

## Install

Reboot into recovery mode and disable SIP (System Integrity Protection)
```
csrutil disable
```

Copy the generated `CHWMInjector.osax` to `/System/Library/ScriptingAdditions/`.

Reboot into recovery mode and enable SIP.
```
csrutil enable
```

Build and run `inject_test` to load the scripting addition bundle into the Dock.

The Dock will now spawn a local unix domain socket and starts listening on port `5050`.

To set window alpha, send: `window_alpha <cgwindowid> <alpha>`
To set window level, send: `window_level <cgwindowid> <kCGWindowLevelKey>`
