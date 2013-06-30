/* bsect.c  -  Boot sector handling */

/* Copyright 1992-1998 Werner Almesberger. See file COPYING for details. */


#include <unistd.h>
#include <stdlib.h>
#include <stdio.h>
#include <ctype.h>
#include <string.h>
#include <fcntl.h>
#include <limits.h>
#include <errno.h>
#include <sys/stat.h>
#include <assert.h>

#include "config.h"
#include "common.h"
#include "cfg.h"
#include "lilo.h"
#include "device.h"
#include "geometry.h"
#include "map.h"
#include "temp.h"
#include "partition.h"
#include "boot.h"
#include "bsect.h"


#ifndef KCF_ROOT_RO
#define KCF_ROOT_RO 1
#endif


int boot_dev_nr;

static BOOT_SECTOR bsect,bsect_orig;
static DESCR_SECTORS descrs;
static DEVICE dev;
static char *boot_devnam,*map_name;
static int fd;
static int image_base = 0,image = 0;
static char temp_map[PATH_MAX+1];
static char *fallback[MAX_IMAGES];
static int fallbacks = 0;


static void open_bsect(char *boot_dev)
{
    struct stat st;

    if (verbose > 0)
	printf("Reading boot sector from %s\n",boot_dev ? boot_dev :
	  "current root.");
    boot_devnam = boot_dev;
    if (boot_dev) {
	if ((fd = open(boot_dev,O_RDWR)) < 0)
	    die("open %s: %s",boot_dev,strerror(errno));
	if (fstat(fd,&st) < 0) die("stat %s: %s",boot_dev,strerror(errno));
	if (!S_ISBLK(st.st_mode)) boot_dev_nr = 0;
	else boot_dev_nr = st.st_rdev;
    }
    else {
	if (stat("/",&st) < 0) pdie("stat /");
	if ((st.st_dev & PART_MASK) > PART_MAX)
	    die("Can't put the boot sector on logical partition 0x%X",
	      st.st_dev);
	fd = dev_open(&dev,boot_dev_nr = st.st_dev,O_RDWR);
    }
    if (boot_dev_nr && !is_first(boot_dev_nr) && !nowarn)
	fprintf(stderr,"Warning: %s is not on the first disk\n",boot_dev ?
	  boot_dev : "current root");
    if (read(fd,(char *) &bsect,SECTOR_SIZE) != SECTOR_SIZE)
	die("read %s: %s",boot_dev ? boot_dev : dev.name,strerror(errno));
    bsect_orig = bsect;
}


void bsect_read(char *boot_dev,BOOT_SECTOR *buffer)
{
    open_bsect(boot_dev);
    *buffer = bsect;
    (void) close(fd);
}


