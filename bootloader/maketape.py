#!/usr/bin/env python3

'''
Assembles a '.tap' file to be send to Altair using bootstrap loading code
Copyright 2022, Don Barber

     This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

    This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.

    You should have received a copy of the GNU General Public License along with this program. If not, see <https://www.gnu.org/licenses/>.


Thanks to https://www.solivant.com/oldstuff/?ps=Old+Computers&pn=1
for a description of the tape block format
'''


#checksum loader
clfname="loader2.rom"
#final loader
flfname="sbl.rom"
#output tape file
tapfile="sbl.tap"

#final load address; lsb first
loadaddress=b"\x00\x2c"

def getChecksum(inbuf):
    d=0
    for b in inbuf:
        #print("Checksum",hex(d),hex(b))
        d=(d+b)%256
    return(d)

oh=open(tapfile,"wb")
with open(clfname,"rb") as fh:
    buf=fh.read()

clsize=len(buf)
cl=buf[::-1]

oh.write(bytes([clsize]*192))
#oh.write(bytes([0]))
oh.write(cl)
#oh.write(bytes([0]*32))

with open(flfname,"rb") as fh:
    buf=fh.read()

flsize=len(buf)
oh.write(bytes([0]*32))

oh.write(bytes([60]))      # write out octal 074 or hex 3c
oh.write(bytes([flsize]))  # this will error if size over 255
                           # and you'll need to rewrite this code to
                           # split it into two blocks
oh.write(loadaddress)
oh.write(buf)

checksum=getChecksum(loadaddress+buf)

oh.write(bytes([checksum]))
oh.write(bytes([0]*12))
oh.write(bytes([120]))   #write out octal 170 or hex 78
oh.write(loadaddress)
oh.write(bytes([0]*12))
oh.close()


