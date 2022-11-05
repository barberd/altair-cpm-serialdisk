; USER AREA for CP/M2 on Altair.
; Version 5.0 of July 23, 1981.

; Copyright (C) 1981 Lifeboat Associates

; Modified by Don Barber to do Disk-over-Serial, May 2022

; This USER AREA is identical to that produced by
; CONFIG.COM Ver 5.x using configurations 0 thru 8
; except for port values and initialization strings.

; It may be used as is or as a prototype for
; your own drivers.  Two pages (512 bytes) are
; available for your custom I/O routines.

; The USER AREA contains a standard CONSOLE driver
; and PRINTER driver with a choice of handshaking type.
; Handshaking may be ETX/ACK, XON/XOFF or NONE.
; Printer may send 0-256 nulls after carriage return.
; The PUNCH and READER routines go to the console.

; The specific console ports and initialization strings
; will depend on the terminal number selected.
; Terminals 0 thru 7 are for specific I/O boards.

; CONFIG terminal #8 will configure for non standard
; console ports when the values for equates "1" thru "8"
; are placed in the data table at 130H together with
; initialization string if needed at "S" and length at "L".

; Type "CONFIG P<cr>" and answer console questions to
; install printer equates "9" thru "J" and init string "S".


; Change MSIZE to the desired CP/M memory size in K.
MSIZE	EQU	48		; Distribution size


; These equates are automatically changed by MSIZE.
BIOS	EQU (MSIZE*1024)-900H	; Memory location of BIOS
USER	EQU	BIOS+500H	; and of this USER AREA
OFFSET	EQU	2580H-USER	; To overlay SYSGEN image

; Misc standard equates.
IOBYT	EQU	3		; Storage location
CR	EQU	0DH		; Carriage return.
LF	EQU	0AH		; Line feed.
BS	EQU	08H		; Back space.

; Hardware equates for Altair 88-2SIO using
; active HIGH hardware as used in CONFIG.COM Terminal #0.

; Change to the appropriate values for your I/O hardware.
; See the instructions accompanying your I/O board for
; the correct ports, flags and initialization code.

; Set hardware sense flags xxxFLG as follows:
;	Active HIGH bits to 1, active LOW to 0.
;	Usually xxxFLG = xxxMSK if active HIGH.
;	or	xxxFLG = 0	if active LOW.

; Hardware equates for console input (TTY).
TISPT	EQU	16		; "1" TTY input status port
TDAMSK	EQU	1		; "2" Data available mask
TDAFLG	EQU	1		; "3" Hardware active HIGH
TDIPT	EQU	17		; "4" TTY data input port

; Hardware equates for console output (TTY).
TOSPT	EQU	16		; "5" TTY output status port
TBEMSK	EQU	2		; "6" Tx buffer empty mask
TBEFLG	EQU	2		; "7" Hardware active HIGH
TDOPT	EQU	17		; "8" TTY data output port

; Hardware equates for printer output (PTR).
POSPT	EQU	18		; "9" PTR output status port
PBEMSK	EQU	2		; "A" Tx buffer empty mask
PBEFLG	EQU	2		; "B" Hardware active HIGH
PDOPT	EQU	19		; "C" PTR data output port

; Hardware equates for printer handshaking (PTR input).
; Usually same ports as printer output with different MSK.
PISPT	EQU	18		; "D" PTR input status port
PDAMSK	EQU	1		; "E" Data available mask
PDAFLG	EQU	1		; "F" Hardware active HIGH
PDIPT	EQU	19		; "G" PTR input data port

; Handshaking equates.
ETX	EQU	'C'-40H		;    Send ETX after a buffer
ACK	EQU	'F'-40H		;    and wait for printers ACK
BUFLEN	EQU	127		;    Buffer length for ETX/ACK
XOFF	EQU	'S'-40H		;    Printer says stop
XON	EQU	'Q'-40H		;    Printer ready for data

