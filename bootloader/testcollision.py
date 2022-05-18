#!/usr/bin/env python3

'''
This program will just identify an error if the byte being loaded matches the LSB of the loading address, which will prevent proper loading. If this triggers, just add a NOP somewhere to offset the bytes appropriately.
Copyright 2022, Don Barber

     This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

    This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.

    You should have received a copy of the GNU General Public License along with this program. If not, see <https://www.gnu.org/licenses/>.
'''

fh=open("loader2.rom","rb")

buf=fh.read()

count=1
for ch in buf:
    if ch==count:
        raise Exception("Collision!",ch,count)
    count +=1
