# Configuration variables

# They can also be stored in a file /etc/lilo.defines, e.g.
# -DIGNORECASE -DONE_SHOT

# The variables configured in this Makefile are ignored if
# /etc/lilo.defines exists

#   BEEP	  Beep after displaying "LILO".
#   IGNORECASE    Image selection is case-insensitive. Passwords are still
#		  case-sensitive.
#   LARGE_EBDA	  Load at 8xxxx instead of 9xxxx to leave more room for the
#		  EBDA (Extended BIOS Data Area)
#   NO1STDIAG	  Don't show diagnostic on read errors in the first stage boot
#   NODRAIN	  Don't drain keyboard buffer after booting.
#   NOINSTDEF     Don't install a new boot sector if INSTALL is not specified.
#   ONE_SHOT      Disable the command-line and password timeout if any key is
#		  hit at the boot prompt.
#   READONLY	  Don't write to disk while booting, e.g. don't overwrite the
#		  default command line in the map file after reading it.
#   REWRITE_TABLE Enable rewriting the partition table at boot time.
#		  loader.
#   USE_TMPDIR	  Create temporary devices in $TMPDIR if set
#   VARSETUP	  Enables use of variable-size setup segments.
#   XL_SECS=n	  Support for extra large (non-standard) floppies.

CONFIG=-DIGNORECASE -DVARSETUP -DREWRITE_TABLE -DLARGE_EBDA -DONE_SHOT

# End of configuration variables

SBIN_DIR=/sbin
CFG_DIR=/etc
BOOT_DIR=/boot
USRSBIN_DIR=/usr/sbin
MAN_DIR=/usr/man

PCONFIG=`( if [ -r $$ROOT/etc/lilo.defines ]; then \
  cat $$ROOT/etc/lilo.defines; else echo $(CONFIG); fi ) | \
  sed 's/-D/-DLCF_/g'` `[ -r /usr/include/asm/boot.h ] && echo -DHAS_BOOT_H`
GO=-DGO=0x`sed '/go/s/^.*go *0 \(....\) A.*$$/\1/p;d' first.lis`

SHELL=/bin/sh
CC=cc
CPP=$(CC) -E
AS86=as86 -0 -a
LD86=ld86 -0

CFLAGS=-Wall -g $(PCONFIG)
LDFLAGS=#-Xlinker -qmagic

OBJS=lilo.o map.o geometry.o boot.o device.o common.o bsect.o cfg.o temp.o \
  partition.o identify.o

.SUFFIXES:	.img .b .com

all:		check-config lilo boot.b dump.b os2_d.b chain.b dparam.com \
		  disk.com activate 

#
# make the bootable diagnostic floppy
#

floppy:		disk.com bootsect.b
		cat bootsect.b disk.com >disk2.b
		dd if=disk2.b of=/dev/fd0
		rm -f disk2.b

check-config:
		$(CPP) check-config.cpp $(PCONFIG) >/dev/null

.c.o:
		$(CC) -c $(CFLAGS) $*.c

.s.o:
		$(AS86) -w -l $*.lis -o $*.o $*.s

.o.img:
		$(LD86) -s -o $*.img $*.o

.img.b:
		dd if=$*.img of=$*.b bs=32 skip=1

activate:	activate.c
		$(CC) -Wall -s -O -o activate activate.c $(LDFLAGS)

disk1.com:	disk1.s
		nasm -f bin -o disk1.com -l disk1.lis  disk1.s

disk1.s:	disk1.S mylilo.h
		$(CPP) -traditional $(PCONFIG) -o disk1.s  disk1.S

disk.com:	disk.b
		cp disk.b disk.com

#disk.b:		disk.img

#disk.img:	disk.o

#disk.o:		disk.s

disk.s:	disk.S lilo.h
		$(CPP) -traditional $(PCONFIG) -o disk.s  disk.S

bootsect.s:	bootsect.S lilo.h version.h
		$(CPP) -traditional $(PCONFIG) -o bootsect.s  bootsect.S

mylilo.h:	lilo.h version.h
		sed <lilo.h >mylilo.h -e "s/=/ equ /" -e "s/!/;/"

dparam.com:	dparam.img
		dd if=dparam.img of=dparam.com bs=288 skip=1

dparam.s:	dparam.S
		cp -p dparam.S dparam.s

lilo:		$(OBJS)
		$(CC) -o lilo $(LDFLAGS) $(OBJS)

boot.b:		first.b second.b
		(dd if=first.b bs=512 conv=sync; dd if=second.b) >boot.b

first.s:	first.S read.S lilo.h version.h lilo
		$(CPP) $(PCONFIG) `./lilo -X` first.S -o first.s
		
second.s:	second.S read.S lilo.h version.h lilo
		$(CPP) $(PCONFIG) $(GO) `./lilo -X` second.S -o second.s

chain.s:	chain.S lilo.h version.h
		$(CPP) $(PCONFIG) $(GO) chain.S -o chain.s

os2_d.s:	chain.S lilo.h version.h
		$(CPP) $(PCONFIG) $(GO) chain.S -DDOS_D -o os2_d.s

#dos_d.s:	chain.S lilo.h version.h first.lis
#		$(CPP) $(PCONFIG) $(GO) chain.S -DDOS_D -o dos_d.s

dump.s:		dump.S lilo.h version.h first.lis
		$(CPP) $(PCONFIG) `./lilo -X` dump.S -DDOS_D -o dump.s \
	          -DGO=0x`sed '/go/s/^.*go  0 \(....\) A.*$$/\1/p;d' first.lis`

xxx.s:		chain.S lilo.h
		$(CPP) chain.S -DXXX -o xxx.s

first.o first.lis:	first.s
		$(AS86) -w -o first.o -l first.lis first.s

second.lis:	second.s
		$(AS86) -w -l second.lis second.s

install:	all
		if [ ! -d $$ROOT$(SBIN_DIR) ]; then mkdir $$ROOT$(SBIN_DIR); fi
		if [ ! -d $$ROOT$(CFG_DIR) ]; then mkdir $$ROOT$(CFG_DIR); fi
		if [ ! -d $$ROOT$(BOOT_DIR) ]; then mkdir $$ROOT$(BOOT_DIR); fi
		if [ ! -d $$ROOT$(USRSBIN_DIR) ]; then \
		  mkdir $$ROOT$(USRSBIN_DIR); fi
		if [ ! -d $$ROOT$(MAN_DIR) ]; then mkdir $$ROOT$(MAN_DIR); fi  
		if [ ! -d $$ROOT$(MAN_DIR)/man5 ]; then \
		  mkdir $$ROOT$(MAN_DIR)/man5; fi  
		if [ ! -d $$ROOT$(MAN_DIR)/man8 ]; then \
		  mkdir $$ROOT$(MAN_DIR)/man8; fi  
		if [ -f $$ROOT$(BOOT_DIR)/boot.b ]; then \
		  mv $$ROOT$(BOOT_DIR)/boot.b $$ROOT$(BOOT_DIR)/boot.old; fi
		if [ -f $$ROOT$(BOOT_DIR)/chain.b ]; then \
		  mv $$ROOT$(BOOT_DIR)/chain.b $$ROOT$(BOOT_DIR)/chain.old; fi
		if [ -f $$ROOT$(BOOT_DIR)/os2_d.b ]; then \
		  mv $$ROOT$(BOOT_DIR)/os2_d.b $$ROOT$(BOOT_DIR)/os2_d.old; fi
		cp boot.b chain.b os2_d.b $$ROOT$(BOOT_DIR)
		cp lilo $$ROOT$(SBIN_DIR)
		strip $$ROOT$(SBIN_DIR)/lilo
		cp keytab-lilo.pl $$ROOT$(USRSBIN_DIR)
		cp manPages/lilo.8 $$ROOT$(MAN_DIR)/man8
		cp manPages/lilo.conf.5 $$ROOT$(MAN_DIR)/man5
		@if [ -e $$ROOT/etc/lilo/install ]; then echo; \
		  echo -n "$$ROOT/etc/lilo/install is obsolete. LILO is now ";\
		  echo "re-installed "; \
		  echo "by just invoking $(SBIN_DIR)/lilo"; echo; fi
		@echo "/sbin/lilo must now be run to complete the update."

dep:
		sed '/\#\#\# Dependencies/q' <Makefile >tmp_make
		$(CPP) $(CFLAGS) -MM *.c >>tmp_make
		mv tmp_make Makefile

version:
		[ -r VERSION ] && [ -d ../lilo -a ! -d ../lilo-`cat VERSION` ]\
		  && mv ../lilo ../lilo-`cat VERSION`

tidy:		
		rm -f *.lis *.img disk.s mylilo.h

clean:		tidy
		rm -f *.o *.s first.b second.b chain.b os2_d.b bootsect.b \
		tmp_make

spotless:	clean
		rm -f lilo activate *.b *.com *.img

### Dependencies
activate.o: activate.c
boot.o: boot.c config.h common.h lilo.h version.h geometry.h cfg.h \
 map.h partition.h boot.h
bsect.o: bsect.c config.h common.h lilo.h version.h cfg.h device.h \
 geometry.h map.h temp.h partition.h boot.h bsect.h
cfg.o: cfg.c common.h lilo.h version.h temp.h cfg.h
common.o: common.c common.h lilo.h version.h
device.o: device.c config.h common.h lilo.h version.h temp.h device.h
geometry.o: geometry.c config.h lilo.h version.h common.h device.h \
 geometry.h cfg.h
identify.o: identify.c cfg.h
lilo.o: lilo.c config.h common.h lilo.h version.h temp.h device.h \
 geometry.h map.h bsect.h cfg.h identify.h partition.h md-int.h
map.o: map.c lilo.h version.h common.h geometry.h map.h
partition.o: partition.c config.h lilo.h version.h common.h cfg.h \
 device.h geometry.h
temp.o: temp.c common.h lilo.h version.h temp.h
test.o: test.c
