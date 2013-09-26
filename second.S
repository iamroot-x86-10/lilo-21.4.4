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


							!!;*HS* first.S에서 넘어올때 레지스터 상태.
							!!;*HS* [REGISTER MAP] 		 !	[MEMORY MAP]
							!!;*HS* [CS] : 0x9B00 : SECONDSEG !	0x07C00 - 0x07DFF : first.S (MBR)
							!!;*HS* [DS] : 0x9A00 : FIRSTSEG  !	0x9A000 - 0x9A1FF : first.S
							!!;*HS* [ES] : 0x9B00 : SECONDSEG !	0x9A200 - 0x9AFFF : stack
							!!;*HS* [FS] : 0x0000 :           !	0x9B000 - ? 	  : second.S
							!!;*HS* [GS] : 0x0000 :           !
							!!;*HS* [SS] : 0x9000 : STACKSEG  !
							!!;*HS* [SP] : 0xB000 : STACK     !


	.text

	.globl	_main
	.org	0

!!;*HS* LILO 인스톨시에 채워지는 값들.
!!;*HS* typedef struct {
!!;*HS*     char jump[6]; /* jump over the data */
_main:	jmp	start

	.org	6

!!;*HS*     char signature[4]; /* "LILO" */
sig:	.ascii	"LILO"
!!;*HS*     unsigned short stage,version;
stage:	.word	STAGE_SECOND
version:.word	VERSION
!!;*HS* } BOOT_PARAMS_2; /* second stage boot loader */
!!;*HS* BOOT_PARANS_2의 값들을 저장한다.

	.org	CODE_START_2

start:	seg	ss		! use a COM port ?	
						!!; ss = 0x9000	
						!!; 0x9A0000 - 6 + DSC_OFF
						!!; DSC_OFF == BOOT_PARAMS_1->descr
						!!; BOOT_PARMAS_1->port의 값을 가져온다.
	mov	dx,DSC_OFF-6+SSDIFF		
		sub	dl,#1			!!; dl이 1이면 시리얼포트 1을 사용하겠다.
						!!; dl이 0이면 시리얼포트를 사용하지않겠다.
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
						!!; 왜 32번의 루프를 도는 것일까?
						!!; 바이오스 영역에 있는 키보드 원형 큐 버퍼가 32byte 이지만
						!!; 아스키/스캔코드로 한번 누르면 2바이트씩 증가한다.
						!!; 실제 인터럽트 16h를 사용해서 비워보면 키버퍼의 최대개수는 15개 
						!!; head, tail의 키가 같으면 비어있는 의미이다. 
						!!; 16번만 돌면 충분히 다비워지는데 32번을 도는 이유는
						!!; 0x480,0x482를 이용하여 키보드 버퍼를 줄이거나 늘릴수 있다.
						!!; 그래서 넉넉하게 32번으로 잡아놓은거 같다.
drkbd:	mov	ah,#1		! is a key pressed ?
	int	0x16				!!; 0x16-1 인터럽트는 Z플레그에 키값이 있으면 0, 그렇지 않으면 1을
						!!; 설정한다.	
	jz	comcom		! no -> done 	!!; 키보드 버퍼가 다 비워졌다.
	xor	ah,ah		! get the key	!!; 0x16-0 인터럽트를 이용하여 아스키/스켄코드로 2byte를 읽어온다.
	int	0x16				!!; 아무것도 안하니깐 결국 비워지는 효과
	loop	drkbd				!!; cx 에 설정된 값만큼 루프를 돈다.
#endif

comcom:	mov	al,#0x4c	! display an 'L' LIL
	call	display				!!;"LILO"의 2번째 'L'을 출력한다.
	xor	ax,ax		! get pointer to disk parameter table in DS:SI
	mov	ds,ax
							!!;;*HS* [REGISTER MAP] 	   !	[MEMORY MAP]
							!!;;*HS* [CS] : 0x9B00 : SECONDSEG !	0x07C00 - 0x07DFF : first.S (MBR)
							!!;;*HS* [DS] : 0x0000 :           !	0x9A000 - 0x9A1FF : first.S
							!!;;*HS* [ES] : 0x9B00 : SECONDSEG !	0x9A200 - 0x9AFFF : stack
							!!;;*HS* [FS] : 0x0000 :           !	0x9B000 - ? 	  : second.S
							!!;;*HS* [GS] : 0x0000 :           !
							!!;;*HS* [SS] : 0x9000 : STACKSEG  !
							!!;;*HS* [SP] : 0xB000 : STACK     !	

	lds	si,0x78				!!; 0x0000:0x78 에 있는 값이 DS:SI에 설정이 된다. 
						!!; DS:SI의 값이 0xF000:0xEFC7
						!!; 0x1e 인터럼트 참조
						!!; 0x0000:0x0078은 real-mode에서의 인터럽트 백터 테이블 
						!!; 영역에 속한다.(0x78 /4 = 0x1e) 
			   			!!; 1E에 해당되는 엔트리 위치가 바로 0x000:0078	

						!!; floppy Disk Initialization Parameter Table Vector를
						!!; 수정하는 작업

						!!; floppy Disk Initialization Parameter Table Vector Definition:
						!!; 12byte로 구성
						!!; 
						!!; offset 
						!!; 00 controller mode 
						!!; 01 Disk Controller Mode
						!!; 02 clock ticks until motor off
						!!; 03 FM or MFM Mode
						!!; 04 last sector on track
						!!; 05 gap length in bytes
						!!; 06 disk data length
						!!; 07 gap length when formatting
						!!; 08 data pattern used during formatting
						!!; 09 floppy head bounce delay
						!!; 0A floppy motor start delay
						!!; 0B flopy motor stop delay

#ifndef LCF_XL_SECS
	cmp	byte ptr (si+4),#9 ! okay ?  			!!;last sector on track 과 9를 비교한다.
	ja	dskok		! yes -> do not patch 		!!; 9보다 크면 dskok로 가라.
								!!; 여기서 9는 '한 트랙 당 섹터 수'의 가능한 최소값이다.??
									!!;;*HS* 위에서 읽어온 disk parameter table은 floppy용이다.
									!!;;*HS* 5" 플리피는 9개, 3.5" 플로피는 18개의 섹터를 가짐으로, 최소값이 9가 된다.
									!!;;*HS* 9보다 작거나 같으면 5"플로피로 생각하고 관련 처리후 dskok(disk ok)로 분기한다.
#endif
	push	cs		! get pointer to new area in ES:DI
	pop	es				!!; CS에 있는 값을 ES로 넣는다.						
	mov	di,#dskprm			!!; dskprm(12bytes)의 위치를 di에 저장
	mov	cx,#6		! copy 12 bytes
	rep
	movsw					!!; DS:SI를 ES:DI로 mov 즉disk initialization parameter table 백터를 
						!!; ES:DI 영역으로 복사한다.
	seg	es		! patch number of sectors 	
						!!; 포인터를 dskprm으로 지정한다. 
#ifndef LCF_XL_SECS
	mov	byte ptr (di-8),#18		!!; last sector on track의 값을 18로 바꾼다.
						!!; di가 현재 vector table의 끝을 가르키고 있기 때문에
						!!; -8을 해주면 last sector on track을 가르킨다.
#else
	mov	byte ptr (di-8),#LCF_XL_SECS
#endif
	cli			! paranoia		
	xor	ax,ax		! store new pointer
	mov	ds,ax
	mov	0x78,#dskprm			!!;기존의 disk parameter vector table의 위치를
						!!;우리의 0x9B00:#dskprm로 바꾼다.
	mov	0x7a,es				!!;여기까지.
	sti					
						!!; 여기 까지가 Disk Initialization Parameter Table Vector를
						!!; 수정하는 작업에 해당한다.

dskok:	seg	cs		! clear the break flag
	mov	byte ptr break,#0		!!; break에 0을 저장.
	call	instto		! get timer interrupt
						!!;*HS* 타이머 인터럽트 핸들러를 바꿔준다.
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
							!!;;*HS* [REGISTER MAP] 	   !	[MEMORY MAP]
							!!;;*HS* [CS] : 0x9B00 : SECONDSEG !	0x07C00 - 0x07DFF : first.S (MBR)
							!!;;*HS* [DS] : 0x9B00 : SECONDSEG !	0x9A000 - 0x9A1FF : first.S
							!!;;*HS* [ES] : 0x9B00 : SECONDSEG !	0x9A200 - 0x9AFFF : stack
							!!;;*HS* [FS] : 0x0000 :           !	0x9B000 - ? 	  : second.S
							!!;;*HS* [GS] : 0x0000 :           !
							!!;;*HS* [SS] : 0x9000 : STACKSEG  !
							!!;;*HS* [SP] : 0xB000 : STACK     !								
