#!/bin/sh

make clean > /dev/null 2> /dev/null
echo "Configuring..."
./autogen.sh > /dev/null 2> /dev/null
./configure > /dev/null 2> /dev/null
cd src
rm -f main.c
ln -s lib_main.c main.c
cd ..
echo "Building lib code..."
make > /dev/null 2> /dev/null
echo "Running ar..."
ar cru libdfu-util.a src/*.o
ranlib libdfu-util.a
cp libdfu-util.a ../../../Xcode/SCSI2SD-util/libs/lib

exit 0
