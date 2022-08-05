
;	Bootstrap code to load tape file into 0x3F00
;       Modified by Don Barber, May 2022

USBSTAT	equ	0AAh
USBDATA	equ	0ACh

	org	0h

#if defined(USBDATA)
#else
        MVI     A,3             ; RESET 6850
        OUT     16              ; PROGRAM FOR 8 BITS
        MVI     A,15H           ; 1STOP,NOPARITY, 16X CLOCK
                                ; NOTE: 2 STOP BITS=11H
        OUT     16
#endif

init:   
        lxi H, 03FC2H

loop:   lxi SP, stack   ; initialize the stack pointer
#if defined(USBDATA)
        in USBSTAT      ; Look for incoming character
        rlc	   ; rotate status bit 7 into carry (0 is byte available)
        rc         ; Loop if status bit is 1
        in USBDATA  ; get the character
#else
	in 16
	rrc        ; rotate status bit 1 into carry (1 is byte available)
	rnc	   ; loop if status bit is 0
	in 17
#endif

        cmp L       ; Is it the same as the value in L?
        rz          ; yes - ignore it and loop back to get another char
        dcr L       ; no - decrement the counter in L
        mov M, A    ; store the received character in RAM @ HL
        rnz         ; loop to get another until L = 0 
        pchl        ; jump to the start of the program we just read.

stack:  dw loop     ; prime the stack with the 
                    ; address of the top of the loop.