; HAND is type of handshaking which can be 0FFH for NONE,
; 6 (ACK) for ETX/ACK or 11H (XON) for XON/XOFF.
HAND	EQU	0FFH		; "H" Type of handshaking

; DEFIOB is initial IOBYT if used.
; 80H sets printer to LPT: device, 0 sets to TTY:.
; Use STAT.COM can modify IOBYT in running CP/M.
DEFIOB	EQU	0		; "I" Default IOBYT

; NULLS is number of nulls sent after carriage return
; to allow printer time to return to left margin.
NULLS	EQU	0		; "J" Printer nulls

;USBSTAT equ     0AAh
;USBDATA equ     0ACh

	ORG	USER		; Start of USER AREA

; JUMP TABLE - Jumps MUST remain here in same order.
CINIT	JMP	CINITR		; Cold boot init
WINIT	JMP	WINITR		; Warm boot init
CONST	JMP	UCONST		; Console status
CONIN	JMP	UCONIN		; Console input
CONOUT	JMP	UCONOUT		; Console output
LIST	JMP	ULIST		; Printer output
PUNCH	JMP	UCONOUT		; Punch output to console
READER	JMP	UCONIN		; Reader input to console
LISTST	JMP	ULISTST		; Printer status

; This 8 byte data area used externally MUST remain.
LENUA:	DW	USRLEN		; Length of USER AREA
USRIOB:	DB	DEFIOB		; "I" Initial IOBYT
HSTYPE:	DB	HAND		; "H" Handshaking type
NULLOC:	DB	NULLS		; "J" Printer nulls
	DB	0,0,0		; Reserved

; These routines use IOBYT to select CP/M CONSOLE and LIST.

UCONST:
	; Select CP/M CONSOLE status routine.
	LDA	IOBYT
	CALL	DEVSEL		; Select device from table.
	DW	TTYIST		; TTY:
	DW	PTRIST		; CRT:
	DW	TTYIST		; BAT:
	DW	TTYIST		; UC1:

UCONIN:
	; Select CP/M CONSOLE input routine.
	LDA	IOBYT
	CALL	DEVSEL		; Select device from table
	DW	TTYIN		; TTY: is normal console.
	DW	PTRIN		; CRT: uses printer driver.
	DW	TTYIN		; BAT:
	DW	TTYIN		; UC1:

UCONOUT:

	; Select CP/M CONSOLE output routine.
	LDA	IOBYT
	CALL	DEVSEL		; Select device from table
	DW	TTYOUT		; TTY:
	DW	PTROUT		; CRT:
	DW	TTYOUT		; BAT:
	DW	TTYOUT		; UC1:

ULIST:
	; Select CP/M LIST output routine.
	LDA	IOBYT
	RLC			; Rotate LIST selection
	RLC			; bits to 0,1
	CALL	DEVSEL		; Select device from table.
	DW	TTYOUT		; TTY: goes to console.
	DW	PTROUT		; CRT: uses printer driver.
	DW	LPTOUT		; LPT: uses handshaking.
	DW	TTYOUT		; UL1:

ULISTST:
	; Select CP/M LIST status routine.
	LDA	IOBYT
	RLC			; Rotate LIST selection
	RLC			; bits to 0,1
	CALL	DEVSEL		; Select device from table.
	DW	TTYOST		; TTY:
	DW	PTROST		; CRT:
	DW	LPTST		; LPT:
	DW	TTYOST		; UL1:

DEVSEL:
	; Select routine from table of caller.
	ANI	3		; Mask IOBYT and
	RLC			; mult times 2.
	MOV	E,A		; Put index into
	MVI	D,0		; DE register.
	POP	H		; Get addr of table
	DAD	D		; and add index.
	MOV	E,M		; Get addr of routine
	INX	H		; into
	MOV	D,M		; DE first,
	XCHG			; then put into HL
	PCHL			; and transfer control.

; Console Physical Drivers

