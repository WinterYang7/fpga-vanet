obj-m := si4463_fpga.o
si4463_fpga-objs := main.o spimsg_ring.o 

KDIR :=/home/wu/Desktop/galileo/802.11p-linux

PWD := $(shell pwd)

EXTRA_CFLAGS += 


default:
	$(MAKE)	-C $(KDIR) SUBDIRS=$(PWD) modules 
clean:
	rm *.o *.ko
	rm *.mod.c