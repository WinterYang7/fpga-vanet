#include <linux/device.h>
#include <linux/spi/spi.h>
#include <linux/interrupt.h>
#include <linux/module.h>
#include <linux/pinctrl/consumer.h>

#include <linux/gpio.h>
#include <linux/irq.h>

#include <linux/delay.h>
#include <linux/kernel.h> /* printk() */
#include <linux/types.h>  /* size_t */
#include <linux/interrupt.h> /* mark_bh */

#include <linux/in.h>
#include <linux/netdevice.h>   /* struct device, and other headers */
#include <linux/etherdevice.h> /* eth_type_trans */
#include <linux/ip.h>          /* struct iphdr */
#include <linux/tcp.h>         /* struct tcphdr */
#include <linux/skbuff.h>

#include <linux/in6.h>
#include <asm/checksum.h>

//#include <linux/wait.h>
#include <linux/kthread.h>

#include <linux/fs.h>

#include <linux/semaphore.h> /* semphone for the TX */
#include <linux/mutex.h>
#include <linux/timer.h>

#include "main.h"
#include "ringbuffer.h"
/* Bit masks for spi_device.mode management.  Note that incorrect
 * settings for some settings can cause *lots* of trouble for other
 * devices on a shared bus:
 *
 *  - CS_HIGH ... this device will be active when it shouldn't be
 *  - 3WIRE ... when active, it won't behave as it should
 *  - NO_CS ... there will be no explicit message boundaries; this
 *	is completely incompatible with the shared bus model
 *  - READY ... transfers may proceed when they shouldn't.
 *
 * REVISIT should changing those flags be privileged?
 */
#define SPI_MODE_MASK		(SPI_CPHA | SPI_CPOL | SPI_CS_HIGH \
				| SPI_LSB_FIRST | SPI_3WIRE | SPI_LOOP \
				| SPI_NO_CS | SPI_READY)


/* GLOBAL */
struct {
	u8* data;
	u8 len;
	int position;
} data_sending;

rbuf_t global_buf_queue;
u8 global_reader[MAXPACKETLEN];
/**
 * CONST Commands
 */
const u8 sendcmd[5] = {0x66, 0,0,0,0};
const u8 recvcmd[5] = {0x77, 0,0,0,0};


struct net_device *global_net_devs;
struct spi_device *spi_save;
struct spidev_data spidev_global;
struct si4463 * global_devrec;

DEFINE_MUTEX(mutex_txrx);
/* TX withdraw timer */
struct timer_list tx_withdraw_timer;

static void withdraw(unsigned long data)
{
//    printk(KERN_ALERT "tx is now approved\n");
	netif_wake_queue(global_net_devs);
}

/* PIN MUX */
#ifndef GALILEO

#else
#define pin_mux_num  9
//https://github.com/intel-iot-devkit/mraa/blob/master/src/x86/intel_galileo_rev_g.c
const struct gpio pin_mux[pin_mux_num] = {
		/*SPI IO11,IO12,IO13*/
		{72, GPIOF_INIT_LOW, NULL},
		{44, GPIOF_INIT_HIGH, NULL},
		{24, GPIOF_INIT_LOW, NULL},

		{42, GPIOF_INIT_HIGH, NULL},

		{46, GPIOF_INIT_HIGH, NULL},
		{30, GPIOF_INIT_LOW, NULL},

		/* IO10 for SRAM indicator */
		{10, GPIOF_IN, NULL},
		{74, GPIOF_INIT_LOW, NULL},
		/*IO9*/


		/*IO7 and IO8*/


		/*IO6*/

		/*IO5*/

		/* IO4 for FPGA irq data */
		{6, GPIOF_IN, NULL}
};
#endif

/*-------------------------------------------------------------------------*/
static void ppp(u8 * arr, int len){
	int i = 0;
	printk(KERN_ALERT "ppp: len=[%d]\n", len);
	for(i = 0;i<len;i++)
		printk(KERN_ALERT "%x ", arr[i]);
	printk(KERN_ALERT "\n");
}

static void write2file(struct file *fp, const char *write_str, int len) {
//    static char buf1[10];
    mm_segment_t fs;
    loff_t pos;

    if( IS_ERR(fp)) {
    	printk(KERN_ALERT "fp is NULL!!\n");
    	return;
    }
    if(write_str == NULL) {
    	printk(KERN_ALERT "write_str is NULL!!\n");
    	return;
    }
//    printk(KERN_ALERT "Len: %d, write_str is %s\n", len, write_str);
	fs =get_fs();
    set_fs(KERNEL_DS);
    pos = 0;
    vfs_write(fp, write_str, len, &pos);
//    pos = 0;
//    vfs_read(fp, buf1, sizeof(buf1), &pos);
//    printk(KERN_ALERT "%s\n",buf1);

    set_fs(fs);
}

#ifndef GALILEO
int set_pinmux(void){

	return 0;

}
#else
int set_pinmux(void){
    int ret;
    struct file *fp;
//    struct file *fp_214;

//    const char s_mode0[] = "mode0";
//    const char s_mode1[] = "mode1";
    const char s_low[] = "low";
    const char s_high[] = "high";
    const char s_in[] = "in";
//    const char s_on[] = "on";

    printk(KERN_ALERT "GALILEO SET PINMUX\n");
//    ret = gpio_request_array(pin_mux, pin_mux_num);
//    printk(KERN_ALERT "gpio_request_array return %d\n", ret);
//

        fp = filp_open("/sys/class/gpio/export", O_WRONLY|O_APPEND, 0);
        write2file(fp, "72", 2);
	filp_close(fp,NULL);
	fp = filp_open("/sys/class/gpio/export", O_WRONLY|O_APPEND, 0);
	write2file(fp, "44", 2);
	filp_close(fp,NULL);
	fp = filp_open("/sys/class/gpio/export", O_WRONLY|O_APPEND, 0);
	write2file(fp, "24", 2);
	filp_close(fp,NULL);
	fp = filp_open("/sys/class/gpio/export", O_WRONLY|O_APPEND, 0);
	write2file(fp, "42", 2);
	filp_close(fp,NULL);
	fp = filp_open("/sys/class/gpio/export", O_WRONLY|O_APPEND, 0);
	write2file(fp, "46", 2);
	filp_close(fp,NULL);
	fp = filp_open("/sys/class/gpio/export", O_WRONLY|O_APPEND, 0);
	write2file(fp, "30", 2);
	filp_close(fp,NULL);

	fp = filp_open("/sys/class/gpio/export", O_WRONLY|O_APPEND, 0);
	write2file(fp, "10", 2);
	filp_close(fp,NULL);
	fp = filp_open("/sys/class/gpio/export", O_WRONLY|O_APPEND, 0);
	write2file(fp, "74", 2);
	filp_close(fp,NULL);
	fp = filp_open("/sys/class/gpio/export", O_WRONLY|O_APPEND, 0);
	write2file(fp, "6", 1);
	filp_close(fp,NULL);

	printk(KERN_ALERT "GALILEO EXPORT GPIO\n");

	ret = gpio_export(72, 1);
	ret = gpio_export(44, 1);
	ret = gpio_export(24, 1);

	ret = gpio_export(42, 1);

	ret = gpio_export(46, 1);
	ret = gpio_export(30, 1);

	// IO10 //
	ret = gpio_export(10, 1);
	ret = gpio_export(74, 1);

	// IO7,8 //

	// IO6 //

	// IO4 //
	ret = gpio_export(6, 1);

    /* SPI */
	//gpio72 have no direction file ..
    fp = filp_open("/sys/class/gpio/gpio44/direction", O_RDWR, 0);
    write2file(fp, s_high, 4);
    fp = filp_open("/sys/class/gpio/gpio24/direction", O_RDWR, 0);
    write2file(fp, s_low, 3);
    fp = filp_open("/sys/class/gpio/gpio42/direction", O_RDWR, 0);
    write2file(fp, s_high, 4);
    fp = filp_open("/sys/class/gpio/gpio46/direction", O_RDWR, 0);
    write2file(fp, s_high, 4);
    fp = filp_open("/sys/class/gpio/gpio30/direction", O_RDWR, 0);
    write2file(fp, s_low, 3);

    /* IO10 */
    fp = filp_open("/sys/class/gpio/gpio10/direction", O_RDWR, 0);
    write2file(fp, s_in, 2);
    fp = filp_open("/sys/class/gpio/gpio74/direction", O_RDWR, 0);
    write2file(fp, s_low, 3);
    /* IO7,8 */

    /* IO6 */

    /* IO4 */
    fp = filp_open("/sys/class/gpio/gpio6/direction", O_RDWR, 0);
    write2file(fp, s_in, 2);
    return 0;
}
#endif
/*-------------------------------------------------------------------------*/


void spidev_complete(void *arg)
{
	complete(arg);
}

inline int
spidev_sync(struct spidev_data *spidev, struct spi_message *message)
{
	DECLARE_COMPLETION_ONSTACK(done);
	int status;

	message->complete = spidev_complete;
	message->context = &done;
	spin_lock_irq(&spidev->spi_lock);
	if (spidev->spi == NULL)
		status = -ESHUTDOWN;
	else
		status = spi_async(spidev->spi, message);
	spin_unlock_irq(&spidev->spi_lock);

	if (status == 0) {
		wait_for_completion(&done);
		status = message->status;
		if (status == 0)
			status = message->actual_length;
	} else {

	}
	return status;
}

inline int spi_write_data(struct spidev_data *spidev, u8* tx_data, int len)
{
	struct spi_transfer	t = {
			.tx_buf		= tx_data,
			.len		= len,
			.cs_change	= 0
		};
	struct spi_message m;
	spi_message_init(&m);
	spi_message_add_tail(&t, &m);
	return spidev_sync(spidev, &m);
}

inline int spi_write_packet(struct spidev_data *spidev, struct sk_buff *skb)
{
	struct spi_transfer	tcmd = {
				.tx_buf		= sendcmd,
				.len		= 1,
				.cs_change	= 0
			};
	struct spi_transfer	tlen = {
				.tx_buf		= &(skb->len),
				.len		= PACKETLEN_BITS,
				.cs_change	= 0
			};
	struct spi_transfer	t = {
			.tx_buf		= skb->data,
			.len		= skb->len,
			.cs_change	= 0
		};
	struct spi_message m;
	spi_message_init(&m);


//	printk(KERN_ALERT "spi_write_packet: len:%d\n",skb->len);
//	ppp(skb->data, skb->len);

	spi_message_add_tail(&tcmd, &m);
	spi_message_add_tail(&tlen, &m);
	spi_message_add_tail(&t, &m);
	spidev_sync(spidev, &m);
//	printk(KERN_ALERT "==========================\n");
//	spi_complete_send(msg);
//	printk(KERN_ALERT "spi_complete_send, status:%d, sendlen:%d\n",
//			 m.status, m.actual_length);
	netif_wake_queue(global_net_devs);
	dev_kfree_skb(skb);
	return 0;
}

inline u16 spi_recv_packetlen(struct spidev_data *spidev)
{
	u32 len;
//	int status;
	struct spi_transfer	t = {
				.tx_buf		= recvcmd,
				.rx_buf		= &len,
				.len		= PACKETLEN_BITS + 2,
				.cs_change	= 0
			};
//	memcpy(len, (blen+1), PACKETLEN_BITS);
	struct spi_message	m;
	spi_message_init(&m);
	spi_message_add_tail(&t, &m);
	spidev_sync(spidev, &m);
//	printk(KERN_ALERT "len1: 0x%x\n", len);
	len = (len >> 16) & 0xff;
//	printk(KERN_ALERT "len2: 0x%x\n", len);
	return len;
}

struct rx_work {
	u8* data;
	u32 len;
	struct work_struct work;
	struct net_device *dev;
};

static void si4463_handle_rx(struct work_struct *work)
{
	struct sk_buff *skb;
	u32 len;
	u8* data;
	struct rx_work *rw = container_of(work, struct rx_work, work);


	len = rw->len;
	data = rw->data;

	skb = alloc_skb(len+2, GFP_KERNEL);
	skb_reserve(skb, 2);
	memcpy(skb_put(skb, len), data, len);

//	printk(KERN_ALERT "spi_complete_recv\n");
//int j;
//for(j=0;j<20;j++)
//	printk(KERN_ALERT "%d ",skb->data[j]);
//printk(KERN_ALERT "\n");
//return 1;
	/* Handover recieved data */



	skb->dev = global_net_devs;
	skb->protocol = eth_type_trans(skb, global_net_devs);
	/* We need not check the checksum */
	skb->ip_summed = CHECKSUM_UNNECESSARY;
	netif_rx(skb);

//	printk(KERN_ALERT "si4463_handle_rx out 2 \n");
	kfree(rw);
	rbuf_enqueue(&global_buf_queue);
}

inline int spi_recv_packet(struct spidev_data *spidev, u32 len)
{
	struct spi_transfer	t;
	int status;
	struct bufunit* ubuf;
	struct spi_message m;
	struct rx_work *work;
	struct module_priv *priv;
	struct sk_buff *skb;
	priv = netdev_priv(global_net_devs);

	u8 * tmp_reciever=kmalloc(MAXPACKETLEN, GFP_KERNEL);
	u8 * tmp_tx=kmalloc(MAXPACKETLEN, GFP_KERNEL);
	memset(tmp_tx, 0, MAXPACKETLEN);

//	ubuf = rbuf_get_avail_msg(&global_buf_queue);
//	ubuf->len_ = len;
	spi_message_init(&m);

	if(len > MAXPACKETLEN){
		printk(KERN_ALERT "spi_recv_packet ERROR!: len: %d\n", len);
		return -1;
	}

//	printk(KERN_ALERT "spi_recv_packet: len: %d\n", len);

	t.tx_buf = tmp_tx;
	t.rx_buf = tmp_reciever;//global_reader;//skb_put(skb, len);//ubuf->buf_;//
	t.cs_change = 0;
	t.len = len;//ubuf->len_;
	t.bits_per_word=BITS_PER_WORD;
	t.speed_hz=SPI_SPEED;
	t.rx_nbits=0;
	spi_message_add_tail(&t, &m);
	status = spidev_sync(spidev, &m);
	if(status<=0){
		kfree(tmp_reciever);
		return status;
	}
//	status = m.status;
//	if (status == 0){
////		printk(KERN_ALERT "spi_actual_length %d\n",m.actual_length);
//	}
//	else {
//		printk(KERN_ALERT "spi_complete_recv: STATUS=%d\n", status);
//		return -1;
//	}

	skb = alloc_skb(len+2, GFP_KERNEL);
	skb_reserve(skb, 2);

	memcpy(skb_put(skb, (len-1)), (tmp_reciever+1), (len-1));
	kfree(tmp_reciever);
	kfree(tmp_tx);
//	work = kzalloc(sizeof(struct rx_work), GFP_KERNEL);
//	if (!work)
//		return -1;
//	INIT_WORK(&work->work, si4463_handle_rx);
//	work->data = ubuf->buf_;
//	work->dev = global_net_devs;
//	work->len = ubuf->len_;
//	queue_work(priv->dev_workqueue, &work->work);

//	printk(KERN_ALERT "spi_complete_recv\n");

//	ppp(skb->data, len);
	/* Handover recieved data */



	skb->dev = global_net_devs;
	skb->protocol = eth_type_trans(skb, global_net_devs);
	/* We need not check the checksum */
	skb->ip_summed = CHECKSUM_UNNECESSARY;
	netif_rx(skb);

	return status;
}



/* Device Private Data */
struct si4463 {
	struct spi_device *spi;
//	struct ieee802154_dev *dev;
	struct net_device *dev;
	struct mutex buffer_mutex; /* only used to protect buf */
	struct completion tx_complete;
	struct work_struct irqwork;

	u8 *buf; /* 3 bytes. Used for SPI single-register transfers. */

	struct mutex mutex_spi;


	bool irq_busy;
	spinlock_t lock;
};

#define printdev(X) (&X->spi->dev)

struct xmit_work {
	struct sk_buff *skb;
	struct work_struct work;
	struct module_priv *priv;
//	u8 chan;
//	u8 page;
};


static void si4463_tx_worker(struct work_struct *work)
{

	struct sk_buff *skb;
	struct xmit_work *xw = container_of(work, struct xmit_work, work);
	struct si4463 *devrec;
	devrec = xw->priv->spi_priv;
	skb = xw->skb;
	mutex_lock(&mutex_txrx);
	spi_write_packet(&spidev_global, skb);
	mutex_unlock(&mutex_txrx);
}

static int si4463_tx(struct sk_buff *skb, struct net_device *dev)
{
	struct xmit_work *work;
	struct module_priv *priv;
	priv = netdev_priv(dev);

//	printk(KERN_ALERT "si4463_tx! dev:%x glo:%x\n", dev, global_net_devs);
	if(ISRAMFULL){
		printk(KERN_ALERT "si4463_tx! RAM is full!!\n");
		add_timer(&tx_withdraw_timer);
		netif_stop_queue(dev);
		return NETDEV_TX_BUSY;
	}

	work = kzalloc(sizeof(struct xmit_work), GFP_ATOMIC);
	if (!work) {
		kfree_skb(skb);
		return NETDEV_TX_BUSY;
	}

	netif_stop_queue(dev);
//
//
	INIT_WORK(&work->work, si4463_tx_worker);
	work->skb = skb;
	work->priv = priv;
	queue_work(priv->dev_workqueue, &work->work);

//	spi_write_packet(&spidev_global, skb);

	return NETDEV_TX_OK;
}


int si4463_release(struct net_device *dev)
{
	printk("si4463_release\n");
    netif_stop_queue(dev);
    free_irq(gpio_to_irq(IRQ_DATA),global_net_devs);
    gpio_free_array(pin_mux, pin_mux_num);

//	kthread_stop(cmd_handler_tsk);
//	kthread_stop(irq_handler_tsk);
    return 0;
}

/*
 * Deal with a transmit timeout.
 */
void si4463_tx_timeout (struct net_device *dev)
{
    struct module_priv *priv = (struct module_priv *) netdev_priv(dev);//dev->priv;
    priv->stats.tx_errors++;

    printk(KERN_ALERT "si4463_tx_timeout\n");
//    netif_wake_queue(dev);

    return;
}



/*
 * When we need some ioctls.
 */
int si4463_ioctl(struct net_device *dev, struct ifreq *rq, int cmd)
{
	printk("si4463_ioctl\n");
    return 0;
}

/*
 * ifconfig to get the packet transmitting status.
 */

struct net_device_stats *si4463_stats(struct net_device *dev)
{
    struct module_priv *priv = (struct module_priv *) netdev_priv(dev);//dev->priv;
    return &priv->stats;
}

/*
 * TCP/IP handshake will call this function, if it need.
 */
int si4463_change_mtu(struct net_device *dev, int new_mtu)
{
    unsigned long flags;
    spinlock_t *lock = &((struct module_priv *) netdev_priv(dev)/*dev->priv*/)->lock;

    /* en, the mtu CANNOT LESS THEN 68 OR MORE THEN 1500. */
    if (new_mtu < 68)
        return -EINVAL;

    spin_lock_irqsave(lock, flags);
    dev->mtu = new_mtu;
    spin_unlock_irqrestore(lock, flags);

    return 0;
}


static irqreturn_t si4463_isr_data(int irq, void *data)
{
//	printk(KERN_ALERT "=====IRQ=====\n");
	struct si4463 *devrec = data;

//	disable_irq_nosync(irq);
	schedule_work(&devrec->irqwork);

	return IRQ_HANDLED;
}

static void si4463_isrwork(struct work_struct *work)
{
	u16 len;
	int status;
	u8* tmp_data;
	struct si4463 *devrec = container_of(work, struct si4463, irqwork);

	mutex_lock(&mutex_txrx);
	len = spi_recv_packetlen(&spidev_global);
	if(len<=0)
		printk(KERN_ALERT "si4463_isrwork: len is 0!!");
	status = spi_recv_packet(&spidev_global, len);
	if(status<=0){
		printk(KERN_ALERT "si4463_isrwork: status %d, len %d\n", status, len);
		tmp_data=kmalloc(len, GFP_KERNEL);
		memset(tmp_data, 0, len);
		spi_write_data(&spidev_global, tmp_data, len);
		kfree(tmp_data);
	}
	mutex_unlock(&mutex_txrx);

//	spi_recv_packet(&spidev_global, 20);
//	enable_irq(devrec->spi->irq);
}

static int si4463_start(struct net_device *dev)
{
//	u8 val;
	int ret, irq;
//	int saved_muxing = 0;
//	int err,tmp;
	/* IRQ */
	irq = gpio_to_irq(IRQ_DATA);
	irq_set_irq_type(irq, IRQ_TYPE_EDGE_FALLING);
    ret = request_irq(irq, si4463_isr_data, IRQ_TYPE_EDGE_FALLING,
//    		dev->name, dev);
    		dev->name, global_devrec);
	if (ret) {
//		dev_err(printdev(global_devrec), "Unable to get IRQ");
		printk("IRQ REQUEST ERROR!\n");
	}
	global_devrec->spi->irq = irq;

	printk(KERN_ALERT "rx_start\n");
	netif_start_queue(dev);
	printk(KERN_ALERT "si4463_start\n");

	return 0;
}

static const struct net_device_ops si4463_netdev_ops = {

	.ndo_open            = si4463_start,
	.ndo_stop            = si4463_release,
	.ndo_start_xmit		 = si4463_tx,
	.ndo_do_ioctl        = si4463_ioctl,
	.ndo_get_stats       = si4463_stats,
	.ndo_change_mtu      = si4463_change_mtu,
	.ndo_tx_timeout      = si4463_tx_timeout,
};

static int si4463_probe(struct spi_device *spi)
{
	int tmp;
	int ret = -ENOMEM;

	struct si4463 *devrec;

//	struct pinctrl *pinctrl;
	printk(KERN_ALERT "si4463: probe(). VERSION:%s, IRQ: %d\n", "20160708,11:31", spi->irq);

	devrec = kzalloc(sizeof(struct si4463), GFP_KERNEL);
	if (!devrec)
		goto err_devrec;

	global_devrec = devrec;

	devrec->buf = kzalloc(3, GFP_KERNEL);
	if (!devrec->buf)
		goto err_buf;

	spi_save = spi;
	spidev_global.spi = spi;
	spin_lock_init(&spidev_global.spi_lock);
//	spin_lock_init(&isHandlingIrq.lock);
//	isHandlingIrq.data = 0;
	mutex_init(&spidev_global.buf_lock);

	/* PIN MUX */
	set_pinmux();

	/* spi setup :
	 * 		SPI_MODE_0
	 * 		MSBFIRST
	 * 		CS active low
	 * 		IRQ??????
	 */
	if (spi == NULL)
		return -ESHUTDOWN;

	tmp = ~SPI_MODE_MASK;

	printk(KERN_ALERT "init: tmp= %x\n", tmp);
	tmp |= SPI_MODE_0;
	tmp |= SPI_NO_CS;

	//tmp |= SPI_CS_HIGH;
	//tmp |= SPI_READY;
	printk(KERN_ALERT "midd: tmp= %x\n", tmp);
	tmp |= spi->mode & ~SPI_MODE_MASK;

	printk(KERN_ALERT "after: tmp= %x\n", tmp);
//	spi->mode = (u16)tmp;
	spi->mode = SPI_MODE_0;
	spi->bits_per_word = BITS_PER_WORD;
	spi->max_speed_hz = SPI_SPEED;
	spi->mode &= ~SPI_LSB_FIRST;

	ret = spi_setup(spi);
	if (ret < 0)
		printk(KERN_ALERT "ERROR! spi_setup return: %d\n", ret);
//	else
//		printk(KERN_ALERT "spi_setup succeed, spi:%x, spidev_global.spi:%x\n", spi, spidev_global.spi);


	mutex_init(&devrec->buffer_mutex);
	mutex_init(&devrec->mutex_spi);
	spin_lock_init(&devrec->lock);

	devrec->spi = spi;
	spi_set_drvdata(spi, devrec);

	/* setup timer */
	setup_timer(&tx_withdraw_timer, withdraw, 0);
	tx_withdraw_timer.expires = WAITINGTIME;
	tx_withdraw_timer.function = withdraw;
	tx_withdraw_timer.data = 0;

	INIT_WORK(&devrec->irqwork, si4463_isrwork);

	rbuf_init(&global_buf_queue);

	return 0;

//err_irq:
//err_read_reg:
//	ieee802154_unregister_device(devrec->dev);
//err_register_device:
//	ieee802154_free_device(devrec->dev);
//err_alloc_dev:
	kfree(devrec->buf);
err_buf:
	kfree(devrec);
err_devrec:
	return ret;
}

//static int si4463_remove(struct spi_device *spi)
//{
//	struct si4463 *devrec = spi_get_drvdata(spi);
//
//	dev_dbg(printdev(devrec), "remove\n");
//
//	free_irq(spi->irq, devrec);
//	flush_work(&devrec->irqwork); /* TODO: Is this the right call? */
//	ieee802154_unregister_device(devrec->dev);
//	ieee802154_free_device(devrec->dev);
//	/* TODO: Will ieee802154_free_device() wait until ->xmit() is
//	 * complete? */
//
//	/* Clean up the SPI stuff. */
//	spi_set_drvdata(spi, NULL);
//	kfree(devrec->buf);
//	kfree(devrec);
//	return 0;
//}


static int spi_remove(struct spi_device *spi)
{
	struct spidev_data	*spidev = spi_get_drvdata(spi);

	/* make sure ops on existing fds can abort cleanly */
	spin_lock_irq(&spidev->spi_lock);
	spidev->spi = NULL;
	spi_set_drvdata(spi, NULL);
	spin_unlock_irq(&spidev->spi_lock);

	/* prevent new opens */
//	mutex_lock(&device_list_lock);
//	list_del(&spidev->device_entry);
//	device_destroy(spidev_class, spidev->devt);
//	clear_bit(MINOR(spidev->devt), minors);
//	if (spidev->users == 0)
//		kfree(spidev);
//	mutex_unlock(&device_list_lock);

	return 0;
}

static const struct of_device_id spidev_dt_ids[] = {
	{ .compatible = "rohm,dh2228fv" },
	{},
};

MODULE_DEVICE_TABLE(of, spidev_dt_ids);

static struct spi_driver spidev_spi_driver = {
	.driver = {
		.name =		"spidev",
		.owner =	THIS_MODULE,
		.of_match_table = of_match_ptr(spidev_dt_ids),
	},
	.probe =	si4463_probe,
	.remove =	spi_remove,

	/* NOTE:  suspend/resume methods are not necessary here.
	 * We don't do anything except pass the requests to/from
	 * the underlying controller.  The refrigerator handles
	 * most issues; the controller driver handles the rest.
	 */
};

void module_net_init(struct net_device *dev)
{
//	printk(KERN_ALERT "module_net_init!\n");
	struct module_priv *priv;
	ether_setup(dev); /* assign some of the fields */
//	si4463_net_dev_setup(dev);

	dev->netdev_ops = &si4463_netdev_ops;

	//MTU
	dev->mtu		= 230;

	dev->dev_addr[0] = 0x18;//(0x01 & addr[0])为multicast
	dev->dev_addr[1] = 0x02;
	dev->dev_addr[2] = 0x03;
	dev->dev_addr[3] = 0x04;
	dev->dev_addr[4] = 0x05;
	dev->dev_addr[5] = 0x06;

	/* keep the default flags, just add NOARP */
	dev->flags           |= IFF_NOARP;
	dev->features        |= NETIF_F_HW_CSUM;
//	dev->features		 |= NETIF_F_LLTX;

	dev->tx_queue_len = 5;
	/*
	 * Then, initialize the priv field. This encloses the statistics
	 * and a few private fields.
	 */
	priv = netdev_priv(dev);
	memset(priv, 0, sizeof(struct module_priv));
	priv->spi_priv = global_devrec;
	global_devrec->dev = global_net_devs;
	priv->dev_workqueue = create_singlethread_workqueue("tx_queue");
	mutex_init(&priv->pib_lock);
//	printk(KERN_ALERT "module_net_init! dev:%x glo:%x\n", dev, global_net_devs);

	spin_lock_init(&priv->lock);
}

static int __init si4463_init(void)
{
	int status, ret, result;

	status = spi_register_driver(&spidev_spi_driver);
	if (status < 0) {
		goto out;
	}

	/* Allocate the NET devices */
	global_net_devs = alloc_netdev(sizeof(struct module_priv), "sif%d", NET_NAME_UNKNOWN, module_net_init);
	if (global_net_devs == NULL)
		goto out;


	ret = -ENODEV;
	if ((result = register_netdev(global_net_devs)))
		printk(KERN_ALERT "demo: error %i registering device \"%s\"\n",result, global_net_devs->name);
	else
		ret = 0;
out:
	return status;
}





//module_spi_driver(spidev_spi_driver);

module_init(si4463_init);

static void __exit si4463_exit(void)
{
	spi_unregister_driver(&spidev_spi_driver);

	if (global_net_devs)
	{
		unregister_netdev(global_net_devs);
		free_netdev(global_net_devs);
	}
	del_timer(&tx_withdraw_timer);

	return;
}
module_exit(si4463_exit);


MODULE_AUTHOR("wu");
MODULE_DESCRIPTION("SI4463 SPI 802.15.4 Controller Driver");
MODULE_LICENSE("GPL");
MODULE_ALIAS("spi:spidev");
