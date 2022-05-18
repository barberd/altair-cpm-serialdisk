;----------------------------------------------------------------------
;
;   CP/M boot loader for Lifeboat Associates CP/M2 Vers 2.20 for
;	the MITS/Altair 8 inch disk controller.
;
;   This loader is read in from track zero, sectors 0 and 2 by the
;   MITS DBL ROM. The loader then reads all of CPM into the proper
;   location in memory and jumps to the cold boot entry point.
;
;   Disassembled by Mike Douglas, May 2020
;
;   Modified by Don Barber to do disk-over-serial, May 2022
;
;----------------------------------------------------------------------
;
;    To patch changes made to this loader into a CP/M image saved
;    from MOVCPM (e.g., CPMxx.COM), use the following commands:
;
;	A>DDT CPMxx.COM
;	-IBOOT.HEX
;	-R900
;       -M980,9FF,A00	(splits code onto sectors 0 and 2)
;	-G0	    	(Go zero, not "oh")
;	A>SYSGEN
;
;----------------------------------------------------------------------

; Set the following equates based on the BIOS settings

MSIZE	equ	48		;memory size in K bytes (0 for relocatable)
BIOSLEN	equ	0900h		;BIOS length in bytes (Lifeboat Altair)
USER	equ	0500h		;offset to user area
CLRTRKS	equ	046Dh		;offset to CLRTRKS in the BIOS
CLDDONE	equ	089dh		;offset to CLDDONE flag in the BIOS

; CP/M size and location equates

CCPLEN	equ	0800h		;CPM 2.2 fixed
BDOSLEN	equ	0E00h		;CPM 2.2 fixed

BIOSBAS	equ	MSIZE*1024-BIOSLEN	;base address of the BIOS
BDOSBAS	equ	BIOSBAS-BDOSLEN		;base address of the BDOS
CCPBASE	equ	BDOSBAS-CCPLEN		;base address of the CCP

BOOTLEN	equ	3*128			;3 sectors for boot code
LOADTK0	equ	CCPBASE-BOOTLEN	 	;load address for track 0
LOADTK1	equ	LOADTK0 + 01000h	;load address for track 1

USBSTAT	equ	0AAH
USBDATA	equ	0ACH

; Disk information equates

NUMSECT	equ	32		;number of sectors per track
ALTLEN	equ	137		;length of Altair sector
SECLEN	equ	128		;length of CPM sector


; ALTBUF - Altair buffer contains the 137 bytes read straight from
;   the Altair drive. It is located 0100h bytes below the where
;   the CCP is loaded

ALTBUF	equ	CCPBASE-0100h	;altair disk buffer

; Tracks 0-5 of Altair disks have this format

T0TRK	equ	0		;offset of track number
T0DATA	equ	3		;offset of 128 byte data payload
T0STOP	equ	131		;offset of stop byte (0ffh)
T0CSUM	equ	132		;offset of checksum


;-----------------------------------------------------------------------------
;  Start of boot loader. Seek to track 0, load track 0, then load track 1,
;     then jump to the cold start BIOS entry.
;-----------------------------------------------------------------------------
	org	0
start	lxi	sp,CCPBASE	;stack grows down from lowest cpm address
	di

; Load track 0 content into memory. Odd sectors are read 1st and stored
;    in every other 128 byte block. Then even sectors are read to fill
;    in the other 128 byte blocks.

	lxi	b,0100h		;B=sector 1, C=track 0 
	lxi	h,loadTk0	;HL->track 0 load address
	mvi	a,0
	sta	TRACK

	call	loadTrk		;load all track 0 data

; Load track 1 content in the same manner.

chkTrk1	

	lxi	b,0101h		;B=sector 1, C=track 1
	lxi	h,loadTk1	;HL->track 1 load address
	mvi	a,1
	sta	TRACK
	call	loadTrk		;load off track 1 data

; Initialize the track table in the BIOS, clear the flag that says
;    cold start is done, then jump into the BIOS with interrupts
;    enabled or disabled based on the BIOS flags byte.

	call	BIOSBAS+CLRTRKS ;clear track table in BIOS

	xra	a		;cold start not complete yet
	sta	BIOSBAS+CLDDONE

	lda	BIOSBAS+user-1	;A=flags (MODE) byte from BIOS
	ani	010H		;enable interrupt flag true?
	jz	BIOSBAS		;no, leave them disabled

	ei			;else, enable interrupts

	jmp	BIOSBAS

;------------------------------------------------------------------------------
;  loadTrk - load a track into memory at it's final address
;------------------------------------------------------------------------------
loadTrk	push	b		;save sector and track number we're on
	push	h		;save destination address
	mov	a,h
	cpi	(CCPBASE >> 8)  ;current address < cpp start addr?
	jc	nxtSec		;yes, skip the next sector

	call	read		;read a sector

	jnz	start		;fatal read error, try again

nxtSec	pop	h		;get the destination pointer back
	lxi	d,0100h		;increment destination by 256 bytes
	dad	d

	pop	b		;get sector number back
	mov	a,b
	adi	2		;jump 2 setors each read
	mov	b,a

	cpi	NUMSECT+1	;past 32 sectors?
	jc	loadTrk		;not yet, keep reading

	sui	NUMSECT-1	;compute starting even sector number
	lxi	d,-0F80h	;compute load address for 1st even sector
	dad	d

	cpi	3		;done both odd and even sectors?
	mov	b,a
	jnz	loadTrk		;no, go to even sectors

	ret

;----------------------------------------------------------------------------
;  read - read a sector from the disk into ALTBUF, then move it to
;      the destination address after error checking. The sector number
;      is passed in B, the destination address is in HL.
;---------------------------------------------------------------------------
read	

	push	b		;save sector number
	push	h		;save address we're writing to next
	call	rdPSec		;read the sector specified in b into ALTBUF

	lxi	d,-6		;-6 bytes from the end is 0FFh stop byte
	dad	d
	inr	m		;this should increment 0FFh to zero
	pop	b		;BC->destination address
	pop	d		;D=sector number, E=track number
	rnz			;exit if stop byte wasn't 0FFh

	lxi	h,ALTBUF+T0TRK	;HL->track byte in ALTBUF
	mov	a,m		;get 1st byte with track number
	ani	07Fh		;get track number alone
	cmp	e		;verify track number is correct
	rnz			;exit if not right track

	inx	h		;move to 128 data payload at offset 3
	inx	h
	inx	h
	call	moveBuf		;move ALTBUF+T0DATA to memory at (HL)

	lxi	h,ALTBUF+T0CSUM	;verify checksum matches

	cmp	m
	ret

;----------------------------------------------------------------------------
; rdPSec - read physical sector. Read the sector specified by B into
;    ALTBUF. Physical sector length is ALTLEN (137) bytes.
;----------------------------------------------------------------------------
rdPSec	dcr	b		;convert 1 indexed sector to 0 indexed


OWAIT1:	IN	USBSTAT
	ANI	40H
	JNZ	OWAIT1
	MVI	A,0FFH		;send the not-the-console-command
	OUT	USBDATA

flSer:  IN      USBSTAT         ;read from serial until empty
        ANI     80H
        JNZ     flSerdn
        IN      USBDATA
        JMP     flSer
flSerdn:

OWAIT2: IN      USBSTAT         ;READY TO WRITE?
        ANI     40H             ;READY
        JNZ     OWAIT2
        MVI     A,10H           ;send disk read
        OUT     USBDATA

OWAIT3: IN      USBSTAT         ;READY TO WRITE?
        ANI     40H             ;READY
        JNZ     OWAIT3
        ORA     A               ;set disk 0
        OUT     USBDATA

OWAIT4: IN      USBSTAT         ;READY TO WRITE?
        ANI     40H             ;READY
        JNZ     OWAIT4
        LDA     TRACK           ;set track num
        OUT     USBDATA

OWAIT5: IN      USBSTAT         ;READY TO WRITE?
        ANI     40H             ;READY
        JNZ     OWAIT5
        MOV     A,B             ;set sector
        OUT     USBDATA

RWAIT:  IN      USBSTAT         ;DATA READY TO READ?
        ANI     80H             ;READY
        JNZ     RWAIT
        IN      USBDATA         ;GET STATUS BYTE
        JNZ     rdBad           ;IF NOT 0 THEN ERROR

	mvi	c,ALTLEN	;C=length of Altair sector (137 bytes)
	lxi	h,ALTBUF	;HL->ALTBUF

rdLoop	in	USBSTAT		;get drive status byte
	ANI	80H		;wait for RXE flag
	JNZ	rdLoop

	in	USBDATA		;read the byte 
	mov	m,a		;store in the read buffer
	inx	h		;increment buffer pointer
	dcr	c		;decrement characters remaining counter
	jnz	rdLoop		;loop until all bytes read

rdDone	xra	a		;return status of zero = good read
rdBad	ret

;----------------------------------------------------------------------------
; moveBuf - move sector buffer (128 bytes) from (HL) to (BC). Compute
;   checksum on all bytes and return in A.
;----------------------------------------------------------------------------
moveBuf	mvi	d,0		;init checksum to zero
	mvi	e,SECLEN	;128 byte data sector length

movLoop	mov	a,m		;move from (HL) to (BC)
	stax	b

	add	d		;add moved byte to checksum
	mov	d,a		;checksum saved in D

	inx	h		;increment both pointers
	inx	b
	dcr	e		;loop until all characters moved
	jnz	movLoop

	ret
TRACK	DB	1
	end