PTRIST:
TTYIST:
	; Console input status routine.
	; Return 0FFH if char ready, 0 if not.
#if defined(USBDATA)
	IN	USBSTAT
	ANI	80H
	JNZ	NOCHARI		; No key was pressed
	MVI	A,0FFH		; Char is ready
	RET
NOCHARI	MVI	A,0
	RET
#else
	XRA     A
        IN      TISPT           ; "1" Read status port
        CMA                     ; Adjust sense
        ANI     TDAMSK          ; "2" Mask status bits
        XRI     TDAFLG          ; "3" Hardware sense
        RZ                      ; No key was pressed
        MVI     A,0FFH          ; Char is ready
        RET
#endif

TTYIN:
	; Console input char to register A.
#if defined(USBDATA)
	CALL	TTYIST		; Is char ready?
	JNZ	TTYIN		; Not yet
	IN	USBDATA
	ANI	7FH		; Strip parity
	RET
#else
	CALL    TTYIST          ; Is char ready?
        JZ      TTYIN           ; Not yet
        XRA     A
        IN      TDIPT           ; "4" Read data port
        ANI     7FH             ; Strip parity
        RET
#endif

PTROST:
TTYOST:
	; Console output status routine.
	; Ret 0FFH if ready for output, 0 if not.
#if defined(USBDATA)
	IN	USBSTAT
	ANI	40H
	JNZ	NOCHARO
	MVI	A,0FFH		; Ready for output
	RET
NOCHARO:MVI	A,0
	RET
#else
        XRA     A
        IN      TOSPT           ; "5" Read status port
        CMA                     ; Adjust sense
        ANI     TBEMSK          ; "6" Mask status bits
        XRI     TBEFLG          ; "7" Hardware sense
        RZ                      ; Not ready
        MVI     A,0FFH          ; Ready for output
        RET
#endif

RAWOUT:
	; Console output char from register C.
#if defined(USBDATA)
	CALL	TTYOST		; Ready to output?
	JNZ	RAWOUT		; Wait until not busy
	MOV	A,C		; Char into accumulator
	OUT	USBDATA		; "8" Output char
	RET
#else
        CALL    TTYOST          ; Ready to output?
        JZ      TTYOUT          ; Wait until not busy
        MOV     A,C             ; Char into accumulator
        OUT     TDOPT           ; "8" Output char
        RET
#endif

TTYOUT:
	CALL	RAWOUT
	;TODO check if FFH and send a second if so
	CPI	0FFh
	JNZ	NOBREAK
	CALL	RAWOUT
NOBREAK RET

PTROUT:
	; Printer output char from register C.
	PUSH	B
	MVI	C,0FFh
	CALL	RAWOUT
	MVI	C,1
	CALL	RAWOUT
	POP	B
	CALL	RAWOUT
	RET

PTRIN:
	MVI	A,0		;dummy, no printer input
	RET

NULLOUT:
	; Null handler for printer output.
	CALL	PTROUT		; Print the char.
	CPI	CR		; Was it a CR?
	RNZ			; Finished if not.
	LDA	NULLOC		; Get nr of nulls to send
	MOV	B,A		; into B reg to count.
	ORA	A		; We are finished
	RZ			; if NULLS = 0.
	MVI	C,0		; This is a null.
NLOOP:
	CALL	PTROUT		; Print a null,
	DCR	B		; decrement count
	JNZ	NLOOP		; and loop until 0.
	MVI	C,CR		; Restore CR to C.
	RET

; LPT logical printer driver does handshaking
; and calls PTR physical drivers. Reg C preserved.

LPTST:
	; LPT logical status routine.
	; Return 0FFH if ready, 0 if busy.
	CALL	PTROST		; Is hardware busy?
	RZ			; Yes
	LDA	HSTYPE		; Should be 0FFH, ACK or XON
	MOV	B,A		; Save type.
	CPI	ACK		; ETX/ACK?
	JZ	PROTO		; Yes, on to handler
	CPI	XON		; XON/XOFF?
	MVI	A,0FFH		; No handshaking in use
	RNZ			; and hardware is ready.
