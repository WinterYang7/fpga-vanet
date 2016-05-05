#ifndef __rbuf_H__
#define __rbuf_H__

/* Define to prevent recursive inclusion
 -------------------------------------*/
#include <linux/types.h>
#include <linux/spinlock.h>
#include <linux/wait.h>
#include <linux/sched.h>
#include <linux/spi/spi.h>

#define RBUF_MAXSIZE 	10
#define BUFSIZE			200



typedef struct _rbuf
{
	int size;
	int next_in; /* 缓冲区中下一个保存数据的位置 */
	int next_out; /* 从缓冲区中取出下一个数据的位置 */
	int capacity; /* 这个缓冲区的可保存的数据的总个数 */
//	mutex_t        mutex;            /* Lock the structure */
	spinlock_t lock;
//    cond_t        	not_full;        /* Full -> not full condition */
//   cond_t        	not_empty;        /* Empty -> not empty condition */
	wait_queue_head_t wait_isempty;
//	struct cmd *data;/* 缓冲区中保存的数据指针 */
	struct spimsg *msg_queue_;
} rbuf_t;

struct spimsg{
	struct spi_message message;
	struct completion done;
	rbuf_t * rbuf_;
	unsigned char *buf_;
	int	len_;
};

/* 初始化环形缓冲区 */
int rbuf_init(rbuf_t *rb);

/* 销毁环形缓冲区 */
void rbuf_destroy(rbuf_t *rb);

/*  */
struct spimsg*  rbuf_get_avail_msg(rbuf_t *rb);

/* 判断缓冲区是否为满 */
bool rbuf_full(rbuf_t *rb);

bool rbuf_almost_full(rbuf_t *c);

bool rbuf_almost_empty(rbuf_t *c);

/* 判断缓冲区是否为空 */
bool rbuf_empty(rbuf_t *rb);

/* 获取缓冲区可存放的元素的总个数 */
int rbuf_capacity(rbuf_t *rb);

int rbuf_len(rbuf_t *rb);

void rbuf_print_status(rbuf_t *rb);

#endif