;;;	sti
						!!; second.S가 잘 로딩 되었는지 검사한다.
						!!; BOOTPARM_2의 값들중 'LILO'와 STAGE_SECOND, VERSION
						!!; 을 검사한다.	
	cmp	sig,#0x494c	! check that this is really loaded at the !!;0x494C == 'LI'
				! right place ...
	jne	crshbrn
	cmp	sig+2,#0x4f4c 			!!;0x4f4c == 'LO'
	jne	crshbrn
	cmp	stage,#STAGE_SECOND
	jne	crshbrn
	cmp	version,#VERSION
	jne	crshbrn
	mov	cmdbeg,#acmdbeg	! probably unattended boot
						!!; 여기까지가 무결성 검사 완료


ldsc:							!!;*HS* first.S를 참조해서, 이미지 디스크립터 테이블을 로딩한다.
							!!;*HS* 첫번째 Image descriptor 로딩 -> 0x9D200
							!!;*HS* 두번째 Image descriptor 로딩 -> 0x9D400
							!!;*HS* 로딩한 2개의 descriptor table의 checksum을 확인한다.
;;;	mov	al,#1		! load the descriptor table
	mov	bx,#DESCR 				!!;*HS* BX == #DESCR == 0x2200							
	seg	ss
	mov	cx,DSC_OFF+SSDIFF   		!!;BOOT_PARAMS_1->descr[0]의 sector,track 값을 cx에 저장
	seg	ss
	mov	dx,DSC_OFF+2+SSDIFF 		!!;BOOT_PARAMS_1->descr[0]의 device,head 값을 dx에 저장
        seg     ss
	mov	al,DSC_OFF+4+SSDIFF 		!!;BOOT_PARAMS_1->descr[0]의 num_sect값을 al에 저장
	call	cread				!!;해당 섹터값을 읽어 0x9200:0x2200에 저장
							!!;*HS* cread는 ES:BX(0x9B00:0x2200 == 0x9D200)에 저장된다.
	jc	fdnok		! error -> retry
;;;	mov	al,#1		! load the second sector
	mov	bx,#DESCR+512       		!!;다음 decriptor table을 저장할 위치는 512바이트 이후이다.
	seg	ss
	mov	cx,DSC_OFF2+SSDIFF 		!!;BOOT_PARAMS_1->descr[1]의sector,track값을 cx에 저장
	seg	ss
	mov	dx,DSC_OFF2+2+SSDIFF 		!!;BOOT_PARAMS_1->descr[1]의device,head값을 dx에 저장
        seg     ss                      ;;;
	mov	al,DSC_OFF2+4+SSDIFF 		!!;BOOT_PARAMS_1->descr[1]의 num_sect값을 al에 저장
	call	cread           		!!;해당 섹터값을 읽어 0x9200:0x2200+512에 저장
							!!;*HS* cread는 ES:BX(0x9B00:0x2400 == 0x9D400)에 저장된다.

							!!;;*HS* [REGISTER MAP] 	   !	[MEMORY MAP]
							!!;;*HS* [CS] : 0x9B00 : SECONDSEG !	0x07C00 - 0x07DFF : first.S (MBR)
							!!;;*HS* [DS] : 0x9B00 : SECONDSEG !	0x9A000 - 0x9A1FF : first.S
							!!;;*HS* [ES] : 0x9B00 : SECONDSEG !	0x9A200 - 0x9AFFF : stack
							!!;;*HS* [FS] : 0x0000 :           !	0x9B000 - ? 	  : second.S
							!!;;*HS* [GS] : 0x0000 :           !	0x9D200 - 0x9D3FF : image descriptor [0] <- BOOT_PARAMS_1.descr[0]이 가리키는 섹터가 로딩됨.
							!!;;*HS* [SS] : 0x9000 : STACKSEG  !	0x9D400 - 0x9D5FF : image descriptor [1] <- BOOT_PARAMS_1.descr[1]이 가리키는 섹터가 로딩됨.
							!!;;*HS* [SP] : 0xB000 : STACK     !	

	jc	fdnok		! error -> retry !!; BOOT_PARAMS_1->descr[0~1]을 메모리로 load하는것을 완료
	mov	si,#DESCR	! compute a checksum of the descriptor table
	mov	bx,#INIT_CKS
	cld
	mov	cx,#0x200   			!!; 0x200 == 512를 의미 한다.
csloop:	lodsw					!!; DS:SI의 값을 AX에 저장 즉, 첫번째 descriptor가 저장되어 있는 위치
	xor	bx,ax				!!; xor를 통하여 2byte 씩 체크섬 결과값을 bx에 누적시킨다.
	loop	csloop				!!; 2개의 섹터 1024bytes 만큼 체크섬 검사
	or	bx,bx		! okay ? 	!!; 누적된 bx의 값이 0이 나와야 정상이다.
	jnz	chkerr				!!; 체크섬 검사 완료
	seg	ss		! load the keyboard translation table
	mov	cx,MSG_OFF+SSDIFF+7		!!; 0x9000:0xA000 + MSG_OFF + 7 = BOOT_PARMS_1->keytab
	                           		!!; sector,track값을 cx에 저장
	seg	ss
	mov	dx,MSG_OFF+SSDIFF+9		!!; BOOT_PARAMS_1->keytab의 device,head값을 dx에 저장
        seg     ss                      ;;;
	mov	al,MSG_OFF+SSDIFF+11    	!!; BOOT_PARAMS_1->keytab의 num_sect값을 al에 저장
	mov	bx,#KEYTABLE			!!; 섹터정보를 읽을 위치를 지정
						!!; 0x9200:0x2800에 저장된다.
							!!;*HS* cread는 ES:BX(0x9B00:0x2800에 == 0x9D800)에 저장된다.

							!!;;*HS* [REGISTER MAP] 	   !	[MEMORY MAP]
							!!;;*HS* [CS] : 0x9B00 : SECONDSEG !	0x07C00 - 0x07DFF : first.S (MBR)
							!!;;*HS* [DS] : 0x9B00 : SECONDSEG !	0x9A000 - 0x9A1FF : first.S
							!!;;*HS* [ES] : 0x9B00 : SECONDSEG !	0x9A200 - 0x9AFFF : stack
							!!;;*HS* [FS] : 0x0000 :           !	0x9B000 - ? 	  : second.S
							!!;;*HS* [GS] : 0x0000 :           !	0x9D200 - 0x9D3FF : image descriptor [0] <- BOOT_PARAMS_1.descr[0]이 가리키는 섹터가 로딩됨.
							!!;;*HS* [SS] : 0x9000 : STACKSEG  !	0x9D400 - 0x9D5FF : image descriptor [1] <- BOOT_PARAMS_1.descr[1]이 가리키는 섹터가 로딩됨.
							!!;;*HS* [SP] : 0xB000 : STACK     !	
							!!;;*HS*                           !	0x9D800 - 0x9D9FF : keyboard translation table
;;;	mov	al,#1
	call	cread
	jc	fdnok
;;;	mov	al,#1		! load the default command line
	mov	bx,#DFLCMD			!!; 0x2600
	seg	ss
	mov	cx,DFCMD_OFF+SSDIFF		!!; BOOT_PARAMS_1->descr[2]의 값을 가져온다. 
						!!; setor,track값을 가져온다.
	seg	ss
	mov	dx,DFCMD_OFF+2+SSDIFF   	!!; device,head값을 가져온다.
	seg	ss                      ;;;
	mov	al,DFCMD_OFF+4+SSDIFF   	!!; num_sect값을 가져온다.
	call	cread				!!; 0x9200:0x2600에 default command line을 로드한다.
	jc	fdnok		! error -> retry !!; load default command line완료
							!!;*HS* cread는 ES:BX(0x9B00:0x2800에 == 0x9D800)에 저장된다.

							!!;;*HS* [REGISTER MAP] 	   !	[MEMORY MAP]
							!!;;*HS* [CS] : 0x9B00 : SECONDSEG !	0x07C00 - 0x07DFF : first.S (MBR)
							!!;;*HS* [DS] : 0x9B00 : SECONDSEG !	0x9A000 - 0x9A1FF : first.S
							!!;;*HS* [ES] : 0x9B00 : SECONDSEG !	0x9A200 - 0x9AFFF : stack
							!!;;*HS* [FS] : 0x0000 :           !	0x9B000 - ? 	  : second.S
							!!;;*HS* [GS] : 0x0000 :           !	0x9D200 - 0x9D3FF : image descriptor [0] <- BOOT_PARAMS_1.descr[0]이 가리키는 섹터가 로딩됨.
							!!;;*HS* [SS] : 0x9000 : STACKSEG  !	0x9D400 - 0x9D5FF : image descriptor [1] <- BOOT_PARAMS_1.descr[1]이 가리키는 섹터가 로딩됨.
							!!;;*HS* [SP] : 0xB000 : STACK     !	0x9D600 - 0x9D7FF : default command line
							!!;;*HS*                           !	0x9D800 - 0x9D9FF : keyboard translation table
	mov	bx,#DFLCMD
	cmp	word ptr (bx),#DC_MAGIC ! okay ?	!!;;*HS* DC_MAGIC == 0xF4F2와 일치하는지 확인한다.
	jne	bdcmag		! no -> do not write 
