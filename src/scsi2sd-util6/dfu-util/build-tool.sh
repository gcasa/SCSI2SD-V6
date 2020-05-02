#!/bin/sh

make clean
./autogen.sh
./configure
cd src
rm -f main.c
ln -s tool_main.c main.c
cd ..
make
 
