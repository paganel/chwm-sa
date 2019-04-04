#!/usr/bin/env bash

rm -rf bin
mkdir bin
mkdir bin/chunkwm-sa.bundle
mkdir bin/chunkwm-sa.bundle/Contents
mkdir bin/chunkwm-sa.bundle/Contents/MacOS
cp Info.plist bin/chunkwm-sa.bundle/Contents/
clang++ payload.mm -shared -fPIC -O3 -o bin/chunkwm-sa.bundle/Contents/MacOS/chunkwm-sa -framework Cocoa -framework Carbon
