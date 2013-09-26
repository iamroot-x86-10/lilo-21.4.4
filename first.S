/* first.S  -  LILO first stage boot loader with LBA32 support */

/* Copyright 1992-1998 Werner Almesberger. See file COPYING for details. */
/* LBA extensions Copyright (C) 1999, John Coffman.  Use subject to the  */
/*  terms of the GNU public license agreement.                           */

#define JRC_NOCOMPACT

#define LILO_ASM
#include "lilo.h"

!!; common.h의 BOOT_PARAMS_1에 맞추어 구조체를 작성한다.	
!!; typedef struct {
!!;    char jump[6]; /* jump over the data */
!!;    char signature[4]; /* "LILO" */
!!;    unsigned short stage,version;
!!;    unsigned short timeout; /* 54 msec delay until input time-out,
!!;			       0xffff: never */
!!;    unsigned short delay; /* delay: wait that many 54 msec units. */
!!;    unsigned char port; /* COM port. 0 = none, 1 = COM1, etc. */
!!;    unsigned char ser_param; /* RS-232 parameters, must be 0 if unused */
!!;    unsigned long timestamp; /* timestamp for restoration */
!!;    SECTOR_ADDR descr[3]; /* 2 descriptors and default command line */
!!;    unsigned char prompt; /* 0 = only on demand, =! 0 = always */
!!;    unsigned short msg_len; /* 0 if none */
!!;    SECTOR_ADDR msg; /* initial greeting message */
!!;    SECTOR_ADDR keytab; /* keyboard translation table */
!!;    SECTOR_ADDR secondary[MAX_SECONDARY+1];
!!; } BOOT_PARAMS_1; /* first stage boot loader */


	.text                   	!!; text 세션 시작 .data .bss .rodata	

	.globl	_main

	.org	0               	!!; 현제 위치를 0번지로 설정

!!; typedef struct 
!!;     char jump[6];
	jmp	start

        .org    3               ! special marker for LBA32 code
	.ascii  "lba"           ! this may be removed in the future
	                        ! when the version check is enough
	.org	6

! Boot device parameters. They are set by the installer.

!!;     char signature[4];
	.ascii	"LILO"
!!;     unsigned short stage,version
	.word	STAGE_FIRST
	.word	VERSION

!!;     unsigned short timeout;
timeout:.word	0		! input timeout
!!;     unsigned short delay;
delay:	.word	0		! boot delay
!!;     unsigned char port;
port:	.byte	0		! COM port (0 = unused, 1 = COM1, etc.)
!!;     unsigned char ser_param;
sparam:	.byte	0		! serial port parameters (0 = unused)

!!;     unsigned long timestamp;
tstamp:	.long	0		! timestamp

!!;     SECTOR_ADDR descr[3];
d1_cx:	.word	0		! first descriptor sector address
d1_dx:	.word	0
d1_al:	.byte	0		! (unused)

d2_cx:	.word	0		! second descriptor sector address
d2_dx:	.word	0
d2_al:	.byte	0		! (unused)

dc_cx:	.word	0		! default command-line sector address
dc_dx:	.word	0
dc_al:	.byte	0		! (unused)

!!;     unsigned char prompt;
prompt:	.byte	0		! indicates whether to always enter prompt
				! (also used as alignment byte)

!!;     unsigned short msg_len;
ms_len:	.word	0		! initial greeting message
!!;     SECTOR_ADDR msg;
ms_cx:	.word	0
ms_dx:	.word	0
ms_al:	.byte	0		! (unused)

!!;     SECTOR_ADDR keytab;
kt_cx:	.word	0		! keyboard translation table
kt_dx:	.word	0
kt_al:	.byte	0

!!;     SECTOR_ADDR secondary[MAX_SECONDARY+1]
d_addr:				! second stage sector addresses
!!; } BOOT_PARAMS_1;
						!!; BOOT_PARAMS_1을 설정하는 부분을 완료
	.org	CODE_START_1			!!; CODE_START_1의 위치에는 second stage sector들에 대한 정보가 있을것이다.
							!!;;*HS*	CODE_START_1은 lilo가 install될 때 d_addr를 시작으로 secondary[MAX_SECONDARY+1]의 값 중 필요한 값을 채운 후에,
							!!;;*HS*	그 다음 위치를 기록한다.
							!!;;*HS*	결과적으로 CODE_START_1은 secondary stage sector들의 정보가 있는 것이 아니라, external parameters의 값이 들어있게 된다.
						
						!!; bios에서 넘어오는 si, es, bx, dl값을 저장해 둔다.
						!!; LILO에서는 MBR에의해 boot가 시작되기 이전에 external parmeter를 boot code에 
						!!; 전달하는 메카니즘을 마련해 두었다.
						!!; SI, EX, BX, DL 레지스터를 사용하여 전달한다.
						!!; DL: 0xFE로 설정되어 external parmeter의 유무를 파악하는데 사용
						!!; ES:SI: "LILO" 스트링에 대한 포인터(어드레스 값)
						!!; ES:BX: external command line에 대한 포인터 값
						!!; 하지만 거의 사용하지 않는다고 함
ext_si:	.word	0				! external interface
ext_es:	.word	0
ext_bx:	.word	0
ext_dl:	.byte	0


						!!; main 함수 시작지점
start:	mov	ax,#BOOTSEG		! set DS
						!!; 0x07C0 == ds == ax
	mov	ds,ax				!!; DS의 값을 0x07C0로 맞춘다.
						!!; 0x7C0는 bios에 의해 mbr에 있는 512byes가 메모리에 올라온 위치이다.

	mov	ext_es,es		! copy possible external parameters
	mov	ext_si,si
	mov	ext_bx,bx
	mov	ext_dl,dl			!!; es, si, bx, dl의 값을 저장해둔다.

						!!; 자기복제 코드 시작
						!!; 부트로더는 자신의 코드를 0x9A00으로 복사한후 나머지 작업을 수행한다.	
	mov	ax,#FIRSTSEG			!!; ax == 0x9A00
	mov	es,ax				!!; es == ax == 0x9A00
	mov	cx,#256				!!; cx == 256
	sub	si,si				!!; si == 0
	sub	di,di				!!; di == 0
	cld					!!; 
	rep					!!; ds:si => es:di로 256번복사한다. 총 512byte로 옮겨둔다.
						!!; 0x7C0에 있는 것을 0x9A00으로 
	movsw					!!; move string word
	jmpi	go,FIRSTSEG 			!!; 0x9A00:go 로 jump, far jump로 인해 cs 값이 변경된다.

							!!;;*HS* [REGISTER MAP] 		!	[MEMORY MAP]
							!!;;*HS* [CS] : 0x9A00 : FIRSTSEG !	0x07C00 - 0x07DFF : first.S (MBR)
							!!;;*HS* [DS] : 0x07C0 : BOOTSEG  !	0x9A000 - 0x9A1FF : first.S
							!!;;*HS* [ES] : 0x9A00 : FIRSTSEG !
							!!;;*HS* [FS] : 0x0000 :          !
							!!;;*HS* [GS] : 0x0000 :          !
							!!;;*HS* [SS] : 0x0000 :          !
							!!;;*HS* [SP] : 0x0000 :          !

go:						!!; lilo가 자기복제를 마친후 바로 수행하는 코드

;       cli				! no interrupts
	mov	ds,ax			! AX is already set
						!!; AX == 0x9A00
;;	mov	es,ax			! (ES may be wrong when restarting)
	mov	ax,#STACKSEG			!!; AX == STACKSEG == 0x9000
	mov	ss,ax				!!; SS == AX == STACKSEG == 0x9000
	mov	sp,#STACK		! set the stack
						!!; SP == STACK == 0xB000
						!!; 0x92000 ~ 0x9B000 까지 스택할당
							!!;;*HS* lilo.h에 보면 0x9A200 ~ 0x9AFFF까지를 stack으로 할당하도록 되어있다.
							!!;;*HS* first.S 이후부터 sp(0xB000)까지를 사용한다고 보면 될 것 같다.

	sti				! now it is safe
						!!; set interrupt, display에서 int 0x10를 호출하기 때문에
						!!; 자기복제와 스택의 할당을 마치면 'L'을 화면에 찍는다.
	mov	al,#0x0d		! gimme a CR ...
	call	display
	mov	al,#0x0a		! ... an LF ...	
						!!; CRLF-줄바꿈
	call	display
	mov	al,#0x4c		! ... an 'L' ...
	call	display
							!!;;*HS* [REGISTER MAP] 		!	[MEMORY MAP]
							!!;;*HS* [CS] : 0x9A00 : FIRSTSEG !	0x07C00 - 0x07DFF : first.S (MBR)
							!!;;*HS* [DS] : 0x9A00 : FIRSTSEG !	0x9A000 - 0x9A1FF : first.S
							!!;;*HS* [ES] : 0x9A00 : FIRSTSEG !	0x9A200 - 0x9AFFF : stack
							!!;;*HS* [FS] : 0x0000 :          !
							!!;;*HS* [GS] : 0x0000 :          !
							!!;;*HS* [SS] : 0x9000 : STACKSEG !
							!!;;*HS* [SP] : 0xB000 : STACK    !

						!!; common.h의 BOOT_PARMS_1의 secondary의 첫번째 배열의 주소값을 가져온다.
							!!;;*HS* 현재 first.S의 앞부분이 될 것 이다.
