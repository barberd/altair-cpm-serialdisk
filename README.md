# altair-cpm-serialdisk
Modifications for Lifeboat CPM 2.2 to run on the Altair 8800 using a virtual floppy drive accessed over serial from a modern PC and matching software for the PC side.

The Altair 8800 had a few options for long term mass storage; the 8" floppy was one of the most common. These are hard to find and maintain today. This software allows to keep disk images on a PC and access them over a serial connection, either rs232 or USB.

# License

Original code by Don Barber is licensed under GPL version 3.

CPM Code is effectively public domain; see http://cpm.z80.de/license.html for specifics.

Other code is subject to the original authors copyrights and their respective licenses.

# Similar software
Drivewire for the Color Computer https://sites.google.com/site/drivewire4/

APE for the Altair http://ape.classiccmp.org/

FDC+ https://deramp.com/fdc_plus.html

# If these exist, why create another one?

APE and FDC+'s software is Windows only. APE requires two serial ports, and FDC+ requires the hardware card. I wanted something that would work on Linux, could carry everything over a single connection, and didn't require special hardware. And it was a fun little project.

# What hardware is used

Right now everything is coded to use the s100computers.com Serial IO board USB port because this is what I have. It would be straightforward to modify the software for other serial cards like a 2SIO card.

# Quick start

Enter the firststage.rom code into the front panel of the Altair at address 0. The code is:

```
041 160 077 061 022 000 333 252 007 330 333 254 275 310 055 167
300 351 003 000
```

Reset and execute from address 0.

Run ./serialdrive.py /dev/ttyUSB0 (replace with your appropriate serial device). In serialdrive hit ctrl-] and enter 'sendsbl' to send the sbl.tap file. CPM should now boot up:

```
CP/M2 on Altair
48K Vers 2.20  
(c) 1981 Lifeboat Associates
Modified 2022 Don Barber for Disk-over-Serial
A>
```

Congrats!

# Building the software

## Prereqs

You'll need a copy of Lifeboat CPM 2.2. Grab LIFEBOAT-CPM22-48K.DSK from https://deramp.com/downloads/altair/software/8_inch_floppy/CPM/CPM%202.2/Lifeboat%20CPM/. Thanks to deramp.com for making this archive available.

You'll also need a copy of my altair2cpmraw scripts to build the images. Grab it at https://github.com/barberd/altair2cpmraw. You'll need to add the appropriate altaircpmraw diskdefs to your system.

I used the zasm assembler to build the software. Conceptually you could use any 8080 assembler, but might have to make minor syntax changes. Zasm is available from https://k1.spdns.de/Develop/Projects/zasm/Distributions/.

## Build the CPM disk image

Move the LIFEBOAT-CPM22-48K.DSK into the cpm directory. Enter the directory and execute ./makeserialcpm.sh, adjusting paths as needed. If it all works, you'll end up with serialcpm.dsk. Move this into the serialdrive directory.

## Build the bootloader 'tape' image

Next, go into the bootloader directory and run ./build.sh. This will produce two files of note: firststage.rom and sbl.tap. Move sbl.tap into the serialdrive directory. firststage.rom is the code you'll need to enter into the front panel of the Altair. Run od -b 'firststage.rom' to show it in octal form or 'hexdump -C firststage.rom' to show it in hexadecimal form.

## Start up the serialdrive software

Next, go into the serialdrive directory and run ./serialdrive.py and see what modules you need to install, such as 'serial' and 'xmodem.' Install them either from your chosen distribution or by using pip. When all set, start it up with `./serialdrive.py /dev/ttyUSB0` adjusting the serial device as appropriate.

# Using serialdrive

Hit ctrl-] to bring up a menu. Hit enter on a blank line to return to the session. Here are the descriptions of the menu options:

### quit

Exit the program

### debug

Start debugging. This shows everything sent or received. Its quite noisy but can be helpful if you're having serial issues. I found a few bad chips on my serial board this way.

### list

List mounted disks

### mount

Use this to mount new disks. For example 'mount 1 zork.dsk' will mount zork on drive b.

### umount

Use this to unmount disks.

### sendsbl

Use this to send the bootloader tape after you've entered the first stage.

### sendfile

Use this to send a raw file straight. Enter 'sendfile filename'

### xget

This will initiate an xmodem get. Enter 'xget filename'. This menu option is rarely used as the 'dsput' command inside CPM will trigger it automatically.

### xsend

This will initiate an xmodem send. Enter 'xsend filename'. This menu option is rarely used as the 'dsget' command inside CPM will trigger it automatically.

## sendgs

This will send a ctrl-].

# DSGET and DSPUT

These software programs are loaded onto the CPM disk. They initiate xmodem send and recieve to exchange files with the host system. They send escape codes that will automatically trigger the appropriate xmodem calls inside serialdrive.py so you won't have to use the menu options of 'xsend' or 'xget.' Just run DSGET.COM <file> or DSPUT.COM <file> inside of CPM.

These are minor modifications of Mike Douglas's PCGET/PCPUT software; credit goes to him.

# But I have more memory than 48k!

Use standard MOVCPM/SYSGEN processes to resize CPM. Refer to the Lifeboat CPM manual.

# Can I run it on Windows instead of Linux?

Um...probably. It might require a slight modification to serialdrive.py's use of select(). Everything else should work just fine.

# Future Improvements

The menu could use several improvements. For example, there is no error checking that disk files actually exist.

Right now the firstboot.asm, loader2.asm, sbl.asm, boot.asm, bios.asm, and user.asm files are all coded for the s100computers.com Serial IO Card USB port. It would be trivial to add 'ifdef' type statements to accommodate other serial cards such as the original MITS SIO and 2SIO cards.

