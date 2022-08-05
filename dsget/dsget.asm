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
	jc	RECEIVEFILE	;line is clear, go receive the file

	cpi	CTRLC		;exit if abort requested
	jz	abort
	jmp	purge

;
;**************RECEIVE FILE****************
;
RECEIVEFILE:
	CALL	ERASEOLDFILE
	CALL	MAKENEWFILE

#if defined(USBDATA)
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
#else
OWAIT0: IN	16
	ANI	02h
	JZ	OWAIT0
	MVI	A,0FFh
	OUT	17
OWAIT1: IN	16
	ANI	02h
	JZ	OWAIT1
	MVI	A,013h
	OUT	17
#endif

	MVI	A,NAK
	CALL	SEND		;SEND NAK

RECVLOOP:
RECVHDR:
	MVI	B,3		;3 SEC TIMEOUT
	CALL	RECV
	JNC	RHNTO		;NO TIMEOUT

RECVHDRTIMEOUT:
RECVSECTERR:			;PURGE THE LINE OF INPUT CHARS
	MVI	B,1		;1 SEC W/NO CHARS
	CALL	RECV
	JNC	RECVSECTERR 	;LOOP UNTIL SENDER DONE

	MVI	A,NAK
	CALL	SEND		;SEND NAK
	JMP	RECVHDR

;GOT CHAR - MUST BE SOH OR CTRL-C TO ABORT

RHNTO:	CPI	SOH
	JZ	GOTSOH

	cpi	CTRLC		;control-c to abort?
	jz	abort		;yes

	CPI	EOT		;end of transmission?
	JZ	GOTEOT		;yes
	JMP	RECVSECTERR

GOTSOH:
	MVI	B,1		;one second timeout
	CALL	RECV
	JC	RECVHDRTIMEOUT

	MOV	D,A		;D=BLK #
	MVI	B,1
	CALL	RECV		;GET CMA'D SECT #
	JC	RECVHDRTIMEOUT

	CMA
	CMP	D		;GOOD SECTOR #?
	JZ	RECVSECTOR

	JMP	RECVSECTERR

;  Receive Sector

RECVSECTOR:
	MOV	A,D		;GET SECTOR #
	STA	RSECTNO
	MVI	C,0		;INIT CKSUM
	LXI	H,80H		;POINT TO BUFFER

RECVCHAR:
	MVI	B,1		;1 SEC TIMEOUT
	CALL	RECV		;GET CHAR
	JC	RECVHDRTIMEOUT

	MOV	M,A		;STORE CHAR
	INR	L		;DONE?
	JNZ	RECVCHAR

;VERIFY CHECKSUM

	MOV	D,C		;SAVE CHECKSUM
	MVI	B,1		;TIMEOUT
	CALL	RECV		;GET CHECKSUM
	JC	RECVHDRTIMEOUT

	CMP	D		;CHECK
	JNZ	RECVSECTERR
;
;GOT A SECTOR, WRITE IF = 1+PREV SECTOR
;
	LDA	RSECTNO
	MOV	B,A		;SAVE IT
	LDA	SECTNO		;GET PREV
	INR	A		;CALC NEXT SECTOR #
	CMP	B		;MATCH?
	JNZ	DOACK

;GOT NEW SECTOR - WRITE IT

	LXI	D,FCB
	MVI	C,WRITE
	CALL	BDOS
	ORA	A
	JNZ	WRITEERROR

	LDA	RSECTNO
	STA	SECTNO		;UPDATE SECTOR #

DOACK	MVI	A,ACK
	CALL	SEND
	JMP	RECVLOOP

WRITEERROR:
	CALL	ERXIT
	DB	CR,LF,LF,'Error Writing File',CR,LF,'$'

GOTEOT:
	MVI	A,ACK		;ACK THE EOT
	CALL	SEND

	LXI	D,FCB		;close the file
	MVI	C,CLOSE
	CALL	BDOS
	INR	A
	JNZ	XFERCPLT

	CALL	ERXIT
	DB	CR,LF,LF,'Error Closing File',CR,LF,'$'
;
ERASEOLDFILE:
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
MAKENEWFILE:
	LXI	D,FCB
	MVI	C,MAKE
	CALL	BDOS
	INR	A		;FF=BAD
	RNZ			;OPEN OK

;DIRECTORY FULL - CAN'T MAKE FILE
	CALL	ERXIT
	DB	CR,LF,LF,"Error - Can't Make File",CR,LF
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
	
noAbort	lxi	d,(160 << 8)	;50 cycles, 6.25ms/wrap*160=1s

MWTI

#if defined(USBDATA)
	IN	USBSTAT
	ANI	080h
	JZ	MCHAR		;GOT CHAR
#else
	IN	16
	ANI	01h
	JNZ	MCHAR		;GOT CHAR
#endif

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

MCHAR	

#if defined(USBDATA)
	IN	USBDATA
#else
	IN	17
#endif
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

sndwt	

#if defined(USBDATA)
	IN	USBSTAT
	ANI	040h
	JNZ	sndwt
#else
	IN	16
	ANI	02h
	JZ	sndwt
#endif
	POP	PSW		;GET CHAR

sndSDR	
#if defined(USBDATA)
	OUT	USBDATA
#else
	OUT	17
#endif
	CPI	0FFh
	jnz	snddone
#if defined(USBDATA)
	OUT	USBDATA		; if sending 0FFh then send twice	
#else
	OUT	17
#endif
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

XFERCPLT:
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