#ifndef LCF_READONLY
	mov	word ptr (bx),#DC_MGOFF ! erase the magic number
						!!; 매직 코드값을 바꾸고 disc에 write 한다.
							!!;;*HS* 현재 DISK가 RO가 아니라면,
							!!;;*HS* 현재 default command line의 magic number를 0x6B6D로 바꾸고,
							!!;;*HS* 바뀐 dflcmd를 file에 덮어쓴다.
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
	br	ldsc		! retry !!; br = jmp

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

							!!;;*HS* [REGISTER MAP] 	   !	[MEMORY MAP]
							!!;;*HS* [CS] : 0x9B00 : SECONDSEG !	0x07C00 - 0x07DFF : first.S (MBR)
							!!;;*HS* [DS] : 0x9B00 : SECONDSEG !	0x9A000 - 0x9A1FF : first.S
							!!;;*HS* [ES] : 0x9B00 : SECONDSEG !	0x9A200 - 0x9AFFF : stack
							!!;;*HS* [FS] : 0x0000 :           !	0x9B000 - ? 	  : second.S
							!!;;*HS* [GS] : 0x0000 :           !	0x9D200 - 0x9D3FF : image descriptor [0] <- BOOT_PARAMS_1.descr[0]이 가리키는 섹터가 로딩됨.
							!!;;*HS* [SS] : 0x9000 : STACKSEG  !	0x9D400 - 0x9D5FF : image descriptor [1] <- BOOT_PARAMS_1.descr[1]이 가리키는 섹터가 로딩됨.
							!!;;*HS* [SP] : 0xB000 : STACK     !	0x9D600 - 0x9D7FF : default command line
							!!;;*HS*                           !	0x9D800 - 0x9D9FF : keyboard translation table

dokay:
	mov	bx, #ospc	! display 'O '
	call	say				!!; say는 스트링을 출력하는 함수
	mov	ospc, #0	! disable the message
						!!; 주소는 그냥 넣어주고, 변수는 ptr을 사용하여 값을 저장한다.
	mov	word ptr vgaovr, #VGA_NOCOVR ! disable VGA override
						!!; vgaovr == VGA_NOCOVR == 0x8000
	mov	word ptr memlim, #0	! no memory limit
	xor	ax, ax		! get the delay and disable further delays
	seg	ss
	xchg	ax, DSC_OFF-8+SSDIFF		!!; ax에는 BOOT_PARAMS_1->delay값이 저장되고 delay에는 0으로 저장
	or	old_del, ax	! remember delay
						!!; old_del에 delay값을 저장한다.
	mov	nodfl, #iloop	! interactive prompt if falling through
	seg	ss		! enter boot prompt ?
	cmp	byte ptr DSC_OFF+15+SSDIFF, #0 	!!; BOOT_PARAMS_1->prompt를 0과 비교한다.
	jne	extp		! yes -> check for external parameters

	mov	nodfl, #bfirst	! boot first image if falling through
	call	waitsh		! wait for a shifting key
	jc	iloop		! key pressed -> enter interactive mode

! Check for external parameters

extp:	seg	ss		! external parameters ?
	cmp	byte ptr EX_OFF+6,#EX_DL_MAG 	!!; 0x9000:0xA000 + CODE_START_1 + 6 즉,ext_dl값과 0xFE 를 비교한다. 
	jne	noex		! no -> go on
	seg	ss		! clear flag
	mov	byte ptr EX_OFF+6,#0		!!; ext_dl값에 0을 저장한다.
	seg	ss		! load the signature pointer
	les	bx,EX_OFF			!!; ss:EX_OFF의 주소값을 es:bx에 저장한다.
	seg	es		! "LI" ?	!!; first.S의 85~100 라인 참고
	cmp	(bx),#EX_MAG_L
	jne	noex		! no -> go on
	seg	es		! "LO" ?
	cmp	(bx+2),#EX_MAG_H
	jne	noex		! no -> go on
	seg	ss
	mov	si,EX_OFF+4	! pointer to the command line 	
						!!;ext_bx값을  si에 저장한다.
	seg	es
	cmp	byte ptr (si),#0 ! empty ?
	je	iloop		! yes -> enter interactive mode 	!!;*HS* interactive mode     -> boot: 프롬프트를 띄움.
									!!;*HS* 	- message 파일의 길이 체크.
									!!;*HS* 	- msg를 파일에서 읽어와 로딩 -> 0x9D000
									!!;*HS* 	- 0x9D000에 올라온 파일을 바탕으로 전체 메시지를 로딩 -> 0x10000
									!!;*HS* 	- call say를 통해 저장된 메시지를 출력한다.
									!!;*HS* 	- boot: 프롬프트를 출력한다.
	jmp	niloop		! enter non-interactive mode 		!!;*HS* non-interactive mode -> 알아서 진행..

! No external parameters after timeout -> boot first image

