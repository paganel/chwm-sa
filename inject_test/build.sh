rm -rf bin
mkdir bin
clang main.m -o bin/inject -framework Cocoa -framework ScriptingBridge
