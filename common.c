/* common.c  -  Common data structures and functions. */

/* Copyright 1992-1998 Werner Almesberger. See file COPYING for details. */


#include <unistd.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <stdarg.h>

#include "common.h"
#include "lilo.h"


int verbose = 0,test = 0,compact = 0,linear = 0,nowarn = 0, lba32 = 0;

unsigned short drv_map[DRVMAP_SIZE+1]; /* fixup maps ... */
int curr_drv_map;
unsigned long prt_map[PRTMAP_SIZE+1];
int curr_prt_map;


volatile void pdie(char *msg)
{
    fflush(stdout);
    perror(msg);
    exit(1);
}


volatile void die(char *fmt,...)
{
    va_list ap;

    fflush(stdout);
    fprintf(stderr,"Fatal: ");       /* JRC */
    va_start(ap,fmt);
    vfprintf(stderr,fmt,ap);
    va_end(ap);
    fputc('\n',stderr);
    exit(1);
}


void *alloc(int size)
{
    void *this;

    if ((this = malloc(size)) == NULL) pdie("Out of memory");
    return this;
}


void *ralloc(void *old,int size)
{
    void *this;

    if ((this = realloc(old,size)) == NULL) pdie("Out of memory");
    return this;
}


char *stralloc(const char *str)
{
    char *this;

    if ((this = strdup(str)) == NULL) pdie("Out of memory");
    return this;
}


int to_number(char *num)
{
    int number;
    char *end;

    number = strtol(num,&end,0);
    if (end && *end) die("Not a number: \"%s\"",num);
    return number;
}


static char *name(int stage)
{
    switch (stage) {
	case STAGE_FIRST:
	    return "First boot sector";
	case STAGE_SECOND:
	    return "Second boot sector";
	case STAGE_CHAIN:
	    return "Chain loader";
	default:
	    die("Internal error: Unknown stage code %d",stage);
    }
    return NULL; /* for GCC */
}


void check_version(BOOT_SECTOR *sect,int stage)
{
    int bs_major, bs_minor;

    if (!strncmp(sect->par_1.signature-4,"LILO",4))
	die("%s has a pre-21 LILO signature",name(stage));
    if (strncmp(sect->par_1.signature,"LILO",4))
	die("%s doesn't have a valid LILO signature",name(stage));
    if (sect->par_1.stage != stage)
	die("%s has an invalid stage code (%d)",name(stage),sect->par_1.stage);

    bs_major = sect->par_1.version & 255;
    bs_minor = sect->par_1.version >> 8;
#if VERSION_MINOR<50
    if (sect->par_1.version != VERSION)
#else
    if (bs_major != VERSION_MAJOR)
#endif
	die("%s is version %d.%d. Expecting version %d.%d.",name(stage),
	    bs_major,bs_minor, VERSION_MAJOR,VERSION_MINOR);
    if (lba32) {
        if (strncmp(sect->sector+3, "lba", 3)) {
	    if (verbose > 0) printf("sector+3 -> %s\n", sect->sector+3);
	    die("%s is not the LBA32 version.", name(stage));
	}
    }
}


int stat_equal(struct stat *a,struct stat *b)
{
    return a->st_dev == b->st_dev && a->st_ino == b->st_ino;
}
