#!/bin/sh

altair2cpmraw.py LIFEBOAT-CPM22-48K.DSK --boot > /dev/null

dd if=LIFEBOAT-CPM22-48K.DSK.cpmraw bs=128 count=64 of=bootchain.bin
zasm -w --asm8080 boot.asm
zasm -w --asm8080 bios.asm
zasm -w --asm8080 user.asm
./embedbootchain.py
(cat bootchain.bin; dd if=LIFEBOAT-CPM22-48K.DSK.cpmraw bs=128 skip=64) > new.dsk.cpmraw
cpmrm -f altaircpmraw new.dsk.cpmraw 0:user.asm
cpmrm -f altaircpmraw new.dsk.cpmraw 0:dsput.com
cpmrm -f altaircpmraw new.dsk.cpmraw 0:dsget.com
cpmcp -f altaircpmraw new.dsk.cpmraw user.asm 0:
cpmcp -f altaircpmraw new.dsk.cpmraw dsput.com 0:
cpmcp -f altaircpmraw new.dsk.cpmraw dsget.com 0:

cpmraw2altair.py new.dsk.cpmraw --boot > /dev/null
mv new.dsk.cpmraw.altair serialcpm.dsk

