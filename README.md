## chunkwm scripting addition

**NOTE**: chunkwm-sa has been integrated into [chunkwm](https://github.com/koekeishiya/chunkwm).
Check the [official docs](https://koekeishiya.github.io/chunkwm/docs/sa.html) for information about this scripting addition
and its integration with chunkwm, as well as further instructions on how to install chunkwm-sa.

## Description

**DISCLAIMER**: Use at your own discretion. I take no responsibility if anything should happen to your
machine while testing or otherwise trying to install this extension.

I have confirmed this to be working on my machine running MacOS El Capitan (10.11.6), Sierra (10.12.6), High Sierra (10.13.0) and Mojave (10.14 Beta) with the below instructions.
(Features that interact with spaces only work on High Sierra and Mojave)

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

If you are running High Sierra or an earlier version, reboot into recovery mode and enable SIP.
```
csrutil enable
```

Build and run `inject_test` to load the scripting addition bundle into the Dock.

The Dock will now spawn a local unix domain socket and starts listening on port `5050`.

To set window alpha, send: `window_alpha <cgwindowid> <alpha>`

To fade into window alpha, send: `window_alpha_fade <cgwindowid> <alpha> <duration>`

To set window level, send: `window_level <cgwindowid> <kCGWindowLevelKey>`

To set window sticky (show on all spaces), send: `window_sticky <cgwindowid> <1 | 0>`

To set window position, send: `window_move <cgwindowid> <x> <y>`

To set window shadow, send: `window_shadow <cgwindowid> <1 | 0>`

To switch to a different space, bypassing animation, send: `space <cgsspaceid>`

To create a new space on the active display, send: `space_create <focused_cgsspaceid_of_a_display>`

To destroy the active space, send: `space_destroy <focused_cgsspaceid_of_a_display>`
