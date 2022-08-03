#!/bin/sh

zasm -w --asm8080 firststage.asm
zasm -w --asm8080 loader2.asm
zasm -w --asm8080 sbl.asm
./maketape.py
./testcollision.py

echo Use this as the bootstrap entered into the front panel:
od -b firststage.rom
