/* partition.h  -  Partition table handling */

/* Copyright 1992-1996 Werner Almesberger. See file COPYING for details. */


#ifndef PARTITION_H
#define PARTITION_H

void part_verify(int dev_nr,int type);

/* Verify the partition table of the disk of which dev_nr is a partition. May
   also try to "fix" a partition table. Fail on non-Linux partitions if the
   TYPE flag is non-zero (unless IGNORE-TABLE is set too). */

void preload_types(void);

/* Preload some partition types for convenience */

#endif
