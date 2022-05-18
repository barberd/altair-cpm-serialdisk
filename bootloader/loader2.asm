;
; 
;	Originally disassembled from DBL tape file
;       Modified for disk-over-serial by Don Barber, May 2022
;
	org	3f00h
;
	di
	lxi     sp,4000h
start:	
	call	inbyte
	cpi	03Ch
	jz	loadb  ; load data block
	cpi	078h
	jnz	start  ; if not data block or jump block, keep going
	call	inbyte ; this is a jump block - so load into c and l
	mov	c,a	
	call	inbyte
	mov	l,c
	mov	h,a
flushlp:in	0AAh	;after reading block suck everything off serial until buffer is empty
	ani	080h
	jnz	flshdn
	in	0ACh
	jmp	flushlp
flshdn:	pchl	       ; swap pc and hl to jump to new code
;
loadb
	call	inbyte 
	mov	c,a	; first byte is size of record
	mvi	b,0     ; initiate checksum
	call	inbyte  ; load low byte of load address
	mov	e,a
	call	inbyte  ; load high byte of load address
	mov	d,a
loadblp:mov	a,d     
	cpi	3fh     ; make sure not loading on top of self
	mvi	a,4fh   ; 'O
	jz	errhand
	call	inbyte  ; bring in next byte
	xchg		
	mov	m,a     ; move it to memory
	cmp	m	; make sure its there
	mvi	a,4dh   ; 'M
	jnz	errhand ;
	inx	h       ; move to next byte
	xchg
	dcr	c       ; decrement counter
	jnz	loadblp   ; loop until done
	mov	c,b     
	call	inbyte  ; bring in checksum
	cmp	c	; check checksum
	jz	start   ; done 
	mvi	a,43h   ; 'C if checksum fails, fall through to error
	
errhand:sta	0000h         ; initiatiate error; store a into 00h
	shld	0001h	      ; store h and l into 01h and 02h
	ei
errlp:	out	0ACh
	hlt

inbyte:	in	0AAh
	ani	080h
	jnz	inbyte
	in	0ACh
	push	psw
	add	b	; add to checksum
	mov	b,a	; store checksum back in b register
	pop	psw
	ret

	end

