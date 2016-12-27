##ENVIRONMENT
 * Tested in 64bit UBUNTU 12.04
 * The following steps assume the environment is 64bit UBUNTU 12.04.

`sudo apt-get install build-essential git diffstat gawk chrpath texinfo libtool gcc-multilib libncurses5-dev
`
##CROSS-COMPILE TOOLCHAIN
1. If 64bit system:
	1. Download [clanton-full-eglibc-x86_64-i586-toolchain-1.4.2.sh](http://storage.tokor.org/pub/galileo_bsp1.0.0/tools/clanton-full-eglibc-x86_64-i586-toolchain-1.4.2.sh) 
	2. Extract: 
``
	./clanton-full-eglibc-x86_64-i586-toolchain-1.4.2.sh
``
2. If 32bit system:
	1. Download [clanton-full-eglibc-i686-i586-toolchain-1.4.2.sh](http://storage.tokor.org/pub/galileo/tools/clanton-full-eglibc-i686-i586-toolchain-1.4.2.sh)
	2. Extract: 
``
	./clanton-full-eglibc-i686-i586-toolchain-1.4.2.sh
``
3. Remember the path to the toolchain for later usage.

##CROSS-COMPILE KERNEL
1. Download kernel:

	```
	git clone https://github.com/CTU-IIG/802.11p-linux.git  
	cd 802.11p-linux  
	git checkout its-g5_v3
	git checkout bf45e0160af428dac8893e48d506ac428fed16b2
	```
1. Patch the kernel:

	```
	git am ../patchset/*.patch

	```
1. Configure the kernel

	```
	mv ../configfile .config
	make menuconfig
	```

	You can manually configure the kernel in the menuconfig, or do noting. Remember to exist menuconfig with saving the config file.

1. Include the toolchain in your PATH:

	```
	export PATH=<path_to_toolchain>/sysroots/x86_64-pokysdk-linux/usr/bin/i586-poky-linux:$PATH
	source <path_to_toolchain>/environment-setup-i586-poky-linux
	```
1. Cross-compile the kernel
	
	``
	make -j4 ARCH=i386 LOCALVERSION= CROSS_COMPILE=i586-poky-linux- 
	``
1. Extract the kernel modules from the build to a target directory (e.g ../galileo-modules)
	
	``
	make modules_install ARCH=i386 LOCALVERSION= INSTALL_MOD_PATH=../galileo-modules CROSS_COMPILE=i586-poky-linux- 
	``
1. Two stuff for later usage:
	* kernel image: arch/x86/boot/bzImage
	* kernel modules: ../galileo-modules/*


##PREPARE THE FILESYSTEM AND SDCARD
1. Download the prebuild [image](https://relvarsoft.com/galileo/galileo_xbolshe_iot_1.2.0_kernel_v3.19.8_featured_201601091.zip).
2. After downloading:
	```
	unzip galileo_xbolshe_iot_1.2.0_kernel_v3.19.8_featured_201601091.zip
	cd galileo_xbolshe_iot_1.2.0_kernel_v3.19.8_featured_201601091
	mkdir tmp
	sudo mount image-full-quark.ext3 tmp
	```
3. Put the kernel modules we have built into image-full-quark.ext3.
	```
	sudo cp -rf <path_to_galileo-modules>/galileo-modules/* tmp/
	sudo umount tmp
	```
4. Put the kernel modules into the initrd.
	```
	gunzip core-image-minimal-initramfs-quark.cpio.gz	
	cd tmp
	cpio -i -F ../core-image-minimal-initramfs-quark.cpio
	sudo cp -rf <path_to_galileo-modules>/galileo-modules/* .
	find . | cpio -o -H newc | gzip -9 > ../core-image-minimal-initramfs-quark.cpio.gz
	cd ..
	```
4. Replace the bzImage with one we have built before.
	``
	cp <path_to_802.11p-linux>/arch/x86/boot/bzImage .
	``
5. Format the SDCARD with fat32 and put everything into it.
	``
	cp * <path_to_sdcard>
	``

##Build the iw
1. Set the toolchain.
	``
	source <path_to_toolchain>/environment-setup-i586-poky-linux
	``
1. iw requires the Netlink Protocol Library Suite (libnl). Download, cross compile and install the Netlink Protocol libraries:

	```
	wget http://www.infradead.org/~tgr/libnl/files/libnl-3.2.24.tar.gz
	tar -xzf libnl-3.2.24.tar.gz
	cd libnl-3.2.24
	./configure --host=i386 --prefix=<path_to_toolchain>/sysroots/x86_64-pokysdk-linux/usr
	make 
	make install
	cd include
	make install
	mv <path_to_toolchain>/sysroots/x86_64-pokysdk-linux/usr/include/libnl3/netlink <path_to_toolchain>/sysroots/x86_64-pokysdk-linux/usr/include/
	```
1. Download and build iw.

	```
	git clone https://github.com/CTU-IIG/802.11p-iw.git
	cd 802.11p-iw
	make
	mv iw iw-ocb
	```

##Configure OCB interface

```
chmod 777 iw-ocb
#./iw-802.11p reg set DE
ip link set wlp1s0 down
./iw-802.11p dev wlp1s0 set type ocb
ip link set wlp1s0 up
./iw-802.11p dev wlp1s0 ocb join 5910 10MHZ

# Get the interface statistics
ip -s link show dev wlan0
```

##

http://www.linuxidc.com/Linux/2007-05/4417.htm
http://blog.csdn.net/youyoulg/article/details/6889101
https://gist.github.com/lisovy/80dde5a792e774a706a9

https://github.com/xbolshe/galileo-custom-images/tree/master/iot_1.2.0_kernel_3.19.8
https://github.com/xbolshe/galileo-sources/tree/master/iot_1.2.0_kernel_3.19.8