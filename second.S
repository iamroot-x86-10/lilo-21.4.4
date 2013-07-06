/* second.S  -  LILO second stage boot loader */

/* Copyright 1992-1998 Werner Almesberger. See file COPYING for details. */
/* LBA additions Copyright (C) 1999, John Coffman.  Use subject to the   */
/*  terms of the GNU public license agreement.                           */


#define LILO_ASM
#include "lilo.h"

#ifdef DEBUG
#define DBG_LREAD 1
#endif


#define UI_MAGIC 0xff		/* take input from keyboard */


	.text

	.globl	_main
	.org	0

_main:	jmp	start

	.org	6

! Boot device parameters. They are set by the installer.

sig:	.ascii	"LILO"
stage:	.word	STAGE_SECOND
version:.word	VERSION

	.org	CODE_START_2

start:	seg	ss		! use a COM port ?				
													!!DSC_OFF == BOOT_PARAMS_1->descr
	mov	dx,DSC_OFF-6+SSDIFF							!!BOOT_PARMAS_1->port의 값을 가져온다.
	sub	dl,#1
	jc	nocom		! no -> go on
	xor	ax,ax		! initialize the serial port
	xchg	al,dh
	push	ax
	push	dx
	int	0x14
	xor	ax,ax		! get the port address
	mov	ds,ax
	pop	bx
	shl	bx,1
	mov	dx,(bx+0x400)
	seg	cs		! keep it
	mov	slbase,dx
	pop	ax		! special baud rate test
	and	al,#0xe0
	cmp	al,#0x20	! 150 bps ?
	je	b19200		! yes -> set 19200 bps
	cmp	al,#0x60	! 600 bps ?
	jne	stdbps		! no -> continue
	mov	bx,#3		! 38400 bps
	jmp	spcbps
b19200:	mov	bx,#6		! 19200 bps
spcbps:	cli			! do not disturb ...
	add	dx,#3		! enable divisor latch access
	in	al,dx
	or	al,#0x80
	out	dx,al
	sub	dx,#3		! set new divisor
	xchg	al,bl
	out	dx,al
	inc	dx
	mov	al,bh
	out	dx,al
	inc	dx		! disable divisor latch access
	inc	dx
	mov	al,bl
	and	al,#0x7f
	out	dx,al
	inc	dx		! address Modem Control Reg.
	in	al,dx
	or	al,#3		! turn on DTR and RTS
	out	dx,al
	sub	dx,#4		! correct base address
	sti			! done
stdbps:	mov	cx,#32		! drain the queue (if any)
drain:	in	al,dx
	loop	drain
	add	dx,#5		! clear the status register
	in	al,dx
	mov	al,#13		! send "\r\nLI" to the serial port
	call	serdisp
	mov	al,#10
	call	serdisp
	mov	al,#0x4c
	call	serdisp
	mov	al,#0x49
	call	serdisp
	jmp	comcom		! proceed with the rest of "LILO"

nocom:
#ifndef LCF_NODRAIN
	mov	cx,#32		! drain type-ahead buffer ?
drkbd:	mov	ah,#1		! is a key pressed ?
	int	0x16
	jz	comcom		! no -> done
	xor	ah,ah		! get the key
	int	0x16
	loop	drkbd
#endif

comcom:	mov	al,#0x4c	! display an 'L'
	call	display
	xor	ax,ax		! get pointer to disk parameter table in DS:SI
	mov	ds,ax
	lds	si,0x78
#ifndef LCF_XL_SECS
	cmp	byte ptr (si+4),#9 ! okay ?
	ja	dskok		! yes -> do not patch
#endif
	push	cs		! get pointer to new area in ES:DI
	pop	es
	mov	di,#dskprm
	mov	cx,#6		! copy 12 bytes
	rep
	movsw
	seg	es		! patch number of sectors
#ifndef LCF_XL_SECS
	mov	byte ptr (di-8),#18
#else
	mov	byte ptr (di-8),#LCF_XL_SECS
#endif
	cli			! paranoia
	xor	ax,ax		! store new pointer
	mov	ds,ax
	mov	0x78,#dskprm
	mov	0x7a,es
	sti
dskok:	seg	cs		! clear the break flag
	mov	byte ptr break,#0
	call	instto		! get timer interrupt
	jmp	restrt		! get going

! Die

crshbrn:mov	al,#63		! display a question mark
	call	display
zzz:	jmp	zzz		! sit here forever

! Restart here after a boot error

restrt: mov	ax,cs		! adjust segment registers
	mov	ds,ax
	mov	es,ax
;;;	cli			! reset SP (we might have restarted with some
	mov	sp,#STACK	! data on the stack)
;;;	sti
	cmp	sig,#0x494c	! check that this is really loaded at the
				! right place ...
	jne	crshbrn
	cmp	sig+2,#0x4f4c
	jne	crshbrn
	cmp	stage,#STAGE_SECOND
	jne	crshbrn
	cmp	version,#VERSION
	jne	crshbrn
	mov	cmdbeg,#acmdbeg	! probably unattended boot
ldsc:
;;;	mov	al,#1		! load the descriptor table
	mov	bx,#DESCR
	seg	ss
	mov	cx,DSC_OFF+SSDIFF
	seg	ss
	mov	dx,DSC_OFF+2+SSDIFF
        seg     ss
	mov	al,DSC_OFF+4+SSDIFF     ;;;
	call	cread
	jc	fdnok		! error -> retry
;;;	mov	al,#1		! load the second sector
	mov	bx,#DESCR+512
	seg	ss
	mov	cx,DSC_OFF2+SSDIFF
	seg	ss
	mov	dx,DSC_OFF2+2+SSDIFF
        seg     ss                      ;;;
	mov	al,DSC_OFF2+4+SSDIFF    ;;;
	call	cread
	jc	fdnok		! error -> retry
	mov	si,#DESCR	! compute a checksum of the descriptor table
	mov	bx,#INIT_CKS
	cld
	mov	cx,#0x200
csloop:	lodsw
	xor	bx,ax
	loop	csloop
	or	bx,bx		! okay ?
	jnz	chkerr
	seg	ss		! load the keyboard translation table
	mov	cx,MSG_OFF+SSDIFF+7
	seg	ss
	mov	dx,MSG_OFF+SSDIFF+9
        seg     ss                      ;;;
	mov	al,MSG_OFF+SSDIFF+11    ;;;
	mov	bx,#KEYTABLE
;;;	mov	al,#1
	call	cread
	jc	fdnok
;;;	mov	al,#1		! load the default command line
	mov	bx,#DFLCMD
	seg	ss
	mov	cx,DFCMD_OFF+SSDIFF
	seg	ss
	mov	dx,DFCMD_OFF+2+SSDIFF
	seg	ss                      ;;;
	mov	al,DFCMD_OFF+4+SSDIFF   ;;;
	call	cread
	jc	fdnok		! error -> retry
	mov	bx,#DFLCMD
	cmp	word ptr (bx),#DC_MAGIC ! okay ?
	jne	bdcmag		! no -> do not write
#ifndef LCF_READONLY
	mov	word ptr (bx),#DC_MGOFF ! erase the magic number
;;;	mov	al,#1
	seg	ss
	mov	cx,DFCMD_OFF+SSDIFF
	seg	ss
	mov	dx,DFCMD_OFF+2+SSDIFF
        seg     ss                      ;;;
	mov	al,DFCMD_OFF+4+SSDIFF   ;;;
	call	cwrite
#endif
	jmp	dokay		! continue
bdcmag:	mov	byte ptr (bx+2),#0 ! disable the command line
	jmp	dokay		! go on
fdnok:	
#if     0
        xor	ax,ax		! reset FDC
	mov	dl,al
	int	0x13
#endif
	br	ldsc		! retry

! Checksum error

chkerr:	mov	al,#45		! display a minus sign
	call	display
sixfeet:jmp	sixfeet		! sit here forever

! List all known boot images

list:	mov	byte ptr (bx),#0 ! set EOL marker
	mov	bx,#crlf	! display a CRLF
	call	say
	mov	si,#DESCR+2	! list all images
	mov	cx,#IMAGES
	xor	dl,dl		! DL counts the images
lloop:	testb	(si),#0xff	! done ?
	jz	ldone		! yes
	mov	bx,si		! display the name
	call	say
	add	si,#MAX_IMAGE_NAME
	inc	dl		! count the image
	test	dl,#3		! inside line -> go on
	jnz	fill
	mov	bx,#crlf	! new line
	call	say
	jmp	imgdne		! next image
fill:	push	bx		! fill with spaces
	mov	al,#0x20
	call	display
	pop	bx
	inc	bx
	cmp	bx,si
	jbe	fill
imgdne:	add	si,#DESCR_SIZE-MAX_IMAGE_NAME
	loop	lloop		! next image
ldone:	test	dl,#3		! already at BOL ?
	jz	atbol		! yes -> no CRLF
	mov	bx,#crlf	! display a CRLF
	call	say
atbol:	br	iloop		! done

! Ready to process user input

dokay:	mov	bx,#ospc	! display 'O '
	call	say
	mov	ospc,#0		! disable the message
	mov	word ptr vgaovr,#VGA_NOCOVR ! disable VGA override
	mov	word ptr memlim,#0 ! no memory limit
	xor	ax,ax		! get the delay and disable further delays
	seg	ss
	xchg	ax,DSC_OFF-8+SSDIFF
	or	old_del,ax	! remember delay
	mov	nodfl,#iloop	! interactive prompt if falling through
	seg	ss		! enter boot prompt ?
	cmp	byte ptr DSC_OFF+15+SSDIFF,#0
	jne	extp		! yes -> check for external parameters
	mov	nodfl,#bfirst	! boot first image if falling through
	call	waitsh		! wait for a shifting key
	jc	iloop		! key pressed -> enter interactive mode

! Check for external parameters

extp:	seg	ss		! external parameters ?
	cmp	byte ptr EX_OFF+6,#EX_DL_MAG
	jne	noex		! no -> go on
	seg	ss		! clear flag
	mov	byte ptr EX_OFF+6,#0
	seg	ss		! load the signature pointer
	les	bx,EX_OFF
	seg	es		! "LI" ?
	cmp	(bx),#EX_MAG_L
	jne	noex		! no -> go on
	seg	es		! "LO" ?
	cmp	(bx+2),#EX_MAG_H
	jne	noex		! no -> go on
	seg	ss
	mov	si,EX_OFF+4	! pointer to the command line
	seg	es
	cmp	byte ptr (si),#0 ! empty ?
	je	iloop		! yes -> enter interactive mode
	jmp	niloop		! enter non-interactive mode

! No external parameters after timeout -> boot first image

noex:	push	cs		! restore ES
	pop	es
	mov	si,#DFLCMD+2	! default command line ?
	cmp	byte ptr (si),#0
	jne	niloop		! yes -> use it
	mov	ax,nodfl	! no idea how to tell as86 to do jmp (addr) :-(
	jmp	ax		! fall through


! Command input processor

iloop:	seg	ss		! message disabled ?
	cmp	MSG_OFF+SSDIFF,#0
	je	nomsg		! yes -> skip this
	mov	bx,#crlf	! move to a new line
	call	say
	seg	ss		! load the message file
	mov	cx,MSG_OFF+SSDIFF+2
	seg	ss
	mov	dx,MSG_OFF+SSDIFF+4
	mov	bx,#MAP
        seg     ss
	mov	al,MSG_OFF+SSDIFF+6
	call	sread
	call	loadfile
	mov	ax,#SYSSEG
	mov	ds,ax
	xor	bx,bx		! set the terminating NUL and disable further
				! messages
	seg	ss
	xchg	bx,MSG_OFF+SSDIFF
	mov	byte ptr (bx),#0
	xor	bx,bx		! display the message
	call	say
	push	cs		! restore segment registers
	pop	ds
	push	cs
	pop	es
nomsg:	mov	cmdbeg,#acmdbeg	! probably unattended boot
	mov	si,#usrinpm	! interactive mode
niloop:	mov	bx,#msg_p	! display boot prompt
	call	say
	mov	bx,#cmdline	! move cursor to the end of the line
clend:	mov	al,(bx)
	or	al,al		! at end ?
	jz	cledne		! yes -> go on
	push	bx		! display the character
	call	display
	pop	bx
	inc	bx		! next one
	jne	clend
cledne:	mov	byte ptr prechr,#32 ! character before command line is a space

! Input loop

input:	seg	es		! interactive mode ?
	cmp	byte ptr (si),#UI_MAGIC
	je	kbinp		! yes -> get keyboard input
	seg	es		! get non-interactive input
	mov	al,(si)
	inc	si
	jmp	gotinp		! go on
	
tolist:	br	list		! ...

kbinp:	mov	cx,#brto	! get a key
	call	getkey
gotinp:	cmp	al,#9		! TAB ?
	je	tolist		! yes -> list images
	cmp	al,#63		! "?" ?
	je	tolist		! yes -> list images
	or	al,al		! NUL ?
	je	nul		! yes -> go on
	cmp	al,#13		! CR ?
	je	cr		! yes -> go on
	cmp	al,#8		! BS ?
	je	todelch		! yes -> erase one character
	cmp	al,#127		! DEL ?
	je	todelch		! yes -> erase one character
	ja	input		! non-printable -> ignore it
	cmp	al,#21		! ^U ?
	je	todell		! yes -> erase the line
	cmp	al,#24		! ^X ?
	je	todell		! yes -> erase the line
	cmp	al,#32		! ignore non-printable characters except space
	jb	input
	ja	noblnk		! no space -> go on
	cmp	(bx-1),al	! second space in a row ?
	je	input		! yes -> ignore it
noblnk:	cmp	bx,#cmdline+CL_LENGTH ! at end of buffer ?
	je	input		! yes -> ignore
	mov	(bx),al		! store in the buffer
	inc	bx		! increment pointer
	push	bx
	call	display		! echo
	pop	bx
	cmp	bx,#cmdline+1	! first character ?
	jne	input		! no -> next input
#ifdef LCF_IGNORECASE
	call	upcase		! convert to upper case
#endif
	mov	cx,#IMAGES	! check if we have a single-key entry
	mov	di,#DESCR+2
	mov	ah,al
sklp:	test	word ptr (di+FLAGS_OFF),#FLAG_SINGLE ! single-key entry ?
	jz	sknext		! no -> try next
	mov	al,(di)		! get first character
#ifdef LCF_IGNORECASE
	call	upcase		! convert to upper case
#endif
	cmp	al,ah		! do we have a match ?
	jne	sknext		! no -> try next
	cmp	byte ptr (di+1),#0 ! at end ?
	je	cr		! yes -> run it
sknext:	add	di,#DESCR_SIZE	! test next entry
	loop	sklp		! next one
	jmp	input		! done -> get more input

todelch:br	delch		! ...
todell:	br	delline		! ...

! End of input, process the command line

nul:	push	bx		! automatic boot - wait for timeout
	mov	ax,old_del
	call	waitsh
	pop	bx
	jnc	crnul		! no key pressed -> continue
	mov	bx,#msg_int	! interrupted -> display a message
	call	say
	br	iloop		! return to interactive prompt

cr:	mov	cmdbeg,#mcmdbeg ! probably manual boot
crnul:	mov	byte ptr break,#0 ! clear the break flag
	push	cs		! set ES to CS
	pop	es
	xor	al,al		! mark end
	mov	(bx),al
	mov	si,#cmdline	! copy command line to save buffer
	mov	di,#lkcbuf
	mov	byte ptr dolock,#0 ! disable locking
	push	es
	push	ds
	pop	es
cpsav:	lodsb			! copy one byte
	stosb
	or	al,al		! at end ?
	jnz	cpsav		! no -> go on
	pop	es
	cmp	bx,#cmdline	! empty line ?
	je	notrspc		! yes -> boot first image
	cmp	byte ptr (bx-1),#32 ! trailing space ?
	jne	notrspc		! no -> go on
	dec	bx		! remove the space
	mov	byte ptr (bx),al
notrspc:mov	si,#cmdline	! scan the command line for "vga=", "kbd=",
	mov	di,si		! "lock" or "mem="
	cld
chkvga:	cmp 	word ptr (si),#0x6776 ! "vga=" ?
	jne	vsktk		! no -> try "kbd="
	cmp	word ptr (si+2),#0x3d61
	jne	vsktk
	call	setvga		! set VGA mode
	jc	toiloop		! error -> get next command
	jmp	vskdb		! proceed by discarding last blank
vsktk:	cmp	word ptr (si),#0x626b ! "kbd=" ?
	jne	vsktl		! no -> try "lock"
	cmp	word ptr (si+2),#0x3d64
	jne	vsktl
	call	putkbd		! pre-load keyboard buffer
	jmp	vskdb		! proceed by discarding last blank
vsktl:	cmp	word ptr (si),#0x6f6c ! "lock" ?
	jne	vsktm		! no -> skip to next blank
	cmp	word ptr (si+2),#0x6b63
	jne	vsktm
	mov	byte ptr dolock,#1 ! enable locking
	add	si,#4		! skip word
vskdb:	dec	di		! discard last blank
	jmp	vsknb		! continue
vsktm:	cmp	word ptr (si),#0x656d ! "mem=" ?
	jne	vsknb		! no -> skip to next blank
	cmp	word ptr (si+2),#0x3d6d
	jne	vsknb
	call	getmem		! get the user-provided memory limit
vsknb:	lodsb			! copy one byte
	stosb
	cmp	al,#32		! space ?
	je	chkvga		! yes -> look for options again
	or	al,al		! at end ?
	jnz	vsknb		! no -> go on
	mov	bx,#crlf	! display a CRLF
	call	say
	cmp	di,#cmdline+1	! empty line ?
emptyl:	je	bfirst		! yes -> boot first image
	jmp	bcmd		! boot the specified image

toiloop:br	iloop		! ...
toinput:br	input		! ...


! Find the boot image and start it

bcmd:	mov	cx,#IMAGES	! test all names
	mov	bx,#DESCR+2
nextn:	mov	si,bx		! compare the names
	mov	di,#cmdline
nextc:	mov	al,(si)		! get next character
	or	al,al		! NUL ?
	jz	dscend		! yes -> possible match
				! get the character
#ifdef LCF_IGNORECASE
	call	upcase
#endif
	mov	ah,al
	mov	al,(di)
#ifdef LCF_IGNORECASE
	call	upcase
#endif
	cmp	al,ah		! character equal ?
	jne	skipn		! no -> try next one
	inc	si		! test next character
	inc	di
	jmp	nextc
dscend:	cmp	byte ptr (di),#32 ! space or NUL -> boot
	je	boot
	cmp	byte ptr (di),#0
	je	boot
skipn:	add	bx,#DESCR_SIZE	! test next name
	loop	nextn
	mov	bx,#msg_nf	! not found -> display a message
	call	say
	br	iloop		! get more input

! Delete one character

delch:	cmp	bx,#cmdline	! at the beginning ?
	je	toinput		! yes -> do nothing
	push	bx		! display BS,SPC,BS
	mov	bx,#bs
	call	say
	pop	bx
	dec	bx		! move the pointer
	jmp	toinput		! go on

! Delete the entire line

delline:cmp	bx,#cmdline	! done ?
	je	toinput		! yes -> go on
	push	bx		! display BS,SPC,BS
	mov	bx,#bs
	call	say
	pop	bx
	dec	bx		! move the pointer
	jmp	delline		! next one

! Boot first after timeout

brto:	mov	bx,#crlf	! display a CRLF
	call	say
	jmp	brfrst		! boot

! Boot the first image

bfirst:	mov	byte ptr lkcbuf,#0 ! clear default
	cmp	byte ptr cmdline,#0 ! is there a default ?
	jne	bcmd		! yes -> boot that image
brfrst:	mov	bx,#DESCR+2	! boot the first image
	mov	si,bx		! copy the name to the command line
	mov	di,#cmdline
	cld
bfcpl:	lodsb			! copy one character
	mov	(di),al
	inc	di
	or	al,al		! NUL ?
	jnz	bfcpl		! no -> next one

! Boot the image BX points to (with password check)

boot:	mov	si,#cmdline	! locate start of options
locopt:	lodsb
	or	al,al		! NUL ?
	je	optfnd		! yes -> no options
	cmp	al,#32		! space ?
	jne	locopt		! no -> continue searching
	cmp	(si),#0		! followed by NUL ?
	jne	optfnd		! no -> go on
	mov	byte ptr (si-1),#0 ! discard trailing space
optfnd:	dec	si		! adjust pointer
	mov	options,si	! store pointer for later use
	cmp	byte ptr (bx+MAX_IMAGE_NAME+1),#0 ! use a password ?
	je	toboot		! no -> boot
	test	(bx+FLAGS_OFF),#FLAG_RESTR ! restricted ?
	jz	dopw		! no -> get the password
	cmp	byte ptr (si),#0! are there any options ?
	jne	dopw		! yes -> password required
toboot:	br	doboot		! ...
dopw:	push	bx		! save the image descriptor
	lea	si,(bx+MAX_IMAGE_NAME+1) ! get a pointer to the password string
	mov	bx,#msg_pw	! display a prompt
	call	say
pwagain:xor	cl,cl		! CL counts characters after a mismatch
pwloop:	push	cx		! get a key
	mov	cx,#pwtime
	call	getkey
	pop	cx
	cmp	al,#13		! CR ?
	je	pwcr		! yes -> handle it
	cmp	al,#21		! ^U ?
	je	pwdell		! yes -> erase line
	cmp	al,#24		! ^X
	je	pwdell
	cmp	al,#8		! BS ?
	je	pwdelch		! yes -> erase one character
	cmp	al,#127		! DEL
	je	pwdelch
	ja	pwloop		! ignore other non-printable characters
	cmp	al,#32
	jb	pwloop
	or	cl,cl		! counting bad input ?
	jnz	pwbad		! yes -> do it
	cmp	al,(si)		! correct input ?
	je	pwgood		! yes -> go on
pwbad:	inc	cl		! count error
	jnz	pwgood		! no overflow -> go on
	dec	cl		! adjust it
	jmp	pwcr		! terminate input
pwgood:	inc	si		! good character -> go on
	jmp	pwloop
pwdell:	pop	si		! reset the pointer
	push	si
	add	si,#MAX_IMAGE_NAME+1
	jmp	pwagain		! get password again
pwdelch:pop	bx		! at the beginning of the line ?
	push	bx
	add	bx,#MAX_IMAGE_NAME+1
	cmp	si,bx
	je	pwloop		! yes -> ignore it
	dec	si		! remove one character
	sub	cl,#1
	jnc	pwloop		! no underflow -> go on
	inc	cl		! adjust it
	jmp	pwloop		! next character
pwtime:	pop	cx		! drop CX ...
	mov	cl,#1		! ... and fail
pwcr:	mov	bx,#crlf	! display a CRLF
	call	say
	pop	bx		! restore the image descriptor
	or	cl,cl		! no errors ?
	jnz	pwfail		! no -> fail
	cmp	byte ptr (si),#0 ! at end ?
	je	doboot		! yes -> continue booting
pwfail:	mov	bx,#msg_pf	! display an error message
	call	say
	br	iloop		! get next input

! Boot the image BX points to

doboot:	mov	byte ptr prechr,#61 ! switch to equal sign
	push	bx		! save image descr
	mov	bx,#msg_l	! say hi
	call	say
	pop	bx		! display the image name
	push	bx
	call	say
	pop	si
	add	si,#ADDR_OFFS
	cld
! take care of the RAM disk first
	mov	word ptr (rdmid),#0 ! clear address
	lodsw			! number of bytes to load (low word)
	mov	dx,ax
	mov	rdszl,ax
	lodsw			! high word
	mov	rdszh,ax
	xchg	ax,dx		! convert to pages
	add	ax,#4095
	adc	dx,#0
	mov	bx,#4096
	div	bx
	mov	bx,ax
	lodsw			! address of the first map sector
	mov	cx,ax
	lodsw
	mov	dx,ax
        lodsb                   ;;;
;;;	inc	si		! skip number of sectors
	or	bx,bx		! no RAM disk ?
	jz	noramd		! yes -> skip it
	push	si		! save SI, ES, and BX (RD size)
	push	es
	push	bx
	mov	bx,#MAP		! load the first map sector
;;;	mov	al,#1
	call	sread
	mov	moff,#0
#ifdef DEBUG
	mov bx,#stepa
	call say
#endif
	mov	ah,#0x88	! okay, compute load address now
	int	0x15		! get amount of memory ...
	cmp	word ptr memlim,#0 ! limit set by user ?
	je	noulim		! no -> continue
	mov	ax,memlim	! use user limit
	sub	ax,#1024	! -1 MB
noulim:	cmp	ax,#0x3c00	! more than 16 MB ?
	jbe	no16mb		! no -> go ahead
	mov	ax,#0x3c00	! limit to 16 MB to be nice to the BIOS
				! (kernel can still use "high" memory)
no16mb:	shr	ax,2		! round to pages
	pop	bx		! subtract RAM disk size
	sub	ax,bx
	jnc	rdokay		! panic if not enough space
	cmp	ax,#128		! we probably need more than 512 kB for the
	ja	rdokay		! kernel to be useful ...
	mov	bx,#msg_rd	! complain
	call	say
	jmpi	restrt,SECONDSEG ! ... and restart if we can
rdokay:	add	ax,#256		! start is at first MB ...
	shl	ax,4		! *16
	mov	(gdt+0x1b),ax	! set up GDT
	mov	byte ptr (gdt+0x1a),#0
	mov	(rdmid),ax	! ... and remember that for patching setup
	xor	ax,ax		! ES=0 is our secret code to load via GDT
	mov	es,ax
	mov	bx,#gdt
	call	lfile		! load it
	pop	es		! restore ES and SI
	pop	si
noramd:
	lodsw			! address of the first map sector
	mov	cx,ax
	lodsw
	mov	dx,ax
;;;	inc	si		! skip number of sectors
        lodsb                   ;;;
        push    ax              ;;;
	mov	word ptr (gdt+0x1b),#0 ! set GDT to "load low"
	lodsw			! get the start page
	or	ax,ax		! load low ?
	jz	nohigh		! yup -> do it
	shl	ax,4		! *16
	mov	(gdt+0x1b),ax	! set up GDT
	mov	byte ptr (gdt+0x1a),#0
nohigh:
        pop     ax              ;;;
	push	si		! save SI
#ifdef DEBUG
        push    ax              ;;;
	mov bx,#step0
	call say
        pop     ax              ;;;
#endif
	mov	bx,#MAP		! load the first map sector
;;;	mov	al,#1
	call	sread
	mov	moff,#0		! reset the pointer
#ifdef DEBUG
	mov bx,#step0b
	call say
#endif
	mov	bx,#DFLCMD	! load the default command line
	seg	ss
	mov	cx,DFCMD_OFF+SSDIFF
	seg	ss
	mov	dx,DFCMD_OFF+2+SSDIFF
        seg     ss                      ;;;
	mov	al,DFCMD_OFF+4+SSDIFF   ;;;
;;;	mov	al,#1
	call	cread
	push	word ptr (DFLCMD) ! push magic number
	mov	bx,#DFLCMD	! load the fallback sector
	call	load1
	pop	ax		! valid magic number ?
#ifndef LCF_READONLY
	cmp	ax,#DC_MAGIC
	je	dclok		! yes -> can write
	cmp	ax,#DC_MGOFF
	jne	nofbck		! invalid -> must not write
dclok:	mov	bx,#DFLCMD	! fallback data present ?
	cmp	word ptr (bx),#DC_MAGIC
	jne	nofbck		! no -> go on
	seg	ss		! write new line
	mov	cx,DFCMD_OFF+SSDIFF
	seg	ss
	mov	dx,DFCMD_OFF+2+SSDIFF
;;;	mov	al,#1
	seg	ss                      ;;;
	mov	al,DFCMD_OFF+4+SSDIFF   ;;;
	call	cwrite
nofbck:
#endif
#ifdef DEBUG
	mov bx,#step1
	call say
#endif
	mov	bx,#DFLCMD	! load the options sector
	call	load1
	mov	si,cmdbeg	! copy non-options part of command line
	mov	di,#PARMLINE
#ifdef	LCF_LARGE_EBDA
	push	#INITSEG
	pop	es
#endif
cpnocl:	cmp	si,options	! at beginning of options ?
	je	cpnodn		! yes -> go on
	movsb			! copy one byte
	jmp	cpnocl		! next one
cpnodn:	mov	si,#DFLCMD	! constant options ?
	cmp	byte ptr (si),#0
	je	nocopt		! no -> go on
	mov	al,#32		! add a space
	stosb
cpcodsp:lodsb			! fetch next byte
	cmp	al,#32		! space ?
	je	cpcodsp		! yes -> discard it
cpcolp:	or	al,al		! NUL ?
	jz	cpcodn		! yes -> done
	stosb			! store byte
	cmp	al,#32		! a space ?
	je	cpcodsp		! yes -> discard next
	lodsb			! get next byte
	jmp	cpcolp
cpcodn:	seg	es
	cmp	byte ptr (di-1),#32 ! last was space ?
	jne	nocopt		! no -> go on
	dec	di		! discard it
nocopt:	mov	si,options	! append variable options
cpvalp:	lodsb			! copy one byte
	stosb
	or	al,al		! NUL ?
	jnz	cpvalp		! no -> go on
#ifdef DEBUG
	mov bx,#step2
	call say
#endif
	push	#INITSEG	! load the original boot sector
	pop	es
	xor	bx,bx		! load now
	call	load1
	seg	es
	mov	CL_MAGIC_ADDR,#CL_MAGIC ! set magic number
#ifndef LCF_LARGE_EBDA
	seg	es
	mov	word ptr CL_OFFSET,#PARMLINE+SECOND_SS
				! set parameter line offset
#else
	seg	es
	mov	word ptr CL_OFFSET,#PARMLINE
				! set parameter line offset
#endif
	pop	si		! restore SI
	lodsw			! get flags bit map
	mov	bx,ax
	lodsw			! copy parameters ... VGA mode ... (done)
	cmp	word ptr vgaovr,#VGA_NOCOVR ! VGA mode not overridden on
				! command line ?
	je	vganorm		! no -> go on
	mov	ax,vgaovr	! use that value
	jmp	vgaset
vganorm:test	bx,#FLAG_VGA
	jz	novga
vgaset:	seg	es
	mov	506,ax
novga:	push	bx		! use flags (BX) later
	test	bx,#FLAG_LOCK	! ... lock target ?
	jnz	lockit		! yup -> do it
	cmp	byte ptr dolock,#0 ! did user ask to lock new target ?
	je	nolock		! no -> go on
lockit:
#ifndef LCF_READONLY
	mov	bx,#lkwbuf	! save the command line
	seg	ss
	mov	cx,DFCMD_OFF+SSDIFF
	seg	ss
	mov	dx,DFCMD_OFF+2+SSDIFF
	push	es

;;;	mov	ax,ds
;;;	mov	es,ax
;;;	mov	ax,#1
        push    ds                      ;;;
        pop     es                      ;;;
        seg     ss                      ;;;
	mov	al,DFCMD_OFF+4+SSDIFF   ;;;

	push	si
	call	cwrite
	pop	si
	pop	es
#endif
nolock:
#ifdef DEBUG
	mov bx,#step3
	call say
	seg	es
#endif
	mov	cx,#SETUPSECS	! default is to load four sectors
#ifdef LCF_VARSETUP
	seg	es		! variable number of sectors ?
	cmp	byte ptr VSS_NUM,#0
	je	lsetup		! no -> use default
	seg	es		! use that number
	mov	cl,VSS_NUM
#endif
lsetup:	
;;;	mov	ax,#SETUPSEG
	push	#SETUPSEG	! load the setup (might meet EOF in the
;;;	mov	es,ax
	pop	es		! process of loading the boot sector of an
	xor	bx,bx		! other operating system)
lsloop:	push	cx
	call	loadopt
	pop	cx
	loop	lsloop
#ifdef DEBUG
	mov bx,#step4
	call say
#endif
	pop	bx		! get flags
	test	bx,#FLAG_MODKRN	! "modern" kernel ?
	jz	loadlow		! no -> avoid all patching and such
	seg	es		! set loader version
	mov	byte ptr (16),#LOADER_VERSION
	seg	es		! version >= 1 ?
	cmp	word ptr (6),#NEW_HDR_VERSION
	jbe	noheap		! no -> do not patch heap
	seg	es		! setup load area size
	mov	word ptr (36),#SLA_SIZE
	seg	es		! patch flags
	or	byte ptr (17),#LFLAG_USE_HEAP
noheap:	cmp	word ptr (rdmid),#0 ! initial RAM disk ?
	je	nordpt		! no -> no need to patch header for that
	xor	al,al		! store RAM disk start address
	mov	ah,(rdmid)
	seg	es
	mov	(24),ax
	xchg	al,ah
	mov	al,(rdmid+1)
	seg	es
	mov	(26),ax
	mov	ax,rdszl	! RAM disk size
	seg	es
	mov	(28),ax
	mov	ax,rdszh
	seg	es
	mov	(30),ax
nordpt:	cmp	word ptr (gdt+0x1b),#0 ! load low ?
	je	loadlow		! yes -> do it
#if 0 /* not necessary ! */
	mov	ax,(gdt+0x1a)	! load high instead: patch setup header ...
	seg	es		! start address
	mov	(20),ax
	mov	ax,(gdt+0x1c)
	xor	ah,ah
	seg	es
	mov	(22),ax
	seg	es		! set "high" flag ...
	mov	byte ptr (17),#LFLAG_HIGH
#endif
	xor	ax,ax		! GDT is already set up ...
	mov	es,ax
	mov	bx,#gdt
	call	lfile		! load the system ...
	jmp	launch		! ... and run it
loadlow:call	loadfile	! load the system
	jmp	launch		! go !

loadfile:
	push	#SYSSEG		! load a file at SYSSEG:0000
	pop	es
	xor	bx,bx
lfile:	call	load
	jmp	lfile

! Load one sector. Issue an error at EOF.

load1:	call	loadit		! load the sector
	mov	bx,#msg_eof	! we only get here at EOF
	call	say
	jmpi	restrt,SECONDSEG
loadit:	call	load		! load it
	pop	ax		! drop return address of load1
	ret

! Load one sector. Start the system at EOF.

loadopt:call	loadit		! load the sector
	jmp	launch		! go

! Load one sequence of sectors. Leave outer function at EOF.

load:	push	es		! save ES:BX
	push	bx
lfetch:	mov	si,moff		! get map offset
	mov	cx,MAP(si)	! get address
	mov	dx,MAP+2(si)
	mov	al,MAP+4(si)
	or	cx,cx		! at EOF ?
	jnz	noteof		! no -> go on
	or	dx,dx
	jnz	noteof
	pop	bx		! restore ES:BX
	pop	es
	pop	ax		! pop return address
	ret			! return to outer function
noteof:	add	si,#5		! increment pointer
	mov	moff,si
	cmp	si,#508		! page end ?
	jb	doload		! no -> load it
	mov	moff,#0		! reset pointer
	push	cs		! adjust ES
	pop	es

        mov     bl,hinib        ;;; this might get clobbered
        push    bx              ;;; so save it
	mov	bx,#MAP		! load map page
	call	sread
        pop     ax              ;;; restore the hi-nibble
	mov     hinib,al        ;;; 

	mov	al,#0x2e	! print a dot
	call	display
	jmp	lfetch		! try again

! Start the kernel

launch: push	es		! save ES:BX (why ???)
	push	bx
	mov	bx,#crlf	! display a CRLF
	call	say
	mov	dx,#0x3f2	! stop the floppy motor
	xor	al,al
	outb
	xor	ax,ax		! reset the FDC
	mov	dl,al
	int	0x13
	call	remto		! free timer interrupt
	push	#INITSEG	! adjust segment registers
	pop	ds
	push	ds
	pop	es
	jmpi	0,SETUPSEG	! start the setup

! Load one sector (called from load)

doload:	pop	bx		! restore ES:BX
	pop	es

! Load a sequence of sectors, possibly moving into "high memory" (> 1 MB)
! afterwards.

xread:	push	ax		! ES == 0 ?
	mov	ax,es
	or	ax,ax
	pop	ax
	jz	rdhigh		! yes -> read into high memory
	br	sread
rdhigh:	push	bx		! okay - DS:BX points to GDT in this case
	mov	bx,#SYSSEG	! adjust ES:BX
	mov	es,bx
	xor	bx,bx
	call	sread		! load the sector(s)
        mov     tempal,al
	pop	bx		! get pointer to GDT
	push	ax		! just in case ...
	push	cx
	push	si
	mov	si,bx		! turn ES:SI into pointer to GDT
	push	ds
	pop	es
	xor	cx,cx		! number of words to move
	mov	ch,tempal
#ifdef DEBUG
	push	si
	push	bx
	push	cx
	mov	al,(si+0x14)
	call	bout
	mov	ax,(si+0x12)
	call	wout
	mov	bx,#mov_ar
	call	say
	mov	al,(si+0x1c)
	call	bout
	mov	ax,(si+0x1a)
	call	wout
	mov	bx,#mov_sz
	call	say
	pop	ax
	push	ax
	call	wout
	mov	bx,#crlf
	call	say
	pop	cx
	pop	bx
	pop	si
#endif
	push	bx		! do the transfer. (save BX, CX and SI because
	push	cx		! we are paranoid)
	push	si
	mov	ah,#0x87
	int	0x15
	pop	si
	pop	cx
	pop	bx
	jc	badmov		! failed ...
	seg	es		! move pointer
	add	(si+0x1a),cx
	seg	es
	adc	byte ptr (si+0x1c),#0
	seg	es
	add	(si+0x1a),cx
	seg	es
	adc	byte ptr (si+0x1c),#0
	sub	ax,ax		! put ES back to 0
	mov	es,ax
	pop	si
	pop	cx
	pop	ax
	ret			! done

badmov:	push	ax		! save the error code
	mov	bx,#msg_bm	! tell the user ...
	br	reset		! (standard procedure)

! Load a sequence of sectors

sread:	push	bx		! save registers
	push	cx
	push	dx
	call	cread
	mov	di,ax		! save AL return count
	jc	rerror		! error -> complain
	pop	dx		! restore registers
	pop	cx
rokay:	pop	bx
        shl     ax,8            ; convert sectors to bytes
        add     ah,ah
	jc	dowrap		! loaded an entire segment -> advance ES
	add	bx,ax		! move BX
	jnc	nowrap		! same segment -> go on
dowrap:	mov	ax,es		! move ES
	add	ax,#0x1000
	mov	es,ax
nowrap:
	mov	ax,di		! restore the block count in AL
aret:	ret			! done

! Read error - try a second time and give up if that fails too

rerror:
#if 0   /* we now have 5 tries down in cread */
	xor	ax,ax		! reset the disk
	mov	dl,al
	int	0x13
	pop	dx		! try again
	pop	cx
	pop	bx
	push	bx
	mov	al,tempal
	call	cread
	jnc	rokay		! okay -> go on
#endif
	push	ax
	mov	bx,#msg_re	! say something
reset:	call	say
	pop	ax		! display the error code
	mov	al,ah
	call	bout
	mov	bx,#crlf	! a CRLF
	call	say
	mov	moff,#0		! restore initial state
	jmpi	restrt,SECONDSEG

! Convert character in AL to upper case

upcase:	cmp	al,#0x61	! lower case character ? ('a')
	jb	nolower		! no -> go on
	cmp	al,#0x7a	! 'z'
	ja	nolower
	sub	al,#0x20	! convert to upper case
nolower:ret			! done

! Display a hexadecimal word/byte/nibble

#ifndef xxDEBUG
wout:	push	ax
	mov	al,ah
	call	bout
	pop	ax
#endif
bout:	push	ax		! save byte
	shr	al,#4		! display upper nibble
	call	nout
	pop	ax
nout:	and	al,#15		! lower nible only
	add	al,#48		! display lower nibble
	cmp	al,#58		! convert to ASCII
	jb	nokay
	add	al,#7
nokay:	br	display		! display it

! Display a NUL-terminated string on the console

say:	mov	al,(bx)		! get byte
	or	al,al		! NUL ?
	jz	aret		! yes -> done
	push	bx		! save pointer
	cmp	al,#10		! \n ?
	jne	nonl		! no -> go on
	mov	al,#13		! display a CRLF
	call	display
	mov	al,#10
nonl:	cmp	al,#12		! ^L ?
	jne	nocls		! no -> go on
	mov	ah,#0xf		! clear the local screen
	int	0x10
	xor	ah,ah
	int	0x10
	jmp	snext		! next character
nocls:	call	display		! display, tty-style
snext:	pop	bx
	inc	bx		! next one
	jmp	say

! Display one character on the console

display:seg	cs		! use a serial port ?
	cmp	slbase,#0
	je	nodser		! no -> go on
	call	serdisp
nodser: xor	bh,bh		! display on screen
	mov	ah,#14
	int	0x10
	ret

serdisp:push	dx		! wait for space in the send buffer
	push	ax
	seg	cs
	mov	dx,slbase
	add	dx,#5
serwait:in	al,dx
	test	al,#0x10	! break -> set break flag
	jz	nobrk
	seg	cs
	mov	byte ptr break,#1
nobrk:	test	al,#0x20	! ready to send ?
	jz	serwait		! no -> wait
	sub	dx,#5		! send the character
	pop	ax
	out	dx,al
	pop	dx		! done
	ret

! Get a key (CX = timeout exit)

getkey: seg	ss		! set the timeout
	mov	ax,DSC_OFF-10+SSDIFF
	call	setto
gwtkey:	mov	ah,#1		! is a key pressed ?
	int	0x16
	jnz	gotkey		! yes -> get it
	mov	dx,slbase	! using a serial port ?
	or	dx,dx
	jz	gnokey		! no -> wait
	add	dx,#5		! character ready ?
	in	al,dx
	test	al,#1
	jz	gnokey		! no -> wait
	sub	dx,#5		! get it
	in	al,dx
	and	al,#0x7f	! strip 8th bit
	jnz	gotch		! ignore NULs
gnokey:	test	byte ptr timeout,#1 ! timed out ?
	jz	gwtkey		! no -> wait
	pop	ax		! discard return address
	jmp	cx		! jump to timeout handler
gotkey:	xor	ah,ah		! read a key
	int	0x16
	push	bx		! keyboard translation (preserve BX)
	mov	bx,#KEYTABLE
	xlatb
	pop	bx
gotch:
#ifdef LCF_ONE_SHOT
	seg	ss		! always enter prompt ?
	cmp	byte ptr DSC_OFF+15+SSDIFF,#0
	je	noosht		! yes -> do not disable timeout
	seg	ss		! disable timeout
	mov	DSC_OFF-10+SSDIFF,#0xffff
noosht:
#endif
	ret			! done

! Shift wait loop (AX = timeout, returns CY set if interrupred)

waitsh:	call	setto		! set timeout
actlp:	mov	ah,#2		! get shift keys
	int	0x16
	and	al,#0x5f	! anything set ? (except NumLock)
	jnz	shpress		! yes -> return with CY set
	mov	dx,slbase	! using a serial port ?
	or	dx,dx
	jz	acnosp		! no -> go on
	cmp	byte ptr break,#0 ! break received ?
	jnz	shpress		! yes -> return with CY set
	add	dx,#5		! check for pending break
	in	al,dx
	test	al,#0x10
	jnz	shpress		! break received -> return with CY set
acnosp:	test	byte ptr timeout,#1 ! timed out ?
	jz	actlp		! no -> wait
	clc			! clear carry
	ret			! done
shpress:stc			! set carry
	ret			! done

! Timeout handling

instto:	push	ds		! install the timeout handler
	xor	ax,ax
	mov	ds,ax
	cli			! no interrupts
	mov	ax,[0x1c*4]	! get the old vector
	seg	cs
	mov	int1c_l,ax
	mov	ax,[0x1c*4+2]
	seg	cs
	mov	int1c_h,ax
	mov	[0x1c*4],#tick	! install new vector
	mov	[0x1c*4+2],cs
	sti			! done
	pop	ds
	ret

remto:	push	es		! remove the interrupt handler
	xor	ax,ax
	mov	es,ax
	cli
	mov	ax,int1c_l	! restore the old vector
	seg	es
	mov	[0x1c*4],ax
	mov	ax,int1c_h
	seg	es
	mov	[0x1c*4+2],ax
	sti			! done
	pop	es
	ret

! AX = ticks, 0xffff = no timeout

setto:	or	ax,ax		! time out immediately ?
	jz	toimmed		! yes -> do it
	cli			! set timeout value
	mov	cntdown,ax
	mov	byte ptr timeout,#0 ! clear timed-out flag
	sti			! done
	ret
toimmed:mov	byte ptr timeout,#0xff ! set the timed-out flag
	ret			! done

tick:	pushf			! save flags
	seg	cs		! no timeout ?
	cmp	cntdown,#0xffff
	je	notzro		! yes -> go on
	seg	cs		! decrement counter
	dec	cntdown
	jnz	notzro		! not zero -> go on
	seg	cs		! set timeout flag
	mov	byte ptr timeout,#0xff
notzro:	popf			! done
	seg	cs
	jmpi	(int1c_l)	! continue with old interrupt

#ifndef LCF_READONLY

! Sector write

cwrite:	
#if 1
        mov     byte ptr (dsk_wrflag),#1        ! flag write operation
        call    cread
        mov     byte ptr (dsk_wrflag),#0        ! flag read operation
#else
        mov	byte ptr (dsk_cmd),#3 ! set command to write
	call	cread		! do it
	mov 	byte ptr (dsk_cmd),#2 ! read again
#endif
	jnc	cwok		! no error - return
	push	ax		! leave no traces
	push	bx
	mov	al,#87		! "W"
	push	ax		! display clobbers AH
	call	display
	pop	ax
	mov	al,ah		! error code
	call	bout
	pop	bx
	pop	ax
        stc                     ! flag error  JRC
cwok:	ret			! done

#endif

! Sector read
!  trashes CX and DI

cread:  
        test    dl,#LINEAR_FLAG|LBA32_FLAG
        jnz     use_linear

        push    ax              ;save the count
	mov	ah,#2		;read command
        call    dsk_do_rw       ; int 0x13 with retries
        pop     cx              ;Carry Set means error on read
        mov     al,cl           ;count in AL, error code in AH
        ret

use_linear:
        mov     ah,hinib        ;will be zero for LINEAR
        xchg    al,dh           ;AX is possible address 
        test    dl,#LBA32_NOCOUNT
        jz      lnread
        mov     ah,dh           ;former count is really hi-nibble
        mov     hinib,ah
        mov     dh,#1           ;set count to 1
lnread:
        xchg    di,ax           ;hi-address to DI
        mov     al,dh           ;count to AL
;;;        and     dl,#0x8F          ;clear all flags from device
        call    lba_read
        mov     al,cl           ;count returned in AL, error code in AH
        ret                     ;Carry Set means error on read


#include "read.S"


! Put tokens into keyboard buffer

putkbd:	add	si,#4		! skip over "kbd="
	push	es
	xor	ax,ax		! set ES to zero
	mov	es,ax
pknext:	lodsb			! get next byte
	or	al,al		! NUL ?
	jz	pkdone		! yes -> done
	cmp	al,#32		! blank ?
	jne	pkrd		! no -> read scan code
pkdone:	dec	si		! return last character
	pop	es		! done
	ret
pkrd:	xor	cx,cx		! clear accumulator
pkrdlp:	cmp	al,#97		! lower case character ?
	jb	pknol		! no -> go on
	sub	al,#32		! make upper case
pknol:	sub	al,#48		! normalize
	cmp	al,#10		! >"9" ?
	jb	pkok		! no -> okay
	cmp	al,#17		! <"A" ?
	jb	pksyn		! yes -> syntax error
	sub	al,#7		! adjust
	cmp	al,#16		! >"F" ?
	jae	pksyn		! yes -> syntax error
pkok:	shl	cx,1		! shift CX
	jc	pksyn		! carry means trouble
	shl	cx,1
	jc	pksyn
	shl	cx,1
	jc	pksyn
	shl	cx,1
	jc	pksyn
	add	cl,al		! put in lowest nibble
	lodsb			! get next byte
	or	al,al		! NUL ?
	jz	pkend		! yes -> at end
	cmp	al,#32		! space ?
	je	pkend		! yes -> at end
	cmp	al,#44		! comma ?
	je	pkmore		! yes -> end of token
	jmp	pkrdlp		! token continues
pksyn:	mov	bx,#msg_pks	! complain
	call	say
pkfls:	lodsb			! flush to end of option
	or	al,al
	jz	pkdone
	cmp	al,#32
	je	pkdone
	jmp	pkfls
pkend:	call	pkput		! store token
	jmp	pkdone		! ... and return
pkmore:	call	pkput		! store token
	jmp	pknext		! handle next token
pkput:	seg	es		! get buffer pointer
	mov	bx,[KBEND]
	mov	dx,bx
	add	dx,#2		! increment it
	cmp	dx,#KBHIGH	! (wrap around end)
	jb	pknadj
	mov	dx,#KBLOW
pknadj: seg	es		! buffer full ?
	cmp	dx,[KBBEG]
	je	pkfull		! yes -> error
	seg	es		! store scan code
	mov	(bx+0x400),cx
	seg	es		! store new pointer
	mov	[KBEND],dx
	ret			! done
pkfull:	mov	bx,#msg_pkf	! complain
	call	say
	pop	ax		! discard return address
	br	pkfls		! abort

! Set VGA mode

setvga:	add	si,#4		! skip over "vga="
	push	si		! save SI
	mov	bx,#vgatab	! scan VGA table
svgatb:	pop	si		! get pointer to option value
	push	si
	mov	cx,(bx)		! get VGA code
	or	cx,cx		! at end ?
	jz	vganum		! yes -> must be numeric
	add	bx,#2		! compare the strings
vgacmp:	lodsb
	call	upcase		! (case-insensitive)
	mov	ah,(bx)
	inc	bx
	or	ah,ah		! at end ?
	jnz	vgamore		! no -> go on
	or	al,al		! at end of line ?
	jz	vgafnd		! yes -> found it
	cmp	al,#32		! space ?
	je	vgafnd		! yes -> found it
	jmp	svgatb		! try next entry otherwise
vgamore:cmp	al,ah
	je	vgacmp		! equal -> next character
vgaskp:	mov	al,(bx)		! skip to end of reference string
	inc	bx
	or	al,al
	jnz	vgaskp
	jmp	svgatb		! try next entry
vgafnd:	pop	ax		! drop SI
vgaput:	mov	vgaovr,cx	! set VGA mode
	dec	si		! read last character again
	clc			! okay, done
	ret
vganum:	pop	si		! get SI
	xor	cx,cx
	mov	ah,cl
	test	byte ptr (si),#0xff ! no value ?
	jz	vgaerr		! yes -> error
vgadig:	lodsb			! get the next character
	or	al,al		! at end ?
	jz	vgaput		! yes -> done
	cmp	al,#32
	je	vgaput
	cmp	al,#48		! is it a digit ?
	jb	vgaerr		! no -> error
	cmp	al,#57
	ja	vgaerr
	sub	al,#48		! cx = cx*10+al-'0'
	mov	bx,cx
	shl	cx,1
	shl	cx,1
	add	cx,bx
	shl	cx,1
	add	cx,ax
	jnc	vgadig		! next one
vgaerr:	mov	bx,#msg_v	! display an error message
	call	say
	stc			! return an error
	ret

vgatab:
#ifdef NORMAL_VGA
	.word	ASK_VGA
	.ascii	"ASK"
	.byte	0
	.word	EXTENDED_VGA
	.ascii	"EXTENDED"
	.byte	0
	.word	EXTENDED_VGA
	.ascii	"EXT"
	.byte	0
	.word	NORMAL_VGA
	.ascii	"NORMAL"
	.byte	0
#endif
	.word	0

! Set memory limit

getmem:	cmp	byte ptr (si+4),#0x6e ! 'n' like 'nopentium' ?
	jne	mlreal		! no -> proceed
	ret			! nice try
mlreal:	push	si		! save SI for copying
	add	si,#4		! advance SI to beginning of number
	call	strtoul		! get number in DX:AX
#if 0
	push ax
	push dx
	push ax
	mov ax,dx
	call wout
	pop ax
	call wout
	pop dx
	pop ax
#endif
	mov	bl,(si)		! get next character
	cmp	bl,#0x4b	! 'K' or 'k' ?
	je	mlthis		! yes -> do not change
	cmp	bl,#0x6b
	je	mlthis
	mov	cx,#10		! divide or multiply by 2^10
	cmp	bl,#0x4d	! 'M' or 'm' ?
	je	mlmul		! yes-> multiply
	cmp	bl,#0x6d
	je	mlmul
	cmp	byte ptr (si),#0 ! NUL ?
	je	mldivl		! yes -> divide
	cmp	byte ptr (si),#32
	je	mldivl		! yes -> divide
	br	s2lbad		! trouble
mldivl:	shr	dx,1		! shr DX:AX,1
	rcr	ax,1
	loop	mldivl		! ten times
	jmp	mlthis		! done
mlmul:	or	dx,dx		! too big already ?
	jnz	mlbig		! yes -> set to 0xffff
mlmull:	shl	ax,1		! shl DX:AX,1
	rcl	dx,1
	loop	mlmull		! ten times
mlthis:	or	dx,dx		! too big ?
	jz	mlnbig		! no -> use AX
mlbig:	mov	ax,#0xffff	! use maximum
mlnbig:	mov	memlim,ax	! set memory limit
	pop	si		! restore SI
	ret			! done


strtoul:          /* string to unsigned long in DX:AX */
	xor     ax,ax
	xor     dx,dx
	mov     cx,#10          ! default radix is decimal
	cmp     byte ptr (si),#0x30        ! == '0'?
	jne     s2lnext
	inc     si
	dec     cx
	dec     cx              ! assume octal : CX = 8
	
	cmp     byte ptr (si),#0x58        ! == 'X'?
	je      s2lhex
	cmp     byte ptr (si),#0x78        ! == 'x'?
	jne     s2lnext
s2lhex: shl     cl,1            ! it is hexadecimal
	inc     si
s2lnext:
        xor     bx,bx
        mov     bl,(si)         ! get next character

	sub     bx,#0x30        ! - '0'
	jb      s2ldone
	cmp     bl,cl           ! compare to radix
	jb      s2lmul
	add     bx,#0x30
	and     bl,#0xFF-0x20   ! convert to Upper Case
	sub     bx,#0x41        ! - 'A'
	cmp     bl,#6
	jnb     s2ldone
	add     bl,#10	
s2lmul:
        push    dx              ! save high order
	mul     cx              ! multiply by radix
	add     ax,bx
	adc     dx,#0           ! carry possible only in radix 10
	pop     bx
	push    dx
	xchg    ax,bx
	mul     cx
	or      dx,dx
	jnz     s2lbad
	pop     dx
	add     dx,ax
	jc      s2lbad
	xchg    ax,bx
	inc     si
	jmp     s2lnext

s2lbad:	mov	bx,#msg_s2l	! complain
	call	say
	jmpi	restrt,SECONDSEG ! start over again
	
s2ldone: ret


msg_s2l:.byte	10
	.ascii	"Invalid number"
	.byte	10,0

! GDT for "high" loading

gdt:	! space for BIOS
	.blkb	0x10
	! source
	.word	0xffff		! no limits
	.word	0		! start: 0x10000
	.byte	1
	.byte	0x93		! permissions
	.word	0		! padding for 80286 mode :-(
	! destination
	.word	0xffff		! no limits
	.word	0		! start - filled in by user
	.byte	0
	.byte	0x93		! permissions
	.word	0		! padding for 80286 mode :-(
	! space for BIOS
	.blkb	0x10

! Some messages

msg_p:	.ascii	"boot: "
	.byte	0

msg_l:	.ascii	"Loading "
	.byte	0

msg_re:	.byte	10
	.ascii	"Error 0x"
	.byte	0

msg_nf:	.ascii	"No such image. [Tab] shows a list."
	.byte	10,0

msg_int:.byte	10
	.ascii	"*Interrupted*"
	.byte	10,0

msg_eof:.byte	10
	.ascii	"Unexpected EOF"
	.byte	10,0

msg_pw:	.ascii	"Password: "
	.byte	0

msg_pf:	.ascii	"Sorry."
	.byte	10,0

msg_v:	.byte	10
	.ascii	"Valid vga values are ASK, NORMAL, EXTENDED or a "
	.ascii	"decimal number."
	.byte	10,0

msg_pks:.byte	10
	.ascii	"Invalid hexadecimal number. - Ignoring remaining items."
	.byte	10,0

msg_pkf:.byte	10
	.ascii	"Keyboard buffer is full. - Ignoring remaining items."
	.byte	10,0

msg_bm:	.byte	10
	.ascii	"Block move error 0x"
	.byte	0

msg_rd:	.byte	10
	.ascii	"Not enough memory for RAM disk"
	.byte	10,0

ospc:	.ascii	"O"
#ifdef LCF_BEEP
	.byte	7
#endif
	.byte	32,0

crlf:	.byte	10,0

bs:	.byte	8,32,8,0

#ifdef DEBUG
stepa:	.ascii	" RAM disk,"
	.byte	0
step0:	.ascii	" map page,"
	.byte	0
step0b:	.ascii	" fallback,"
	.byte	0
step1:	.ascii	" options,"
	.byte	0
step1b:	.ascii	" fallback,"
	.byte	0
step2:	.ascii	" boot,"
	.byte	0
step3:	.ascii	" setup,"
	.byte	0
step4:	.ascii	" system "
	.byte	0

sax:	.ascii	"AX="
	.byte	0
sbx:	.ascii	" BX="
	.byte	0
scx:	.ascii	" CX="
	.byte	0
sdx:	.ascii	" DX="
	.byte	0
ses:	.ascii	" ES="
	.byte	0
sdone:	.byte	10
	.byte	0

mov_ar:	.ascii	" -> "
	.byte	0
mov_sz:	.ascii	", words "
	.byte	0
#endif

hinib:  .byte   0               ;;; hi-nibble of address
tempal:	.byte	0
moff:	.word	0		! map offset

cntdown:.word	0		! count-down
timeout:.byte	0		! timed out

int1c_l:.word	0		! old timer interrupt
int1c_h:.word	0

old_del:.word	0		! delay before booting

nodfl:	.word	0		! action if no defaults are present

slbase:	.word	0		! serial port base (or 0 if unused)
break:	.byte	0		! break received flag

usrinpm:.byte	UI_MAGIC

cmdbeg:	.word	0
options:.word	0

rdmid:	.word	0		! RAM disk address, "middle" part
rdszl:	.word	0		! RAM disk size
rdszh:	.word	0

vgaovr:	.word	0		! VGA mode overwrite
memlim:	.word	0		! memory limit
dskprm:	.word	0,0,0,0,0,0

lkwbuf:	.word	DC_MAGIC
lkcbuf:	.blkb	256
dolock:	.byte	0

acmdbeg:.ascii	"auto "
mcmdbeg:.ascii	"BOOT_IMAGE"
prechr:	.byte	32		! space: guard double blank supression
				! equal sign: variable assignment
cmdline:.byte	0
theend:
