rm -rf bin
mkdir bin
clang chwm_injector.m -shared -o bin/CHWMInjector -framework Cocoa
