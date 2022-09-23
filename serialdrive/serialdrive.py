#!/usr/bin/env python3

'''
Disk-over-Serial agent for Altair 8800 CPM 2.2.
Emulates a 8" floppy drive over serial.
Copyright 2022 Don Barber

     This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

    This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.

    You should have received a copy of the GNU General Public License along with this program. If not, see <https://www.gnu.org/licenses/>.

'''


import serial
import serial.threaded
import sys
import tty
import termios
import struct
import xmodem
import time
import os
import threading
import select

#debug=True
debug=False

def menu(link):
    global debug
    while True:
        print("Command?\nquit\ndebug\nlist\nmount <drivenum> <file>\numount <drivenum>\nsendsbl (Send Serial Boot Loader)\nsendfile (raw)\nxget (xmodem get)\nxsend(xmodem send)\nsendgs (Send ^])\n>")
        command=input().split(' ')
        if command[0]=='':
            print("Returning to session\r\n")
            break
        elif command[0][0]=='q':
            termios.tcsetattr(sys.stdin.fileno(), termios.TCSADRAIN, stdin_old_settings)
            sys.exit()
        elif command[0]=='list':
            print(link.drives)
        elif command[0]=='mount':
            try:
                if int(command[1])>=0 and int(command[1])<=255:
                    link.drive_mount(int(command[1]),command[2])
            except:
                print("Invalid drive number.")
        elif command[0]=='umount':
            try:
                if int(command[1])>=0 and int(command[1])<=255:
                    link.drive_umount(int(command[1]))
            except:
                print("Invalid drive number.")
        elif command[0]=='sendsbl':
            print("Sending sbl.tap.")
            with open('sbl.tap',"rb") as indbl:
                ser.write(indbl.read())
        elif command[0]=='sendfile':
            print("Filename?\r\n")
            sendfname=input()
            with open(sendfname,"rb") as indbl:
                ser.write(indbl.read())
        elif command[0]=='xsend':
            link.xmodem=True
            x = threading.Thread(target=xmodemsend, args=(link,))
            x.start()
        elif command[0]=='xget':
            link.xmodem=True
            x = threading.Thread(target=xmodemrecv, args=(link,))
            x.start()
        elif command[0]=='sendgs':
            ser.write(b'\x1d')
        elif command[0]=='debug':
            if debug:
                debug=False
                print("Disabling debug")
            else:
                debug=True
                print("Enabling debug")
    return

TRACKS=77
SECTRK=32
SECLEN=137

def xmodemrecv(link):
    termios.tcsetattr(sys.stdin.fileno(), termios.TCSADRAIN, stdin_old_settings)
    while True:
        try:
            print("Filename?\r\n")
            fname=input()
            stream = open(fname,"wb")
            break
        except:
            pass
    tty.setraw(sys.stdin.fileno())
    modem = xmodem.XMODEM(link.getc,link.putc,mode="xmodem")
    modem.recv(stream,retry=8)
    stream.close()
    link.xmodem=False

def xmodemsend(link):
    termios.tcsetattr(sys.stdin.fileno(), termios.TCSADRAIN, stdin_old_settings)
    while True:
        try:
            print("Filename?\r\n")
            fname=input()
            stream = open(fname,"rb")
            break
        except:
            pass
    tty.setraw(sys.stdin.fileno())
    modem = xmodem.XMODEM(link.getc,link.putc,mode="xmodem")
    modem.send(stream,retry=8)
    stream.close()
    link.xmodem=False

