/* first.S  -  LILO first stage boot loader with LBA32 support */

/* Copyright 1992-1998 Werner Almesberger. See file COPYING for details. */
/* LBA extensions Copyright (C) 1999, John Coffman.  Use subject to the  */
/*  terms of the GNU public license agreement.                           */

#define JRC_NOCOMPACT

#define LILO_ASM
#include "lilo.h"



	.text

	.globl	_main

	.org	0

_main:	cli			! NT 4 blows up if this is missing
	jmp	start

        .org    3               ! special marker for LBA32 code
	.ascii  "lba"           ! this may be removed in the future
	                        ! when the version check is enough
	.org	6

! Boot device parameters. They are set by the installer.

	.ascii	"LILO"
	.word	STAGE_FIRST
	.word	VERSION

timeout:.word	0		! input timeout
delay:	.word	0		! boot delay
port:	.byte	0		! COM port (0 = unused, 1 = COM1, etc.)
sparam:	.byte	0		! serial port parameters (0 = unused)

tstamp:	.long	0		! timestamp

d1_cx:	.word	0		! first descriptor sector address
d1_dx:	.word	0
d1_al:	.byte	0		! (unused)

d2_cx:	.word	0		! second descriptor sector address
d2_dx:	.word	0
d2_al:	.byte	0		! (unused)

dc_cx:	.word	0		! default command-line sector address
dc_dx:	.word	0
dc_al:	.byte	0		! (unused)

prompt:	.byte	0		! indicates whether to always enter prompt
				! (also used as alignment byte)

ms_len:	.word	0		! initial greeting message
ms_cx:	.word	0
ms_dx:	.word	0
ms_al:	.byte	0		! (unused)

kt_cx:	.word	0		! keyboard translation table
kt_dx:	.word	0
kt_al:	.byte	0

d_addr:				! second stage sector addresses

	.org	CODE_START_1

ext_si:	.word	0		! external interface
ext_es:	.word	0
ext_bx:	.word	0
ext_dl:	.byte	0

start:	mov	ax,#BOOTSEG	! set DS
	mov	ds,ax
	mov	ext_es,es	! copy possible external parameters
	mov	ext_si,si
	mov	ext_bx,bx
	mov	ext_dl,dl
	mov	ax,#FIRSTSEG	! beam us up ...
	mov	es,ax
	mov	cx,#256
	sub	si,si
	sub	di,di
	cld
	rep
	movsw
	jmpi	go,FIRSTSEG


go:
;       cli			! no interrupts
	mov	ds,ax		! AX is already set
;;	mov	es,ax		! (ES may be wrong when restarting)
	mov	ax,#STACKSEG
	mov	ss,ax
	mov	sp,#STACK	! set the stack
	sti			! now it is safe

	mov	al,#0x0d	! gimme a CR ...
	call	display
	mov	al,#0x0a	! ... an LF ...
	call	display
	mov	al,#0x4c	! ... an 'L' ...
	call	display
	
lagain:	mov	si,#d_addr	! ready to load the second stage loader
	push	#SECONDSEG
	pop	es
	xor	bx,bx
;;	cld                     ! this was done above

sload:	lodsw			! get CX
	xchg	cx,ax
	
#ifndef JRC_NOCOMPACT
        lodsw			! get DX
	mov	dx,ax
	or	ax,cx		! at EOF ?
	jz	done		! yes -> start it
        lodsb
        test    dl,#LINEAR_FLAG|LBA32_FLAG
#else
        lodsb
	test    al,#LINEAR_FLAG|LBA32_FLAG
#endif
        jnz     use_linear
#ifdef JRC_NOCOMPACT
        dec     si
	lodsw
	mov     dx,ax
	or      ax,cx
	jz      done
	lodsb
#endif
        mov     ah,#2           ! read command
        int     0x13            ! BIOS read
        jmp     rd_done

use_linear:
#ifndef JRC_NOCOMPACT
        xchg    al,dh           ! save count in DH, address to AL
        mov     ah,hinib        ! linear will get 0
        test    dl,#LBA32_NOCOUNT  ! check if count omitted
        jz      count_ok
        mov     hinib,dh        ! save the hi-nibble
        mov     ah,dh
        mov     dh,#1           ! count is 1
count_ok:
        xchg    ax,di           ! LBA to DI
        mov     al,dh
#else
        mov     dl,al
	lodsw
	test    dl,#LBA32_FLAG
	jnz     is_lba
	xor     ah,ah           ! was LINEAR, zero the hi-nibble (was count)
is_lba:
        xchg    ax,di
;;;	mov     al,#1
#endif
;;;        and     dl,#0x8F        ! clear all the spurious flags
	call	lba_read
rd_done:
	jc	error		! error -> start over again
	add	bh,#2    	! next sector
	jmp	sload

done:	mov	al,#0x49	! display an 'I'
	call	display
	jmpi	0,SECONDSEG	! start the second stage loader


#ifndef JRC_NOCOMPACT
hinib:  .byte   0
#endif

error:
#ifndef LCF_NO1STDIAG
        mov	al,#32          ! display a space
	call	display
;;;		        ! display error code in AH
	call	bout
#endif
	xor	ax,ax		! reset the FDC
;;;	mov	dl,al
	int	0x13
	jmp	lagain		! redo from start

#ifndef LCF_NO1STDIAG
bout:	rol     ax,4            ! bring hi-nibble to position
	call	nout
	rol     ax,4            ! bring lo-nibble to position
nout:	and	al,#15		! display one nibble
	add	al,#48
	cmp	al,#58
	jb	nokay
	add	al,#7
nokay:				! fall through
#endif
display:  push  ax              ! new display does not affect AX
        xor	bh,bh		! display on screen
	mov	ah,#14
	int	0x10
	pop     ax
	ret
	
	
#include "read.S"

	
theend:
