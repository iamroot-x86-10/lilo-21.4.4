/* lilo.h  -  LILO constants */

/* Copyright 1992-1998 Werner Almesberger. See file COPYING for details. */


/* This file is also included by the boot loader assembler code. Put
   everything that isn't legal C syntax or isn't swallowed by the
   preprocessor into #ifdef LILO_ASM ... #endif */


#ifndef LILO_H
#define LILO_H

/*
 * Starting with 2.1.something, Linux kernels put VGA constants and segment
 * definitions into asm/boot.h instead of linux/config.h
 */

#ifdef HAS_BOOT_H
#include <asm/boot.h>
#else
#include <linux/config.h>
#endif
#if 0
#define VERSION		21 /* Boot sector, map file, and chain loader format
			      revision. This number does not necessarily have
			      to correspond to the version number of the entire
			      package, but it usually does. */
#else
#include "version.h"
#define VERSION 256*VERSION_MINOR+VERSION_MAJOR
#endif
#define MAJMIN_RAM	0x101 /* RAM disk */
#define MAJOR_FD	2 /* floppy disks */
#define MAJOR_HD	3 /* IDE-type hard disks */
#define MAJOR_SD	8 /* SCSI disks */
#define MAJOR_XT	13 /* XT-type hard disks */
#define MAJOR_IDE2	22 /* IDE on second interface */
#define MAJOR_IDE3	33 /* IDE on third interface */
#define MAJOR_IDE4	34 /* IDE on fourth interface */
#define MAJOR_ESDI	36 /* PS/2 ESDI drives */
#define MAJOR_DAC960	48 /* First Mylex DAC960 PCI RAID controller */
#define MAJOR_IDE5	55 /* IDE on fifth interface */
#define MAJOR_IDE6	57 /* IDE on sixth interface */
#define COMPAQ_SMART2_MAJOR	72 /* First Smart/2 Major */

#define MAX_IMAGES      ((SECTOR_SIZE*2-2)/sizeof(IMAGE_DESCR))
			  /* maximum number of images */
#define MAX_IMAGE_NAME	15 /* maximum name length (w/o terminating NUL) */
#define MAX_PW		15 /* maximum password length */
#define MAX_SECONDARY	10 /* maximum number of sectors in the 2nd stage
			     loader */
#define SECTOR_SIZE	512 /* disk sector size */
#ifndef BLOCK_SIZE /* may also come from linux/fs.h */
#define BLOCK_SIZE	1024 /* disk block size */
#endif

#define ADDR_OFFS MAX_IMAGE_NAME+MAX_PW+2 /* options address offset */

#define PARTITION_ENTRY	   16	/* size of one partition entry */
#define PARTITION_ENTRIES  4    /* number of partition entries */
#define PART_TABLE_SIZE    (PARTITION_ENTRY*PARTITION_ENTRIES)
#define PART_TABLE_OFFSET  0x1be /* offset in the master boot sector */
#define PART_ACT_ENT_OFF   0	/* offset in entry for active flag */
#define PART_TYPE_ENT_OFF  4	/* offset in entry for partition type */

#define PART_MASK  15 /* largest common partition bits mask */
#define PART_MAX    4 /* biggest primary partition number */

#define PART_LINUX_MINIX  0x81	/* Linux/MINIX partition */
#define PART_LINUX_NATIVE 0x83	/* Linux native (file system) */

#define MAX_BOOT_SIZE	0x1b6	/* (leave some space for NT's and DR DOS' dirty
				   hacks) scream if the boot sector gets any
				   bigger */

#define INIT_CKS	0xabcd	/* initial descriptor table checksum */

#define BOOT_SIGNATURE	0xaa55	/* boot signature */
#define BOOT_SIG_OFFSET	510	/* boot signature offset */

#define PART_DOS12	1	/* DOS 12 bit FAT partition type */
#define PART_DOS16_SMALL 4	/* DOS 16 bit FAT partition type, < 32 MB */
#define PART_DOS16_BIG	6	/* DOS 16 bit FAT partition type, >= 32 MB */
#define PART_INVALID	98	/* invalid partition type */

#define HIDDEN_OFF	0x10	/* type offset to hide partition (OS/2 BM) */
#define PART_HDOS12	PART_DOS12+HIDDEN_OFF
#define PART_HDOS16_SMALL PART_DOS16_SMALL+HIDDEN_OFF
#define PART_HDOS16_BIG	PART_DOS16_BIG+HIDDEN_OFF

#define STAGE_FIRST	1	/* first stage loader code */
#define STAGE_SECOND	2	/* second stage loader code */
#define	STAGE_CHAIN	0x10	/* chain loader code */

#define SETUPSECS	4	/* nr of setup sectors */
#define VSS_NUM		497	/* address where variable setup size is
				   stored */
#define MAX_KERNEL_SECS	1024	/* absolute maximum kernel size */
#define SPECIAL_SECTORS	2	/* special sectors (don't compact) at beginning
				   of map sections */

#define LINEAR_FLAG	0x40	/* mark linear address */
#define LBA32_FLAG      0x20    /* mark lba 32-bit address */
#define LBA32_NOCOUNT   0x10    /* mark address with count absent */
#define DEV_MASK        0x8f    /* mask to actual device code */

#define	EX_OFF		CODE_START_1+SSDIFF /* external parameter block */
#define EX_DL_MAG	0xfe	/* magic number in DL */
#define EX_MAG_L	0x494c	/* magic number at ES:SI, "LI" */
#define EX_MAG_H	0x4f4c	/* magic number at ES:SI+2, "LO" */

#define BIOS_MAX_DEVS	2	/* BIOS devices (2 fd, 2 hd) */
#define BIOS_MAX_HEADS  256	/* 8 bits head number */
#define BIOS_MAX_CYLS   1024	/* 10 bits cylinder number */
#define BIOS_MAX_SECS   63	/* 6 bits sector number (no, it's not 64) */

#define FLAG_VGA	1	/* override VGA mode */
#define FLAG_RESTR	2	/* restrict additional parameters */
#define FLAG_LOCK	4	/* lock on target */
#define FLAG_MODKRN	8	/* modern kernel with high memory support */
#define FLAG_KERNEL	16	/* image is a kernel */
#define FLAG_SINGLE	32	/* single key activation */

#define VGA_NOCOVR	0x8000	/* VGA setting not overridden on command line */

#define SER_DFL_PRM	0xa3	/* default serial parameters: 2400n8 */

#define DC_MAGIC	0xf4f2	/* magic number of default cmd. line sector */
#define DC_MGOFF	0x6b6d	/* magic number for disabled line */

#define MAX_MESSAGE	65535	/* maximum message length */

#define NEW_HDR_SIG	"HdrS"	/* setup header signature */
#define NEW_HDR_VERSION	0x200	/* header version number */
#define LOADER_VERSION	1	/* loader version, for SETUP_HDR.loader */
#define LFLAG_HIGH	1	/* SETUP_HDR.flags */
#define LFLAG_USE_HEAP	0x80

#define PRTMAP_SIZE	32	/* number of partition type mappings */
#define DRVMAP_SIZE	8	/* number of drive mappings */

#ifdef LILO_ASM

BOOTSEG   = 0x07C0			! original address of boot-sector
PARTS_LOAD= 0x0600			! partition sector load address
PARTS_SCR = 0x0800			! ditto, for non-boot partitions
PART_TABLE= 0x07BE			! partition table

FIRSTSEG  = 0x9A00
STACKSEG  = 0x9000
#ifndef LCF_LARGE_EBDA
SECONDSEG = 0x9B00			! second stage loader segment
#else
SECONDSEG = 0x0B00			! second stage loader segment
#endif

INITSEG   = DEF_INITSEG			! we move boot here - out of the way
SETUPSEG  = DEF_SETUPSEG		! setup starts here
SYSSEG    = DEF_SYSSEG			! system loaded at 0x10000 (65536).
SSDIFF	  = 0xA000
STACK	  = 0xB000			! top of stack
DESCR	  = 0x2200			! descriptor load area offset
DFLCMD	  = 0x2600			! default command line
MAP	  = 0x2000			! map load area offset
KEYTABLE  = 0x2800			! keyboard translation table offset

#ifndef LCF_LARGE_EBDA
PARMLINE  = 0x2a00			! parameter line construction area off.
#else
PARMLINE  = 0XB000			! parameter line construction area off.
#endif

SECOND	  = 0x1000			! second stage loader load address
SECOND_SS = 0xB000			! second as seen from SS:0000
SLA_SIZE  = 0x9E00			! setup load area size
KBBEG     = 0x41A			! beginning of keyboard buffer
KBEND	  = 0x41C			! end of keyboard buffer
KBLOW	  = 0x1e
KBHIGH	  = 0x3e

! 0x007BE-0x007FD    64 B    partition table
! 0x07C00-0x07DFF   0.5 kB   boot load address
! 0x10000-0x8FFFF   512 kB   kernel
! 0x90000-0x901FF   0.5 kB   Linux floppy boot sector
! 0x90200-0x99FFF  39.5 kB   setup
! 0x9A000-0x9A1FF   0.5 kB   boot sector (first stage loader)
! 0x9A200-0x9AFFF   3.5 kB   stack
! 0x9B000-0x9CFFF     8 kB   second stage loader
! 0x9D000-0x9D1FF   0.5 kB   file map load area
! 0x9D200-0x9D5FF     1 kB   descriptor table load area
! 0x9D600-0x9D7FF   0.5 kB   default command line load area
! 0x9D800-0x9D9FF   0.5 kB   keyboard translation table load area
! 0x9DA00-0x9DDFF     1 kB   parameter line construction area
! 0x9DE00-0x9F9FF   7.5 kB   scratch space
! 0x9FC00-0x9FFFF     1 kB   driver swapper

CL_MAGIC_ADDR	= 0x20			! command line magic number
CL_MAGIC	= 0xa33f		! very unusual command sequence
CL_OFFSET	= 0x22			! command line offset
CL_LENGTH	= 0x4e			! maximum length
CL_KERNEL	= 256			! maximum passed to kernel

! 0x90020-0x90021     2 by   command line magic number
! 0x90022-0x90023     2 by   command line offset

#endif

#endif
