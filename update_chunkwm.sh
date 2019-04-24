./build.sh
xxd -i -a bin/CHWMInjector.osax/Contents/Resources/chunkwm-sa.bundle/Contents/MacOS/chunkwm-sa sa_bundle.cpp
xxd -i -a bin/CHWMInjector.osax/Contents/MacOS/CHWMInjector sa_core.cpp
mv sa_core.cpp ../../C++/chunkwm/src/core/sa_core.cpp
mv sa_bundle.cpp ../../C++/chunkwm/src/core/sa_bundle.cpp
