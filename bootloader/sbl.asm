;***************************************************************
;*                                                             *
;* Altair Disk Boot Loader                                     *
;* Version 4.1                                                 *
;*                                                             *
;* DISASSEMBLED BY MARTIN EBERHARD, 4 MARCH 2012               *
;* FROM AN EPROM WITH A PRINTED LABEL THAT SAID 'DBL 4.1'.     *
;* THIS EPROM WAS FOUND SOCKETED IN A MITS TURNKEY BOARD.      *

;  Modified by Don Barber 2022
;  To do disk-over-serial from a PC instead

;*                                                             *
;* ONCE IN RAM, THIS PROGRAM READS FROM THE DISK STARTING AT   *
;* TRACK 00, SECTOR 00. SECTOR DATA (WHICH INCLUDES THE ACTUAL *
;* DATA PAYLOAD, AS WELL AS HEADER AND TRAILER BYTES) IS FIRST *
;* LOADED INTO A RAM BUFFER IN MEMORY JUST AFTER THIS PROGRAM. *
;* THE DATA PAYLOAD THEN GETS MOVED INTO MEMORY STARTING AT    *
;* ADDRESS 0000H (DMAADR), CHECKING THE CHECKSUM ALONG THE WAY.*
;*                                                             *
;* EACH SECTOR HAS A 16-BIT VALUE IN ITS HEADER THAT IS THE    *
;* BYTE COUNT FOR THE FILE TO LOAD - THIS MANY BYTES ARE READ  *
;* FROM THE DISK. WHEN DONE (ASSUMING NO ERRORS), THIS PROGRAM *
;* JUMPS TO 0000 (DMAADR), TO EXECUTE THE LOADED CODE.         *
;*                                                             *
;* SECTORS ARE INTERLEAVED 2:1 ON THE DISK, THE EVEN SECTORS   *
;* ARE READ FIRST, AND THEN THE ODD SECTORS.                   *
;*                                                             *
;* WHEN DATA IS MOVED FROM THE RAM BUFFER TO ITS FINAL MEMORY  *
;* LOCATION, IT IS READ BACK TO VERIFY CORRECT WRITE. ANY      *
;* FAILURE WILL RESULT IN AN ABORT WITH A 'M' ERROR.           *
;*                                                             *
;* ANY READ ERRORS (EITHER A CHECKSUM ERROR OR AN INCORRECT    *
;* SYNC BYTE) WILL CAUSE A RETRY OF THE SECTOR READ. AFTER     *
;* 10H RETRIES, THIS PROGRAM WILL ABORT WITH A 'C' ERROR.      *
;*                                                             *
;* IF THE PROGRAM ABORTS BECAUSE OF AN ERROR, IT WILL ALSO     *
;* TURN THE FRONT PANEL 'INTE' LED ON.                         *
;*                                                             *
;*   DISK SECTOR FORMAT               BUFFER ADDRESS           *
;*     1 BYTE:   ?                       2CEBH                 *
;*     2 BYTES: 16-BIT FILE-SIZE         2CECH                 *
;*   128 BYTES: DATA PAYLOAD             2CEEH                 *
;*     1 BYTE:  SYNC (FFH)               2D6EH                 *
;*     1 BYTE:  CHECKSUM                 2D6FH                 *
;*     1 BYTE:  ?                        2D70H                 *
;*                                                             *
;***************************************************************

DMAADR	EQU	0000H		;JUMPS HERE ONCE LOAD IS DONE
RETRIES	EQU	10H		;MAX NUMBER OF RETRIES

SENSE	EQU	0FFH		;FRONT PANEL SENSE SWITCHES

; USB REGISTERS

;USBDATA	EQU	0ACH
;USBSTAT	EQU	0AAH

;***************************************************************
; CODE MOVER: MOVES LOADER INTO LOW MEMORY
;***************************************************************

	;ORG	0FF00H
	ORG	02C00H

	DI			;FRONT PANEL INTE LED OFF
				;BECAUSE NO ERROR YET.

;---------------------------------------------------------------
; INITIALIZATION
;---------------------------------------------------------------

;SET UP THE STACK IN MEMORY AFTER THIS PROGRAM AND AFTER
;THE DISK DATA BUFFER

	LXI	SP,STACK	;SET UP STACK

	LXI     D,DMAADR        ;PUT DISK DATA STARTING HERE

;WAIT FOR CONTROLLER TO BE ENABLED (INCLUDING DOOR SHUT)

;---------------------------------------------------------------
; READ DISK DATA UNTIL WE'VE READ AS MEANY BYTES AS INDICATED
; AS THE FILE SIZE IN THE SECTOR HEADERS, AND PUT IT AT (DE)
;---------------------------------------------------------------

	MVI	A,0
	STA	TRACK
NXTRAC:	MVI	B,0		;INITIAL SECTOR NUMBER

NXTSEC:	MVI	A,RETRIES	;INITIALIZE RETRY COUNTER

;READ ONE SECTOR INTO THE BUFFER
; ON ENTRY:
;    A = RETRIES
;    B = SECTOR NUMBER
;   DE = MEMORY ADDRESS FOR SECTOR DATA

RDSECT:	

	PUSH	PSW		;SAVE RETRY COUNTER
	PUSH	D		;SAVE DEST ADDRESS FOR RETRY
	PUSH	B		;SAVE B=SECTOR NUMBER
	PUSH	D		;SAVE DEST ADDRESS FOR MOVE
	LXI	D,8089H		;E=BYTES PER SECTOR, D=JUNK
	LXI	H,BUFFER	;HL POINTS TO DISK BUFFER

#if defined(USBDATA)
OWAIT1:	IN	USBSTAT		;READY TO WRITE?
	ANI	40H		;READY
	JNZ	OWAIT1
	MVI	A,0FFH		;send not-the-console command
	OUT	USBDATA

OWAIT2:	IN	USBSTAT		;READY TO WRITE?
	ANI	40H		;READY
	JNZ	OWAIT2
	MVI	A,10H		;send disk read
	OUT	USBDATA

OWAIT3:	IN	USBSTAT		;READY TO WRITE?
	ANI	40H		;READY
	JNZ	OWAIT3
	XRA	A		;set disk 0
	OUT	USBDATA

OWAIT4:	IN	USBSTAT		;READY TO WRITE?
	ANI	40H		;READY
	JNZ	OWAIT4
	LDA	TRACK	;set track num
	OUT	USBDATA

OWAIT5:	IN	USBSTAT		;READY TO WRITE?
	ANI	40H		;READY
	JNZ	OWAIT5
	MOV	A,B		;set sector
	OUT	USBDATA	

RWAIT:	IN	USBSTAT		;DATA READY TO READ?
	ANI	80H		;READY
	JNZ	RWAIT

	IN	USBDATA		;GET STATUS BYTE
#else
OWAIT1:	IN	16		;READY TO WRITE?
	ANI	02H		;READY
	JZ	OWAIT1
	MVI	A,0FFH		;send not-the-console command
	OUT	17

OWAIT2:	IN	16		;READY TO WRITE?
	ANI	02H		;READY
	JZ	OWAIT2
	MVI	A,10H		;send disk read
	OUT	17

OWAIT3:	IN	16		;READY TO WRITE?
	ANI	02H		;READY
	JZ	OWAIT3
	XRA	A		;set disk 0
	OUT	17

OWAIT4:	IN	16		;READY TO WRITE?
	ANI	02H		;READY
	JZ	OWAIT4
	LDA	TRACK	;set track num
	OUT	17

OWAIT5:	IN	16		;READY TO WRITE?
	ANI	02H		;READY
	JZ	OWAIT5
	MOV	A,B		;set sector
	OUT	17	

RWAIT:	IN	16		;DATA READY TO READ?
	ANI	01H		;READY
	JZ	RWAIT

	IN	17		;GET STATUS BYTE
#endif
	ORA	A
	JZ	DWAIT		;IF NOT 0 THEN ERROR
	POP	D		;clean up stack
	POP	B		;and prepare for error
	JMP	BADSEC

;---------------------------------------------------------------
;LOOP TO READ 137 BYTES FROM THE 'DISK' over serial AND PUT INTO THE RAM
; BUFFER. 
;---------------------------------------------------------------
DWAIT:	
#if defined(USBDATA)
	IN	USBSTAT		;DATA READY?
	ANI	80H		;READY
	JNZ	DWAIT
	IN	USBDATA		;GET A BYTE OF DISK DATA
#else
	IN	16		;DATA READY?
	ANI	01H		;READY
	JZ	DWAIT
	IN	17		;GET A BYTE OF DISK DATA
#endif

	MOV	M,A		;PUT IT IN MEMORY
	INX	H		;BUMP MEMORY POINTER
	DCR	E		;BUMP & TEST BYTE COUNT		.
	JNZ	DWAIT		;AGAIN, UNLESS BYTE COUNT = 0
SECDON:

;---------------------------------------------------------------
; MOVE THE DATA TO ITS FINAL LOCATION, AND CHECK THE CHECKSUM AS
; WE MOVE THE DATA. ALSO VERIFY THE MEMORY WRITE.
;---------------------------------------------------------------
	POP	H			;RECOVER DEST ADDRESS
	LXI	D,BUFFER+3		;START OF DATA PAYLOAD
	LXI	B,0080H			;B=INITIAL CHECKSUM,
					;C=DATA BYTES/SECTOR

MOVLUP:	LDAX	D		;GET A BYTE FROM THE BUFFER		.
	MOV	M,A		;WRITE IT TO RAM
	CMP	M		;SUCCESSFUL WRITE TO RAM?
	JNZ	MEMERR		;NO: GIVE UP

	ADD	B		;COMPUTE CHECKSUM		.
	MOV	B,A

	INX	D		;BUMP SOURCE POINTER
	INX	H		;BUMP DESTINATION POINTER
	DCR	C		;NEXT BYTE
	JNZ	MOVLUP		;KEEP GOING THROUGH 128 BYTES


	LDAX	D		;THE NEXT BYTE MUST BE FF
	CPI	0FFH
	JNZ	RDDONE		;OTHERWISE IT'S A BAD READ

	INX	D		;THE NEXT BYTE IS THE CHECKSUM
	LDAX	D
	CMP	B		;MATCH THE COMPUTED CHECKSUM?

RDDONE:	POP	B		;RESTORE SECTOR NUMBER
	XCHG			;PUT MEMORY ADDRESS INTO DE
				;AND BUFFER POINTER INTO HL
	JNZ	BADSEC		;CHECKSUM ERROR OR MISSING FF?

	POP	PSW		;CHUCK OLD SECTOR NUMBER
	POP	PSW		;CHUCK OLD RAM ADDRESS
	LHLD	BUFFER+1	;GET FILE BYTE COUNT FROM HEADER
	CALL	CMP16		;COMPARE TO NEXT RAM ADDRESS
	JNC	DONE		;DONE IF ADDRESS > FILE SIZE

;---------------------------------------------------------------
; SET UP FOR NEXT SECTOR
; THE DISK HAS A 2:1 SECTOR INTERLEAVE - 
; FIRST READ ALL THE EVEN SECTORS, THEN READ ALL THE ODD SECTORS
;---------------------------------------------------------------
	INR	B		;BUMP SECTOR NUMBER BY 2
	INR	B
	MOV	A,B		;LAST EVEN OR ODD SECTOR ALREADY?
	CPI	20H
	JC	NXTSEC		;NO: KEEP READING

	MVI	B,1		;START READING THE ODD SECTORS
	JZ	NXTSEC		;UNLESS WE FINISHED THEM TOO

	LDA	TRACK
	INR	A		;Go to next track
	STA	TRACK

	JMP	NXTRAC		;BEGINNING OF THE NEXT TRACK

DONE:	JMP	DMAADR		;GO EXECUTE WHAT WE LOADED

;---------------------------------------------------------------
; SECTOR ERROR:
; RESTORE TO BEGINNING OF SECTOR AND SEE IF WE CAN RETRY
;---------------------------------------------------------------
BADSEC:	POP	D		;RESTORE MEMORY ADDRESS
	POP	PSW		;GET RETRY COUNTER
	DCR	A		;BUMP RETRY COUNTER
	JNZ	RDSECT		;NOT ZERO: TRY AGAIN

; FALL INTO SECERR

;---------------------------------------------------------------
;ERROR ABORT ROUTINE: WRITE ERROR INFO TO MEMORY AT 0, HANG
;FOREVER, WRITING A ONE-CHARACTER ERROR CODE TO ALL OUTPUT PORTS
; ENTRY AT SECERR PRINTS 'C', SAVES BUFFER POINTER AT 0001H
;   THE BUFFER POINTER WILL BE 2D6EH IF IT WAS A SYNCHRONIZATION
;   ERROR, AND IT WILL BE 2D6FH IF IT WAS A CHECKSUM ERROR
; ENTRY AT MEMERR PRINTS 'M', SAVES OFFENDING ADDRESS AT 0001H
; THE FRONT PANEL INTE LED GETS TURNED ON TO INDICATE AN ERROR.
;---------------------------------------------------------------
SECERR:	MVI	A,'C'		;ERROR CODE

	DB	01		;USE "LXI B" TO SKIP 2 BYTES

MEMERR: MVI	A,'M'		;MEMORY ERROR

	EI			;TURN FORNT PANEL INTE LED ON

	STA	DMAADR		;SAVE ERROR CODE AT 0000
	SHLD	DMAADR+1	;SAVE OFFENDING ADDRESS AT 0001

;HANG FOREVER, WRITING ERROR CODE (IN A) TO EVERY KNOWN PORT

#if defined(USBDATA)
	OUT	USBDATA		;WRITE ERROR CODE TO USB 
#else
	OUT	17		;WRITE ERROR CODE TO USB 
#endif

ERHANG:	JMP	ERHANG		;HANG FOREVER

;---------------------------------------------------------------
; SUBROUTINE TO COMPARE DE to HL
; C SET IF HL>DE
;---------------------------------------------------------------
CMP16:	MOV	A,D		;LOW BYTES EQUAL?
	CMP	H
	RNZ			;NO: RET WITH C CORRECT
	MOV	A,E		;HIGH BYTES EQUAL?
	CMP	L
	RET			;RETURN WITH RESULT IN C
TRACK:	DB	0
;---------------------------------------------------------------
;DISK BUFFER IN RAM RIGHT AFTER THE LOADER
;---------------------------------------------------------------
BUFFER:	DW	00H		;FILLS THE EPROM OUT WITH 00'S
;	DS	87H
;---------------------------------------------------------------
; AND FINALLY THE STACK, WHICH GROWS DOWNWARD
;---------------------------------------------------------------
;STSP:	DS	08H		;SPACE FOR STACK
STACK:	EQU	$+135+8

	END