class SerialLink(serial.threaded.Protocol):

    def __init__(self,ser):

        self.ser = ser
        self.onbreak = False
        self.bufferbytes = 0
        self.readbuffer = b''
        self.buffercallback = None
        self.drives={}
        self.xmodem=False
        self.xmodembuffer=b''

    def __call__(self):
        return self

    def drive_mount(self,drivenum,filename):
        self.drives[drivenum] = filename

    def drive_umount(self,drivenum):
        if drivenum in self.drives:
            del self.drives[drivenum]

    def debug_out(self):
        if debug:
            sys.stdout.write(" Debug: "+hex(self.readbuffer[0])+" ")

    def disk_check(self):
        drivenum = self.readbuffer[0]
        if debug:
            print("\nReceived disk check for drive %i."%(drivenum))
        try:
            with open(self.drives[drivenum],"rb") as fh:
                self.ser.write(b'\x00') #send successful
                if debug:
                    print("\nSending back success.")
        except:
            self.ser.write(b'\xFF') #send back error
            if debug:
                print("\nSending back error due to read error.")

    def disk_read(self):
        #collect drive, track, and sector request, then 
        #read 137 bytes and send back to serial
        drivenum = self.readbuffer[0]
        track = self.readbuffer[1]
        sector = self.readbuffer[2]
        if debug:
            print("\nReceived read request for drive %i track %i sector %i."%(drivenum,track,sector))
        if drivenum in self.drives:
            try:
                if track>=TRACKS:
                    raise Exception("Invalid track number.")
                if sector>=SECTRK:
                    raise Exception("Invalid sector number.")
                with open(self.drives[drivenum],"rb") as fh:
                    fh.seek(track*SECLEN*SECTRK+sector*SECLEN)
                    inbuf = fh.read(SECLEN)
                    self.ser.write(b'\x00') #send successful
                    self.ser.write(inbuf)   #send incoming data
          #          if debug:
          #              for ch in inbuf:
          #                  sys.stdout.write(hex(ch)+" ")
                    #print(inbuf[1:3]) 
            except Exception as err:
                print("Error:",err)
                self.ser.write(b'\xFF') #send back error
        else:
            print("Error! Drive not mounted.")
            self.ser.write(b'\xFF') #send error back

    def disk_write(self):
        #collect drive, track, and sector information and write rest of 137 bytes
        #to image file
        drivenum = self.readbuffer[0]
        track = self.readbuffer[1]
        sector = self.readbuffer[2]
        if debug:
            print("\nReceived write request for drive %i track %i sector %i."%(drivenum,track,sector))
        if drivenum in self.drives:
            try:
                with open(self.drives[drivenum],"r+b") as fh:
                    fh.seek(track*SECLEN*SECTRK+sector*SECLEN)
                    fh.write(self.readbuffer[3:]) 
          #          if debug:
          #              for ch in self.readbuffer[3:]:
          #                  sys.stdout.write(hex(ch)+" ")
                    fh.flush()
                self.ser.write(b'\x00') #send successful
            except Exception as err:
                print("\nError with write:",err)
                self.ser.write(b'\xFF') #send error
        else:
            self.ser.write(b'\xFF') #send error

    def getc(self,size,timeout=1):
        now=time.time()
        while True:
            if len(self.xmodembuffer)>=size:
                data = self.xmodembuffer[:size]
                self.xmodembuffer = self.xmodembuffer[size:]
                return data
            if time.time()-now>timeout:
                break
        return None

    def putc(self,data,timeout=1):
        self.ser.write(data)
        self.ser.flush()

    def data_received(self, data):
        if len(data)>1:                 #recurse if received more than one
            for ch in struct.unpack(str(len(data)) + 'c', data):
                self.data_received(ch)
            return
        #sys.stdout.write(hex(data[0])+" ")
        #print(hex(data[0]))
        if self.bufferbytes>0:
            self.readbuffer += data
            self.bufferbytes -= 1
            if self.bufferbytes==0 and self.buffercallback is not None:
                self.buffercallback()
                self.readbuffer = b''
                self.buffercallback = None
        elif self.onbreak:
            if data==b'\xFF':   #got a second break, which means it was
                                #meant to be sent by the original program
                if self.xmodem:
                    self.xmodembuffer += data
                else:
                    sys.stdout.buffer.write(data)
                    sys.stdout.flush()
            if data==b'\xFE': # debug out
                self.bufferbytes=1
                self.buffercallback = self.debug_out
            if data==b'\x01': # printer/list out
                pass
            elif data==b'\x02': # punch out
                pass
            elif data==b'\x03': # reader out
                pass
            elif data==b'\x0F': # disk check
                self.bufferbytes=1
                self.buffercallback = self.disk_check
            elif data==b'\x10': # disk read
                self.bufferbytes=3
                self.buffercallback = self.disk_read
            elif data==b'\x11': # disk write
                self.bufferbytes=140
                self.buffercallback = self.disk_write
            elif data==b'\x12': # xmodem recv from PC
                self.xmodem=True
                x = threading.Thread(target=xmodemrecv, args=(self,))
                x.start()
            elif data==b'\x13': # xmodem send from PC
                self.xmodem=True
                x = threading.Thread(target=xmodemsend, args=(self,))
                x.start()
            self.onbreak=False
        elif data==b'\xFF':
            self.onbreak = True
        elif self.xmodem:
            self.xmodembuffer += data
        else:
            if debug:
                print(hex(data[0]))
            sys.stdout.buffer.write(data)
            #if data==b'\r':
            #    sys.stdout.buffer.write(b'\n')
            sys.stdout.flush()

