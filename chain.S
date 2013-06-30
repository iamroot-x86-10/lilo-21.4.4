/* chain.S  -  LILO boot chainer */

/* Copyright 1992-1998 Werner Almesberger. See file COPYING for details. */


#define LILO_ASM
#include "lilo.h"


	.text

	.globl	_main
	.org	0

_main:	jmp	start

	.org	3
	.ascii	"lba" 		;this marker may be removed in the future
				;   -- JRC
	
	.org	6

	.ascii	"LILO"
	.word	STAGE_CHAIN
	.word	VERSION

offset:	.word	0
drive:	.byte	0
	.byte	0			! head, always zero

hint:	.word	drvmap			! pointer to drive map

ptable:	.blkw	0x20			! partition table to preload

start:	cli				! set SS:SP to 0:7C00
	xor	ax,ax
	mov	ss,ax
	mov	sp,#0x7c00
	sti
	mov	ax,#SETUPSEG		! move boot sector to default location
	mov	ds,ax
	xor	ax,ax
	mov	es,ax
	mov	cx,#256
mtmp = SETUPSECS-1			! broken math ...
	mov	si,#mtmp*512
	mov	di,#BOOTSEG*16
	rep
	movsw
#ifdef DOS_D
dos4:   mov	dl,drive
	seg	es
	mov	BOOTSEG*16+0x24,dl
	mov	si,offset
	mov	dx,ptable+8(si)
	seg     es
	mov	BOOTSEG*16+0x1C,dx
	mov	dx,ptable+10(si)
	seg     es
	mov     BOOTSEG*16+0x1E,dx
#endif
	mov	cx,#0x20		! move partition table
	mov	si,#ptable
	mov	di,#PART_TABLE
	rep
	movsw
					! mess with the partition table
#if defined(LCF_REWRITE_TABLE) || defined(LCF_READONLY)
	mov	si,#prtmap		! get partition table change rules
prtclp:	lodsw				! bios == 0 indicates end
	or	al,al
	jz	pmend			! at end -> quit
	cmp	al,cache		! already in cache ?
	je	incache			! yes -> no loading required
	push	ax			! save table data
	call	flush			! flush the cache
	pop	ax
	push	ax
	mov	cache,al		! remember drive in cache
	cmp	al,drive		! boot drive ?
	jne	noc			! no -> load into scratch area
	xor	ax,ax			! load at 0000:0600
	mov	bx,#PARTS_LOAD
	jmp	loadit
noc:	mov	ax,ds
	mov	bx,#PARTS_SCR		! scratch area
loadit:	mov	es,ax			! set up pointers and remember them
	mov	ces,ax
	mov	cbx,bx
	mov	ax,#0x201		! load partition table, one sector
	mov	dx,cache		! drive from cache (DH = 0)
	mov	cx,#1
	int	0x13			! load it
	jc	wrfail			! error -> abort
	pop	ax			! get BIOS and offset
incache:les	bx,cbx			! load pointer
	add	bx,#PART_TABLE_OFFSET	! move to partition table
	add	bl,ah			! offset is always in [0x1be,0x1fd]
	lodsw				! see what we need to do
	seg	es			! match ?
	cmp	byte ptr (bx),al
	jne	nocng			! no -> do not change
	seg	es			! change
	mov	byte ptr (bx),ah
	mov	byte ptr dirty,#1	! mark as dirty
nocng:	br	prtclp			! next one

flush:	test	byte ptr dirty,#1	! dirty ?
	jz	noflush			! no -> do not write
	mov	ax,#0x301		! write one sector
	mov	dx,cache		! get the drive
	or	dl,dl			! nothing cached ?
	jz	noflush			! no -> do not flush
	les	bx,cbx			! reload pointer
	int	0x13			! write ...
	jc	wrfail			! argl
noflush:ret
pmend:	call	flush			! flush table
	br	nopp			! and proceed
wrfail:	mov	si,#failmsg		! complain
	call	say
	mov	ax,#FIRSTSEG		! try to restart LILO
	jmpi	#GO,FIRSTSEG

cache:	.byte	0			! drive, 0 means not cached
	.byte	0			! head, always 0
cbx:	.blkw	1
ces:	.blkw	1
dirty:	.byte	0

#endif

nopp:
	mov	ax,drvmap		! need to install mapper ?
	or	ax,ax
	jz	noimap			! no -> go on
	call	swap13
noimap:

	mov	si,offset		! DS:SI and ES:SI point to the partition
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
#if 0
	mov	bp,#0			! might help some boot problems
	mov	ax,#0xaa55		! boot signature (just in case ...)
	jmpi	#BOOTSEG*16,0		! start boot sector
#else
/* boot code from the OS2 Boot Manager */
	mov	bx,#BOOTSEG*16
	
	mov	ss,ax			! on all processors since the 186
	mov	sp,bx			! these instructions are locked
	
	mov	(si),dl			! yes, put it in the partition table
	mov	bp,si
	push	ax
	push	bx
	retf
#endif


#ifdef XXX
lilosig:.ascii	"LILO"
cmd:	.ascii	"98"
	.byte	0
#endif

#if defined(LCF_REWRITE_TABLE)

! Display a NUL-terminated string on the console

say:	lodsb			! get byte
	or	al,al		! NUL ?
	jz	aret		! yes -> done
	mov	ah,#14		! display, tty-style
	xor	bh,bh
	int	0x10
	jmp	say		! next one
aret:	ret			! done

failmsg:.ascii	"Rewrite error."
	.byte	13,10,0

#endif

swap13: seg	es		! allocate 1 kB
	dec	word ptr [0x413]
	int	0x12		! get start segment
;;;	mov	cl,#6
;;;	shl	ax,cl
	shl	ax,#6		! we are running on a 386
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

new13:	push	ax		! save AX (contains function code in AH)
	push	bp		! need BP to mess with stack
	mov	bp,sp
	! Stack layout:
	!
	!   +8	INT flags
	!   +6	INT CS
	!   +4	INT IP
	!   +2	AX
	! BP+0 BP
	pushf			! push flags (to act like interrupt)
	push	si
	mov	si,#drvmap-new13
mapfl:	seg	cs		! get next entry
	lodsw
	or	ax,ax		! at end ?
	jz	nomap		! yes -> do not map
	cmp	dl,al		! match ?
	jne	mapfl		! no -> continue
	mov	dl,ah		! map drive
nomap:	pop	si		! restore SI
	mov	8(bp),ax	! overwrite old flags (to remember mapping)
	mov	ax,2(bp)	! restore AX
	mov	bp,(bp)		! restore BP
	.byte	0x9a		! CALL FAR
old13of:.word	0
old13sg:.word	0
	push	bp		! save BP again
	mov	bp,sp
	! New stack layout:
	!
	!   +10	mapping (was flags)
	!   +8	INT CS
	!   +6	INT IP
	!   +4	AX
	!   +2  obsolete BP
	! BP+0  BP
	xchg	ax,4(bp)	! save AX and get command
	pushf			! fix driver number, if necessary
	cmp	ah,#8 ! do not fix
	je	done13
	cmp	ah,#0x15 ! do not fix
	je	done13
	mov	ax,10(bp)	! no mapping ?
	or	ax,ax
	jz	done13
	mov	dl,al		! fix mapping
done13:	mov	ax,4(bp)	! restore AX
	pop	10(bp)		! restore flags
	pop	bp		! get BP
	add	sp,#4		! fix SP
	iret			! done

drvmap:	.blkw	DRVMAP_SIZE+1

new13end:

#if defined(LCF_REWRITE_TABLE)
prtmap:	.blkw	PRTMAP_SIZE*2+1	! only first word of last entry is read
#endif

theend:
