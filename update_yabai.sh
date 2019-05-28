./build.sh
xxd -i -a bin/CHWMInjector.osax/Contents/Resources/chunkwm-sa.bundle/Contents/MacOS/chunkwm-sa sa_bundle.c
xxd -i -a bin/CHWMInjector.osax/Contents/MacOS/CHWMInjector sa_core.c
mv sa_core.c ../../C/yabai/src/sa_core.c
mv sa_bundle.c ../../C/yabai/src/sa_bundle.c
