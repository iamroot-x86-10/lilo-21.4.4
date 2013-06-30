# make with 'make disk' from C51
#
AS=nasm16
#AS=nasm

disk.com:	disk.s
	$(AS)  -f bin -o disk.com -l disk.lis  disk.s