noex:	push	cs		! restore ES
	pop	es
	mov	si,#DFLCMD+2	! default command line ?
	cmp	byte ptr (si),#0
	jne	niloop		! yes -> use it
	mov	ax,nodfl	! no idea how to tell as86 to do jmp (addr) :-(
	jmp	ax		! fall through


! Command input processor

							!!;;*HS* [REGISTER MAP] 	   !	[MEMORY MAP]
							!!;;*HS* [CS] : 0x9B00 : SECONDSEG !	0x07C00 - 0x07DFF : first.S (MBR)
							!!;;*HS* [DS] : 0x9B00 : SECONDSEG !	0x9A000 - 0x9A1FF : first.S
							!!;;*HS* [ES] : 0x9B00 : SECONDSEG !	0x9A200 - 0x9AFFF : stack
							!!;;*HS* [FS] : 0x0000 :           !	0x9B000 - ? 	  : second.S
							!!;;*HS* [GS] : 0x0000 :           !	0x9D200 - 0x9D3FF : image descriptor [0] <- BOOT_PARAMS_1.descr[0]이 가리키는 섹터가 로딩됨.
							!!;;*HS* [SS] : 0x9000 : STACKSEG  !	0x9D400 - 0x9D5FF : image descriptor [1] <- BOOT_PARAMS_1.descr[1]이 가리키는 섹터가 로딩됨.
							!!;;*HS* [SP] : 0xB000 : STACK     !	0x9D600 - 0x9D7FF : default command line
							!!;;*HS*                           !	0x9D800 - 0x9D9FF : keyboard translation table

!!;*HS* iloop
!!;*HS* 	- message 파일의 길이 체크.
!!;*HS* 	- msg를 파일에서 읽어와 로딩 -> 0x9D000
!!;*HS* 	- 0x9D000에 올라온 파일을 바탕으로 전체 메시지를 로딩 -> 0x10000
!!;*HS* 	- call say를 통해 저장된 메시지를 출력한다.
!!;*HS* 	- boot: 프롬프트를 출력한다.
iloop:
	seg	ss		! message disabled ?
	cmp	MSG_OFF+SSDIFF, #0
	je	nomsg		! yes -> skip this	!!;*HS* 	- message 파일의 길이 체크. 0이면 nomsg
	mov	bx,#crlf	! move to a new line
	call	say

	seg	ss		! load the message file
	mov	cx,MSG_OFF+SSDIFF+2
	seg	ss
	mov	dx,MSG_OFF+SSDIFF+4
	mov	bx,#MAP 				!!;*HS* BX == #MAP == 0x2000
	seg     ss
	mov	al, MSG_OFF+SSDIFF+6 			!!;*HS* AL == keytab의 주소를 넣었음.
	call	sread 					
	call	loadfile				!!;*HS* ES == SYSSEG == 0x10000, BX == 0
	mov	ax, #SYSSEG				!!;*HS* AX == SYSSEG == 0x10000
	mov	ds, ax
	xor	bx, bx		! set the terminating NUL and disable further
				! messages

							!!;;*HS* [REGISTER MAP] 	    !	[MEMORY MAP]
							!!;;*HS* [CS] : 0x09B00 : SECONDSEG !	0x07C00 - 0x07DFF : first.S (MBR)
							!!;;*HS* [DS] : 0x10000 : SYSSEG    !	0x10000 - ?       : loaded message... using BOOT_PARAMS_1.map
							!!;;*HS* [ES] : 0x10000 : SYSSEG    !	0x9A000 - 0x9A1FF : first.S
							!!;;*HS* [FS] : 0x00000 :           !	0x9A200 - 0x9AFFF : stack
							!!;;*HS* [GS] : 0x00000 :           !	0x9B000 - ? 	  : second.S
							!!;;*HS* [SS] : 0x09000 : STACKSEG  !	0x9D000 - 0x9D1FF : file map load area
							!!;;*HS* [SP] : 0x0B000 : STACK     !	0x9D200 - 0x9D3FF : image descriptor [0] <- BOOT_PARAMS_1.descr[0]이 가리키는 섹터가 로딩됨.
							!!;;*HS*                            !	0x9D400 - 0x9D5FF : image descriptor [1] <- BOOT_PARAMS_1.descr[1]이 가리키는 섹터가 로딩됨.
							!!;;*HS*                            !	0x9D600 - 0x9D7FF : default command line
							!!;;*HS*                            !	0x9D800 - 0x9D9FF : keyboard translation table

	seg	ss
	xchg	bx, MSG_OFF+SSDIFF
	mov	byte ptr (bx), #0
	xor	bx, bx		! display the message
	call	say
	push	cs		! restore segment registers
	pop	ds
	push	cs
	pop	es
							!!;;*HS* [REGISTER MAP] 	    !	[MEMORY MAP]
							!!;;*HS* [CS] : 0x09B00 : SECONDSEG !	0x07C00 - 0x07DFF : first.S (MBR)
							!!;;*HS* [DS] : 0x09B00 : SECONDSEG !	0x10000 - ?       : loaded message... using BOOT_PARAMS_1.map
							!!;;*HS* [ES] : 0x09B00 : SECONDSEG !	0x9A000 - 0x9A1FF : first.S
							!!;;*HS* [FS] : 0x00000 :           !	0x9A200 - 0x9AFFF : stack
							!!;;*HS* [GS] : 0x00000 :           !	0x9B000 - ? 	  : second.S
							!!;;*HS* [SS] : 0x09000 : STACKSEG  !	0x9D000 - 0x9D1FF : file map load area
							!!;;*HS* [SP] : 0x0B000 : STACK     !	0x9D200 - 0x9D3FF : image descriptor [0] <- BOOT_PARAMS_1.descr[0]이 가리키는 섹터가 로딩됨.
							!!;;*HS*                            !	0x9D400 - 0x9D5FF : image descriptor [1] <- BOOT_PARAMS_1.descr[1]이 가리키는 섹터가 로딩됨.
							!!;;*HS*                            !	0x9D600 - 0x9D7FF : default command line
							!!;;*HS*                            !	0x9D800 - 0x9D9FF : keyboard translation table
nomsg:
	mov	cmdbeg, #acmdbeg ! probably unattended boot
	mov	si, #usrinpm	 ! interactive mode

niloop:
	mov	bx, #msg_p	! display boot prompt
	call	say
	mov	bx, #cmdline	! move cursor to the end of the line

clend:
	mov	al, (bx)
	or	al, al		! at end ?
	jz	cledne		! yes -> go on
	push	bx		! display the character
	call	display
	pop	bx
	inc	bx		! next one
	jne	clend

cledne:
	mov	byte ptr prechr, #32 ! character before command line is a space

! Input loop

input:
	seg	es		! interactive mode ?
	cmp	byte ptr (si),#UI_MAGIC
	je	kbinp		! yes -> get keyboard input
	seg	es		! get non-interactive input
	mov	al,(si)
	inc	si
	jmp	gotinp		! go on
	
tolist:	br	list		! ...

kbinp:
	mov	cx,#brto	! get a key
	call	getkey

gotinp:
	cmp	al,#9		! TAB ?
	je	tolist		! yes -> list images
	cmp	al,#63		! "?" ?
	je	tolist		! yes -> list images
	or	al,al		! NUL ?
	je	nul			! yes -> go on
	cmp	al,#13		! CR ?
	je	cr			! yes -> go on
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

noblnk:
	cmp	bx,#cmdline+CL_LENGTH ! at end of buffer ?
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

cr:
	mov		cmdbeg, #mcmdbeg ! probably manual boot

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

							!!;*HS* [REGISTER MAP] 	           !	[MEMORY MAP]
							!!;*HS* [CS] : 0x09B00 : SECONDSEG !	0x07C00 - 0x07DFF : first.S (MBR)
							!!;*HS* [DS] : 0x09B00 : SECONDSEG !	0x10000 - ?       : loaded message... using BOOT_PARAMS_1.map
							!!;*HS* [ES] : 0x09B00 : SECONDSEG !	0x9A000 - 0x9A1FF : first.S
							!!;*HS* [FS] : 0x00000 :           !	0x9A200 - 0x9AFFF : stack
							!!;*HS* [GS] : 0x00000 :           !	0x9B000 - ? 	  : second.S
							!!;*HS* [SS] : 0x09000 : STACKSEG  !	0x9D000 - 0x9D1FF : file map load area
							!!;*HS* [SP] : 0x0B000 : STACK     !	0x9D200 - 0x9D3FF : image descriptor [0] <- BOOT_PARAMS_1.descr[0]이 가리키는 섹터가 로딩됨.
							!!;*HS*                            !	0x9D400 - 0x9D5FF : image descriptor [1] <- BOOT_PARAMS_1.descr[1]이 가리키는 섹터가 로딩됨.
							!!;*HS*                            !	0x9D600 - 0x9D7FF : default command line
							!!;*HS*                            !	0x9D800 - 0x9D9FF : keyboard translation table

!!;*HS* 현재 BX는 부팅할 image의 IMAGE_DESCR을 가리키고 있다.
!!;*HS* typedef struct {
!!;*HS*     char name[MAX_IMAGE_NAME+1];
!!;*HS*     char password[MAX_PW+1];
!!;*HS*     unsigned short rd_size[2]; /* RAM disk size in bytes, 0 if none */
!!;*HS*     SECTOR_ADDR initrd,start;
!!;*HS*     unsigned short start_page; /* page at which the kernel is loaded high, 0 if loading low */
!!;*HS*     unsigned short flags,vga_mode;
!!;*HS* } IMAGE_DESCR;
doboot:							
	mov	byte ptr prechr, #61	! switch to equal sign
	push	bx			! save image descr

	mov	bx, #msg_l		! say hi
	call	say
	pop	bx			! display the image name
							!!;;*HS* "Linux"와 같은 Image의 name을 출력.
	push	bx
	call	say
	pop	si
	add	si, #ADDR_OFFS				!!;;*HS* si == bx+ADDR_OFFS == IMAGE_DESCR.rd_size
	cld 						!!;;*HS* lodsw가 순방향으로 진행.

					! take care of the RAM disk first
	mov	word ptr (rdmid), #0	! clear address
	lodsw				! number of bytes to load (low word)
							!!;;*HS* AX == rd_size[0]
	mov	dx, ax
	mov	rdszl, ax 				!!;;*HS* rdszl == AX == rd_size[0]
	lodsw				! high word
	mov	rdszh, ax 				!!;;*HS* rdszh == AX == rd_size[1]
	xchg	ax, dx			! convert to pages
							!!;;*HS* AX == rd_size[0], DX == rd_size[1]
						!!; ax: low dx: high
	add	ax, #4095 				!!;;*HS* 4096으로 AX를 나눌 때 소숫점 이하가 올림되도록 하기 위함.
	adc	dx, #0 					!!;;*HS* AX+4095로 캐리가 발생하면 dx가 1 증가함.
	mov	bx, #4096 				!!;;*HS* 
	div	bx				!!; dx:ax / bx ==> ax: 몫 dx: 나머지
							!!;;*HS* AX == (DX:AX)/4096
	mov	bx, ax 					!!;;*HS* BX == AX == RAMDISK의 page개수

							!!;;*HS* 아래 코드를 통해서 IMAGE_DESCR.initrd필드에 해당하는 부분을 CX,DX,AL로 읽어 온다.
	lodsw				! address of the first map sector
	mov	cx, ax				!!; CX == sector,track

	lodsw
	mov	dx,ax				!!; DX == device,head
    	lodsb                   	;;; num_sect 	!!;;*HS* AL == num_sect

    							!!;;*HS* si == IMAGE_DESCR.start
;;;	inc	si			! skip number of sectors
	or	bx, bx			! no RAM disk ?
							!!;;*HS* bx == 0이면 rd_size == 0이므로 램디스크를 사용하지 않음.
	jz	noramd			! yes -> skip it
	push	si			! save SI, ES, and BX (RD size)
	push	es
	push	bx
	mov	bx, #MAP		! load the first map sector
;;;	mov	al,#1
	call	sread 					!!;;*HS* 램디스크 map 섹터 address를 로드 -> 0x9D000
	mov	moff, #0
#ifdef DEBUG
	mov bx,#stepa
	call say
#endif

							!!;*HS* [REGISTER MAP] 	           !	[MEMORY MAP]
							!!;*HS* [CS] : 0x09B00 : SECONDSEG !	0x07C00 - 0x07DFF : first.S (MBR)
							!!;*HS* [DS] : 0x09B00 : SECONDSEG !	0x10000 - ?       : loaded message... using BOOT_PARAMS_1.map
							!!;*HS* [ES] : 0x09B00 : SECONDSEG !	0x9A000 - 0x9A1FF : first.S
							!!;*HS* [FS] : 0x00000 :           !	0x9A200 - 0x9AFFF : stack
							!!;*HS* [GS] : 0x00000 :           !	0x9B000 - ? 	  : second.S
							!!;*HS* [SS] : 0x09000 : STACKSEG  !	0x9D000 - 0x9D1FF : file map load area, ramdisk가 있다면 이곳에 정보가 로드됨.
							!!;*HS* [SP] : 0x0B000 : STACK     !	0x9D200 - 0x9D3FF : image descriptor [0] <- BOOT_PARAMS_1.descr[0]이 가리키는 섹터가 로딩됨.
							!!;*HS*                            !	0x9D400 - 0x9D5FF : image descriptor [1] <- BOOT_PARAMS_1.descr[1]이 가리키는 섹터가 로딩됨.
							!!;*HS*                            !	0x9D600 - 0x9D7FF : default command line
							!!;*HS*                            !	0x9D800 - 0x9D9FF : keyboard translation table


!!;;*HS* 메모리 체크 및 GDT 초기화 관련 루틴
	mov	ah, #0x88		! okay, compute load address now
	int	0x15			! get amount of memory ...
						!!; ax = 1K의 갯수
							!!;;*HS* INT 15h를 이용해서 램의 크기를 구하고,
							!!;;*HS* 1M위 상위 extended memory의 크기를 KiB단위로 AX에 할당
	cmp	word ptr memlim, #0	! limit set by user ?
	je	noulim			! no -> continue
	mov	ax, memlim		! use user limit
	sub	ax, #1024		! -1 MB

noulim:
	cmp	ax, #0x3c00		! more than 16 MB ?
	jbe	no16mb			! no -> go ahead
	mov	ax, #0x3c00		! limit to 16 MB to be nice to the BIOS
					! (kernel can still use "high" memory)
							!!;;*HS* extended memory가 16MB가 넘더라도 16MB로 제한한다.

no16mb:
	shr	ax, 2			! round to pages
						!!; ax = 4K의 갯수
	pop	bx			! subtract RAM disk size
	sub	ax, bx
							!!;;*HS* 여기까지 수행하면,,,
							!!;;*HS* AX == (현재 장착된 RAM size - RAMDISK size)
	jnc	rdokay			! panic if not enough space
							!!;;*HS* 현재 장착됨 RAM size가 RAMDISK를 가질 수 있다면, rdokay(ramdisk okay)로 점프.
	cmp	ax, #128		! we probably need more than 512 kB for the
	ja	rdokay			! kernel to be useful ...
	mov	bx,#msg_rd		! complain
	call	say
	jmpi	restrt, SECONDSEG	! ... and restart if we can

rdokay:
	add	ax, #256		! start is at first MB ...
						!!; ax = ax + 256(단위 4K)
						!!; ax = ax + 1MB
	shl	ax, 4			! *16

	mov	(gdt+0x1b), ax		! set up GDT
	mov	byte ptr (gdt+0x1a), #0
							!!;;*HS* 램디스크 map 섹터 address를 로드 -> 0x9D000
	mov	(rdmid),ax		! ... and remember that for patching setup
	xor	ax, ax			! ES=0 is our secret code to load via GDT
	mov	es, ax
	mov	bx, #gdt
	call	lfile			! load it
	pop	es			! restore ES and SI
	pop	si

							!!;*HS* [REGISTER MAP] 	           !	[MEMORY MAP]
							!!;*HS* [CS] : 0x09B00 : SECONDSEG !	0x07C00 - 0x07DFF : first.S (MBR)
							!!;*HS* [DS] : 0x09B00 : SECONDSEG !	0x10000 - ?       : loaded message... using BOOT_PARAMS_1.map
							!!;*HS* [ES] : 0x09B00 : SECONDSEG !	0x9A000 - 0x9A1FF : first.S
							!!;*HS* [FS] : 0x00000 :           !	0x9A200 - 0x9AFFF : stack
							!!;*HS* [GS] : 0x00000 :           !	0x9B000 - ? 	  : second.S
							!!;*HS* [SS] : 0x09000 : STACKSEG  !	0x9D000 - 0x9D1FF : file map load area, ramdisk가 있다면 이곳에 정보가 로드됨.
							!!;*HS* [SP] : 0x0B000 : STACK     !	0x9D200 - 0x9D3FF : image descriptor [0] <- BOOT_PARAMS_1.descr[0]이 가리키는 섹터가 로딩됨.
							!!;*HS*                            !	0x9D400 - 0x9D5FF : image descriptor [1] <- BOOT_PARAMS_1.descr[1]이 가리키는 섹터가 로딩됨.
							!!;*HS*                            !	0x9D600 - 0x9D7FF : default command line
							!!;*HS*                            !	0x9D800 - 0x9D9FF : keyboard translation table

!!;*HS* BOOT MAP을 로딩하는 루틴.
!!;*HS* BOOT MAP[0].descriptor ==> fallback sector
!!;*HS* BOOT MAP[1].descriptor ==> option sector
!!;*HS* BOOT MAP[2].descriptor ==> bootsect 		(real-mod kernel block #1)
!!;*HS* BOOT MAP[3].descriptor ==> setup 		(real-mod kernel block #2)
!!;*HS* BOOT MAP[4].descriptor ==> setup 		(real-mod kernel block #2)
!!;*HS* BOOT MAP[5].descriptor ==> setup 		(real-mod kernel block #2)
!!;*HS* BOOT MAP[6].descriptor ==> setup 		(real-mod kernel block #2)

noramd:							
						!!; IMAGE_DESCRIPTOR -> SECTOR 를 불러옴
							!!;*HS* 현재 ES:SI -> IMAGE_DESCR.start
							!!;*HS* 아래 코드는 start 필드의 값을 CX.DX.AL로 가져온다.
	lodsw				! address of the first map sector !!; es:si -> ax 복사
	mov	cx,ax
	lodsw
	mov	dx,ax
;;;	inc	si		! skip number of sectors
    	lodsb                   ;;;
    	push    ax              ;;;
	mov	word ptr (gdt+0x1b),#0 ! set GDT to "load low"
	lodsw			! get the start page 		
						!!; 0 이면 low 메모리에, 아니면 high 메모리에 
						!!; AX == IMAGE_DSECR->startpage
	or	ax,ax		! load low ?
	jz	nohigh		! yup -> do it 		!!;*HS* nohigh == 0이면 low memory로 커널을 로딩하라는 뜻.
							!!;*HS* 아래 3줄 코드는 high memory로 커널을 로딩하기 위해서,
							!!;*HS* AX == start_page값, 즉 페이지 번호가 12bit만큼 left shift되어 (페이지번호 4KiB가 byte단위로 변환되어)
							!!;*HS* GDT의 destination start 주소 위치에 기록되게 된다.
	shl	ax,4		! *16  		!!; 4K 단위에서 256 바이트 단위로 변환
	mov	(gdt+0x1b),ax	! set up GDT
	mov	byte ptr (gdt+0x1a),#0
nohigh:
    pop     ax              ;;; 		!!; ax 를 불러오면, start->num_sect 값
	push	si		! save SI 	!!; si 에는 IMAGE_DSECR->flag 를 가리키는 주소값 저장
#ifdef DEBUG
        push    ax              ;;;
	mov bx,#step0
	call say
        pop     ax              ;;;
#endif
						!!; [부가 설명] MAP load area (0x9D000) 에는 start page 의 sector 정보를 load
    						!!; load 된 정보를 사용해서 실제 데이터 복사되는 주소는 SYSSEG = 0x100000 (1MB)
	mov	bx,#MAP		! load the first map sector
;;;	mov	al,#1
	call	sread       
							!!;*HS* IMAGE_DESCR.start에 지정된 정보를 통해 disk로부터 섹터를 읽어들이고,
							!!;*HS* 그 값은 ES:BX로 로딩이 되며, 커널 이미지의 위치를 나타내는 descriptor들이 MAP으로 로딩되게 된다.
							!!;*HS* 다시 그 MAP을 하나하나 읽어 커널을 로딩하게 된다.
	mov	moff,#0		! reset the pointer
#ifdef DEBUG
	mov bx,#step0b
	call say
#endif
	mov	bx,#DFLCMD	! load the default command line 
						!!; es:bx 에 default command line 을 재로딩함
	seg	ss
	mov	cx,DFCMD_OFF+SSDIFF
	seg	ss
	mov	dx,DFCMD_OFF+2+SSDIFF
    seg ss                      ;;;
	mov	al,DFCMD_OFF+4+SSDIFF   ;;;
;;;	mov	al,#1
	call	cread
	push	word ptr (DFLCMD) ! push magic number 		
						!!; 바꾸어 놓은 magic number 는 0x6b6d
	mov	bx,#DFLCMD	! load the fallback sector
	call	load1				!!; MAP load area 에 있는 start page 의 sector 정보를 이용해서 한 섹터만 로딩 -> fallback sector
	pop	ax		! valid magic number ?
#ifndef LCF_READONLY
	cmp	ax,#DC_MAGIC			!!; DC_MAGIC = 0xf4f2
	je	dclok		! yes -> can write
	cmp	ax,#DC_MGOFF			!!; DC_MGOFF = 0x6b6d
	jne	nofbck		! invalid -> must not write

						!!; Default Command Lind 에는 fallback sector 가 loading 되어 있고,
						!!; fallback sector 를  default command line 인 것으로 가장하기 위해서 처음 두 바이트에 매직 넘버를 넣어줌
							!!;*HS* [REGISTER MAP] 	           !	[MEMORY MAP]
							!!;*HS* [CS] : 0x09B00 : SECONDSEG !	0x07C00 - 0x07DFF : first.S (MBR)
							!!;*HS* [DS] : 0x09B00 : SECONDSEG !	0x10000 - ?       : loaded message... using BOOT_PARAMS_1.map
							!!;*HS* [ES] : 0x09B00 : SECONDSEG !	0x9A000 - 0x9A1FF : first.S
							!!;*HS* [FS] : 0x00000 :           !	0x9A200 - 0x9AFFF : stack
							!!;*HS* [GS] : 0x00000 :           !	0x9B000 - ? 	  : second.S
							!!;*HS* [SS] : 0x09000 : STACKSEG  !	0x9D000 - 0x9D1FF : file map load area, ramdisk가 있다면 이곳에 정보가 로드됨.
							!!;*HS* [SP] : 0x0B000 : STACK     !	0x9D200 - 0x9D3FF : image descriptor [0] <- BOOT_PARAMS_1.descr[0]이 가리키는 섹터가 로딩됨.
							!!;*HS*                            !	0x9D400 - 0x9D5FF : image descriptor [1] <- BOOT_PARAMS_1.descr[1]이 가리키는 섹터가 로딩됨.
							!!;*HS*                            !	0x9D600 - 0x9D7FF : *** fallback sector ***
							!!;*HS*                            !	0x9D800 - 0x9D9FF : keyboard translation table
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
	call	load1				!!; load1 호출에서 복귀하는 방법은 찾지 못함
	mov	si,cmdbeg	! copy non-options part of command line   
						!!; si = MAP(si+10), cmdbeg = "auto "
	mov	di,#PARMLINE			!!; 0x2a00
#ifdef	LCF_LARGE_EBDA
	push	#INITSEG
	pop	es
#endif
						!!; Option 값들을 parameter 에 저장
						!!; options 에는 boot: 함수에서 저장된 부팅 옵션값(?) 이 들어있음
cpnocl:	cmp	si,options	! at beginning of options ?   	
	je	cpnodn		! yes -> go on  !!; option 이 auto 이면 jump 
						!!; -> 옵션 값들이 들어있다고 하더라도 마지막에는 auto 가 있어야 될 것으로 추측됨
	movsb			! copy one byte !!; DS:SI -> ES:DI 로 복사
	jmp	cpnocl		! next one
cpnodn:	mov	si,#DFLCMD	! constant options ?
	cmp	byte ptr (si),#0		!!; option sector 의 첫 번째 바이트 값을 0 과 비교 -> null 인지 체크하는 용도
	je	nocopt		! no -> go on
	mov	al,#32		! add a space
	stosb					!!; al -> es:di 1 바이트 저장하고 di = di +1
cpcodsp:lodsb			! fetch next byte
				  		!!; ds:si -> al
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
	cmp	byte ptr (di-1),#32 ! last was space ?  	!!; pamameter line 의 마지막 값을 space 와 비교
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

							!!;*HS* [REGISTER MAP] 	           !	[MEMORY MAP]
							!!;*HS* [CS] : 0x09B00 : SECONDSEG !	0x07C00 - 0x07DFF : first.S (MBR)
							!!;*HS* [DS] : 0x09B00 : SECONDSEG !	0x10000 - ?       : loaded message... using BOOT_PARAMS_1.map
							!!;*HS* [ES] : 0x09B00 : SECONDSEG !	0x9A000 - 0x9A1FF : first.S
							!!;*HS* [FS] : 0x00000 :           !	0x9A200 - 0x9AFFF : stack
							!!;*HS* [GS] : 0x00000 :           !	0x9B000 - ? 	  : second.S
							!!;*HS* [SS] : 0x09000 : STACKSEG  !	0x9D000 - 0x9D1FF : file map load area, ramdisk가 있다면 이곳에 정보가 로드됨.
							!!;*HS* [SP] : 0x0B000 : STACK     !	0x9D200 - 0x9D3FF : image descriptor [0] <- BOOT_PARAMS_1.descr[0]이 가리키는 섹터가 로딩됨.
							!!;*HS*                            !	0x9D400 - 0x9D5FF : image descriptor [1] <- BOOT_PARAMS_1.descr[1]이 가리키는 섹터가 로딩됨.
							!!;*HS*                            !	0x9D600 - 0x9D7FF : option sector 가 결국 default command line이 된다.
							!!;*HS*                            !	0x9D800 - 0x9D9FF : parameter line

	push	#INITSEG	! load the original boot sector !!; INITSEG = 0x9000
	pop	es
	xor	bx,bx		! load now
	call	load1						!!; option sector 다음 sector 인  boot sector 를 읽어옴
	seg	es
	mov	CL_MAGIC_ADDR,#CL_MAGIC ! set magic number  	!!; CL_MAGIC_ADDR = 0x20, CL_MAGIC = 0xa33f
								!!; es:0x0020 <- 0xa33f
#ifndef LCF_LARGE_EBDA
	seg	es
	mov	word ptr CL_OFFSET,#PARMLINE+SECOND_SS		!!; 0x9000:(0xB000+0x2a00) = 0x9DA00
								!!; es:0x0022 <- 0x9DA00
				! set parameter line offset
#else
	seg	es
	mov	word ptr CL_OFFSET,#PARMLINE
				! set parameter line offset
#endif
	pop	si		! restore SI			!!; IMAGE_DESC->flag 주소값 불러옴 
	lodsw			! get flags bit map
	mov	bx,ax						!!; flag 값 저장 
	lodsw			! copy parameters ... VGA mode ... (done)
	cmp	word ptr vgaovr,#VGA_NOCOVR ! VGA mode not overridden on
				! command line ?
	je	vganorm		! no -> go on
	mov	ax,vgaovr	! use that value
	jmp	vgaset
vganorm:test	bx,#FLAG_VGA  					!!; FLAG_VGA = 1
	jz	novga			  			!!; FLAG_VGA 다르면 jump
vgaset:	seg	es
	mov	506,ax						!!; 0x90506 <- ax
novga:	push	bx		! use flags (BX) later
	test	bx,#FLAG_LOCK	! ... lock target ?  		!!; FLAG_LOCK = 4
	jnz	lockit		! yup -> do it   		!!; 같으면 jump
	cmp	byte ptr dolock,#0 ! did user ask to lock new target ?
	je	nolock		! no -> go on

							!!;*HS* [REGISTER MAP] 	           !	[MEMORY MAP]
							!!;*HS* [CS] : 0x09B00 : SECONDSEG !	0x07C00 - 0x07DFF : first.S (MBR)
							!!;*HS* [DS] : 0x09B00 : SECONDSEG !	0x10000 - ?       : loaded message... using BOOT_PARAMS_1.map
							!!;*HS* [ES] : 0x09000 : INITSEG   !	0x90000 - 0x901FF : bootsect (real-mod kernel block #1)
							!!;*HS* [FS] : 0x00000 :           !	0x9A000 - 0x9A1FF : first.S
							!!;*HS* [GS] : 0x00000 :           !	0x9A200 - 0x9AFFF : stack
							!!;*HS* [SS] : 0x09000 : STACKSEG  !	0x9B000 - ? 	  : second.S
							!!;*HS* [SP] : 0x0B000 : STACK     !	0x9D000 - 0x9D1FF : file map load area, ramdisk가 있다면 이곳에 정보가 로드됨.
							!!;*HS*                            !	0x9D200 - 0x9D3FF : image descriptor [0] <- BOOT_PARAMS_1.descr[0]이 가리키는 섹터가 로딩됨.
							!!;*HS*                            !	0x9D400 - 0x9D5FF : image descriptor [1] <- BOOT_PARAMS_1.descr[1]이 가리키는 섹터가 로딩됨.
							!!;*HS*                            !	0x9D600 - 0x9D7FF : option sector 가 결국 default command line이 된다.
							!!;*HS*                            !	0x9D800 - 0x9D9FF : parameter line

lockit:
#ifndef LCF_READONLY
	mov	bx,#lkwbuf	! save the command line  	!!; lkwbuf = 0xf4f2
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
	call	cwrite   			!!; 0x9b00:#lkwbuf 부터의 데이터를 디스크 writing  
						!!; 다음 부팅부터는 사용자가 입력한 값을 자동으로 불러옴 ; auto save 기능
	pop	si
	pop	es
#endif


!!;*HS* MAP sector 4 ~ 7섹터를 읽는다. 4*512 = 4096byte == 0x1000 byte
nolock:
#ifdef DEBUG
	mov bx,#step3
	call say
	seg	es
#endif
	mov	cx,#SETUPSECS	! default is to load four sectors  
						!!; SETUPSECS = 4
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
						!!; SETUPSEG = 0x9020
;;;	mov	es,ax
	pop	es		! process of loading the boot sector of an
	xor	bx,bx		! other operating system)
lsloop:	push	cx
	call	loadopt				!!; MAP Load Area 의 4 번째를 불러옴 
						!!; [0] fallback, [1] option, [2] boot, [3] setup.S
	pop	cx
	loop	lsloop		 
#ifdef DEBUG
	mov bx,#step4
	call say
#endif

							!!;*HS* [REGISTER MAP] 	           !	[MEMORY MAP]
							!!;*HS* [CS] : 0x09B00 : SECONDSEG !	0x07C00 - 0x07DFF : first.S (MBR)
							!!;*HS* [DS] : 0x09B00 : SECONDSEG !	0x10000 - ?       : loaded message... using BOOT_PARAMS_1.map
							!!;*HS* [ES] : 0x09020 : SETUPSEG  !	0x90000 - 0x901FF : bootsect (real-mod kernel block #1)
							!!;*HS* [FS] : 0x00000 :           !	0x90200 - 0x911FF : setup    (real-mod kernel block #2)
							!!;*HS* [GS] : 0x00000 :           !	0x9A000 - 0x9A1FF : first.S
							!!;*HS* [SS] : 0x09000 : STACKSEG  !	0x9A200 - 0x9AFFF : stack
							!!;*HS* [SP] : 0x0B000 : STACK     !	0x9B000 - ? 	  : second.S
							!!;*HS*                            !	0x9D000 - 0x9D1FF : file map load area, ramdisk가 있다면 이곳에 정보가 로드됨.
							!!;*HS*                            !	0x9D200 - 0x9D3FF : image descriptor [0] <- BOOT_PARAMS_1.descr[0]이 가리키는 섹터가 로딩됨.
							!!;*HS*                            !	0x9D400 - 0x9D5FF : image descriptor [1] <- BOOT_PARAMS_1.descr[1]이 가리키는 섹터가 로딩됨.
							!!;*HS*                            !	0x9D600 - 0x9D7FF : option sector 가 결국 default command line이 된다.
							!!;*HS*                            !	0x9D800 - 0x9D9FF : parameter line

!!;*HS* 실제 커널( (head+misc) + compressed kernel )을 메모리에 올린다.
!!;*HS* bzImage일 경우 (modern kernel)   0x100000에 로드
!!;*HS* zImage일 경우                    0x10000에 로드
!!;*HS*
	pop	bx		! get flags
	test	bx,#FLAG_MODKRN	! "modern" kernel ?	  	!!; FLAG_MODKRN = 8
	jz	loadlow		! no -> avoid all patching and such
	seg	es		! set loader version		!!; es = 0x9020
	mov	byte ptr (16),#LOADER_VERSION			!!; 0x9020:0x0010 = 0x90210
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
	mov	es,ax				!!; es == 0 이면 gdt 의 destination 주소값으로 복사, destination 설정은 rdokay 에서
	mov	bx,#gdt				!!; lfile 에서 호출하는 doload 에서 bx 값으로 gdt 의 destination 값을 사용함
	call	lfile		! load the system ...
	jmp	launch		! ... and run it
loadlow:call	loadfile	! load the system
	jmp	launch		! go !

loadfile:
	push	#SYSSEG		! load a file at SYSSEG:0000
	pop	es
	xor	bx, bx

lfile:
	call	load
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

load:
	push	es		! save ES:BX
	push	bx

lfetch:
	mov	si, moff	! get map offset
	mov	cx, MAP(si)	! get address
	mov	dx, MAP+2(si)			!!; (MAP+si+2)
	mov	al, MAP+4(si)
	or	cx, cx		! at EOF ?
	jnz	noteof		! no -> go on
	or	dx, dx
	jnz	noteof
	pop	bx		! restore ES:BX
	pop	es
	pop	ax		! pop return address
	ret			! return to outer function

noteof:
	add	si, #5		! increment pointer
	mov	moff, si
	cmp	si, #508	! page end ?
	jb	doload		! no -> load it
	mov	moff, #0	! reset pointer
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

							!!;*HS* [REGISTER MAP] 	           !	[MEMORY MAP]
							!!;*HS* [CS] : 0x09B00 : SECONDSEG !	0x07C00 - 0x07DFF : first.S (MBR)
							!!;*HS* [DS] : 0x09B00 : SECONDSEG !	0x10000 - ?       : loaded message... using BOOT_PARAMS_1.map
							!!;*HS* [ES] : 0x00000 :           !	0x90000 - 0x901FF : bootsect (real-mod kernel block #1)
							!!;*HS* [FS] : 0x00000 :           !	0x90200 - 0x911FF : setup    (real-mod kernel block #2)
							!!;*HS* [GS] : 0x00000 :           !	0x9A000 - 0x9A1FF : first.S
							!!;*HS* [SS] : 0x09000 : STACKSEG  !	0x9A200 - 0x9AFFF : stack
							!!;*HS* [SP] : 0x0B000 : STACK     !	0x9B000 - ? 	  : second.S
							!!;*HS*                            !	0x9D000 - 0x9D1FF : file map load area, ramdisk가 있다면 이곳에 정보가 로드됨.
							!!;*HS*                            !	0x9D200 - 0x9D3FF : image descriptor [0] <- BOOT_PARAMS_1.descr[0]이 가리키는 섹터가 로딩됨.
							!!;*HS*                            !	0x9D400 - 0x9D5FF : image descriptor [1] <- BOOT_PARAMS_1.descr[1]이 가리키는 섹터가 로딩됨.
							!!;*HS*                            !	0x9D600 - 0x9D7FF : option sector 가 결국 default command line이 된다.
							!!;*HS*                            !	0x9D800 - 0x9D9FF : parameter line

launch: push	es		! save ES:BX (why ???)		!!; es = 0 
	push	bx						!!; bx = #gdt
	mov	bx,#crlf	! display a CRLF
	call	say
	mov	dx,#0x3f2	! stop the floppy motor
	xor	al,al
	outb
	xor	ax,ax		! reset the FDC
	mov	dl,al
	int	0x13
	call	remto		! free timer interrupt
	push	#INITSEG	! adjust segment registers	!!; 0x9000
	pop	ds
	push	ds
	pop	es
	jmpi	0,SETUPSEG	! start the setup		!!; 0x9020 -> Setup.S 가 loading 되어 있는 곳, kernel 코드 시작

							!!;*HS* 바로 위 setup 코드로 점프후 상태.
							!!;*HS* [REGISTER MAP] 	           !	[MEMORY MAP]
							!!;*HS* [CS] : 0x09020 : SETUPSEG  !	0x07C00 - 0x07DFF : first.S (MBR)
							!!;*HS* [DS] : 0x09000 : INITSEG   !	0x10000 - ?       : loaded message... using BOOT_PARAMS_1.map
							!!;*HS* [ES] : 0x09000 : INITSEG   !	0x90000 - 0x901FF : bootsect (real-mod kernel block #1)
							!!;*HS* [FS] : 0x00000 :           !	0x90200 - 0x911FF : setup    (real-mod kernel block #2)
							!!;*HS* [GS] : 0x00000 :           !	0x9A000 - 0x9A1FF : first.S
							!!;*HS* [SS] : 0x09000 : STACKSEG  !	0x9A200 - 0x9AFFF : stack
							!!;*HS* [SP] : 0x0B000 : STACK     !	0x9B000 - ? 	  : second.S
							!!;*HS*                            !	0x9D000 - 0x9D1FF : file map load area, ramdisk가 있다면 이곳에 정보가 로드됨.
							!!;*HS*                            !	0x9D200 - 0x9D3FF : image descriptor [0] <- BOOT_PARAMS_1.descr[0]이 가리키는 섹터가 로딩됨.
							!!;*HS*                            !	0x9D400 - 0x9D5FF : image descriptor [1] <- BOOT_PARAMS_1.descr[1]이 가리키는 섹터가 로딩됨.
							!!;*HS*                            !	0x9D600 - 0x9D7FF : option sector 가 결국 default command line이 된다.
							!!;*HS*                            !	0x9D800 - 0x9D9FF : parameter line

! Load one sector (called from load)

doload:
	pop	bx		! restore ES:BX
	pop	es

! Load a sequence of sectors, possibly moving into "high memory" (> 1 MB)
! afterwards.

xread:
	push	ax		! ES == 0 ?
	mov	ax, es
	or	ax, ax
	pop	ax
	jz	rdhigh		! yes -> read into high memory
	br	sread

rdhigh:
	push	bx		! okay - DS:BX points to GDT in this case
	mov	bx, #SYSSEG	! adjust ES:BX
	mov	es, bx
	xor	bx, bx
	call	sread		! load the sector(s)
	mov     tempal, al
	pop	bx		! get pointer to GDT
	push	ax		! just in case ...
	push	cx
	push	si
	mov	si, bx		! turn ES:SI into pointer to GDT
	push	ds
	pop	es
	xor	cx, cx		! number of words to move
	mov	ch, tempal
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
	mov	ah, #0x87
	int	0x15
	pop	si
	pop	cx
	pop	bx
	jc	badmov		! failed ...
	seg	es		! move pointer
	add	(si+0x1a), cx
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

badmov:
	push	ax		! save the error code
	mov	bx,#msg_bm	! tell the user ...
	br	reset		! (standard procedure)

! Load a sequence of sectors

sread:
	push	bx		! save registers
	push	cx
	push	dx
	call	cread
	mov	di, ax		! save AL return count
	jc	rerror		! error -> complain
	pop	dx		! restore registers
	pop	cx

rokay:
	pop		bx
	!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!;
	!!; shl ax, 8 => al * 256 = ah
	!!; add ah, ah => ah * 2 ==> al * 512
	!!; 읽은 sector를 byte로 변환한다.
	!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!;
	shl	ax, 8   ; convert sectors to bytes
	add     ah, ah
	jc	dowrap	! loaded an entire segment -> advance ES
	add	bx, ax	! move BX
	jnc	nowrap	! same segment -> go on

dowrap:
	!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!;
	!!; overfllow 발생
	!!; es를 0x1000 증가
	!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!;
	mov	ax, es		! move ES
	add	ax, #0x1000
	mov	es, ax

nowrap:
	mov	ax, di		! restore the block count in AL

aret:
	ret			! done

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

say:	mov	al,(bx)		! get byte 			!!; al에는 'O'가 들어 간다.
	or	al,al		! NUL ?        			!!; 문자열의 마지막을 검사
	jz	aret		! yes -> done  			!!; return 한다.
	push	bx		! save pointer
	cmp	al,#10		! \n ?         			!!; al값이 '\n'이면 CRLF를 display한다.
	jne	nonl		! no -> go on
	mov	al,#13		! display a CRLF
	call	display
	mov	al,#10
nonl:	cmp	al,#12		! ^L ?
	jne	nocls		! no -> go on
	mov	ah,#0xf		! clear the local screen
	int	0x10						!!; 0x10-0xf 인터럽트를 통해 mode currently set을 
								!!; al 레지스터에 받아온다.
	xor	ah,ah
	int	0x10						!!; 0x10-0 을 통하여 video mode를 셋팅한다. 
								!!; 이렇게 하면 'clear the local screen'이 되나보다.
	jmp	snext		! next character
nocls:	call	display		! display, tty-style
snext:	pop	bx						!!; bx 값을 다시 가져와서
	inc	bx		! next one 			!!; 다음 포인팅 연산을 한다.
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

waitsh:
	call	setto		! set timeout

actlp:
	!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!;
	!!; int 0x16, 2: Read Keyboard Flags
	!!; 사용자가 Key입력을 할때까지 또는 delay 시간동안 아래를 수행
	!!; timeout이전에 키가 눌리면 set carry, 아니면 clear carry
	!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!;
	mov	ah, #2		! get shift keys
	int	0x16
	and	al, #0x5f	! anything set ? (except NumLock)
	jnz	shpress		! yes -> return with CY set
	mov	dx, slbase	! using a serial port ?
	or	dx, dx
	jz	acnosp		! no -> go on
	cmp	byte ptr break, #0 ! break received ?
	jnz	shpress		! yes -> return with CY set
	add	dx, #5		! check for pending break
	in	al, dx
	test	al,#0x10
	jnz	shpress		! break received -> return with CY set

acnosp:
	test	byte ptr timeout, #1	! timed out ?
	jz	actlp		! no -> wait
	clc			! clear carry
	ret			! done

shpress:
	stc			! set carry
	ret			! done

						!!; Timeout handling 0x1C 핸들러를 등록한다.
						!!; Time interrupt 
							!!;*HS* [REGISTER MAP] 		  !	[MEMORY MAP]
							!!;*HS* [CS] : 0x9B00 : SECONDSEG !	0x07C00 - 0x07DFF : first.S (MBR)
							!!;*HS* [DS] : 0x0000 :           !	0x9A000 - 0x9A1FF : first.S
							!!;*HS* [ES] : 0x9B00 : SECONDSEG !	0x9A200 - 0x9AFFF : stack
							!!;*HS* [FS] : 0x0000 :           !	0x9B000 - ? 	  : second.S
							!!;*HS* [GS] : 0x0000 :           !
							!!;*HS* [SS] : 0x9000 : STACKSEG  !
							!!;*HS* [SP] : 0xB000 : STACK     !

instto:	push	ds		! install timeout handler
	xor	ax,ax
	mov	ds,ax
	cli			! no interrupts
	mov	ax,[0x1c*4]	! get the old vector 
							!!;*HS* AX = IVT중 0x1C번 서비스 주소.
	seg	cs				!!; 
	mov	int1c_l,ax			!!; 0x1C의 old vector 를 저장
	mov	ax,[0x1c*4+2]	
	seg	cs
	mov	int1c_h,ax			!!; 여기까지 
						!!; 주소하나는 4bytes를 사용하기 때문에 
						!!; init1c_h:ini1c_l에 각각 저장 한다. 
	mov	[0x1c*4],#tick	! install new vector
							!!;*HS* 0x1C 인터럽트 핸들러를 cs:tick로 바꿈.
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

setto:
	or	ax, ax		! time out immediately ?
	jz	toimmed		! yes -> do it
	cli			! set timeout value
	mov	cntdown, ax
	mov	byte ptr timeout, #0	! clear timed-out flag
	sti			! done
	ret

toimmed:
	mov	byte ptr timeout, #0xff ! set the timed-out flag
	ret			! done

tick:
	pushf			! save flags	!!;현재 플레그값들을 스택에 모두 저장
	seg	cs		! no timeout ?
	cmp	cntdown,#0xffff			!!; cntdown을 0xFFFF로 설정하면 새로 등록한
						!!; time-interupt를 사용하지 않고 
						!!; 원래의 interrupt handler만 수행함
	je	notzro		! yes -> go on	!!; 같으면 notzro로 간다
	seg	cs		! decrement counter
	dec	cntdown				!!;contdown을 감소하다가 0이되면
						!!;timeout에 0xFF를 저장
	jnz	notzro		! not zero -> go on
	seg	cs		! set timeout flag
	mov	byte ptr timeout,#0xff
notzro:	popf			! done		!!; 원래의 time-interrupt handler를	
						!!; 호출 해준다.
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
        call    dsk_do_rw       ; int 0x13 with retries	!!; 복습하면서 찾아보기
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
	.word	0xffff		! no limits GDT size
	.word	0		! start - filled in by user base 0 ~ 15
	.byte	0								!!; 16 ~ 23
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

lkwbuf:	.word	DC_MAGIC !!; 0xf4f4
lkcbuf:	.blkb	256
dolock:	.byte	0

acmdbeg:.ascii	"auto "
mcmdbeg:.ascii	"BOOT_IMAGE"
prechr:	.byte	32		! space: guard double blank supression
				! equal sign: variable assignment
cmdline:.byte	0
theend:
