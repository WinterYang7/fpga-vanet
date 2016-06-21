module total_link(
	clk,
	
	//SPI_slave引脚
	cpu_mosi,
	cpu_miso,
	cpu_sclk,
	cpu_irq_recv,
	cpu_irq_full,
	
	//wireless_ctrl引脚
	si4463_mosi,
	si4463_miso,
	si4463_sclk,
	si4463_ss_n,
	si4463_reset,
	si4463_irq,
	
	//SRAM 的引脚
	sram_mem_addr,
	Dout,
	CE_n,
	OE_n,
	WE_n,
	LB_n,
	UB_n,

	//LED灯指示当前状态
	led,
	debug_wire,
	Spi_Current_State
);
input	clk;
output[3:0] led;
output[7:0] Spi_Current_State;
output[1:0] debug_wire;

/*
assign Spi_Current_State[0]=clk;
assign Spi_Current_State[1]=0;
assign Spi_Current_State[2]=0;
assign Spi_Current_State[3]=0;
assign Spi_Current_State[4]=0;
assign Spi_Current_State[5]=0;
assign Spi_Current_State[6]=0;
assign Spi_Current_State[7]=0;*/
//assign Spi_Current_State={7'b0000000,slave_write_sram};
//assign Spi_Current_State=sram_count_to_slave[7:0];
	
	//SPI_slave引脚
input	cpu_mosi;
output	cpu_miso;
input	cpu_sclk;
output	cpu_irq_recv;
output cpu_irq_full;
assign cpu_irq_full=(sram_count_to_master>18'h1FF80)?1:0; //当FIFO_I还剩255个字节时，提示cpu可以将正在发送的发送过来，但不能发送下一个数据
//	assign cpu_irq_full=sram_full_to_slave;                //这样做还有一个好处，就是不用担心因为SRAM已满，导致数据无法写入而出错，最终数据包的长度与实际写入SRAM中的数据个数不一致。
																			//如果数据个数不一致，那么SPI_ctrl会阻塞到获取数据的地方，因此必须伽利略必须发送更多数据来填充前一个数据的空白。
	//wireless_ctrl引脚
output	si4463_mosi;
input	si4463_miso;
output	si4463_sclk;
output	si4463_ss_n;
output	si4463_reset;
input	si4463_irq;

	//SRAM 的引脚
output[17:0]	sram_mem_addr;
inout[15:0]	Dout;
output	CE_n;
output	OE_n;
output	WE_n;
output	LB_n;
output	UB_n;

//SRAM与spi_slave的连线
wire config_write_sram;
wire config_write_sram_done;

wire slave_read_sram;
wire slave_write_sram;
wire sram_full_to_slave;
wire sram_empty_to_slave;
wire sram_hint_to_slave;
wire[17:0] sram_count_to_slave;
wire[15:0] sram_data_from_slave;
wire[15:0] sram_data_to_slave;

//SRAM与wireless的连线
wire wireless_control_need_reset_wire;

wire config_read_sram;
wire config_read_sram_done;

wire master_read_sram;
wire master_write_sram;
wire sram_full_to_master;
wire sram_empty_to_master;
wire sram_hint_to_master;
wire[17:0] sram_count_to_master;
wire[15:0] sram_data_from_master;
wire[15:0] sram_data_to_master;
wire SRAM_AlmostFull_to_master;
assign SRAM_AlmostFull_to_master=(sram_count_to_slave>18'h1FF80)?1:0;

//Wireless_Ctrl与spi_master的连线
wire master_rd_n;
wire master_wr_n;
wire master_rrdy;
wire master_trdy;
wire master_signal_tmt;
wire master_select;
wire master_reset_n;
wire[2:0] master_mem_addr;
wire[15:0] data_to_master;
wire[15:0] data_from_master;

//Wireless_Ctrl与spi_slave的连线
wire signal_for_recved_irq;



SRAM_ctrl sram(
	.clk(clk),
	//重置信号
	.wireless_control_need_reset(wireless_control_need_reset_wire),

	//对SRAM读写的控制信号
	.slave_read(slave_read_sram),
	.slave_write(slave_write_sram),
	.master_read(master_read_sram),
	.master_write(master_write_sram),
	
	.config_read(config_read_sram),//for wireless control
	.config_read_done(config_read_sram_done),
	
	.config_write(config_write_sram),//for spi slave
	.config_write_done(config_write_sram_done),
	
	//数据线
	.slave_data_to_sram(sram_data_from_slave),
	.slave_data_from_sram(sram_data_to_slave),
	
	.master_data_to_sram(sram_data_from_master),
	.master_data_from_sram(sram_data_to_master),
	
	//指示由哪个控制单元获得SRAM控制权限
	.slave_hint(sram_hint_to_slave),
	.master_hint(sram_hint_to_master),
	
	//指示缓冲区大小和状态
	.fifo_i_empty(sram_empty_to_master),
	.fifo_i_full(sram_full_to_slave),
	.fifo_i_count(sram_count_to_master),
	
	.fifo_o_empty(sram_empty_to_slave),
	.fifo_o_full(sram_full_to_master),
	.fifo_o_count(sram_count_to_slave),
	
	//SRAM引脚
	.mem_addr(sram_mem_addr),
	.Dout(Dout),
	.CE_n(CE_n),
	.OE_n(OE_n),
	.WE_n(WE_n),
	.LB_n(LB_n),
	.UB_n(UB_n)//,
	
	//.count(Spi_Current_State)
		//用于输出当前状态
	//.SRAM_Ctrl_Status(Spi_Current_State)
);

Slave_Ctrl slave(
	.clk(clk),
	
	//与CPU的接口
	.mosi(cpu_mosi),
	.miso(cpu_miso),
	.sclk(cpu_sclk),
	
	//与SRAM的接口
	.Config_write_sram(config_write_sram),//SPI slave should write the configuration space
	.Config_write_sram_done(config_write_sram_done),
	
	.SRAM_read(slave_read_sram),
	.SRAM_write(slave_write_sram),
	.SRAM_hint(sram_hint_to_slave),
	.Data_to_sram(sram_data_from_slave),
	.Data_from_sram(sram_data_to_slave),
	.SRAM_full(sram_full_to_slave),
	.SRAM_empty(sram_empty_to_slave),
	.SRAM_count(sram_count_to_slave),
	
	//帧接收中断,与wireless_ctrl连接
	//.frame_recved_int(signal_for_recved_irq), //可以删掉了
	
	//与CPU连接的中断
	.cpu_recv_int(cpu_irq_recv)//,
	
	//.Spi_Current_State_1(Spi_Current_State)
	//用于输出当前状态
	//.Slave_Ctrl_Status(Spi_Current_State)
);

Wireless_Ctrl wireless(
	.clk(clk),
	
	//SRAM接口
	.Config_read_sram(config_read_sram),//wireless control can only read configurations.
	.Need_reset_from_sram(wireless_control_need_reset_wire),
	.Config_read_sram_done(config_read_sram_done),
	
	.SRAM_read(master_read_sram),
	.SRAM_write(master_write_sram),
	.SRAM_full(sram_full_to_master),
	.SRAM_hint(sram_hint_to_master),
	.SRAM_empty(sram_empty_to_master),
	.SRAM_count(sram_count_to_master),
	.Data_to_sram(sram_data_from_master),
	.Data_from_sram(sram_data_to_master),
	.SRAM_AlmostFull(SRAM_AlmostFull_to_master),
	
	//Si4463接口
	.Si4463_int(si4463_irq),
	.Si4463_reset(si4463_reset),
	
	//SPI_master接口
	.Data_to_master(data_to_master),
	.Data_from_master(data_from_master),
	.master_mem_addr(master_mem_addr),
	.master_read_n(master_rd_n),
	.master_write_n(master_wr_n),
	.master_reset_n(master_reset_n),
	.master_rrdy(master_rrdy),
	.master_trdy(master_trdy),
	.master_tmt(master_signal_tmt),
	.master_spi_sel(master_select),
	
	//接收完一个帧后的脉冲信号
	//.frame_recved_int(signal_for_recved_irq),
	
	//指示当前状态
	.led(led),
	.Si4463_Ph_Status_1(Spi_Current_State),
	.wireless_debug(debug_wire)//for DUBUG
);

spi_master spi(
	.clk(clk),
	.data_from_cpu(data_to_master),
	.mem_addr(master_mem_addr),
	.read_n(master_rd_n),
	.write_n(master_wr_n),              
	.reset_n(master_reset_n),
	.spi_select(master_select),
                
	.data_to_cpu(data_from_master),
	.dataavailable(master_rrdy),
	.transmitterempty(master_signal_tmt),
	.readyfordata(master_trdy),
	//endofpacket
	//irq
	
	.MISO(si4463_miso),
	.MOSI(si4463_mosi),
	.SCLK(si4463_sclk),
	.SS_n(si4463_ss_n)
);

endmodule