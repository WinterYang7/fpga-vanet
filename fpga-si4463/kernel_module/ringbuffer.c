#include <linux/slab.h>
#include "ringbuffer.h"

DEFINE_MUTEX(mutex_rbuf);



/* 初始化环形缓冲区 */
int rbuf_init(rbuf_t *rb)
{
	int i;
	spin_lock_init(&rb->lock);
	init_waitqueue_head(&rb->wait_isempty);

	rb->size = RBUF_MAXSIZE;
	rb->next_in = 0;
	rb->next_out = 0;
	rb->capacity = RBUF_MAXSIZE;

	rb->msg_queue_ = kmalloc(RBUF_MAXSIZE*sizeof(struct bufunit), GFP_KERNEL);
	for (i = 0; i < RBUF_MAXSIZE; i++)
	{
		rb->msg_queue_[i].len_ = 0;
		rb->msg_queue_[i].buf_ = kmalloc(BUFSIZE, GFP_KERNEL);
	}

	return 0;
}

/* 销毁环形缓冲区 */
void rbuf_destroy(rbuf_t *c)
{
	int i;
	for(i=0; i<RBUF_MAXSIZE; i++){
		kfree(c->msg_queue_->buf_);
	}
	kfree(c->msg_queue_);
}


struct bufunit* rbuf_get_avail_msg(rbuf_t *rb)
{
//	printk(KERN_ALERT "rbuf_dequeue\n");
	struct bufunit *msg;
	if (rbuf_empty(rb))
	{
		printk(KERN_ALERT "ringbuffer is EMPTY!\n");
		wait_event_interruptible(rb->wait_isempty, !rbuf_empty(rb));
	}

//	printk(KERN_ALERT "next_in:%d, size: %d\n", rb->next_in, rb->size);
	spin_lock(&rb->lock);
//	mutex_lock(&mutex_rbuf);
	msg = &(rb->msg_queue_[rb->next_out++]);
	rb->size--;
	rb->next_out %= rb->capacity;

	spin_unlock(&rb->lock);
//	mutex_unlock(&mutex_rbuf);
	//return ret;
	return msg;
}

/*  */
int rbuf_enqueue(rbuf_t *rb)
{
//	printk(KERN_ALERT "rbuf_enqueue\n");
//	int ret;
	//ppp(cmd_->data, cmd_->len);

//	printk(KERN_ALERT "len: %d, datap: %x, next_in:%d, size: %d\n", cmd_->len, cmd_->data, rb->next_in, rb->size);
	spin_lock(&rb->lock);
//	mutex_lock(&mutex_rbuf);
	rb->next_in++;
	rb->size++;
	rb->next_in %= rb->capacity;

	//ppp(rb->data[rb->next_in-1].data, rb->data[rb->next_in-1].data)

	spin_unlock(&rb->lock);
//	mutex_unlock(&mutex_rbuf);
	wake_up_interruptible(&rb->wait_isempty);
	return 0;
}


/* 判断缓冲区是否为满 */
bool rbuf_full(rbuf_t *c)
{
	return (c->size == c->capacity);
}

bool rbuf_almost_full(rbuf_t *c)
{
	return (c->size >= (c->capacity - 5));
}

/*  */
bool rbuf_almost_empty(rbuf_t *c){
	return (c->size < 10);
}

/* 判断缓冲区是否为空 */
bool rbuf_empty(rbuf_t *c)
{
	return (c->size == 0);
}

/* 获取缓冲区可存放的元素的总个数 */
int rbuf_capacity(rbuf_t *c)
{
	return c->capacity;
}

int rbuf_len(rbuf_t *c)
{
	return c->size;
}



void rbuf_print_status(rbuf_t *rb) {
//	spin_lock(&rb->lock);
	printk(KERN_ALERT "size: %d\n", rb->size);
	printk(KERN_ALERT "next_in: %d\n", rb->next_in);
	printk(KERN_ALERT "next_out %d\n", rb->next_out);
//	spin_unlock(&rb->lock);
//	printk(KERN_ALERT "", );
}

