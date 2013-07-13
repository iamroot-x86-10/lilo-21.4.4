/* first.S  -  LILO first stage boot loader with LBA32 support */

/* Copyright 1992-1998 Werner Almesberger. See file COPYING for details. */
/* LBA extensions Copyright (C) 1999, John Coffman.  Use subject to the  */
/*  terms of the GNU public license agreement.                           */

#define JRC_NOCOMPACT

#define LILO_ASM
#include "lilo.h"


	.text                   	!! text 세션 시작 .data .bss .rodata	

	.globl	_main

	.org	0               	!! 현제 위치를 0번지로 설정

_main:	cli                 	!! NT 4 blows up if this is missing 인터럽트 클리어
	jmp	start
	.org    3					! special marker for LBA32 code
	.ascii  "lba"           	! this may be removed in the future
	                        	! when the version check is enough
	.org 	6

!! BOOT_PARMS_1(0)->jump에 여기까지의 6bytes가 들어간다.


!! common.h의 BOOT_PARAMS_1에 마추어 구조체를 작성한다.	
!! typedef struct {
!!    char jump[6]; /* jump over the data */
!!    char signature[4]; /* "LILO" */
!!    unsigned short stage,version;
!!    unsigned short timeout; /* 54 msec delay until input time-out,
!!			       0xffff: never */
!!    unsigned short delay; /* delay: wait that many 54 msec units. */
!!    unsigned char port; /* COM port. 0 = none, 1 = COM1, etc. */
!!    unsigned char ser_param; /* RS-232 parameters, must be 0 if unused */
!!    unsigned long timestamp; /* timestamp for restoration */
!!    SECTOR_ADDR descr[3]; /* 2 descriptors and default command line */
!!    unsigned char prompt; /* 0 = only on demand, =! 0 = always */
!!    unsigned short msg_len; /* 0 if none */
!!    SECTOR_ADDR msg; /* initial greeting message */
!!    SECTOR_ADDR keytab; /* keyboard translation table */
!!    SECTOR_ADDR secondary[MAX_SECONDARY+1];
!! } BOOT_PARAMS_1; /* first stage boot loader */

! Boot device parameters. They are set by the installer
                        			!! BOOT_PARAMS_1 작성
	.ascii	"LILO"      			!!              -> signature 
	.word	STAGE_FIRST 			!!              -> stage
	.word	VERSION     			!!              -> version

timeout:.word	0					! input timeout
delay:	.word	0					! boot delay
port:	.byte	0					! COM port (0 = unused, 1 = COM1, etc.)
sparam:	.byte	0					! serial port parameters (0 = unused)

tstamp:	.long	0					! timestamp

d1_cx:	.word	0					! first descriptor sector address
d1_dx:	.word	0
d1_al:	.byte	0					! (unused)

d2_cx:	.word	0					! second descriptor sector address
d2_dx:	.word	0
d2_al:	.byte	0					! (unused)

dc_cx:	.word	0					! default command-line sector address
dc_dx:	.word	0
dc_al:	.byte	0					! (unused)

prompt:	.byte	0       			! indicates whether to always enter prompt
									! (also used as alignment byte)

ms_len:	.word	0					! initial greeting message
ms_cx:	.word	0
ms_dx:	.word	0
ms_al:	.byte	0					! (unused)

kt_cx:	.word	0					! keyboard translation table
kt_dx:	.word	0
kt_al:	.byte	0

d_addr:								! second stage sector addresses
									!! BOOT_PARAMS_1을 설정하는 부분을완료
	.org	CODE_START_1			!! CODE_START_1의 위치에는 second stage sector들에 대한 정보가 있을것이다.

									!! bios에서 넘어오는 si, es, bx, dl값을 저장해 둔다.
									!! LILO에서는 MBR에의해 boot가 시작되기 이전에 external parmeter를 boot code에 
									!! 전달하는 메카니즘을 마련해 두었다.
									!! SI, EX, BX, DL 레지스터를 사용하여 전달한다.
									!! DL: 0xFE로 설정되어 external parmeter의 유무를 파악하는데 사용
									!! ES:SI: "LILO" 스트링에 대한 포인터(어드레스 값)
									!! ES:BX: external command line에 대한 포인터 값
									!! 하지만 거의 사용하지 않는다고 함
ext_si:	.word	0					! external interface
ext_es:	.word	0
ext_bx:	.word	0
ext_dl:	.byte	0


									!! main 함수 시작지점
start:	mov	ax,#BOOTSEG				! set DS
									!! 0x07C0 == ds == ax
	mov	ds,ax						!! DS의 값을 0x07C0로 마춘다.
									!! 0x7C0는 bios에 의해 mbr에 있는 512byes가 메모리에 올라온 위치이다.

	mov	ext_es,es					! copy possible external parameters
	mov	ext_si,si
	mov	ext_bx,bx
	mov	ext_dl,dl					!! es, si, bx, dl의 값을 저장해둔다.

									!! 자기복제 코드 시작
									!! 부트로더는 자신의 코드를 0x9A00으로 복사한후 나머지 작업을 수행한다.	
	mov	ax,#FIRSTSEG				!! ax == 0x9A00
	mov	es,ax						!! es == ax == 0x9A00
	mov	cx,#256						!! cx == 256
	sub	si,si						!! si == 0
	sub	di,di						!! di == 0
	cld								!! 
	rep								!! ds:si => es:di로 256번복사한다. 총 512byte로 옮겨둔다.
									!! 0x7C0에 있는 것을 0x9A00으로 
	movsw							!! move string word
	jmpi	go,FIRSTSEG 			!! 0x9A00:go 로 jump

								
go:									!! lilo가 자기복제를 마친후 바로 수행하는 코드
;       cli							! no interrupts
	mov	ds,ax						!! AX == 0x9A00 ! AX is already set
;;	mov	es,ax						! (ES may be wrong when restarting)
	mov	ax,#STACKSEG				!! 0x9000		
	mov	ss,ax			
	mov	sp,#STACK					!! 0x92000 ~ 0x9B000 까지 스택할당 ! set the stack
	sti								!! set interrupt, disply에서 int 0x10를 호출하기 때문에 ! now it is safe

									!! 자기복제와 스택의 할당을 마치면 'L'을 화면에 찍는다.
	mov	al,#0x0d					! gimme a CR ...
	call	display
	mov	al,#0x0a					! ... an LF ...	!! CRLF-줄바꿈
	call	display
	mov	al,#0x4c					! ... an 'L' ...
	call	display

									!! common.h의 BOOT_PARMS_1의 secondary의 첫번째 배열의 주소값을 가져온다.
lagain:	mov	si,#d_addr 				! ready to load the second stage loader
	push	#SECONDSEG				!! 0x9B00 second.S를 저장할 위치
	pop	es							!! es == 0x9B00
	xor	bx,bx						!! bx == 0
;;	cld                     		! this was done above

sload:	lodsw						!! ds:si 값을 ax로 가져온다. ! get CX
	xchg	cx,ax					!! cx == ds:si BOOT_PARMS_1->secondry[0]의 2바이트가 저장된다.
									!! cx -> ax, ax -> cx : cx = ds:si ax = 0 

#ifndef JRC_NOCOMPACT				!! 1024개 이상의 실린더를 사용할 수 있게끔
        lodsw						! get DX
	mov	dx,ax						!! dx 에는 BOOT_PARMS_1->secondry[0][2]의 2바이트가 저장된다.	
									!! CX에는 sector, track, DX에는 device, head값을 저장한다. 
	or	ax,cx						! at EOF ?		
	jz	done						! yes -> start it
        lodsb						!! AL에 num_of_sector 값을 저장한다.
        test    dl,#LINEAR_FLAG|LBA32_FLAG  
#else
        lodsb						!! al에 device의 값을 가져온다.	
	test    al,#LINEAR_FLAG|LBA32_FLAG
#endif
        jnz     use_linear			!! ZF!=0 use_linear
#ifdef JRC_NOCOMPACT
        dec     si					!! 
	lodsw							!! ax에 BOOT_PARMS_1->secondry[0][2]의 2바이트를 저장한다. 
	mov     dx,ax					!! dx에 device, head를 저장한다.
	or      ax,cx					!! EOF
	jz      done					!! ZF=0 done	
	lodsb							!! al에 number of sector 를 저장
#endif
        mov     ah,#2           	! read command
        int     0x13            	! BIOS read
        jmp     rd_done

use_linear:
#ifndef JRC_NOCOMPACT
        xchg    al,dh           	! save count in DH, address to AL
        mov     ah,hinib        	! linear will get 0
        test    dl,#LBA32_NOCOUNT   ! check if count omitted
        jz      count_ok
        mov     hinib,dh        	! save the hi-nibble
        mov     ah,dh
        mov     dh,#1           	! count is 1
count_ok:
        xchg    ax,di           	! LBA to DI
        mov     al,dh
#else
        mov     dl,al				!! al을 dl에 넣는다.: device값이 저장된다.
	lodsw							!! ah:에는 head 가 들어가고 al에는 num_of_secter
	test    dl,#LBA32_FLAG
	jnz     is_lba
	xor     ah,ah          			! was LINEAR, zero the hi-nibble (was count)
is_lba:
        xchg    ax,di				!! di에는 ax(head:num_of_sec)값을 저장하고, ax는 0이 설정된다.
;;;	mov     al,#1
#endif
;;;        and     dl,#0x8F        	! clear all the spurious flags
	call	lba_read
rd_done:
									!! 0x13-2 인터럽트가 성공하면 CF=0, 그렇지 않으면 CF=1로 설정된다.
									!! AH에는 status 정보가 AL에는 number_of_sectoers가 저장되어 있다.
	jc	error						! error -> start over again
	add	bh,#2    					! next sector
	jmp	sload

done:	mov	al,#0x49				! display an 'I'
	call	display
	jmpi	0,SECONDSEG				! start the second stage loader


#ifndef JRC_NOCOMPACT
hinib:  .byte   0
#endif

error:
#ifndef LCF_NO1STDIAG
        mov	al,#32          		! display a space
	call	display
;;;		        					! display error code in AH
	call	bout
#endif
	xor	ax,ax						! reset the FDC
;;;	mov	dl,al
	int	0x13
	jmp	lagain						! redo from start

#ifndef LCF_NO1STDIAG
bout:	rol     ax,4            	! bring hi-nibble to position
	call	nout
	rol     ax,4            		! bring lo-nibble to position
nout:	and	al,#15					! display one nibble
	add	al,#48
	cmp	al,#58
	jb	nokay
	add	al,#7
nokay:								! fall through
#endif
display:  push  ax              	! new display does not affect AX
        xor	bh,bh					! display on screen
	mov	ah,#14
	int	0x10			 
	pop     ax
	ret
	
	
#include "read.S"

	
theend:
