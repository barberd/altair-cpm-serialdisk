;**********************************************************************
;
;  DSGET - This CP/M program receives a file from a PC via a serial 
;  port and writes it to the CP/M file system. The XMODEM protocol
;  is used for file transfer.
;
;  PCGET Original Hacked together by Mike Douglas for the H89.
;  Modified by Don Barber to work with the disk-over-serial and
;  s100computers.com Serial IO Card USB Module.
;
;  This program is gutted from the Ward Christenson MODEM program.
;
;	Ver	Date	   Desc
;   	---    --------    ---------------------------
;	1.0    09/01/19	   Initial version
;       1.0a   05/15/21    Don Barber's DSGET mods
;
;***********************************************************************

;  Serial Port Equates

USBSTAT	EQU	0AAh
USBDATA	EQU	0ACh

; Transfer related equates

SOH	EQU	1
EOT	EQU	4
ACK	EQU	6
NAK	EQU	15H
CTRLC	EQU	3
LF	EQU	10
CR	EQU	13

	ORG	100H

; Verify a file name was specified. Display help message if not.

	lda	PARAM1		;A=1st character of parameter 1
	cpi	' '		;make sure file name present
	jnz	haveFn		;yes, have a file name

	lxi	d,mHelp		;display usage message
	mvi	c,print
	call	BDOS
	ret			;return to CPM

; Switch to local stack and initialize for transfer

havefN	LXI	SP,STACK	;SP=MY STACK

doXfer	xra	a		;init sector number to zero
	sta	SECTNO
	
	lxi	d,mSend 
	MVI	C,PRINT		;display the send file prompt
	CALL	BDOS

;  GOBBLE UP GARBAGE CHARS FROM THE LINE

purge	MVI	B,1		;times out after 1 second if no data
	CALL	RECV
	jc	RECEIVE$FILE	;line is clear, go receive the file

	cpi	CTRLC		;exit if abort requested
	jz	abort
	jmp	purge

;
;**************RECEIVE FILE****************
;
RECEIVE$FILE:
	CALL	ERASE$OLD$FILE
	CALL	MAKE$NEW$FILE

OWAIT0: IN	USBSTAT
	ANI	040h
	JNZ	OWAIT0
	MVI	A,0FFh
	OUT	USBDATA
OWAIT1: IN	USBSTAT
	ANI	040h
	JNZ	OWAIT1
	MVI	A,013h
	OUT	USBDATA
	MVI	A,NAK
	CALL	SEND		;SEND NAK

RECV$LOOP:
RECV$HDR:
	MVI	B,3		;3 SEC TIMEOUT
	CALL	RECV
	JNC	RHNTO		;NO TIMEOUT

RECV$HDR$TIMEOUT:
RECV$SECT$ERR:			;PURGE THE LINE OF INPUT CHARS
	MVI	B,1		;1 SEC W/NO CHARS
	CALL	RECV
	JNC	RECV$SECT$ERR 	;LOOP UNTIL SENDER DONE

	MVI	A,NAK
	CALL	SEND		;SEND NAK
	JMP	RECV$HDR

;GOT CHAR - MUST BE SOH OR CTRL-C TO ABORT

RHNTO:	CPI	SOH
	JZ	GOT$SOH

	cpi	CTRLC		;control-c to abort?
	jz	abort		;yes

	CPI	EOT		;end of transmission?
	JZ	GOT$EOT		;yes
	JMP	RECV$SECT$ERR

GOT$SOH:
	MVI	B,1		;one second timeout
	CALL	RECV
	JC	RECV$HDR$TIMEOUT

	MOV	D,A		;D=BLK #
	MVI	B,1
	CALL	RECV		;GET CMA'D SECT #
	JC	RECV$HDR$TIMEOUT

	CMA
	CMP	D		;GOOD SECTOR #?
	JZ	RECV$SECTOR

	JMP	RECV$SECT$ERR

;  Receive Sector

RECV$SECTOR:
	MOV	A,D		;GET SECTOR #
	STA	RSECTNO
	MVI	C,0		;INIT CKSUM
	LXI	H,80H		;POINT TO BUFFER

RECV$CHAR:
	MVI	B,1		;1 SEC TIMEOUT
	CALL	RECV		;GET CHAR
	JC	RECV$HDR$TIMEOUT

	MOV	M,A		;STORE CHAR
	INR	L		;DONE?
	JNZ	RECV$CHAR

;VERIFY CHECKSUM

	MOV	D,C		;SAVE CHECKSUM
	MVI	B,1		;TIMEOUT
	CALL	RECV		;GET CHECKSUM
	JC	RECV$HDR$TIMEOUT

	CMP	D		;CHECK
	JNZ	RECV$SECT$ERR
;
;GOT A SECTOR, WRITE IF = 1+PREV SECTOR
;
	LDA	RSECTNO
	MOV	B,A		;SAVE IT
	LDA	SECTNO		;GET PREV
	INR	A		;CALC NEXT SECTOR #
	CMP	B		;MATCH?
	JNZ	DO$ACK

;GOT NEW SECTOR - WRITE IT

	LXI	D,FCB
	MVI	C,WRITE
	CALL	BDOS
	ORA	A
	JNZ	WRITE$ERROR

	LDA	RSECTNO
	STA	SECTNO		;UPDATE SECTOR #

DO$ACK	MVI	A,ACK
	CALL	SEND
	JMP	RECV$LOOP

WRITE$ERROR:
	CALL	ERXIT
	DB	CR,LF,LF,'Error Writing File',CR,LF,'$'

GOT$EOT:
	MVI	A,ACK		;ACK THE EOT
	CALL	SEND

	LXI	D,FCB		;close the file
	MVI	C,CLOSE
	CALL	BDOS
	INR	A
	JNZ	XFER$CPLT

	CALL	ERXIT
	DB	CR,LF,LF,'Error Closing File',CR,LF,'$'
;
ERASE$OLD$FILE:
	LXI	D,FCB
	MVI	C,SRCHF		;SEE IF IT EXISTS
	CALL	BDOS
	INR	A		;FOUND?
	RZ			;NO, RETURN

ERAY:	LXI	D,FCB
	MVI	C,ERASE
	CALL	BDOS
	RET
;
MAKE$NEW$FILE:
	LXI	D,FCB
	MVI	C,MAKE
	CALL	BDOS
	INR	A		;FF=BAD
	RNZ			;OPEN OK

;DIRECTORY FULL - CAN'T MAKE FILE
	CALL	ERXIT
	DB	CR,LF,LF,'Error - Can''t Make File',CR,LF
	DB	'(directory must be full)',CR,LF,'$'
;
; S U B R O U T I N E S
;
; - - - - - - - - - - - - - - -

;EXIT PRINTING MESSAGE FOLLOWING 'CALL ERXIT'

ERXIT	POP	D		;GET MESSAGE
	MVI	C,PRINT
	CALL	BDOS		;PRINT MESSAGE
	JMP	WBOOT		;DO WARM BOOT TO EXIT

; - - - - - - - - - - - - - - -
;MODEM RECV
;-------------------------------------
RECV	PUSH	D		;save DE

MSEC	;push	b		;save BC and HL for BDOS call to check
	;push	h		;  for operator CTRL-C
	;mvi	c,DIRCTIO	;see if abort requested at console
	;mvi	e,0FFh		;E=FF means input operation
	;call	BDOS
	;pop	h		;restore saved registers
	;pop	b
	
	;cpi	CTRLC		;abort requested?
	;jnz	noAbort		;no

	;pop	d		;restore DE
	;ret			;exit with CTRL-C as the character
	
noAbort	lxi	d,(160 shl 8)	;50 cycles, 6.25ms/wrap*160=1s

MWTI	IN	USBSTAT
	ANI	080h
	NOP
	NOP
	JZ	MCHAR		;GOT CHAR

	DCR	E		;COUNT DOWN
	JNZ	MWTI		;FOR TIMEOUT
	DCR	D
	JNZ	MWTI

	DCR	B		;DCR # OF SECONDS
	JNZ	MSEC

;MODEM TIMED OUT RECEIVING

	POP	D		;RESTORE D,E
	STC			;CARRY SHOWS TIMEOUT
	RET

;GOT MODEM CHAR

MCHAR	IN	USBDATA
	POP	D		;RESTORE DE
	PUSH	PSW		;CALC CHECKSUM
	ADD	C
	MOV	C,A
	POP	PSW
	ORA	A		;TURN OFF CARRY TO SHOW NO TIMEOUT
	RET

; - - - - - - - - - - - - - - -
;MODEM SEND CHAR ROUTINE
;----------------------------------
;
SEND	PUSH	PSW		;CHECK IF MONITORING OUTPUT
	ADD	C		;CALC CKSUM
	MOV	C,A

sndwt	IN	USBSTAT
	ANI	040h
	JNZ	sndwt
	POP	PSW		;GET CHAR

sndSDR	OUT	USBDATA
	CPI	0FFh
	jnz	snddone
	OUT	USBDATA		; if sending 0FFh then send twice	
snddone
	RET

;-----------------------------------------
;  messages
;-----------------------------------------

mSend	db	'Send file now using XMODEM...$'
mHelp	db	CR,LF,'DSGET Ver 1.0a for Disk-over-Serial',CR,LF,LF
	db	'Receives a file from a PC compatible with the',CR,LF
        db      'disk-over-serial CPM BIOS and PC software over',CR,LF
	db	'the s100computers.com Serial IO Card USB port',CR,LF
        db      'using the XMODEM protocol.',CR,LF,LF
	db	'Usage: DSGET file.ext',CR,LF
	db	CR,LF,'$'

;DONE - CLOSE UP SHOP

XFER$CPLT:
	CALL	ERXIT
	DB	CR,LF,LF,'Transfer Complete',CR,LF,'$'

abort:	call	ERXIT
	db	CR,LF,LF,'Transfer Aborted',CR,LF,'$'

	DS	40		;STACK AREA
STACK	EQU	$

RSECTNO	DS	1		;RECEIVED SECTOR NUMBER
SECTNO	DS	1		;CURRENT SECTOR NUMBER 

;
; BDOS EQUATES (VERSION 2)
;
WBOOT	EQU	0		;WARM BOOT JUMP ADDRESS
RDCON	EQU	1
WRCON	EQU	2
DIRCTIO	EQU	6		;CONSOLE DIRECT I/O
PRINT	EQU	9
CONST	EQU	11		;CONSOLE STAT
OPEN	EQU	15		;0FFH=NOT FOUND
CLOSE	EQU	16		;   "	"
SRCHF	EQU	17		;   "	"
SRCHN	EQU	18		;   "	"
ERASE	EQU	19		;NO RET CODE
READ	EQU	20		;0=OK, 1=EOF
WRITE	EQU	21		;0=OK, 1=ERR, 2=?, 0FFH=NO DIR SPC
MAKE	EQU	22		;0FFH=BAD
REN	EQU	23		;0FFH=BAD
STDMA	EQU	26
BDOS	EQU	5
REIPL	EQU	0
FCB	EQU	5CH		;DEFAULT FCB
PARAM1	EQU	FCB+1		;COMMAND LINE PARAMETER 1 IN FCB
PARAM2	EQU	PARAM1+16	;COMMAND LINE PARAMETER 2

	END