void bsect_open(char *boot_dev,char *map_file,char *install,int delay,
  int timeout)
{
    static char coms[] = "0123";
    static char parity[] = "OoNnEe";
    static char bps[] = "19200\000300\00038400\0001200\0002400\0004800\000"
      "9600\000";
    GEOMETRY geo;
    struct stat st;
    int i_fd,m_fd,kt_fd,sectors;
    char *message,*colon,*serial,*walk,*this,*keytable;
    unsigned char table[SECTOR_SIZE];
    unsigned long timestamp;

    if (stat(map_file,&st) >= 0 && !S_ISREG(st.st_mode))
	die("Map %s is not a regular file.",map_file);
    open_bsect(boot_dev);
    part_verify(boot_dev_nr,0);
#ifndef LCF_NOINSTDEF
    if (!install) install = DFL_BOOT;
#endif
    if (install) {
	if (verbose > 0) printf("Merging with %s\n",install);
	i_fd = geo_open(&geo,install,O_RDONLY);
	timestamp = bsect.par_1.timestamp; /* preserve timestamp */
	if (read(i_fd,(char *) &bsect,MAX_BOOT_SIZE) != MAX_BOOT_SIZE)
	    die("read %s: %s",boot_dev ? boot_dev : dev.name,strerror(errno));
	bsect.par_1.timestamp = timestamp;
	if (fstat(i_fd,&st) < 0)
	    die("stat %s: %s",boot_dev ? boot_dev : dev.name,strerror(errno));
	map_begin_section(); /* no access to the (not yet open) map file
		required, because this map is built in memory */
	map_add(&geo,1,(st.st_size+SECTOR_SIZE-1)/SECTOR_SIZE-1);
	sectors = map_write(bsect.par_1.secondary,MAX_SECONDARY,1);
	if (verbose > 1)
	    printf("Secondary loader: %d sector%s.\n",sectors,sectors == 1 ?
	      "" : "s");
	geo_close(&geo);
    }
    check_version(&bsect,STAGE_FIRST);
    if ((colon = strrchr(map_name = map_file,':')) == NULL)
	strcat(strcpy(temp_map,map_name),MAP_TMP_APP);
    else {
	*colon = 0;
	strcat(strcat(strcpy(temp_map,map_name),MAP_TMP_APP),colon+1);
	*colon = ':';
    }
    map_create(temp_map);
    temp_register(temp_map);
    *(unsigned short *) &bsect.sector[BOOT_SIG_OFFSET] = BOOT_SIGNATURE;
    if (!(message = cfg_get_strg(cf_options,"message")))
	bsect.par_1.msg_len = 0;
    else {
	if (verbose > 0) printf("Mapping message file %s\n",message);
	m_fd = geo_open(&geo,message,O_RDONLY);
	if (fstat(m_fd,&st) < 0) die("stat %s: %s",message,strerror(errno));
	if (st.st_size > MAX_MESSAGE)
	    die("%s is too big (> %d bytes)",message,MAX_MESSAGE);
	map_begin_section();
	map_add(&geo,0,((bsect.par_1.msg_len = st.st_size)+SECTOR_SIZE-1)/
	  SECTOR_SIZE);
	sectors = map_end_section(&bsect.par_1.msg,0);
	if (verbose > 1)
	    printf("Message: %d sector%s.\n",sectors,sectors == 1 ?  "" : "s");
	geo_close(&geo);
    }
    serial = cfg_get_strg(cf_options,"serial");
    if (serial) {
	if (!*serial || !(this = strchr(coms,*serial)))
	    die("Invalid serial port in \"%s\" (should be 0-3)",serial);
	else bsect.par_1.port = (this-coms)+1;
	if (!serial[1]) bsect.par_1.ser_param = SER_DFL_PRM;
	else {
	    if (serial[1] != ',')
		die("Serial syntax is <port>[,<bps>[<parity>[<bits>]]]");
	    walk = bps;
	    bsect.par_1.ser_param = 0;
	    while (*walk) {
		if (!strncmp(serial+2,walk,strlen(walk))) break;
		bsect.par_1.ser_param += 0x20;
		walk = strchr(walk,0)+1;
	    }
	    if (!*walk) die("Unsupported baud rate");
	    if (!*(serial += 2+strlen(walk)))
		bsect.par_1.ser_param |= SER_DFL_PRM & 0x3f;
	    else {
		if (!(this = strchr(parity,*serial)))
		    die("Valid parity values are N, O and E");
		else bsect.par_1.ser_param |= (((this-parity) >> 1)+1) << 4;
		if (!serial[1])
		    bsect.par_1.ser_param |= bsect.par_1.ser_param & 8 ? 2 : 3;
		else {
		    if (serial[1] != '7' && serial[1] != '8')
			die("Only 7 or 8 bits supported");
		    bsect.par_1.ser_param |= serial[1]-'5';
		    if (serial[2]) die("Synax error in SERIAL");
		}
	    }
	}
	if (delay < 20 && !cfg_get_flag(cf_options,"prompt")) {
	    fprintf(stderr,"Setting DELAY to 20 (2 seconds)\n");
	    delay = 20;
	}
    }
    bsect.par_1.prompt = cfg_get_flag(cf_options,"prompt");
    if (delay*100/55 > 0xffff) die("Maximum delay is one hour.");
	else bsect.par_1.delay = delay*100/55;
    if (timeout == -1) bsect.par_1.timeout = 0xffff;
    else if (timeout*100/55 >= 0xffff) die("Maximum timeout is one hour.");
	else bsect.par_1.timeout = timeout*100/55;
    if (!(keytable = cfg_get_strg(cf_options,"keytable"))) {
	int i;

	for (i = 0; i < 256; i++) table[i] = i;
    }
    else {
	if ((kt_fd = open(keytable,O_RDONLY)) < 0)
	    die("open %s: %s",keytable,strerror(errno));
	if (read(kt_fd,table,256) != 256)
	    die("%s: bad keyboard translation table",keytable);
	(void) close(kt_fd);
    }
    map_begin_section();
    map_add_sector(table);
    (void) map_write(&bsect.par_1.keytab,1,0);
    memset(&descrs,0,SECTOR_SIZE*2);
    if (cfg_get_strg(cf_options,"default")) image = image_base = 1;
}


static int dev_number(char *dev)
{
    struct stat st;

    if (stat(dev,&st) >= 0) return st.st_rdev;
    return to_number(dev);
}


static int get_image(char *name,const char *label,IMAGE_DESCR *descr)
{
    char *here,*deflt;
    int this_image,other;

    if (!label) {
        here = strrchr(label = name,'/');
        if (here) label = here+1;
    }
    if (strlen(label) > MAX_IMAGE_NAME) die("Label \"%s\" is too long",label);
    for (other = image_base; other <= image; other++) {
#ifdef LCF_IGNORECASE
	if (!strcasecmp(label,descrs.d.descr[other].name))
#else
	if (!strcmp(label,descrs.d.descr[other].name))
#endif
	    die("Duplicate label \"%s\"",label);
	if ((((descr->flags & FLAG_SINGLE) && strlen(label) == 1) ||
          (((descrs.d.descr[other].flags) & FLAG_SINGLE) &&
	  strlen(descrs.d.descr[other].name) == 1)) &&
#ifdef LCF_IGNORECASE
	  toupper(*label) == toupper(*descrs.d.descr[other].name))
#else
	  *label == *descrs.d.descr[other].name)
#endif
	    die("Single-key clash: \"%s\" vs. \"%s\"",label,
	      descrs.d.descr[other].name);
    }

    if (image_base && (deflt = cfg_get_strg(cf_options,"default")) &&
#ifdef LCF_IGNORECASE
      !strcasecmp(deflt,label))
#else
      !strcmp(deflt,label))
#endif
	this_image = image_base = 0;
    else {
	if (image == MAX_IMAGES)
	    die("Only %d image names can be defined",MAX_IMAGES);
	this_image = image++;
    }
    descrs.d.descr[this_image] = *descr;
    strcpy(descrs.d.descr[this_image].name,label);
    return this_image;
}


static char options[SECTOR_SIZE]; /* this is ugly */


