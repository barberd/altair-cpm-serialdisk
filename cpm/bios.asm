;----------------------------------------------------------------------
;
;   BIOS for Lifeboat Associates CP/M2 Vers 2.20 for the MITS/Altair
;   	8 inch disk controller.
;
;   Disassembled by Patrick Linstruth and Mike Douglas, May 2020
;
;   Modified by Don Barber for Disk-Over-Serial, May 2022
;
;----------------------------------------------------------------------
;
;   To patch changes made to this BIOS into a CP/M image saved from
;   MOVCPM (e.g., CPMxx.COM), use the following commands:
;
;	A>DDT CPMxx.COM
;	-IBIOS.HEX
;	-Rxxxx      (where xxxx = BIAS computed below)
;	-G0	    (Go zero, not "oh")
;	A>SYSGEN
;
;-----------------------------------------------------------------------
	
JMP	equ	0C3h

; BIOS size equates
MSIZE	equ	48		;Distribution size
BIOSLEN	equ	0900h		;BIOS length

; CP/M size equates

CCPLEN	equ	0800h		;CP/M 2.2 fixed
BDOSLEN	equ	0E00h		;CP/M 2.2 fixed
SYSGEN	equ	0900h		;SYSGEN image location
USER	equ	0500h		;offset to the user area
BOOTLEN	equ	3*128		;boot loader length

; These equates are automatically changed by MSIZE.

BIOS	equ	(MSIZE*1024)-BIOSLEN	;BIOS base address
BDOS	equ	BIOS-BDOSLEN		;BDOS base address
BDOSENT	equ	BDOS+6			;BDOS entry address
CCP	equ	BDOS-CCPLEN		;CCP base address
BIAS	equ	SYSGEN+BOOTLEN-CCP	;puts CCP,BDOS,BIOS in SYSGEN image
BIOSGEN	equ	BIOS+BIAS		;BIOS ends up here in SYSGEN image

	org	BIOS

; CCP equates

CMDLINE	equ	CCP+7		;location of command line in the CCP

; CPM page zero equates

WBOOTV	equ	00h		;warm boot vector location
BDOSV	equ	05h		;bdos entry vector location
CDISK	equ	04h		;CPM current disk
DEFDMA	equ	80h		;default dma address

USBSTAT EQU     0AAH
USBDATA EQU     0ACH

; Disk information equates

NUMTRK	equ	77		;number of tracks
NUMSECT	equ	32		;number of sectors per track
ALTLEN	equ	137		;length of Altair sector
SECLEN	equ	128		;length of CPM sector
DSM	equ	149		;max block number (150 blocks of 2048 bytes)
DRM	equ	63		;max directory entry number (64 entries) 
CKS	equ	(DRM+1)/4	;directory check space
MAXTRY	equ	5		;maximum number of disk I/O tries
UNTRACK	equ	7Fh		;unknown track number

; Misc equates

CR	equ	13		;ascii for carriage return
LF	equ	10		;ascii for line feed

;-----------------------------------------------------------------------------
;
;  BIOS Entry Jump Table
;
;-----------------------------------------------------------------------------
	jmp	boot		;cold boot entry
wboote	jmp	wboot		;warm boot entry
	jmp	const		;console input status
	jmp	conin		;console input
;	jmp	coninUl		;unload head before console input
	jmp	conout		;console output
	jmp	list		;printer output
;	jmp	listUl		;unload head before printer output
	jmp	punch		;punch output
	jmp	reader		;reader input
	jmp	home		;home disk
	jmp	seldsk		;select specified drive
	jmp	settrk		;set specified track
	jmp	setsec		;set specified sector
	jmp	setdma		;set sector transfer address
	jmp	read		;read sector
	jmp	write		;write sector
	jmp	listst		;printer status
	jmp	sectran		;sector translate

mBanner	db	CR,LF
	db	'CP/M2 on Altair',CR,LF
	db	'0'+(MSIZE/10),'0'+(MSIZE % 10)
	db	'K Vers 2.20  ',CR,LF
	db	'(c) 1981 Lifeboat Associates',CR,LF
	db	'Modified 2022 Don Barber for Disk-over-Serial$'

; Diaplay message at HL until '$' reached

dispMsg	mov	a,m		;A=character to display
	cpi	'$'		;$ means end of string
	rz

	mov	c,m		;C=character to display
	inx	h
	push	h

	call	conout		;display the character
	pop	h
	jmp	dispMsg

;----------------------------------------------------------------------------
; boot - Cold boot BIOS entry. CPM is already loaded in memory. Hand
;    control to the CCP.
;----------------------------------------------------------------------------

boot	

	xra	a
	sta	CDISK		;set initially to drive A
	call	cinit		;cold initialize user area
	jmp	entCpm		;go to cp/m

;----------------------------------------------------------------
; wboot - Warm boot BIOS entry. Reload CPM from disk up to, but
;    not including the BIOS. Re-enter CPM after loading.
;----------------------------------------------------------------
wboot	lxi	sp,0100h	;init stack pointer
	call	clrTrks		;clear current track and track table
	xra	a
	sta	diskNum		;disk zero is boot disk
	sta	trkNum		;set track number to zero

	lxi	h,CCP-BOOTLEN	;HL->where 1st sector would go if allowed
	inr	a		;A=1=first sector (1-indexed)
	call	loadTrk		;load track 0

	mvi	a,1		;move to track 1
	sta	trkNum
	lxi	h,CCP+0E80h	;HL->where track 1 goes
	call	loadTrk

	call	winit		;warm initialize user area

; entCpm - enter CPM. Set page zero variables, enter CPM with or without
;   command line based on the flags variable

entCpm	

	mvi	a,JMP		;8080 "jmp" opcode
	sta	WBOOTV		;store in 1st byte of warm boot vector
	sta	BDOSV		;and 1st byte of BDOS entry vector

	lxi	h,wboote	;HL=warm start address in BIOS
	shld	WBOOTV+1	;put it after the jmp
	lxi	h,BDOSENT	;HL=BDOS entry address
	shld	BDOSV+1		;put it after the jump

	lxi	h,cldDone	;get the "cold start done" flag
	mov	a,m
	ora	a		;Z false if cold start already done
	mvi	m,1		;indicate cold start has been done
	push	psw		;save the test result

	lxi	h,mBanner	;HL->cold start message
	cz	dispMsg		;display only during cold start

	pop	psw		;recover cold start status 
	lxi	h,CDISK		;HL->CP/Mcurrent disk
	mov	c,m		;C=current disk number
	lda	flags		;check the "process command line" flags
	jz	coldSt		;jump if we're in cold start

	ani	fWRMCMD 	;in warm start, execute command line?
	jmp	cmdChk

coldSt	

	ani	fCLDCMD		;in cold start, execute command line?

cmdChk	jz	CCP+3		;no, enter CCP and clear cmd line
	jmp	CCP		;yes, enter CCP with possible cmd line

; loadTrk - load one track into memory. Read odd sectors into every other 
;    128 bytes of memory until the BIOS base address is reached or all
;    32 sectors in the track have been read. Then read even sectors into
;    the opposite 128 byte sections of memory until the BIOS base address
;    is reached or all 32 sectors in the track have been read.

loadTrk	sta	secNum		;save the sector number we're on
	shld	dmaAddr		;save the destination address
	
	mov	a,h		;A=MSB of address to check
	cpi	(BIOS >> 8)	;current address >= BIOS start address?
	jnc	nxtSec		;yes, skip read (don't overwrite BIOS)
	
	cpi	(CCP >> 8)	;current address < CCP start address?
	jc	nxtSec		;yes, skip read (not to valid data yet)
	
	call	read		;read a sector
	jnz	wboot		;fatal read error, restart
	
nxtSec	lhld	dmaAddr		;HL->destination address
	lxi	d,0100h		;increment address by 256 bytes
	dad	d
	
	lda	secNum		;A=sector number
	adi	2		;jump 2 sectors each read
	cpi	NUMSECT+1	;past the last sector in the track?
	jc	loadTrk		;not yet, keep reading
	
	sui	NUMSECT-1	;compute starting even sector number
	lxi	d,-0F80h	;compute load address for 1st even sector
	dad	d
	
	cpi	3		;done both odd and even sectors in a track?
	jnz	loadTrk		;no, go do even sectors
	
	ret

;-----------------------------------------------------------------------------
; dpHead - disk parameter header for each drive
;-----------------------------------------------------------------------------
dpHead	dw	xlate,0,0,0,dirBuf,mitsDrv,csv0,alv0
	dw	xlate,0,0,0,dirBuf,mitsDrv,csv1,alv1
	dw	xlate,0,0,0,dirBuf,mitsDrv,csv2,alv2
	dw	xlate,0,0,0,dirBuf,mitsDrv,csv3,alv3

;-----------------------------------------------------------------------------
; mitsdrv - disk parameter block with block size of 2048 bytes.
;   Per CPM docs, EXM should be 1 and AL0,AL1 should be 80h, 00h.
;   This would give two logical extents per physical extent (32K per
;   physical extent). The settings here give one logical extent per
;   physical extent (16K per physical extent). This was done to
;   maintain compatibility with CPM 1.4 disks.
;-----------------------------------------------------------------------------
mitsDrv	dw	NUMSECT		;sectors per track
	db	4		;allocation block shift factor (BSH)
	db	0Fh		;data location block mask (BLM)
	db	0		;extent mask (EXM), see note above
	dw	DSM		;maximum block number (DSM)
	dw	DRM		;maximum directory entry number (DRM)
	db	80h,0		;AL0, AL1, see note above
	dw	CKS		;CKS (DRM+1)/4
	dw	2		;reserved tracks for CPM and bootloader

;----------------------------------------------------------------------------
; seldsk - Select Disk BIOS entry. C contains the disk number to select.
;    Validate the disk number and return a pointer to the disk parameter
;    header in HL. Zero is returned in HL for invalid drive number. The
;    selected disk number is stored in diskNum. No actual drive activity 
;    takes place.
;----------------------------------------------------------------------------
seldsk	mov	a,c		;A=drive number
	ani	07Fh
	lxi	h,numDisk	;verify drive number less than number of disks
	cmp	m
	jnc	selerr		;drive number error
	
	sta	diskNum		;save the selected disk number
	
	mvi	h,0		;compute disk parameter header address
	mov	l,a		;(16*drvNum) + dpHead
	dad	h
	dad	h
	dad	h
	dad	h
	lxi	d,dpHead
	dad	d		;HK->DPH for the passed drive
	ret
	
selerr	lxi	h,0		;error, set HL=0, cdisk=0, A=1
	xra	a
	sta	CDISK
	inr	a
	ret

;----------------------------------------------------------------------------
; home - Home BIOS entry. Set track to zero. No drive activity takes
;    place.
;----------------------------------------------------------------------------
home:	mvi	c,0		;C=track=zero

;----------------------------------------------------------------------------
; settrk - Set Track BIOS entry. C contains the desired track number.
;    The track number is saved in trkNum for later use. No actual
;    drive activity takes place.
;----------------------------------------------------------------------------
settrk:	mov	a,c		;save track number from C in trkNum
	sta	trkNum
	ret

;----------------------------------------------------------------------------
; setsec - Set Sector BIOS entry. C contains the desired sector number.
;    The sector number has already been translated through the skew table.
;    The sector number is saved in secNum for later use. No actual
;    drive activity takes place.
;----------------------------------------------------------------------------
setsec:	mov	a,c		;save sector number from C in secNum
	sta	secNum
	ret

;----------------------------------------------------------------------------
; setdma - Set DMA BIOS entry. BC contains the address for reading or
;    writing sector data for subsequent I/O operations. The address is
;    stored in dmaAddr.
;----------------------------------------------------------------------------
setdma:	mov	h,b		;save transfer address from BC in dmaAddr
	mov	l,c
	shld	dmaAddr
	ret

;----------------------------------------------------------------------------
; sectran - Sector translation BIOS entry. Convert logical sector number in
;    BC to physical sector number in HL using the skew table passed in DE.
;----------------------------------------------------------------------------
sectran	lxi	h,xlate		;HL->translate table
	mvi	b,0		;form BC=input sector number
	dad	b		;HL->physical sector number
	
	mov	l,m		;get physical sector in L
	mvi	h,0		;form HL=physical sector number
	ret

;---------------------------------------------------------------------------
; xlate - sector translation table for skew
;---------------------------------------------------------------------------
xlate	db	01,09,17,25,03,11,19,27,05,13,21,29,07,15,23,31
	db	02,10,18,26,04,12,20,28,06,14,22,30,08,16,24,32

; coninUl - A program calling conin to do console input is used as an
;   indicator that this is a good time to unload the head.

coninUl	
	jmp	conin

; listUl - A program calling list to do printer output unloads the disk
;   head. This entry point is presently NOT used.

listUl	
	jmp	list

;----------------------------------------------------------------------------
; read - Read sector BIOS entry. Read one sector using the trkNum, secNum
;    and dmaAddr specified for diskNum. Returns 0 in A if successful, 1 
;    in A if a non-recoverable error has occured.
;----------------------------------------------------------------------------
read	mvi	a,1		;set the "verify track number" flag to true
	call	rTrkSec		;retrieve track in C, physical sector in B
	di
	call	readSec		;read the sector

	jmp	exitDio		;disk i/o exit routine

;----------------------------------------------------------------------------
; write - Write sector BIOS entry. Write one sector using the trkNum, secNum
;    and dmaAddr specified for diskNum. Returns 0 in A if successful, 1 in A
;    if a non-recoverable error has occured.
;----------------------------------------------------------------------------
write	xra	a		;set the "verify track number" flag to false
	call	rTrkSec		;retrieve track in C, physical sector in B
	di
	call	wrtSec		;write sector
	jnz	exitDio		;write failed, exit
	
	lda	flags		;verifying writes?
	ani	fWRTVFY
	jz	exitDio		;no, exit
	
	mvi	a,1		;set the "verify track number" flag to true
	call	rTrkSec		;retrieve track in C, physical sector in B
	lxi	h,altBuf	;(this isn't actually used by readSec)
	call	readSec		;read the sector just written

;  exitDio - exit disk i/o. Restore interrupts if enable interrupt flag
;     is set.

exitDio	push	psw		;save status from I/O call
	lda	flags		;should we re-enable interrupts?
	ani	fENAINT
	jz	noInts		;no
	ei			;else, enable them
	
noInts	pop	psw		;restore I/O status
	mvi	a,0		;if status zero, return zero
	rz	
	inr	a		;else return A=1 for error

	ret

; rTrkSec - return track in C, physical sector in B

rTrkSec	sta	trkVrfy		;save the passed track verify flag
	lda	diskNum
	mov	c,a
	call	chkMnt		;manually mount another disk?
	mov	a,c
	sta	diskNum		;update disk number
	
	lhld	trkNum		;L=track number, H=sector number
	mov	c,l		;return C=track number
	dcr	h		;convert 1-32 to 0-31 for Altair FDC
	mov	b,h		;return B=physical sector
	ret

; chkMnt - check if we need to mount another disk in this drive

chkMnt	lda	flags		;single disk mode enabled?
	ani	fMNTDSK
	rz			;no
	
	lxi	h,mntdrv	;HL->mounted drive number
	mov	a,c
	adi	'A'		;are we mounting a different drive?
	cmp	m
	jz	mounted		;no, drive is already mounted
	
	mov	m,a		;else, save new mounted drive
	lxi	h,mMount	;prompt to change disks
	call	dispMsg
	call	conin		;wait for character input
	
mounted	mvi	c,0		;physical drive is always drive 0
	ret

mMount	db	CR,LF,'Mount disk '
mntdrv	db	'A'
	db	', then <cr>',CR,LF,'$'

;-----------------------------------------------------------------------------
; readSec - read sector. Selects the drive in diskNum, seeks to the track
;    in C and then reads the sector specified in B into the buffer
;    pointed to by dmaAddr.
;----------------------------------------------------------------------------
readSec	
	mvi     a,MAXTRY        ;set retry count (5 tries)
        sta     rtryCnt
	lda	diskNum
	sta	selNum
	
reReadP	push	b		;save sector number

reRead	call	rtryChk		;decrement and check retry counter
	pop	b
	rnz			;return if no more retries
	
	push	b		;save sector number
	mov	a,b		;A=sector number
	call	altSkew		;do 17 sector skew like Altair Basic does
	
	lxi	h,altBuf	;HK->altair sector buffer
	call	rdPSec		;read physical sector
	
	lda	flags		;raw I/O or normal (move to dmaAddr)?
	ani	fRAWIO
	jnz	rdExit		;raw I/O, leave data in altBuf and exit
	
	lda	trkNum		;process data based on track#
	cpi	6		;tracks 0-5 processed directly below
	jnc	rTrk676		;jmp for tracks 6-76

; validate and move data for sectors in tracks 0 - 5

	lxi	h,altBuf+T0STOP	;should have 0FFh at byte 131 in altBuf
	inr	m
	jnz	reRead		;wasn't 255, re-try the sector read
	
	lxi	h,altBuf+T0TRK	;track number + 80h at byte 0 in altBuf
	mov	a,m
	ani	07Fh		;get track number alone
	pop	b		;sector number off the stack
	cmp	c		;track number in C match track # in data?
	jnz	rdTrkEr		;no, have track number error
	
	push	b		;sector back on stack
	lhld	dmaAddr		;HL->data destination 
	mov	b,h		;BC->data destination
	mov	c,l
	
	lxi	h,altBuf+T0DATA	;data starts at byte 3 of altBuf
	call	moveBuf		;move cpm sector to (dmaAddr), return checksum
	
	lxi	h,altBuf+T0CSUM	;sector checksum is in altBuf + 132
	cmp	m
	jnz	reRead		;checksum fail, re-try the sector read
	
	pop	b		;sector number off stack
	xra	a		;return success code
	ret

; rTrk676 - validate and move data for sectors in tracks 6-76

rTrk676	dcx	h		;move back to last by read (offset 136)
	mov	a,m
	ora	a		;verify it is zero
	jnz	reRead		;not zero, re-try the sector read
	
	dcx	h		;move back to offset 135
	inr	m		;should have 0FFh here
	jnz	reRead		;0FFh not preset, re-try the sector read
	
	lxi	h,altBuf+T6TRK	;verify 1st byte of altBuf matches track #
	mov	a,m
	ani	07Fh		;get track number alone
	pop	b		;sector off stack
	cmp	c		;track number in c match track # in data?
	jnz	rdTrkEr		;no, have track number error
	
	inx	h		;move to offset 1, should have sector num here
	mov	a,m
	cmp	b		;verify it matches requested sector number
	jnz	reReadP		;sector match fail, retry the sector read
	
	push	b		;sector back on stack
	lhld	dmaAddr		;HL=>data destination
	mov	b,h		;BC->data destination
	mov	c,l
	
	lxi	h,altBuf+T6DATA	;data starts at byte 7 in altBuf
	call	moveBuf		;move cpm sector to (dmaAddr), return checksum
	
	lxi	h,altBuf+6	;add bytes 2,3,5 and 6 to checksum
	mov	b,m		;B=byte 6
	dcx	h
	mov	c,m		;C=byte 5
	dcx	h
	mov	d,m		;D=byte 4 (checksum byte)
	dcx	h
	mov	e,m		;E=byte 3
	dcx	h		;M=byte 2
	
	add	e		;add bytes 3, 6, 5 and 2 (not 4) to checksum
	add	b
	add	c
	add	m
	cmp	d		;compare to checksum
	jnz	reRead		;checksum fail, re-try the sector read
	
	pop	b		;sector off stack
	xra	a		;return success code

	ret

; rdTrkEr - Track number error during the read operation

rdTrkEr	
	jmp	reReadP		;retry the sector read (push B entry)

; rdExit - exit read (raw) where data is left in altBuf

rdExit	pop	b
	xra	a
	ret

; rdPSec - read physical sector. Read the physical Altair sector (0-31)
;    specified by e into the buffer specified by HL. Physical sector
;    length is ALTLEN (137) bytes.

rdPSec	


OWAIT1: IN      USBSTAT         ;READY TO WRITE?
        ANI     40H             ;READY
        JNZ     OWAIT1
        MVI     A,0FFH           ;send not-the-console command
        OUT     USBDATA

	CALL	flSer		; flush buffer

OWAIT2: IN      USBSTAT         ;READY TO WRITE?
        ANI     40H             ;READY
        JNZ     OWAIT2
        MVI     A,10H           ;send disk read
        OUT     USBDATA

OWAIT3: IN      USBSTAT         ;READY TO WRITE?
        ANI     40H             ;READY
        JNZ     OWAIT3
	LDA	diskNum		;set diskNum
        OUT     USBDATA

OWAIT4: IN      USBSTAT         ;READY TO WRITE?
        ANI     40H             ;READY
        JNZ     OWAIT4
        LDA     trkNum           ;set track num
        OUT     USBDATA

OWAIT5: IN      USBSTAT         ;READY TO WRITE?
        ANI     40H             ;READY
        JNZ     OWAIT5
	MOV	a,e		;set sector
        OUT     USBDATA

RWAIT:  IN      USBSTAT         ;DATA READY TO READ?
        ANI     80H             ;READY
        JNZ     RWAIT
        IN      USBDATA         ;GET STATUS BYTE
	ORA	A
        JNZ	rBad		;IF NOT 0 THEN ERROR

	mvi	c,ALTLEN	;C=length of Altair sector (137 bytes)
	
rdLoop	in	USBSTAT		;get drive status byte
	ani	80H		;wait for RXE
	jnz	rdLoop
	
	in	USBDATA		;read the byte
	mov	m,a		;store in the read buffer
	inx	h		;increment buffer pointer
	dcr	c		;decrement characters remaining in counter
	jnz	rdLoop		;loop until all bytes read
	
rDone	xra	a		;return success of zero = good read
rBad	ret

;------------------------------------------------------------------------------
; wrtSec - Write a sector. Selects the drive in diskNum, seeks to the
;    track in C and then writes the sector specified in B from the
;    buffer pointed to by dmaAddr.
;-----------------------------------------------------------------------------
wrtSec	
	mvi     a,MAXTRY        ;set retry count (5 tries)
        sta     rtryCnt
	lda	diskNum
	sta	selNum

	lda	trkNum		;process data differently depending on track #
	cpi	6		;tracks 0-5 processed directly below
	jnc	wTrk676		;jump to process tracks 6-76

;  Sector write for tracks 0-5

	push	b		;save sector number
	mov	a,c		;A=track number
	lxi	b,altBuf	;BC->altair sector buffer
	stax	b		;put track number at offset 0
	
	xra	a		;put 0100h (16 bit) at offset 1,2
	inx	b
	stax	b
	inr	a
	inx	b
	stax	b
	
	inx	b		;BC->cpm data in altBuf at offset 3
	lhld	dmaAddr		;HL->data buffer
	call	moveBuf		;move cpm sector from (dmaAddr) to altBuf
	
	mvi	a,0FFh		;offset 131 is stop byte (0FFh)
	stax	b
	
	inx	b		;offset 132 is checksum
	mov	a,d		;A=checksum
	stax	b		;store it at offset 132
	
	pop	b		;sector off stack
	jmp	setHCS		;got set head current setting

; wTrk676 - write sector for tracks 6-76

wTrk676	push	b		;save sector number
	lxi	b,altBuf+T6DATA	;BC->cpm data in altBuf at offset 7
	lhld	dmaAddr		;HL->data buffer
	call	moveBuf		;move cpm sector from (dmaAddr) to altBuf
	
	mvi	a,0FFh		;offset 135 is stop byte (0FFh)
	stax	b
	
	inx	b		;offset 136 is unused (store zero)
	xra	a
	stax	b
	
	mov	a,d		;A=checksum
	lhld	altBuf+2	;add bytes at offset 2 and 3 to checksum
	add	h
	add	l
	
	lhld	altBuf+5	;add bytes at offset 5 and 6 to checksum
	add	h
	add	l
	sta	altBuf+T6CSUM	;store final checksum at offset 4
	
	pop	b		;sector off stack
	lxi	h,altBuf	;HL->altair sector buffer
	mov	m,c		;store track number at offset 0
	inx	h
	mov	m,b		;store sector number at offset 1

setHCS	mov	a,c		;A=track number
	adi	(-43 and 0FFh)	;add -43 (1st track for HCS bit = 1)
	mvi	a,0		;set A=0 without affecting carry
	rar			;80h if track >= 43
	stc
	rar			;C0h if track >= 43, else 80h
	mov	d,a		;D=control command for the drive
	mov	a,b		;A=sector number

	call	altSkew		;do sector skew like Altair Disk BASIC

; wait for sector true and the right sector number

wtWrSec	

WWAIT1: IN      USBSTAT
        ANI     40H
        JNZ     WWAIT1
        MVI     A,0FFH           ;send the not-the-console-command
        OUT     USBDATA

	CALL	flSer		;flush buffer

WWAIT2: IN      USBSTAT         ;READY TO WRITE?
        ANI     40H             ;READY
        JNZ     WWAIT2
        MVI     A,11H           ;send disk write
        OUT     USBDATA

WWAIT3: IN      USBSTAT         ;READY TO WRITE?
        ANI     40H             ;READY
        JNZ     WWAIT3
	LDA	diskNum	        ;set disk
        OUT     USBDATA

WWAIT4: IN      USBSTAT         ;READY TO WRITE?
        ANI     40H             ;READY
        JNZ     WWAIT4
        LDA     trkNum          ;set track num
        OUT     USBDATA

WWAIT5: IN      USBSTAT         ;READY TO WRITE?
        ANI     40H             ;READY
        JNZ     WWAIT5
	MOV	a,e 		;set sector
        OUT     USBDATA

	lxi	h,altBuf	;HL->altair sector buffer
	lxi	b,0100h+ALTLEN	;C=137 bytes to write, B=1 byte of 0's at end
	mvi	a,80h		;1st byte of sector is sync byte
	ora	m		;sync byte must have msb set
	mov	e,a		;E=next byte to write
	inx	h
	
; wrSec - write physical sector loop


wrSec	in	USBSTAT		;read drive status register
	ani	40H		;TXE?
	jnz	wrSec		;no, keep waiting
	
	mov	a,e		;put byte to write into accumulator
	out	USBDATA		;write the byte
		
	mov	e,m		;E=byte to write next time through this loop
	inx	h		;increment source buffer pointer
	dcr	c		;decrement chars remaining (bytes just written)
	jnz	wrSec		;loop if count <> 0
	
; wrDone - write is done. Now write # of zeros specified in B (just 1)

wrDone:
;	in	USBSTAT		;wait for another write flag
;	ANI	40H
;	jnz	wrDone

	;TODO
	;mvi	a,0	
	;out	USBDATA		;write zero b times
	;dcr	b
	;jnz	wrDone

wdLoop:	in	USBSTAT
	ANI	80H
	JNZ	wdLoop
	IN	USBDATA		;read status back from seriallink
	ORA	A
	JNZ	wBad		;error for write
	
	xra	a		;return success status
wBad	ret

flSer:	IN	USBSTAT		;read from serial until empty
	ANI	80H
	JNZ	flSerdn
	IN	USBDATA
	JMP	flSer
flSerdn:RET

;------------------------------------------------------------------------------
; moveBuf - move sector buffer (128 bytes) from (HL) to (BC). Compute
;   checksum on all bytes and return in A.
;------------------------------------------------------------------------------
moveBuf	mvi	d,0		;D=checksum
	mvi	e,SECLEN	;E=buffer length (128 bytes)
	
movLoop	mov	a,m		;move from (HL) to (BC)
	stax	b
	
	add	d		;add byte to checksum
	mov	d,a
	
	inx	b		;increment both pointers
	inx	h
	dcr	e		;decrement character count
	jnz	movLoop		;loop until count = 0

	ret

;------------------------------------------------------------------------------
; altSkew - Do Altair sector skew like disk BASIC. For sectors greater than 6,
;    physical = (logical * 17) mod 32. Returns physical sector number in E.
;    This is done on top of the secTran skew table mechanism of CPM. The math
;    works out such that this call to altSkew does almost nothing.
;------------------------------------------------------------------------------
altSkew	mov	e,a		;E=input sector number
	lda	trkNum		;see if track number >= 6
	cpi	6
	rc			;track < 6, exit
	
	mov	a,e		;multiply by 17
	add	a
	add	a
	add	a
	add	a
	add	e
	ani	01Fh		;keep lower 5 bits (0-31)
	mov	e,a	
	ret

;------------------------------------------------------------------------------
;  clrTrks - Initialize current track and the track table entry for each
;     drive to "unknown." This entry point is called by the boot loader
;     as well.
;------------------------------------------------------------------------------
clrTrks	lxi	h,flags		;HL->flags byte
	mov	a,m		;A=flags byte
	ani	0F7h
	mov	m,a		;clear force track verification
	mvi	a,UNTRACK	;A=undefined track	
	sta	selNum		;no drive selected
	lxi	h,256*UNTRACK+UNTRACK	;HL=7F7F
	shld	trkTbl
	shld	trkTbl+2
	ret

;------------------------------------------------------------------------------
; rtryChk - retry counter check. Decrement retry counter. Returns zero if
;     more tries left, non-zero if retry counter reaches zero.
;------------------------------------------------------------------------------
rtryChk	lxi	h,rtryCnt	;HL->retry counter
	dcr	m		;decrement the count
	jz	retErr		;error if it reaches zero
	
	xra	a		;return zero - still ok
	ret

; retErr - Return error code with 1 in accumulator and non-zero status flag

retErr	mvi	a,1
	ora	a
	ret


;------------------------------------------------------------------------------
; USER AREA for CP/M2 on Altair
;
; Copyright (C) 1981 Lifeboat Associates
;
; User area is at offset 500h from start of the BIOS
;------------------------------------------------------------------------------

; The number of disks and the flags (MODE) byte are stored just before the
;     USER area.

	org	BIOS+USER-5

numDisk	db	4		;number of disks
	dw	altBuf		;not referenced anywhere
	db	10h		;not referenced anywhere
flags	db	0		;flags defined below 

fCLDCMD	equ	01h		;true = CCP process cmd on cold start
fWRMCMD	equ	02h		;true = CCP process cmd on warm start
fMNTDSK	equ	04h		;true = single disk mounting
fRAWIO	equ	08h		;r/w directly from altBuf
fENAINT	equ	10h		;enable interrupts after disk I/O
fWRTVFY	equ	40h		;write verify flag (true = verify)
fTRKVFY	equ	80h		;force track number verification

; JUMP TABLE - Jumps MUST remain here in same order.

cinit	jmp	cinitr		;Cold boot init
winit	jmp	nulUser		;Warm boot init
const	jmp	nulUser		;Console status
conin	jmp	nulUser		;Console input
conout	jmp	nulUser		;Console output
list	jmp	nulUser		;Printer output
punch	jmp	nulUser		;Punch output
reader	jmp	nulUser		;Reader input
listst	jmp	nulUser		;Printer status

; Null User Function

nulUser	
	xra	a		;return zero status 
	ret

; Set the CCP input buffer to run CONFIG.COM on startup

cinitr	lxi	d,CMDLINE	;DE->command line destination in CCP
	lxi	h,cmdStr	;HL->command line string 
	mvi	b,CMDLEN	;B=length of command string 
	call	movStr		;move command into CCP input buffer 

	lxi	h,BDOS+0AFh	;HL->bdos wait$err
	shld	const 		;console status jumps to wait$err
	shld	conin		;console input jumps to wait$err
	shld	conout		;console output jumps to wait$err

	mvi	a,jmp		;initialize the warm boot and
	sta	WBOOTV		;   BDOS jump vectors on page 0 
	sta	BDOSV
	lxi	h,wboote	;HL=BIOS warm start entry address
	shld	WBOOTV+1
	lxi	h,BDOSENT	;HL=BDOS entry address
	shld	BDOSV+1

	xra	a		;drive 0 is current disk
	sta	CDISK
	mov	c,a		;also pass to CCP in C
	jmp	CCP		;enter the CCP and execute CONFIG.COM

cmdStr:	db	6,'CONFIG',0
CMDLEN	equ	$-cmdStr

movStr:	mov	a,m 		;move (HL) to (DE) for B bytes
	stax	d 
	inx	h
	inx	d 
	dcr	b
	jnz	movStr
	ret 


	org	BIOS+USER+200h	;reserve 200h bytes for the user area
;------------------------------------------------------------------------------
; altBuf - Altair buffer contains the 137 bytes read straight from the 
;   Altair drive. This BIOS assumes the disk is laid out in a manner
;   similar to the Altair Disk Basic format. Sectors in tracks 0-5
;   have a different layout than sectors in tracks 6-76.
;------------------------------------------------------------------------------
altBuf:	ds	ALTLEN		;altair disk buffer

; Tracks 0-5

T0TRK	equ	0		;offset of track number
T0DATA	equ	3		;offset of 128 byte data payload
T0STOP	equ	131		;offset of stop byte (0FFh)
T0CSUM	equ	132		;offset of checksum

; Tracks 6-76

T6TRK	equ	0		;offset of track number
T6SEC	equ	1		;offset of sector number
T6CSUM	equ	4		;offset of checksum
T6DATA	equ	7		;offset of 128 byte data payload
T6STOP	equ	135		;offset of stop byte (0FFh)
T6ZERO	equ	136		;offset of unused, but checked for zero.

;-----------------------------------------------------------------------------
;  Disk scratchpad areas defined in the DPH table
;-----------------------------------------------------------------------------
dirBuf	ds	128		;BDOS directory scratchpad
alv0	ds	(DSM/8 + 1)	;disk allocation bitmap
csv0	ds	CKS		;change disk checksum area
alv1	ds	(DSM/8 + 1)
csv1	ds	CKS
alv2	ds	(DSM/8 + 1)
csv2	ds	CKS
alv3	ds	(DSM/8 + 1)
csv3	ds	CKS

;-----------------------------------------------------------------------------
; disk control data
;-----------------------------------------------------------------------------
diskNum ds	1		;current disk number
trkNum	ds	1		;track num (sector num MUST follow in memory)
secNum	ds	1		;sector number for disk operations
dmaAddr ds	2		;dma address for disk operations
trkVrfy	ds	1		;verify track number if <> 0
selNum	ds	1		;disk number currently selected on controller
rtryCnt	ds	1		;retry counter
cldDone	ds	1		;true after cold start has completed
trkTbl	ds	4		;current track for each drive

;-----------------------------------------------------------------------------
; Computed size and location equates
;-----------------------------------------------------------------------------
CLRTOFF	equ	clrTrks-BIOS	;offset to clrTrks (needed by boot.asm)
COLDOFF	equ	cldDone-BIOS	;offset to cldDone flag (needed for boot.asm)

BIOSCNT	equ	$-BIOS		;count of bytes in the BIOS

	end

