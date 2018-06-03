rm -rf bin
mkdir bin
clang chwm_injector.m -shared -O3 -o bin/CHWMInjector -framework Cocoa