static void bsect_common(IMAGE_DESCR *descr)
{
    struct stat st;
    char *here,*root,*ram_disk,*vga,*password;
    char *literal,*append,*fback;
    char fallback_buf[SECTOR_SIZE];

    *descr->password = 0;
    descr->flags = 0;
    memset(fallback_buf,0,SECTOR_SIZE);
    memset(options,0,SECTOR_SIZE);
    if ((cfg_get_flag(cf_kernel,"read-only") && cfg_get_flag(cf_kernel,
      "read-write")) || (cfg_get_flag(cf_options,"read-only") && cfg_get_flag(
      cf_options,"read-write")))
	die("Conflicting READONLY and READ_WRITE settings.");
    if (cfg_get_flag(cf_kernel,"read-only") || cfg_get_flag(cf_options,
      "read-only")) strcat(options,"ro ");
    if (cfg_get_flag(cf_kernel,"read-write") || cfg_get_flag(cf_options,
      "read-write")) strcat(options,"rw ");
    if ((root = cfg_get_strg(cf_kernel,"root")) || (root = cfg_get_strg(
      cf_options,"root")))
	if (strcasecmp(root,"current")) 
	    sprintf(strchr(options,0),"root=%x ",dev_number(root));
	else {
	    if (stat("/",&st) < 0) pdie("stat /");
	    sprintf(strchr(options,0),"root=%x ",(unsigned int) st.st_dev);
	}
    if ((ram_disk = cfg_get_strg(cf_kernel,"ramdisk")) || (ram_disk =
      cfg_get_strg(cf_options,"ramdisk")))
	sprintf(strchr(options,0),"ramdisk=%d ",to_number(ram_disk));
    if (cfg_get_flag(cf_kernel,"lock") || cfg_get_flag(cf_options,"lock"))
#ifdef LCF_READONLY
	die("This LILO is compiled READONLY and doesn't support the LOCK "
	  "option");
#else
	descr->flags |= FLAG_LOCK;
#endif
    if ((vga = cfg_get_strg(cf_kernel,"vga")) || (vga = cfg_get_strg(cf_options,
      "vga"))) {
#ifndef NORMAL_VGA
	die("VGA mode presetting is not supported by your kernel.");
#else
	descr->flags |= FLAG_VGA;
	     if (!strcasecmp(vga,"normal")) descr->vga_mode = NORMAL_VGA;
	else if (!strcasecmp(vga,"ext") || !strcasecmp(vga,"extended"))
		descr->vga_mode = EXTENDED_VGA;
	else if (!strcasecmp(vga,"ask")) descr->vga_mode = ASK_VGA;
	else descr->vga_mode = to_number(vga);
#endif
    }
    if ((password = cfg_get_strg(cf_all,"password")) || (password =
      cfg_get_strg(cf_options,"password"))) {
	if (strlen(password) > MAX_PW)
	    die("Password \"%s\" is too long",password);
	strcpy(descr->password,password);
    }
    if (cfg_get_flag(cf_all,"restricted") || cfg_get_flag(cf_options,
      "restricted")) {
	if (!password) die("RESTRICTED is only valid if PASSWORD is set.");
	descr->flags |= FLAG_RESTR;
    }
    if (cfg_get_flag(cf_all,"single-key") ||
      cfg_get_flag(cf_options,"single-key")) descr->flags |= FLAG_SINGLE;
    if ((append = cfg_get_strg(cf_kernel,"append")) || (append =
      cfg_get_strg(cf_options,"append"))) strcat(options,append);
    literal = cfg_get_strg(cf_kernel,"literal");
    if (literal) strcpy(options,literal);
    if (*options) {
	here = strchr(options,0);
	if (here[-1] == ' ') here[-1] = 0;
    }
    fback = cfg_get_strg(cf_kernel,"fallback");
    if (fback) {
#ifdef LCF_READONLY
	die("This LILO is compiled READONLY and doesn't support the FALLBACK "
	  "option");
#else
	if (descr->flags & FLAG_LOCK)
	    die("LOCK and FALLBACK are mutually exclusive");
	*(unsigned short *) fallback_buf = DC_MAGIC;
	strcpy(fallback_buf+2,fback);
	fallback[fallbacks++] = stralloc(fback);
#endif
    }
    *(unsigned long *) descr->rd_size = 0; /* no RAM disk */
    descr->start_page = 0; /* load low */
    map_begin_section();
    map_add_sector(fallback_buf);
    map_add_sector(options);
}