lagain:	mov	si,#d_addr 		! ready to load the second stage loader
	push	#SECONDSEG			!!; 0x9B00 second.S를 저장할 위치
							!!;;*HS* SECONDSEG는 LCF_LARGE_EBDA가 설정되어 있는지에 따라 값이 달라진다.
	pop	es				!!; es == 0x9B00
							!!;;*HS* [REGISTER MAP] 		 !	[MEMORY MAP]
							!!;;*HS* [CS] : 0x9A00 : FIRSTSEG  !	0x07C00 - 0x07DFF : first.S (MBR)
							!!;;*HS* [DS] : 0x9A00 : FIRSTSEG  !	0x9A000 - 0x9A1FF : first.S
							!!;;*HS* [ES] : 0x9B00 : SECONDSEG !	0x9A200 - 0x9AFFF : stack
							!!;;*HS* [FS] : 0x0000 :           !
							!!;;*HS* [GS] : 0x0000 :           !
							!!;;*HS* [SS] : 0x9000 : STACKSEG  !
							!!;;*HS* [SP] : 0xB000 : STACK     !

	xor	bx,bx				!!; bx == 0
;;	cld                     	! this was done above

sload:	lodsw				! get CX
						!!; ds:si 값을 ax로 가져온다.
	xchg	cx,ax				!!; cx == ds:si BOOT_PARMS_1->secondry[0]의 2바이트가 저장된다.
						!!; cx -> ax, ax -> cx : cx = ds:si ax = 0 

#ifndef JRC_NOCOMPACT				!!; 1024개 이상의 실린더를 사용할 수 있게끔
							!!;;*HS* 1024이상의 실린더를 사용할 수 있도록 하는 것은 EDD로, LBA32_FLAG와 연관이 있다.
							!!;;*HS* JRC_NOCOMPACT는 multi-sector read 기능을 사용할 것인지를 확인하는 flag이다.
							!!;;*HS* 결과적으로 JRC_NOCOMPACT, LBA32_FLAG가 셋팅되어야만 EDD를 사용가능하다.
        lodsw				! get DX
	mov	dx,ax				!!; dx 에는 BOOT_PARMS_1->secondry[0][2]의 2바이트가 저장된다.	
						!!; CX에는 sector, track, DX에는 device, head값을 저장한다. 
	or	ax,cx			! at EOF ?		
	jz	done			! yes -> start it
        lodsb					!!; AL에 num_of_sector 값을 저장한다.
        test    dl,#LINEAR_FLAG|LBA32_FLAG  
#else
        lodsb					!!; al에 device의 값을 가져온다.
	test    al,#LINEAR_FLAG|LBA32_FLAG
#endif
        jnz     use_linear			!!; ZF!=0 use_linear
        						!!;;*HS* LBA32_FLAG가 존재할 경우에 INT 13h가 아닌 EDD(Enhanced Disk Drive Specification)을 사용하게 되어 있다.
        						!!;;*HS* 그 이유는,
        						!!;;*HS* 기존 CHS를 사용하는 INT 13h를 이용하게 되면, Cylinder 10bit, Head 8bit, Sector 6bit 총 24bit를 이용해서 어드레싱하게 되는데,
        						!!;;*HS* 이때 primary disk(MBR이 있는)가 8.4 GiB이상이라면 사용할 수 없게 된다.
        						!!;;*HS* LBA32_FLAG를 가지고 use_linear 함수?를 사용하게 되면,
        						!!;;*HS* ATA Task File을 이용한 packet을 작성해서 동작합으로 64bit addressing을 통해 더 큰 HDD를 지원 할 수 있다.
        						!!;;*HS* LILO는 LBA32_FLAG가 셋팅되어야만 EDD를 사용하도록 되어 있다.
        						!!;;*HS* 
        						!!;;*HS* use_linear에서 lba_read를 통해 EDD를 사용하는 부분이 나오는데,
        						!!;;*HS* 실제 INT 13h 0x41을 통해 BIOS가 EDD를 지원하는지 확인하고 진행하도록 되어있다. 관련 내용은 나중에 real-mode kernel에서도 확인한다.
