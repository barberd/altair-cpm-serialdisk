;
;  IMSAI with SIO-2 serial ports
;
;  PCPUT - This CP/M program sends a file from a CP/M system to a PC
;  via a serial The file transfer uses the XMODEM protocol. 
;
;  Note this program is gutted from the Ward Christenson Modem program.
;
;  Hacked together by Mike Douglas for IMSAI with SIO-2 serial board.
;  Then hacked again by Don Barber to use s100computers.com Serial IO Board
;  USB module combined with the disk-over-serial CPM bios.
;
;	Ver	Date	   Desc
;   	---    --------    -----------------------------------------------
;	1.0    09/21/19	   Initial version
;	1.1    06/05/20    Get rid of "For North Star" in help banner
;	1.2    04/06/21    Add assembly option to use alternate port base
;			   address (10h instead of 00h)
;       1.2a   05/15/21    Modifications by Don Barber for USB + DS
;
;  Serial Port Equates

;USBSTAT	EQU	0AAh
;USBDATA	EQU	0ACh

ERRLMT  EQU     5               ;MAX ALLOWABLE ERRORS

;DEFINE ASCII CHARACTERS USED

SOH	EQU	1
EOT	EQU	4
ACK	EQU	6
NAK	EQU	15H
CTRLC	EQU	3		;Control-C
LF	EQU	10
CR	EQU	13

	org	100h

;  Verify a file name was specified

	lda	PARAM1		;A=1st character of parameter 1
	cpi	' '		;make sure file name present
	jnz	haveFn		;yes, have a file name

	lxi	d,mHelp		;display usage message
	mvi	c,print
	call	bdos
	ret			;return to CPM

haveFn

;  doXfer - Switch to local stack and do the transfer

doXfer	

	LXI	H,0		;HL=0
	DAD	SP		;HL=STACK FROM CP/M
	SHLD	STACK		;..SAVE IT
	LXI	SP,STACK	;SP=MY STACK

	xra	a		
	sta	SECTNO		;initialize sector number to zero

	CALL	OPEN$FILE	;OPEN THE FILE
	lxi	d,mRcv

sendA	MVI	C,PRINT
	CALL	BDOS		;PRINT ID MESSAGE

;  GOBBLE UP GARBAGE CHARS FROM THE LINE

purge	MVI	B,1		;times out after 1 second if no data
	CALL	RECV
	jc	lineClr		;line is clear, go wait for initial NAK

	cpi	ctrlc		;exit if abort requested
	jz	abort

	jmp	purge

lineClr	xra	a		;clear crc flag = checksum mode
	sta	crcFlag

#if defined(USBDATA)
OWAIT0: IN	USBSTAT		;tell CPM disk-over-serial agent
	ANI	040h            ;to start up xmodem to receive file
	JNZ	OWAIT0
	MVI	a,0FFh
	OUT	USBDATA
OWAIT1: IN	USBSTAT
	ANI	040h
	JNZ	OWAIT1
	MVI	a,012h
	OUT	USBDATA
#else
OWAIT0: IN	16		;tell CPM disk-over-serial agent
	ANI	002h            ;to start up xmodem to receive file
	JZ	OWAIT0
	MVI	a,0FFh
	OUT	17
OWAIT1: IN	16
	ANI	02h
	JZ	OWAIT1
	MVI	a,012h
	OUT	17
#endif

; WAIT FOR INITIAL NAK, THEN SEND THE FILE
	

WAITNAK	MVI	B,1		;TIMEOUT DELAY
	CALL	RECV
	JC	WAITNAK

	cpi	ctrlc		;abort requested?
	jz	abort

	CPI	NAK		;NAK RECEIVED?
	jz	SENDB		;yes, send file in checksum mode

	cpi	'C'		;'C' for CRC mode received?
	JNZ	WAITNAK		;no, keep waiting

	sta	crcFlag		;set CRC flag non-zero = true
				;fall through to start the send operation
;
;*****************SEND A FILE***************
;

;READ SECTOR, SEND IT

SENDB	CALL	READ$SECTOR
	LDA	SECTNO		;INCR SECT NO.
	INR	A
	STA	SECTNO

;SEND OR REPEAT SECTOR

REPTB	MVI	A,SOH
	CALL	SEND

	LDA	SECTNO
	CALL	SEND

	LDA	SECTNO
	CMA
	CALL	SEND

	lxi	h,0		;init crc to zero
	shld	crc16
	mov	c,h		;init checksum in c to zero
	LXI	H,80H

SENDC	MOV	A,M
	CALL	SEND
	call	calCrc		;update CRC
	INX	H
	MOV	A,H
	CPI	1		;DONE WITH SECTOR?
	JNZ	SENDC

; Send checksum or CRC based on crcFlag

	lda	crcFlag		;crc or checksum?
	ora	a
	jz	sndCsum		;flag clear = checksum

	lda	crc16+1		;a=high byte of CRC
	call	SEND		;send it
	lda	crc16		;a=low byte of crc
	jmp	sndSkip		;skip next instruction	

sndCsum	mov	a,c		;send the checksum byte

sndSkip	call	SEND

;GET ACK ON SECTOR

	MVI	B,4		;WAIT 4 SECONDS MAX
	CALL	RECV
	JC	REPTB		;TIMEOUT, SEND AGAIN

;NO TIMEOUT SENDING SECTOR

	CPI	ACK		;ACK RECIEVED?
	JZ	SENDB		;..YES, SEND NEXT SECT

	cpi	ctrlc		;control-c to abort?
	jz	abort

	JMP	REPTB		;PROBABLY NAK - TRY AGAIN
;
;
; S U B R O U T I N E S
;
;OPEN FILE
OPEN$FILE LXI	D,FCB
	MVI	C,OPEN
	CALL	BDOS
	INR	A		;OPEN OK?
	RNZ			;GOOD OPEN

	CALL	ERXIT
	DB	CR,LF,'Can''t Open File',CR,LF,'$'

; - - - - - - - - - - - - - - -
;EXIT PRINTING MESSAGE FOLLOWING 'CALL ERXIT'
ERXIT	POP	D		;GET MESSAGE
	MVI	C,PRINT
	CALL	BDOS		;PRINT MESSAGE

	LHLD	STACK		;GET ORIGINAL STACK
	SPHL			;RESTORE IT
	RET			;--EXIT-- TO CP/M

; - - - - - - - - - - - - - - -
;MODEM RECV
;-------------------------------------
RECV	PUSH	D		;SAVE
MSEC	lxi	d,(124shl 8)	;63 cycles, 8.064ms/wrap*124=1s (2MHz)

MWTI	
#if defined(USBDATA)
	IN	USBSTAT		;(10)
	ANI	080h		;(7)
	JZ	MCHAR		;(10) GOT CHAR
#else
	IN	16		;(10)
	ANI	001h		;(7)
	JNZ	MCHAR		;(10) GOT CHAR
#endif

; no character present, decrement timeout

	cpi	0		;(7) waste some time
	cpi	0		;(7) waste some time
	DCR	E		;(5) COUNT DOWN
	JNZ	MWTI		;(10) FOR TIMEOUT

	DCR	D		;do msb every 256th time
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

SENDW	
#if defined(USBDATA)
	IN	USBSTAT
	ANI	040h
	JNZ	SENDW
#else
	IN	16
	ANI	02h
	JZ	SENDW
#endif

	POP	PSW		;GET CHAR

#if defined(USBDATA)
	OUT	USBDATA
#else
	OUT	17
#endif
	CPI	0FFh
	JNZ	snddone
#if defined(USBDATA)
        OUT	USBDATA		; send second 0xFF to BIOS
#else
        OUT	17		; send second 0xFF to BIOS
#endif
snddone	RET

;
;FILE READ ROUTINE
;
READ$SECTOR:
	LXI	D,FCB
	MVI	C,READ
	CALL	BDOS
	ORA	A
	RZ

	DCR	A		;EOF?
	JNZ	RDERR

;EOF

	XRA	A
	STA	ERRCT

SEOT	MVI	A,EOT
	CALL	SEND
	MVI	B,3		;WAIT 3 SEC FOR TIMEOUT
	CALL	RECV
	JC	EOTTOT		;EOT TIMEOUT

	CPI	ACK
	JZ	XFER$CPLT

;ACK NOT RECIEVED

EOTERR	LDA	ERRCT
	INR	A
	STA	ERRCT
	CPI	ERRLMT
	JC	SEOT

	CALL	ERXIT
	db	CR,LF,LF
	db	'No ACK received on EOT, but transfer is complete.',CR,LF,'$'

;
;TIMEOUT ON EOT
;
EOTTOT	JMP	EOTERR
;
;READ ERROR
;
RDERR	CALL	ERXIT
	DB	CR,LF,'File Read Error',CR,LF,'$'

;DONE - CLOSE UP SHOP

XFER$CPLT:
	CALL	ERXIT
	DB	CR,LF,LF,'Transfer Complete',CR,LF,'$'

abort	call	erxit
	DB	CR,LF,LF,'Transfer Aborted',CR,LF,'$'

;-----------------------------------------------------------------------------
; calCrc - update the 16-bit CRC with one more byte. 
;    (Copied from M. Eberhard)
; On Entry:
;   a has the new byte
;   crc16 is current except this byte
; On Exit:
;   crc16 has been updated
;   Trashes a,de
;-----------------------------------------------------------------------------
calCrc	push	b		;save bc, hl
	push	h
	lhld	crc16		;get CRC so far
	xra	h		;XOR into CRC top byte
	mov	h,a
	lxi	b,1021h		;bc=CRC16 polynomial
	mvi	d,8		;prepare to rotate 8 bits

; do 8 bit shift/divide by CRC polynomial

cRotLp	dad	h		;16-bit shift
	jnc	cClr		;skip if bit 15 was 0

	mov	a,h		;CRC=CRC xor 1021H
	xra	b
	mov	h,a
	mov	a,l
	xra	c
	mov	l,a

cClr	dcr	d
	jnz	cRotLp		;rotate 8 times

; save the updated CRC and exit

	shld	crc16		;save updated CRC
	pop	h		;restore hl, bc
	pop	b
	ret

;-----------------------------------------
;  messages
;-----------------------------------------

mRcv	db	'Start XMODEM file receive now...$'

mHelp	db	CR,LF
	db	'DSPUT ver 1.2a for Disk-over-serial CPM',CR,LF
	db	LF
	db	'Transmits a file to a PC through the s100computers.com',CR,LF
	db	'Serial IO Board USB serial port',CR,LF
	db	'using the XMODEM protocol.',CR,LF
	db	LF
	db	'Usage: DSPUT file.ext',CR,LF,'$'

; Data Area

	DS	40	;STACK AREA
STACK	DS	2	;STACK POINTER
SECTNO	DS	1	;CURRENT SECTOR NUMBER 
ERRCT	DS	1	;ERROR COUNT
crcFlag	ds	1	;non-zero if using CRC
crc16	ds	2	;computed crc

;
; BDOS EQUATES (VERSION 2)
;
RDCON	EQU	1
WRCON	EQU	2
PRINT	EQU	9
CONST	EQU	11	;CONSOLE STAT
OPEN	EQU	15	;0FFH=NOT FOUND
CLOSE	EQU	16	;   "	"
SRCHF	EQU	17	;   "	"
SRCHN	EQU	18	;   "	"
ERASE	EQU	19	;NO RET CODE
READ	EQU	20	;0=OK, 1=EOF
WRITE	EQU	21	;0=OK, 1=ERR, 2=?, 0FFH=NO DIR SPC
MAKE	EQU	22	;0FFH=BAD
REN	EQU	23	;0FFH=BAD
STDMA	EQU	26
BDOS	EQU	5
REIPL	EQU	0
FCB	EQU	5CH	;SYSTEM FCB
PARAM1	EQU	FCB+1	;COMMAND LINE PARAMETER 1 IN FCB
PARAM2	EQU	PARAM1+16	;COMMAND LINE PARAMETER 2
	END
