##Galileo、FPGA、射频模块等的SPI通道
1. 连接关系总览：Galileo (spi_master) <=ICSP=> (spi_slave)FPGA (spi_master) <=io11~io13=> 射频模块
2. Galileo板子通过ICSP（6pin）接口与FPGA板子连接，同时阻断两个板子之间IO11（MOSI）、IO12（MISO）、IO13（SCK）的物理连接；
	1. 通过FPGA板子的原理图可知，ICSP的io没有与FPGA的io有连接。又因为电压是5v所以不能与FPGA板子上引出的io口直连。
	2. 临时的解决方案是将ICSP上的io与arduino排针上没有用到pin进行连接（其内部连上了5v<->3.3v的转压芯片），对应关系是sck<=>IO9，MISO<=>PIN1，MOSI<=>PIN0。代价是串口（ttyG0）用不了了。
	3. Galileo与FPGA的spi通道不需要片选信号
2. FPGA上采用两个SPI模块，一头为slave与galileo连接，一头为master控制射频模块。
	1. master端的连接方式采用io11~io13，片选信号使用io8