static void bsect_done(char *name,IMAGE_DESCR *descr)
{
    char *alias;
    int this_image,this;

    if (!*name) die("Invalid image name.");
    alias = cfg_get_strg(cf_all,"alias");
    this = alias ? get_image(NULL,alias,descr) : -1;
    this_image = get_image(name,cfg_get_strg(cf_all,"label"),descr);
    if ((descr->flags & FLAG_SINGLE) &&
      strlen(descrs.d.descr[this_image].name) > 1 &&
      (!alias || strlen(alias) > 1))
	die("SINGLE-KEYSTROKE requires the label or the alias to be only "
	  "a single character");
    if (verbose >= 0) {
	printf("Added %s",descrs.d.descr[this_image].name);
	if (alias) printf(" (alias %s)",alias);
	if (this_image && this) putchar('\n');
	else printf(" *\n");
    }
    if (verbose > 2) {
	printf("%4s<dev=0x%02x,hd=%d,cyl=%d,sct=%d>\n","",
	  descr->start.device,descr->start.head,descr->start.track,
	  descr->start.sector);
	if (*options) printf("%4s\"%s\"\n","",options);
    }
}


int bsect_number(void)
{
    return image_base ? 0 : image;
}


static void unbootable(void)
{
    fflush(stdout);
    fprintf(stderr,"\nWARNING: The system is unbootable !\n");
    fprintf(stderr,"%9sRun LILO again to correct this.","");
    exit(1);
}


void check_fallback(void)
{
    char *start,*end;
    int i,image;

    for (i = 0; i < fallbacks; i++) {
	for (start = fallback[i]; *start && *start == ' '; start++);
	if (*start) {
	    for (end = start; *end && *end != ' '; end++);
	    if (*end) *end = 0;
	    for (image = 0; image < MAX_IMAGES; image++)
#ifdef LCF_IGNORECASE
		if (!strcasecmp(descrs.d.descr[image].name,start)) break;
#else
		if (!strcmp(descrs.d.descr[image].name,start)) break;
#endif
	    if (image == MAX_IMAGES) die("No image \"%s\" is defined",start);
	}
    }
}


void bsect_update(char *backup_file,int force_backup)
{
    struct stat st;
    char temp_name[PATH_MAX+1];
    int bck_file;

    if (!backup_file) {
	sprintf(temp_name,BACKUP_DIR "/boot.%04X",boot_dev_nr);
	backup_file = temp_name;
    }
    bck_file = open(backup_file,O_RDONLY);
    if (bck_file >= 0 && force_backup) {
	(void) close(bck_file);
	bck_file = -1;
    }
    if (bck_file >= 0) {
	if (verbose > 0)
	    printf("%s exists - no backup copy made.\n",backup_file);
    }
    else {
	if ((bck_file = creat(backup_file,0644)) < 0)
	    die("creat %s: %s",backup_file,strerror(errno));
	if (write(bck_file,(char *) &bsect_orig,SECTOR_SIZE) != SECTOR_SIZE)
	    die("write %s: %s",backup_file,strerror(errno));
	if (verbose > 0)
	    printf("Backup copy of boot sector in %s\n",backup_file);
	if (fstat(bck_file,&st) < 0)
	    die("fstat %s: %s",backup_file,strerror(errno));
	bsect.par_1.timestamp = st.st_mtime;
    }
    if (close(bck_file) < 0) die("close %s: %s",backup_file,strerror(errno));
    map_done(&descrs,bsect.par_1.descr);
    if (lseek(fd,0,0) < 0)
	die("lseek %s: %s",boot_devnam ? boot_devnam : dev.name,
	  strerror(errno));
    if (verbose > 0) printf("Writing boot sector.\n");
    if (write(fd,(char *) &bsect,SECTOR_SIZE) != SECTOR_SIZE)
	die("write %s: %s",boot_devnam ? boot_devnam : dev.name,
	  strerror(errno));
    if (!boot_devnam) dev_close(&dev);
    else if (close(fd) < 0) {
	    unbootable();
	    die("close %s: %s",boot_devnam,strerror(errno));
	}
    temp_unregister(temp_map);
    if (rename(temp_map,map_name) < 0) {
	unbootable();
	die("rename %s %s: %s",temp_map,map_name,strerror(errno));
    }
    (void) sync();
}


void bsect_cancel(void)
{
    map_done(&descrs,bsect.par_1.descr);
    if (boot_devnam) (void) close(fd);
    else dev_close(&dev);
    temp_unregister(temp_map);
    if (verbose<9) (void) remove(temp_map);
}


static int present(char *var)
{
    char *path;

    if (!(path = cfg_get_strg(cf_top,var))) die("No variable \"%s\"",var);
    if (!access(path,F_OK)) return 1;
    if (!cfg_get_flag(cf_all,"optional") && !cfg_get_flag(cf_options,
      "optional")) return 1;
    if (verbose >= 0) printf("Skipping %s\n",path);
    return 0;
}


void do_image(void)
{
    IMAGE_DESCR descr;
    char *name;

    cfg_init(cf_image);
    (void) cfg_parse(cf_image);
    if (present("image")) {
	bsect_common(&descr);
	descr.flags |= FLAG_KERNEL;
	name = cfg_get_strg(cf_top,"image");
	if (!cfg_get_strg(cf_image,"range")) boot_image(name,&descr);
	else boot_device(name,cfg_get_strg(cf_image,"range"),&descr);
	bsect_done(name,&descr);
    }
    cfg_init(cf_top);
}


void do_other(void)
{
    IMAGE_DESCR descr;
    char *name;

    cfg_init(cf_other);
    cfg_init(cf_kernel); /* clear kernel parameters */
    curr_drv_map = curr_prt_map = 0;
    (void) cfg_parse(cf_other);
    if (present("other")) {
	bsect_common(&descr);
	name = cfg_get_strg(cf_top,"other");
	boot_other(cfg_get_strg(cf_other,"loader"),name,
	  cfg_get_strg(cf_other,"table"),&descr);
	bsect_done(name,&descr);
    }
    cfg_init(cf_top);
}


void bsect_uninstall(char *boot_dev,char *backup_file,int validate)
{
    struct stat st;
    char temp_name[PATH_MAX+1];
    int bck_file;

    open_bsect(boot_dev);
    if (*(unsigned short *) &bsect.sector[BOOT_SIG_OFFSET] != BOOT_SIGNATURE)
	die("Boot sector of %s does not have a boot signature",boot_dev ?
	  boot_dev : dev.name);
    if (!strncmp(bsect.par_1.signature-4,"LILO",4))
	die("Boot sector of %s has a pre-21 LILO signature",boot_dev ?
	  boot_dev : dev.name);
    if (strncmp(bsect.par_1.signature,"LILO",4))
	die("Boot sector of %s doesn't have a LILO signature",boot_dev ?
	  boot_dev : dev.name);
    if (!backup_file) {
	sprintf(temp_name,BACKUP_DIR "/boot.%04X",boot_dev_nr);
	backup_file = temp_name;
    }
    if ((bck_file = open(backup_file,O_RDONLY)) < 0)
	die("open %s: %s",backup_file,strerror(errno));
    if (fstat(bck_file,&st) < 0)
	die("fstat %s: %s",backup_file,strerror(errno));
    if (validate && st.st_mtime != bsect.par_1.timestamp)
	die("Timestamp in boot sector of %s differs from date of %s\n"
	  "Try using the -U option if you know what you're doing.",boot_dev ?
	  boot_dev : dev.name,backup_file);
    if (verbose > 0) printf("Reading old boot sector.\n");
    if (read(bck_file,(char *) &bsect,PART_TABLE_OFFSET) != PART_TABLE_OFFSET)
	die("read %s: %s",backup_file,strerror(errno));
    if (lseek(fd,0,0) < 0)
	die("lseek %s: %s",boot_dev ? boot_dev : dev.name,strerror(errno));
    if (verbose > 0) printf("Restoring old boot sector.\n");
    if (write(fd,(char *) &bsect,PART_TABLE_OFFSET) != PART_TABLE_OFFSET)
	die("write %s: %s",boot_dev ? boot_dev : dev.name,strerror(errno));
    if (!boot_devnam) dev_close(&dev);
    else if (close(fd) < 0) {
	    unbootable();
	    die("close %s: %s",boot_devnam,strerror(errno));
	}
    exit(0);
}
