/* partition.c  -  Partition table handling */

/* Copyright 1992-1998 Werner Almesberger. See file COPYING for details. */


#include <unistd.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <fcntl.h>
#include <limits.h>
#include <errno.h>
#include <sys/stat.h>

#include <linux/fs.h>
#include <linux/kdev_t.h>

#include "config.h"
#include "lilo.h"
#include "common.h"
#include "cfg.h"
#include "device.h"
#include "geometry.h"


/* For older kernels ... */

#define EXTENDED_PARTITION 0x85
 
#ifndef DOS_EXTENDED_PARTITION
#define DOS_EXTENDED_PARTITION EXTENDED_PARTITION
#endif

#ifndef LINUX_EXTENDED_PARTITION
#define LINUX_EXTENDED_PARTITION EXTENDED_PARTITION
#endif


void part_verify(int dev_nr,int type)
{
    GEOMETRY geo;
    DEVICE dev;
    char backup_file[PATH_MAX+1];
    int fd,bck_file,part,size,lin_3d,cyl;
    struct partition part_table[PART_MAX];

    if (!(dev_nr & PART_MASK) || (dev_nr & PART_MASK) > PART_MAX ||
      (MAJOR(dev_nr) != MAJOR_HD && MAJOR(dev_nr) != MAJOR_XT &&
       MAJOR(dev_nr) != MAJOR_SD && MAJOR(dev_nr) != MAJOR_IDE2 &&
       MAJOR(dev_nr) != MAJOR_IDE3 && MAJOR(dev_nr) != MAJOR_IDE4 &&
       MAJOR(dev_nr) != MAJOR_IDE5 && MAJOR(dev_nr) != MAJOR_IDE6 &&
      MAJOR(dev_nr) != MAJOR_DAC960)) return;
    geo_get(&geo,dev_nr & ~PART_MASK,-1,1);
    fd = dev_open(&dev,dev_nr & ~PART_MASK,cfg_get_flag(cf_options,"fix-table")
      && !test ? O_RDWR : O_RDONLY);
    part = (dev_nr & PART_MASK)-1;
    if (lseek(fd,PART_TABLE_OFFSET,0) < 0) pdie("lseek partition table");
    if (!(size = read(fd,(char *) part_table,sizeof(struct partition)*
      PART_MAX))) die("Short read on partition table");
    if (size < 0) pdie("read partition table");
    if (type && part_table[part].sys_ind != PART_LINUX_MINIX &&
      part_table[part].sys_ind != PART_LINUX_NATIVE &&
      part_table[part].sys_ind != DOS_EXTENDED_PARTITION &&
      part_table[part].sys_ind != LINUX_EXTENDED_PARTITION) {
	fflush(stdout);
	fprintf(stderr,"Device 0x%04X: Partition type 0x%02X does not seem "
	  "suitable for a LILO boot sector\n",dev_nr,part_table[part].sys_ind);
	if (!cfg_get_flag(cf_options,"ignore-table")) exit(1);
    }
    cyl = part_table[part].cyl+((part_table[part].sector >> 6) << 8);
    lin_3d = (part_table[part].sector & 63)-1+(part_table[part].head+
      cyl*geo.heads)*geo.sectors;
    if ((lin_3d > part_table[part].start_sect || (lin_3d <
      part_table[part].start_sect && cyl != BIOS_MAX_CYLS-1)) && !nowarn) {
	fflush(stdout);
	fprintf(stderr,"Device 0x%04X: Invalid partition table, %d%s entry\n",
	  dev_nr & ~PART_MASK,part+1,!part ? "st" : part == 1 ? "nd" : part ==
	  2 ? "rd" : "th");
	fprintf(stderr,"  3D address:     %d/%d/%d (%d)\n",part_table[part].
	  sector & 63,part_table[part].head,cyl,lin_3d);
	cyl = part_table[part].start_sect/geo.sectors/geo.heads;
	fprintf(stderr,"  Linear address: %d/%d/%d (%d)\n",part_table[part].
	  sector = (part_table[part].start_sect % geo.sectors)+1,part_table
	  [part].head = (part_table[part].start_sect/geo.sectors) %
	  geo.heads,cyl,part_table[part].start_sect);
	part_table[part].sector |= cyl >> 8;
	part_table[part].cyl = cyl & 0xff;
	if (!cfg_get_flag(cf_options,"fix-table") && !cfg_get_flag(cf_options,
	  "ignore-table")) exit(1);
	if (test || cfg_get_flag(cf_options,"ignore-table"))
	    fprintf(stderr,"The partition table is *NOT* being adjusted.\n");
	else {
	    sprintf(backup_file,BACKUP_DIR "/part.%04X",dev_nr & ~PART_MASK);
	    if ((bck_file = creat(backup_file,0644)) < 0)
		die("creat %s: %s",backup_file,strerror(errno));
	    if (!(size = write(bck_file,(char *) part_table,
	      sizeof(struct partition)*PART_MAX)))
		die("Short write on %s",backup_file);
	    if (size < 0) pdie(backup_file);
	    if (close(bck_file) < 0)
		die("close %s: %s",backup_file,strerror(errno));
	    if (verbose > 0)
		printf("Backup copy of partition table in %s\n",backup_file);
	    printf("Writing modified partition table to device 0x%04X\n",
	      dev_nr & ~PART_MASK);
	    if (lseek(fd,PART_TABLE_OFFSET,0) < 0)
		pdie("lseek partition table");
	    if (!(size = write(fd,(char *) part_table,sizeof(struct partition)*
	      PART_MAX))) die("Short write on partition table");
	    if (size < 0) pdie("write partition table");
	}
    }
    dev_close(&dev);
}


typedef struct _change_rule {
    const char *type;
    unsigned char normal;
    unsigned char hidden;
    struct _change_rule *next;
} CHANGE_RULE;


static CHANGE_RULE *change_rules = NULL;


void do_cr_reset(void)
{
    CHANGE_RULE *next;

    while (change_rules) {
	next = change_rules->next;
	free((char *) change_rules->type);
	free(change_rules);
	change_rules = next;
    }
}


static unsigned char cvt_byte(const char *s)
{
    char *end;
    unsigned long value;

    value = strtoul(s,&end,0);
    if (value > 255 || *end) cfg_error("\"%s\" is not a byte value",s);
    return value;
}


static void add_type(const char *type,int normal,int hidden)
{
    CHANGE_RULE *rule;

    for (rule = change_rules; rule; rule = rule->next)
	if (!strcasecmp(rule->type,type))
	    die("Duplicate type name: \"%s\"",type);
    rule = alloc_t(CHANGE_RULE);
    rule->type = stralloc(type);
    rule->normal = normal == -1 ? hidden ^ HIDDEN_OFF : normal;
    rule->hidden = hidden == -1 ? normal ^ HIDDEN_OFF : hidden;
    rule->next = change_rules;
    change_rules = rule;
}


void do_cr_type(void)
{
    const char *normal,*hidden;

    cfg_init(cf_change_rule);
    (void) cfg_parse(cf_change_rule);
    normal = cfg_get_strg(cf_change_rule,"normal");
    hidden = cfg_get_strg(cf_change_rule,"hidden");
    if (normal)
	add_type(cfg_get_strg(cf_change_rules,"type"),cvt_byte(normal),
	  hidden ? cvt_byte(hidden) : -1);
    else {
	if (!hidden)
	    cfg_error("At least one of NORMAL and HIDDEN must be present");
	add_type(cfg_get_strg(cf_change_rules,"type"),cvt_byte(hidden),-1);
    }
    cfg_unset(cf_change_rules,"type");
}


void do_cr(void)
{
    cfg_init(cf_change_rules);
    (void) cfg_parse(cf_change_rules);
}


#if defined(LCF_REWRITE_TABLE)

/*
 * Rule format:
 *
 * +------+------+------+------+
 * |drive |offset|expect| set  |
 * +------+------+------+------+
 *     0      1      2      3
 */

static void add_rule(unsigned char bios,unsigned char offset,
  unsigned char expect,unsigned char set)
{
    int i;

    if (curr_prt_map == PRTMAP_SIZE)
	cfg_error("Too many change rules (more than %s)",PRTMAP_SIZE);
    if (verbose >= 3)
	printf("  Adding rule: disk 0x%02x, offset 0x%x, 0x%02x -> 0x%02x\n",
	    bios,PART_TABLE_OFFSET+offset,expect,set);
    prt_map[curr_prt_map] = (set << 24) | (expect << 16) | (offset << 8) | bios;
    for (i = 0; i < curr_prt_map; i++) {
	if (prt_map[i] == prt_map[curr_prt_map])
	  die("Repeated rule: disk 0x%02x, offset 0x%x, 0x%02x -> 0x%02x",
	    bios,PART_TABLE_OFFSET+offset,expect,set);
	if ((prt_map[i] & 0xffff) == ((offset << 8) | bios) &&
	  (prt_map[i] >> 24) == expect)
	    die("Redundant rule: disk 0x%02x, offset 0x%x: 0x%02x -> 0x%02x "
	      "-> 0x%02x",bios,PART_TABLE_OFFSET+offset,
	     (prt_map[i] >> 16) & 0xff,expect,set);
    }
    curr_prt_map++;
}

#endif


static int has_partition;


#if 0

void do_cr_auto(void)
{
    struct stat st_tab,st_oth;
    char char *table;

    if (has_partition) cfg_error("AUTOMATIC must be before PARTITION");
    table = cfg_get_strg(cf_other,"table");
    if (!table) cfg_error("TABLE must be set to use AUTOMATIC");
    if (stat(table,&st_tab) < 0)
	cfg_error("stat %s: %s",table,strerror(errno));
    /*
     * Etc. Actually, all this doesn't make too much sense, because what we
     * really should do is to scan all available fixed drives and add those
     * to the list. Of course, we don't have the slightest idea of what
     * drives are accessible, fixed, etc. So the only option left is to let
     * the user handle everything by manual configuration ...
     */
}

#endif


void do_cr_part(void)
{
    GEOMETRY geo;
    struct stat st;
    char *tmp;
    int partition,part_base;

    tmp = cfg_get_strg(cf_change,"partition");
    if (stat(tmp,&st) < 0) die("stat %s: %s",tmp,strerror(errno));
    geo_get(&geo,st.st_rdev & ~PART_MASK,-1,1);
    partition = st.st_rdev & PART_MASK;
    if (!S_ISBLK(st.st_mode) || !partition || partition > PART_MAX)
	cfg_error("\"%s\" isn't a primary partition",tmp);
    part_base = (partition-1)*PARTITION_ENTRY;
    has_partition = 1;   
    cfg_init(cf_change_dsc);
    (void) cfg_parse(cf_change_dsc);
    tmp = cfg_get_strg(cf_change_dsc,"set");
    if (tmp) {
#if defined(LCF_REWRITE_TABLE)
	CHANGE_RULE *walk;
	char *here;
	int hidden;

	if (strlen(tmp) < 7 || !(here = strrchr(tmp,'_')) ||
	  ((hidden = strcasecmp(here+1,"normal")) &&
	  strcasecmp(here+1,"hidden")))
	    cfg_error("Type name must end with _normal or _hidden");
	*here = 0;
	for (walk = change_rules; walk; walk = walk->next)
	    if (!strcasecmp(walk->type,tmp)) break;
	if (!walk) cfg_error("Unrecognized type name");
	add_rule(geo.device,part_base+PART_TYPE_ENT_OFF,hidden ? walk->normal :
	  walk->hidden,hidden ? walk->hidden : walk->normal);
#else
	die("This LILO is compiled without REWRITE_TABLE and doesn't support "
	  "the SET option");
#endif
    }
    if (cfg_get_flag(cf_change_dsc,"activate")) {
#if defined(LCF_REWRITE_TABLE)
	add_rule(geo.device,part_base+PART_ACT_ENT_OFF,0x00,0x80);
	if (cfg_get_flag(cf_change_dsc,"deactivate"))
	    cfg_error("ACTIVATE and DEACTIVATE are incompatible");
#else
	die("This LILO is compiled without REWRITE_TABLE and doesn't support "
	  "the ACTIVATE option");
#endif
    }
    if (cfg_get_flag(cf_change_dsc,"deactivate"))
#if defined(LCF_REWRITE_TABLE)
	add_rule(geo.device,part_base+PART_ACT_ENT_OFF,0x80,0x00);
#else
	die("This LILO is compiled without REWRITE_TABLE and doesn't support "
	  "the DEACTIVATE option");
#endif
    cfg_unset(cf_change,"partition");
}


void do_change(void)
{
    cfg_init(cf_change);
    has_partition = 0;
    (void) cfg_parse(cf_change);
}


void preload_types(void)
{
    add_type("DOS12",PART_DOS12,PART_HDOS12);
    add_type("DOS16_small",PART_DOS16_SMALL,PART_HDOS16_SMALL);
    add_type("DOS16_big",PART_DOS16_BIG,PART_HDOS16_SMALL);
#if 0 /* don't know if it makes sense to add these too */
    add_type("OS2",0x07,0x17);
    add_type("OS2BM",0x0a,0x1a);
    add_type("Netware",0x64,0x74);
    /* What types do VFAT, FAT32, and WNT use ? */
#endif
}
