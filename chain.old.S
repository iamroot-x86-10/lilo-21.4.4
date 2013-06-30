/* chain.S  -  LILO boot chainer */

/* Copyright 1992-1997 Werner Almesberger. See file COPYING for details. */


#define LILO_ASM
#include "lilo.h"


	.text

	.globl	_main
	.org	0

_main:	jmp	start

	.org	2

	.ascii	"LILO"
	.word	STAGE_CHAIN
	.word	VERSION

offset:	.word	0
drive:	.byte	0
	.byte	0			! head, always zero

start:	cli				! set SS:SP to 0:7C00
	xor	ax,ax
	mov	ss,ax
	mov	ax,#0x7c00
	mov	sp,ax
	sti
	mov	ax,#SETUPSEG		! move boot sector to default location
	mov	ds,ax
	xor	ax,ax
	mov	es,ax
	mov	cx,#256
	mov	si,#512
	mov	di,#BOOTSEG*16
	rep
	movsw
	push	bx			! save secret message
#ifdef DOS_D
#if 0
	seg	es
	cmp	byte ptr BOOTSEG*16+0x26,#0x29
	je	dos4
	mov	bx,#baddos		! complain
	call	say
	mov	ax,#FIRSTSEG		! restart LILO
	jmpi	#GO,FIRSTSEG
#endif
dos4:	seg	es
	mov	byte ptr BOOTSEG*16+0x24,#0x81
#endif
	mov	cx,#0x20		! move partition table
	mov	si,#PART_TABLE_OFFSET
	mov	di,#PART_TABLE
	rep
	movsw
#if defined(SWAP_HD) || defined(SWAP_FD)
	call	swap13
#endif
					! table entry
	pop	bx			! get secret message (active partition)
#ifdef LCF_REWRITE_TABLE
	or	bl,bl			! none set ?
	jz	tonopp			! yes -> do not patch
br tonopp
	cmp	bx,#0x81		! valid code ?
	jb	towrfail		! no -> abort
	cmp	bx,#0x84
	jna	wrokay			! yes -> continue
towrfail:br	wrfail
tonopp:	br	nopp
wrokay:	push	bx			! save BX
	xor	ax,ax			! ES becomes 0
	mov	es,ax
	mov	ax,#0x201		! load partition table, one sector
	mov	dx,#0x80		! first drive
	mov	cx,#1
	mov	bx,#PARTS_LOAD
	int	0x13			! load it
	jc	wrfail			! error -> abort
	mov	cx,#4			! process all four entries
	mov	bx,#PART_TABLE
ptchpt:	seg	es			! clear all active flags
	mov	byte ptr (bx),#0
#if defined(LCF_FIX_TYPE) && defined(LCF_HIDE_DOS)
	seg	es
	mov	al,(bx+4)		! get partition type
	cmp	al,#PART_DOS12		! hidden ?
	je	hideme			! no -> hide it
	cmp	al,#PART_DOS16
	je	hideme
	cmp	al,#PART_DOS32
	jne	nonrel			! already hidden -> continue
hideme:	add	al,#HIDDEN_OFF		! write back corrected value
	seg	es
	mov	(bx+4),al
#endif
nonrel:	add	bx,#16			! next entry
	loop	ptchpt
	pop	bx			! compute active flag position
	dec	bx
	shl	bl,1
	shl	bx,1
	shl	bx,1
	shl	bx,1
	cmp	bx,offset		! right ?
	jne	wrfail			! no -> abort
	seg	es			! set active flag
	mov	byte ptr (bx+PART_TABLE),#0x80
#ifdef LCF_FIX_TYPE
	seg	es			! is this a 
	mov	al,byte ptr (bx+PART_TABLE+4)
	cmp	al,#PART_HDOS12		! hidden ?
	je	unhideme		! yes -> unhide it
	cmp	al,#PART_HDOS16
	je	unhideme
	cmp	al,#PART_HDOS32
	jne	nounhid			! not hidden -> continue
unhideme:sub	al,#HIDDEN_OFF		! write back corrected value
	seg	es
	mov	(bx+PART_TABLE+4),al
#endif
nounhid:mov	ax,#0x301		! save it (restore all registers for
	mov	dx,#0x80		! paranoia)
	mov	cx,#1
	mov	bx,#0x600
	int	0x13			! write ...
	jc	wrfail			! argl
	mov	bx,#passmsg		! confirm modification
	call	say
	jmp	nopp
wrfail:	mov	bx,#failmsg		! complain
	call	say
	mov	ax,#FIRSTSEG		! restart LILO
	jmpi	#GO,FIRSTSEG
#endif
nopp:	mov	si,offset		! DS:SI and ES:SI point to the partition
	add	si,#PART_TABLE
	mov	dx,drive		! initialize DX (drive and head)
	xor	ax,ax			! set DS and ES to zero
#ifdef XXX
	mov	ax,ds
	mov	es,ax
	mov	si,#lilosig
	mov	bx,#cmd
	mov	dl,#0xfe
#else
	mov	ds,ax
	mov	es,ax
#endif
	mov	bp,#0			! might help some boot problems
	mov	ax,#0xaa55		! boot signature (just in case ...)
	jmpi	#BOOTSEG*16,0		! start boot sector

#ifdef XXX
lilosig:.ascii	"LILO"
cmd:	.ascii	"98"
	.byte	0
#endif

#if defined(DOS_D) || defined(LCF_REWRITE_TABLE)

! Display a NUL-terminated string on the console

say:	mov	al,(bx)		! get byte
	or	al,al		! NUL ?
	jz	aret		! yes -> done
	push	bx		! save pointer
	mov	ah,#14		! display, tty-style
	xor	bh,bh
	int	0x10
	pop	bx
	inc	bx		! next one
	jmp	say
aret:	ret			! done

#ifdef DOS_D
baddos:	.ascii	"Need DOS version 4 or newer."
	.byte	13,10,0
#endif

failmsg:.ascii	"Rewrite error."
	.byte	13,10,0

passmsg:.ascii	"Rewrote the partition table."
	.byte	13,10,0

#endif

#if defined(SWAP_HD) || defined(SWAP_FD)

swap13: seg	es		! allocate 1 kB
	dec	word ptr [0x413]
	int	0x12		! get start segment
	mov	cl,#6
	shl	ax,cl
	cli			! disable interrupts
	xor	bx,bx		! zero a few registers
	mov	di,bx
	seg	es		! change offset
	xchg	bx,[0x4c]
	mov	old13of,bx
	mov	bx,ax		! change segment
	seg	es
	xchg	bx,[0x4e]
	mov	old13sg,bx
	mov	es,ax		! move drive swapper
	mov	si,#new13
	mov	cx,#new13end-new13
	rep
	movsb
	sti			! enable interrupts
	ret			! done

new13:	seg	cs		! save function code
	mov	fcode-new13,ah
	test	dl,#0x80	! hard disk drive ?
#ifdef SWAP_FD
	jnz	noswap		! yes -> go on
#else
	jz	noswap		! no -> go on
#endif
	xor	dl,#1		! swap drive 0 and 1
noswap:	pushf
	.byte	0x9a		! CALL FAR
old13of:.word	0
old13sg:.word	0
	pushf			! fix driver number, if necessary
	seg	cs
	cmp	byte ptr fcode-new13,#8	! do not fix
	je	done13
	seg	cs
	cmp	byte ptr fcode-new13,#0x15 ! do not fix
	je	done13
	test	dl,#0x80	! hard disk drive ?
#ifdef SWAP_FD
	jnz	done13		! yes -> go on
#else
	jz	done13		! no -> go on
#endif
	xor	dl,#1		! fix it
done13:	seg	cs
	mov	tmpbx-new13,bx	! restore flags
	mov	bx,sp
	seg	ss
	pop	6(bx)
	seg	cs
	mov	bx,tmpbx-new13
	iret			! done
new13end:
fcode:	.byte	0		! function code
tmpbx:	.word	0

#endif

theend:
