/* common.h  -  Common data structures and functions. */

/* Copyright 1992-1998 Werner Almesberger. See file COPYING for details. */


#ifndef COMMON_H
#define COMMON_H

#include <sys/stat.h>
#include <asm/types.h>
#include <linux/genhd.h>

#include "lilo.h"


#define O_NOACCESS 3  /* open a file for "no access" */


typedef struct {
    unsigned char sector,track; /* CX */
    unsigned char device,head; /* DX */
    unsigned char num_sect; /* AL */
} SECTOR_ADDR;

typedef struct {
    char name[MAX_IMAGE_NAME+1];
    char password[MAX_PW+1];
    unsigned short rd_size[2]; /* RAM disk size in bytes, 0 if none */
    SECTOR_ADDR initrd,start;
    unsigned short start_page; /* page at which the kernel is loaded high, 0
				  if loading low */
    unsigned short flags,vga_mode;
} IMAGE_DESCR;

typedef struct {
    char jump[6]; /* jump over the data */
    char signature[4]; /* "LILO" */
    unsigned short stage,version;
    unsigned short timeout; /* 54 msec delay until input time-out,
			       0xffff: never */
    unsigned short delay; /* delay: wait that many 54 msec units. */
    unsigned char port; /* COM port. 0 = none, 1 = COM1, etc. */
    unsigned char ser_param; /* RS-232 parameters, must be 0 if unused */
    unsigned long timestamp; /* timestamp for restoration */
    SECTOR_ADDR descr[3]; /* 2 descriptors and default command line */
    unsigned char prompt; /* 0 = only on demand, =! 0 = always */
    unsigned short msg_len; /* 0 if none */
    SECTOR_ADDR msg; /* initial greeting message */
    SECTOR_ADDR keytab; /* keyboard translation table */
    SECTOR_ADDR secondary[MAX_SECONDARY+1];
} BOOT_PARAMS_1; /* first stage boot loader */

typedef struct {
    char jump[6]; /* jump over the data */
    char signature[4]; /* "LILO" */
    unsigned short stage,version;
} BOOT_PARAMS_2; /* second stage boot loader */

typedef struct {
    char jump[6]; /* jump over the data */
    char signature[4]; /* "LILO" */
    unsigned short stage,version; /* stage is 0x10 */
    unsigned short offset; /* partition entry offset */
    unsigned char drive; /* BIOS drive code */
    unsigned char head; /* head; always 0 */
    unsigned short drvmap; /* offset of drive map */
    unsigned char ptable[PARTITION_ENTRY*PARTITION_ENTRIES]; /* part. table */
} BOOT_PARAMS_C; /* chain loader */

typedef union {
    BOOT_PARAMS_1 par_1;
    BOOT_PARAMS_2 par_2;
    BOOT_PARAMS_C par_c;
    unsigned char sector[SECTOR_SIZE];
} BOOT_SECTOR;

typedef union {
    struct {
	unsigned short checksum;
	IMAGE_DESCR descr[MAX_IMAGES]; /* boot file descriptors */
    } d;
    unsigned char sector[SECTOR_SIZE*2];
} DESCR_SECTORS;

typedef struct {
    unsigned short jump;	/*  0: jump to startup code */
    char signature[4];		/*  2: "HdrS" */
    unsigned short version;	/*  6: header version */
    unsigned short x,y,z;	/*  8: LOADLIN hacks */
    unsigned short ver_offset;	/* 14: kernel version string */
    unsigned char loader;	/* 16: loader type */
    unsigned char flags;	/* 17: loader flags */
    unsigned short a;		/* 18: more LOADLIN hacks */
    unsigned long start;	/* 20: kernel start, filled in by loader */
    unsigned long ramdisk;	/* 24: RAM disk start address */
    unsigned long ramdisk_size;	/* 28: RAM disk size */
    unsigned short b,c;		/* 32: bzImage hacks */
    unsigned short heap_end_ptr;/* 36: end of free area after setup code */
} SETUP_HDR;

#define alloc_t(t) ((t *) alloc(sizeof(t)))


extern int verbose,test,compact,linear,nowarn,lba32;
extern int boot_dev_nr;

extern unsigned short drv_map[DRVMAP_SIZE+1]; /* needed for fixup maps */
extern int curr_drv_map;
extern unsigned long prt_map[PRTMAP_SIZE+1];
extern int curr_prt_map;


volatile void pdie(char *msg);

/* Do a perror and then exit. */

volatile void die(char *fmt,...);

/* fprintf an error message and then exit. */

void *alloc(int size);

/* Allocates the specified number of bytes. Dies on error. */

void *ralloc(void *old,int size);

/* Changes the size of an allocated memory area. Dies on error. */

char *stralloc(const char *str);

/* Like strdup, but dies on error. */

int to_number(char *num);

/* Converts a string to a number. Dies if the number is invalid. */

void check_version(BOOT_SECTOR *sect,int stage);

/* Verify that a boot sector has the correct version number. */

int stat_equal(struct stat *a,struct stat *b);

/* Compares two stat structures. Returns a non-zero integer if they describe
   the same file, zero if they don't. */

#endif
