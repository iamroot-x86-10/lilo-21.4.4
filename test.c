#include <stdio.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <sys/ioctl.h>
#include <linux/fs.h>


int main(int argc,char **argv)
{
    int fd,i,block;
    struct phyloc_result phyloc;
    struct stat st;

printf("%d %d\n",sizeof(off_t),sizeof(loff_t));
    fd = open(argv[1],O_RDONLY);
    if (fd < 0) {
	perror(argv[1]);
	return 1;
    }
    if (fstat(fd,&st) < 0) {
	perror("stat");
	return 1;
    }
    for (i = 0; i < (st.st_size >> 10); i++) {
	block = i;
	if (ioctl(fd,FIBMAP,&block) < 0) {
	    perror("FIBMAP");
	    break;
	}
	printf("%d ",block);
    }
    putchar('\n');
lseek(fd,100,SEEK_SET);
    while (1) {
	if (ioctl(fd,FIPHYLOC,&phyloc) < 0) {
	    perror("FIPHYLOC");
	    return 1;
	}
	if (!phyloc.size) break;
	printf("0x%04x(%d,%d) ",phyloc.device,(int) phyloc.start,
	  (int) phyloc.size);
    }
    putchar('\n');
    return 0;
}
