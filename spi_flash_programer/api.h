#define PROG_B 3 //low reset
#define MUX 2 //acive high
#define CS 10

/* write enable */
void enable_write(void);
void wait_for_write(void);
void readMD_ID(void);
/* Page program (02h) */
void pp(unsigned char addr[3], unsigned char* data, int size);
/* Read data (03h) */
void rd(unsigned char addr[3], unsigned char * buf, unsigned int size);
void rd2print(unsigned char addr[3], int size);
int rd4cmp(unsigned char addr[3], unsigned char * data, int size);
/* Chip Erase (CE) (C7h) */
void chip_erase(void);