if __name__ == '__main__':  # noqa
    import argparse

    parser = argparse.ArgumentParser(
        description='Simple Serial to Network (TCP/IP) redirector.',
        epilog="""\
NOTE: no security measures are implemented. Anyone can remotely connect
to this service over the network.
Only one connection at once is supported. When the connection is terminated
it waits for the next connect.
""")
    parser.add_argument(
        'SERIALPORT',
        help="serial port name")

    parser.add_argument(
        'BAUDRATE',
        type=int,
        nargs='?',
        help='set baud rate, default: %(default)s',
        default=19200)

    parser.add_argument(
        '-q', '--quiet',
        action='store_true',
        help='suppress non error messages',
        default=False)

    parser.add_argument(
        '-l', '--localecho',
        action='store_true',
        help='Enable Local Echo',
        default=False)

    group = parser.add_argument_group('serial port')

    group.add_argument(
        "--bytesize",
        choices=[5, 6, 7, 8],
        type=int,
        help="set bytesize, one of {5 6 7 8}, default: 8",
        default=8)

    group.add_argument(
        "--parity",
        choices=['N', 'E', 'O', 'S', 'M'],
        type=lambda c: c.upper(),
        help="set parity, one of {N E O S M}, default: N",
        default='N')

    group.add_argument(
        "--stopbits",
        choices=[1, 1.5, 2],
        type=float,
        help="set stopbits, one of {1 1.5 2}, default: 1",
        default=1)

    group.add_argument(
        '--rtscts',
        action='store_true',
        help='enable RTS/CTS flow control (default off)',
        default=False)

    group.add_argument(
        '--xonxoff',
        action='store_true',
        help='enable software flow control (default off)',
        default=False)

    group.add_argument(
        '--rts',
        type=int,
        help='set initial RTS line state (possible values: 0, 1)',
        default=None)

    group.add_argument(
        '--dtr',
        type=int,
        help='set initial DTR line state (possible values: 0, 1)',
        default=None)

    group = parser.add_argument_group('network settings')

    exclusive_group = group.add_mutually_exclusive_group()

    args = parser.parse_args()

    ser = serial.serial_for_url(args.SERIALPORT, do_not_open=True)
    ser.baudrate = args.BAUDRATE
    ser.bytesize = args.bytesize
    ser.parity = args.parity
    ser.stopbits = args.stopbits
    ser.rtscts = args.rtscts
    ser.xonxoff = args.xonxoff


    if args.rts is not None:
        ser.rts = args.rts

    if args.dtr is not None:
        ser.dtr = args.dtr

    if not args.quiet:
        sys.stderr.write(
            '--- Serial drive for Altair on {p.name}  {p.baudrate},{p.bytesize},{p.parity},{p.stopbits} ---\n'
            '--- type Ctrl-] for command menu\n'.format(p=ser))


    try:
        ser.open()
    except serial.SerialException as e:
        sys.stderr.write('Could not open serial port {}: {}\n'.format(ser.name, e))
        sys.exit()

    link = SerialLink(ser)
    serial_worker = serial.threaded.ReaderThread(ser, link)
    serial_worker.start()
    link.drive_mount(0,"serialcpm.dsk")

    stdin_old_settings = termios.tcgetattr(sys.stdin.fileno())
    tty.setraw(sys.stdin.fileno())

    try:
        while True:
            if link.xmodem:
                time.sleep(1)
            else:
                #using select so another thread (mostly the xmodem threads)
                #can grab stdin instead
                (rlist,wlist,xlist) = select.select([sys.stdin],[],[],1)
                if sys.stdin in rlist:
                    ch = sys.stdin.buffer.read(1)
                    if ch==b'\x1d': # ctrl-] menu
                        termios.tcsetattr(sys.stdin.fileno(), termios.TCSADRAIN, stdin_old_settings)
                        menu(link)
                        tty.setraw(sys.stdin.fileno())
                        continue
                    if args.localecho:
                        if ch==b'\r':
                            ch=b'\r\n'
                        sys.stdout.write(ch)
                        sys.stdout.flush()
                    while True:
                        if not link.onbreak:   # loop until disk access
                            ser.write(ch)      # is no longer taking up
                            break              # serial connection
    except Exception as err:
        print("Error:",err,"\r\n")

    termios.tcsetattr(sys.stdin.fileno(), termios.TCSADRAIN, stdin_old_settings)