#ifdef JRC_NOCOMPACT
        dec     si					!!; 
	lodsw						!!; ax에 BOOT_PARMS_1->secondry[0][2]의 2바이트를 저장한다. 
	mov     dx,ax					!!; dx에 device, head를 저장한다.
	or      ax,cx					!!; EOF
	jz      done					!!; ZF=0 done	
	lodsb						!!; al에 number of sector 를 저장
#endif
        mov     ah,#2           	! read command
        int     0x13            	! BIOS read
        jmp     rd_done

use_linear:
#ifndef JRC_NOCOMPACT
        xchg    al,dh           	! save count in DH, address to AL
        mov     ah,hinib        	! linear will get 0
        test    dl,#LBA32_NOCOUNT   	! check if count omitted
        jz      count_ok
        mov     hinib,dh        	! save the hi-nibble
        mov     ah,dh
        mov     dh,#1           	! count is 1
count_ok:
        xchg    ax,di           	! LBA to DI
        mov     al,dh
#else
        mov     dl,al				!!; al을 dl에 넣는다.: device값이 저장된다.
	lodsw					!!; ah:에는 head 가 들어가고 al에는 num_of_secter
	test    dl,#LBA32_FLAG
	jnz     is_lba
	xor     ah,ah          		! was LINEAR, zero the hi-nibble (was count)
is_lba:
        xchg    ax,di				!!; di에는 ax(head:num_of_sec)값을 저장하고, ax는 0이 설정된다.
;;;	mov     al,#1
#endif
;;;        and     dl,#0x8F        	! clear all the spurious flags
	call	lba_read
rd_done:
						!!; 0x13-2 인터럽트가 성공하면 CF=0, 그렇지 않으면 CF=1로 설정된다.
						!!; AH에는 status 정보가 AL에는 number_of_sectoers가 저장되어 있다.
	jc	error			! error -> start over again
	add	bh,#2    		! next sector
	jmp	sload

done:	mov	al,#0x49		! display an 'I'
	call	display
	jmpi	0,SECONDSEG		! start the second stage loader

							!!;;*HS* [REGISTER MAP] 		 !	[MEMORY MAP]
							!!;;*HS* [CS] : 0x9B00 : SECONDSEG !	0x07C00 - 0x07DFF : first.S (MBR)
							!!;;*HS* [DS] : 0x9A00 : FIRSTSEG  !	0x9A000 - 0x9A1FF : first.S
							!!;;*HS* [ES] : 0x9B00 : SECONDSEG !	0x9A200 - 0x9AFFF : stack
							!!;;*HS* [FS] : 0x0000 :           !	0x9B000 - ? 	  : second.S
							!!;;*HS* [GS] : 0x0000 :           !
							!!;;*HS* [SS] : 0x9000 : STACKSEG  !
							!!;;*HS* [SP] : 0xB000 : STACK     !

#ifndef JRC_NOCOMPACT
hinib:  .byte   0
#endif

error:
#ifndef LCF_NO1STDIAG
        mov	al,#32          	! display a space
	call	display
;;;		        		! display error code in AH
	call	bout
#endif
	xor	ax,ax			! reset the FDC
;;;	mov	dl,al
	int	0x13
	jmp	lagain			! redo from start

#ifndef LCF_NO1STDIAG
bout:	rol     ax,4            	! bring hi-nibble to position
	call	nout
	rol     ax,4            	! bring lo-nibble to position
nout:	and	al,#15			! display one nibble
	add	al,#48
	cmp	al,#58
	jb	nokay
	add	al,#7
nokay:					! fall through
#endif
display:  push  ax              	! new display does not affect AX
        xor	bh,bh			! display on screen
	mov	ah,#14
	int	0x10			 
	pop     ax
	ret
	
	
#include "read.S"

	
theend:
