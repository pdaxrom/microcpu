#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <termios.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <stdlib.h>
#include <errno.h>

#define BAUDRATE B115200
#define MODEMDEVICE "/dev/ttyUSB0"
#define _POSIX_SOURCE 1 /* POSIX compliant source */
#define FALSE 0
#define TRUE 1

volatile int STOP=FALSE; 

int main(int argc, char *argv[])
{
    int fd, res;
    char buf[255];

    struct termios tty;
    struct termios tty_old;
    memset (&tty, 0, sizeof tty);


    fd = open(argv[1], O_RDWR | O_NOCTTY); 

    if (fd <0) {
	perror(MODEMDEVICE);
	exit(-1);
    }

    if ( tcgetattr(fd, &tty) != 0 ) {
	fprintf(stderr, "error %d from tcgetattr\n", errno);
    }

    /* Save old tty parameters */
    tty_old = tty;

    /* Set Baud Rate */
    cfsetospeed (&tty, (speed_t)BAUDRATE);
    cfsetispeed (&tty, (speed_t)BAUDRATE);

    /* Setting other Port Stuff */
    tty.c_cflag     &=  ~PARENB;            // Make 8n1
    tty.c_cflag     &=  ~CSTOPB;
    tty.c_cflag     &=  ~CSIZE;
    tty.c_cflag     |=  CS8;

    tty.c_cflag     &=  ~CRTSCTS;           // no flow control
    tty.c_cc[VMIN]   =  1;                  // read doesn't block
    tty.c_cc[VTIME]  =  5;                  // 0.5 seconds read timeout
    tty.c_cflag     |=  CREAD | CLOCAL;     // turn on READ & ignore ctrl lines

    /* Make raw */
    cfmakeraw(&tty);

    /* Flush Port, then applies attributes */
    tcflush(fd, TCIFLUSH);
    if ( tcsetattr(fd, TCSANOW, &tty ) != 0) {
	fprintf(stderr, "error %d from tcsetattr\n", errno);
    }

    if (!strcmp(argv[2], "save")) {
	unsigned int s;
	unsigned int e;
	sscanf(argv[4], "%x", &s);
	sscanf(argv[5], "%x", &e);

	fprintf(stderr, "> %x %x\n", s, e);

	FILE *outf = fopen(argv[3], "wb");
	if (outf) {
	    unsigned char tmp[5] = { 'S', (s >> 8) & 0xff, s & 0xff, (e >> 8) & 0xff, e & 0xff };
	    write(fd, tmp, 5);

	    for (; s < e; s++) {
		res = read(fd, buf, 1);   /* returns after 5 chars have been input */
		if (res < 0) {
		    fprintf(stderr, "error %d\n", errno);
		    break;
		}
		fwrite(buf, 1, 1, outf);
	    }
	    res = read(fd,buf,1);   /* returns after 5 chars have been input */
	    if (buf[0] == 'O') {
		fprintf(stderr, "OK\n");
	    }
	    fclose(outf);
	} else {
	    fprintf(stderr, "Can't open outfile\n");
	}
    }

    if (!strcmp(argv[2], "load")) {
	unsigned int s;
	unsigned int e;


	FILE *inf = fopen(argv[3], "rb");
	if (inf) {
	    if (argc < 5) {
		s = 0x100;
	    } else {
		sscanf(argv[4], "%x", &s);
	    }

	    if (argc < 6) {
		fseek(inf, 0, SEEK_END);
		e = s + ftell(inf);
		fseek(inf, 0, SEEK_SET);
	    } else {
		sscanf(argv[5], "%x", &e);
	    }

	    fprintf(stderr, "< %x %x\n", s, e);

	    unsigned char tmp[5] = { 'L', (s >> 8) & 0xff, s & 0xff, (e >> 8) & 0xff, e & 0xff };
	    write(fd, tmp, 5);

	    for (; s < e; s++) {
		fread(buf, 1, 1, inf);
		res = write(fd, buf, 1);   /* returns after 5 chars have been input */
		if (res < 1) {
		    fprintf(stderr, "error %d\n", errno);
		    break;
		}
	    }
	    res = read(fd,buf,1);   /* returns after 5 chars have been input */
	    if (buf[0] == 'O') {
		fprintf(stderr, "OK\n");
	    }
	    fclose(inf);
	} else {
	    fprintf(stderr, "Can't open infile\n");
	}
    }

    if (!strcmp(argv[2], "go")) {
	unsigned int s;
	unsigned int e;
	sscanf(argv[3], "%x", &s);

	fprintf(stderr, "go %x\n", s);

	unsigned char tmp[5] = { 'G', (s >> 8) & 0xff, s & 0xff };
	write(fd, tmp, 3);
    }

    tcsetattr(fd, TCSANOW, &tty_old);

    return 0;
}