PROTO:
	; Mark ready if ACK rvcd when ETX/ACK in use
	; or respond to XON/XOFF.
	CALL	PTRIST		; Is hs char ready?
	CNZ	PTRIN		; Yes, get it.
	CMP	B		; Proper go ahead char?
	JZ	READY		; Yes, must be ACK or XON.
	CPI	XOFF		; XOFF rcvd?
	JNZ	NLEGAL		; No, ignore char.
	INR	B		; Make XON
	INR	B		; into XOFF to make sure
	CMP	B		; XON/OFF in use.
	JZ	BUSY		; XOFF properly rcvd.
NLEGAL:
	LDA	LPTFLG		; Not legal hs char so
	ORA	A		; return with prev status.
	RET
READY:
	MVI	A,0FFH		; Mark ready
	STA	LPTFLG		; at software flag
	ORA	A		; and return NZ.
	RET

LPTOUT:
	; LPT output routine from register C.
	CALL	LPTST		; Get status
	JZ	LPTOUT		; Wait until ready
	CALL	NULLOUT		; Then print char
	LDA	HSTYPE		; Load protocol type
	CPI	ACK		; Using ETX/ACK?
	RNZ			; No, exit.
	; Process ETX/ACK protocol here.
	; Check for ESCAPE sequence first.
	LXI	H,BUFCNT
	MOV	A,C		; Was last char
	CPI	1BH		; an ESCAPE?
	JNZ	ETXOUT		; No
	MOV	A,M		; Get ETX count
	CPI	4		; If over 3 left
	JNC	ETXOUT		; process normally.
	MVI	M,3		; Send 3 char before ETX.
ETXOUT:
	; Count down until BUFLEN characters sent,
	; then send ETX and wait for printers ACK.
	DCR	M		; Count down but
	RNZ			; do nothing until 0
	MVI	M,BUFLEN	; Then reset count
	MVI	C,ETX		; and send ETX 
	CALL	PTROUT		; to printer.
BUSY:
	XRA	A		; Mark busy
	STA	LPTFLG		; at software flag
	RET			; and ret Z set.

LPTINIT:
	; Initialize printer driver.
	MVI	A,0FFH		; Mark printer ready
	STA	LPTFLG		; at software flag.
	MVI	A,BUFLEN	; Initialize
	STA	BUFCNT		; buffer count.
	RET

	; Handshaking variables
BUFCNT:	DB	0		; ETX/ACK buffer count.
LPTFLG:	DB	0		; LPT status flag.
				; Ready=0FFH, Busy=0

WINITR:
	; Any warm boot initialization goes here.
	DB	0,0,0		; Patch room
	RET

CINITR:
	; Hardware initialization on cold boot goes
	; here if needed.  Make sure it ends with a RET.
	LDA	USRIOB		; Load initial IOBYT
	STA	IOBYT		; and store.
	CALL	LPTINIT		; Init printer driver.
	DB	0,0,0		; Patch room

	; Initialization string for terminal #8
	; of length "L" usually begins at "S" below.
	; In this case, initialization is for 88-2SIO.
STRING:				; "S"

#if defined(USBDATA)

#else
	MVI	A,3		; RESET 6850
	OUT	16		; PROGRAM FOR 8 BITS
	OUT	18
	MVI	A,15H		; 1STOP,NOPARITY, 16X CLOCK
				; NOTE: 2 STOP BITS=11H
	OUT	16
	OUT	18
	IN	17		; CLEAR
	IN	17		; INPUT
	IN	19		; BUFFER
	IN	19
#endif
	RET			; DONE

STRLEN	EQU	$-STRING	; "L"

USRLEN	EQU	$-USER		; Length of USER AREA

