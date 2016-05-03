
#define MTU              192

#include <linux/netdevice.h>
#include <linux/spi/spi.h>

#define SPI_SPEED 7000000//
#define BITS_PER_WORD 8

#define PACKETLEN_BITS	1

//#define DEBUG
#define GALILEO

struct spidev_data {
	dev_t			devt;
	spinlock_t		spi_lock;
	struct spi_device	*spi;
	struct list_head	device_entry;

	/* buffer is NULL unless this device is open (users > 0) */
	struct mutex		buf_lock;
	unsigned		users;
	u8			*buffer;
};




/* this is the private data struct of ednet */
struct module_priv
{
    struct net_device_stats stats;
    struct sk_buff *skb;
	struct workqueue_struct	*dev_workqueue;
	struct si4463 * spi_priv;

	struct mutex pib_lock;
    spinlock_t lock;
};


// PIN Definitions:


#ifndef GALILEO
/* common */

/////////////////////////////////////////////////////////////
#else
/////////////////////////////////////////////////////////////
/* common */
#define IRQ_DATA 		6 //IO4  //interrpt
#define RAM_FULL_PIN	10
#define ISRAMFULL	(gpio_get_value(RAM_FULL_PIN)>0)
#define	WAITINGTIME	jiffies + HZ/100; //jiffies + HZ/2 are 0.5s
#endif//GALILEO

