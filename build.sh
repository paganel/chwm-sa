#!/usr/bin/env bash

rm -rf bin
mkdir bin
mkdir bin/CHWMInjector.osax
mkdir bin/CHWMInjector.osax/Contents
mkdir bin/CHWMInjector.osax/Contents/MacOS
mkdir bin/CHWMInjector.osax/Contents/Resources

cp osax_files/Info.plist bin/CHWMInjector.osax/Contents/
cp osax_files/CHWMInjector.sdef bin/CHWMInjector.osax/Contents/Resources/

cd sa_core
./build.sh
cd ..
cp sa_core/bin/CHWMInjector bin/CHWMInjector.osax/Contents/MacOS/

cd payload
./build.sh
cd ..
cp -r payload/bin/chunkwm-sa.bundle bin/CHWMInjector.osax/Contents/Resources/
