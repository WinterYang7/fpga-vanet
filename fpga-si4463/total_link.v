module total_link(
	clk,
	
	//SPI_slave����
	cpu_mosi,
	cpu_miso,
	cpu_sclk,
	cpu_irq_recv,
	cpu_irq_full,
	
	//wireless_ctrl����
	si4463_mosi,
	si4463_miso,
	si4463_sclk,
	si4463_ss_n,
	si4463_reset,
	si4463_irq,
	
	//SRAM ������
	sram_mem_addr,
	Dout,
	CE_n,
	OE_n,
	WE_n,
	LB_n,
	UB_n,

	//LED��ָʾ��ǰ״̬
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
	
	//SPI_slave����
input	cpu_mosi;
output	cpu_miso;
input	cpu_sclk;
output	cpu_irq_recv;
output cpu_irq_full;
assign cpu_irq_full=(sram_count_to_master>18'h1FF80)?1:0; //��FIFO_I��ʣ255���ֽ�ʱ����ʾcpu���Խ����ڷ��͵ķ��͹����������ܷ�����һ������
//	assign cpu_irq_full=sram_full_to_slave;                //����������һ���ô������ǲ��õ�����ΪSRAM���������������޷�д��������������ݰ��ĳ�����ʵ��д��SRAM�е����ݸ�����һ�¡�
																			//������ݸ�����һ�£���ôSPI_ctrl����������ȡ���ݵĵط�����˱���٤���Ա��뷢�͸������������ǰһ�����ݵĿհס�
	//wireless_ctrl����
output	si4463_mosi;
input	si4463_miso;
output	si4463_sclk;
output	si4463_ss_n;
output	si4463_reset;
input	si4463_irq;

	//SRAM ������
output[17:0]	sram_mem_addr;
inout[15:0]	Dout;
output	CE_n;
output	OE_n;
output	WE_n;
output	LB_n;
output	UB_n;

//SRAM��spi_slave������
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

//SRAM��wireless������
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

//Wireless_Ctrl��spi_master������
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

//Wireless_Ctrl��spi_slave������
wire signal_for_recved_irq;



SRAM_ctrl sram(
	.clk(clk),
	//�����ź�
	.wireless_control_need_reset(wireless_control_need_reset_wire),

	//��SRAM��д�Ŀ����ź�
	.slave_read(slave_read_sram),
	.slave_write(slave_write_sram),
	.master_read(master_read_sram),
	.master_write(master_write_sram),
	
	.config_read(config_read_sram),//for wireless control
	.config_read_done(config_read_sram_done),
	
	.config_write(config_write_sram),//for spi slave
	.config_write_done(config_write_sram_done),
	
	//������
	.slave_data_to_sram(sram_data_from_slave),
	.slave_data_from_sram(sram_data_to_slave),
	
	.master_data_to_sram(sram_data_from_master),
	.master_data_from_sram(sram_data_to_master),
	
	//ָʾ���ĸ����Ƶ�Ԫ���SRAM����Ȩ��
	.slave_hint(sram_hint_to_slave),
	.master_hint(sram_hint_to_master),
	
	//ָʾ��������С��״̬
	.fifo_i_empty(sram_empty_to_master),
	.fifo_i_full(sram_full_to_slave),
	.fifo_i_count(sram_count_to_master),
	
	.fifo_o_empty(sram_empty_to_slave),
	.fifo_o_full(sram_full_to_master),
	.fifo_o_count(sram_count_to_slave),
	
	//SRAM����
	.mem_addr(sram_mem_addr),
	.Dout(Dout),
	.CE_n(CE_n),
	.OE_n(OE_n),
	.WE_n(WE_n),
	.LB_n(LB_n),
	.UB_n(UB_n)
	
	//.count(Spi_Current_State)
		//���������ǰ״̬
	//.SRAM_Ctrl_Status(Spi_Current_State),

);

Slave_Ctrl slave(
	.clk(clk),
	
	//��CPU�Ľӿ�
	.mosi(cpu_mosi),
	.miso(cpu_miso),
	.sclk(cpu_sclk),
	
	//��SRAM�Ľӿ�
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
	
	//֡�����ж�,��wireless_ctrl����
	//.frame_recved_int(signal_for_recved_irq), //����ɾ����
	
	//���������ǰ״̬
//	.Slave_Ctrl_Status(Spi_Current_State),
//	.Slave_Ctrl_Debug(debug_wire),
	
	//��CPU���ӵ��ж�
	.cpu_recv_int(cpu_irq_recv)
	
	//.Spi_Current_State_1(Spi_Current_State)

	
);

Wireless_Ctrl wireless(
	.clk(clk),
	
	//SRAM�ӿ�
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
	
	//Si4463�ӿ�
	.Si4463_int(si4463_irq),
	.Si4463_reset(si4463_reset),
	
	//SPI_master�ӿ�
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
	
	//������һ��֡��������ź�
	//.frame_recved_int(signal_for_recved_irq),
	
	.Si4463_Ph_Status_1(Spi_Current_State),
	.wireless_debug(debug_wire),//for DUBUG
	
	//ָʾ��ǰ״̬
	.led(led)

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