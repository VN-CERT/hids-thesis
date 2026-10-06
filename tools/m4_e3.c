/* m4_e3.c — E3: getppid, ngu 300s, connect localhost. */
#define _GNU_SOURCE
#include <arpa/inet.h>
#include <netinet/in.h>
#include <stdlib.h>
#include <sys/socket.h>
#include <unistd.h>
#include <sys/syscall.h>

int main(int argc, char **argv)
{
	int port, s;
	struct sockaddr_in a;

	if (argc != 2) {
		write(2, "usage: m4_e3 <port>\n", 20);
		return 1;
	}
	port = atoi(argv[1]);
	if (port <= 0 || port > 65535)
		return 1;
	{
		unsigned char b;

		if (read(STDIN_FILENO, &b, 1) != 1)
			return 1;
	}
	syscall(SYS_getppid);
	sleep(300);
	s = socket(AF_INET, SOCK_STREAM, 0);
	if (s < 0)
		return 1;
	a.sin_family = AF_INET;
	a.sin_port = htons((uint16_t)port);
	a.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
	if (connect(s, (struct sockaddr *)&a, sizeof(a)) != 0)
		return 1;
	close(s);
	return 0;
}
