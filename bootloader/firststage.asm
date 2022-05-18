
;	Bootstrap code to load tape file into 0x3F00
;       Modified by Don Barber, May 2022


	org	0h

init:   
        lxi H, 03F70H

loop:   lxi SP, stack   ; initialize the stack pointer
        in 0AAh      ; Look for incoming character
        rlc	   ; rotate status bit 7 into carry (0 is byte available)
        rc         ; Loop if status bit is 1

        in 0ACh      ; get the character
        cmp L       ; Is it the same as the value in L?
        rz          ; yes - ignore it and loop back to get another char
        dcr L       ; no - decrement the counter in L
        mov M, A    ; store the received character in RAM @ HL
        rnz         ; loop to get another until L = 0 
        pchl        ; jump to the start of the program we just read.

stack:  dw loop     ; prime the stack with the 
                    ; address of the top of the loop.

