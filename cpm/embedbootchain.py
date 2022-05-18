#!/usr/bin/env python3

'''
Embeds the compiled files into the appropriate spots of the bootchain for
later installation on disk
Copyright 2022, Don Barber

     This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

    This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.

    You should have received a copy of the GNU General Public License along with this program. If not, see <https://www.gnu.org/licenses/>.
'''

oh = open("bootchain.bin","r+b")

#read boot.bin
#put first 128 bytes in sector 0 (*128 = 0)
#put second 128 bytes in sector 2 (*128 = 256)
with open("BOOT.rom","rb") as ih:
    buf=ih.read(256)
    oh.seek(0)
    oh.write(buf[0:128])
    oh.seek(2*128)
    oh.write(buf[128:])

#read bios.bin
#put first 2176 bytes in sector 47-63 (*128 = 6016)
with open("BIOS.rom","rb") as ih:
    buf=ih.read(2176)
    oh.seek(47*128)
    oh.write(buf)

#read user.bin
#put into bios+500h in sector 57 (*128 = 7296)
with open("user.rom","rb") as ih:
    buf=ih.read(512)
    oh.seek(57*128)
    oh.write(buf)

oh.close()







