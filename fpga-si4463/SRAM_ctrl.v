`timescale 1ns / 1ps

//126KB for Input, First 1KB for configuration space
`define MAX_FIFO_I_PTR  17'b01111111111111111
`define MIN_FIFO_I_PTR  17'b00000001000000010
`define CONFIG_START_P	17'b00000000000000000
`define CONFIG_MAXEND_P	17'b00000001000000000
`define FIFO_I_SIZE (`MAX_FIFO_I_PTR-`MIN_FIFO_I_PTR+1)
//127KB for Output 63K*16bit
`define MAX_FIFO_O_PTR 	17'b11111111111111111
`define MIN_FIFO_O_PTR 	17'b10000000000000000
`define FIFO_O_SIZE (`MAX_FIFO_O_PTR-`MIN_FIFO_O_PTR+1)

module SRAM_ctrl(
	clk,
	
	//控制wireless_control的重置
	wireless_control_need_reset,
	
	//对SRAM读写的控制信号
	slave_read,
	slave_write,
	master_read,
	master_write,
	
	//配置文件格式：前两个字节为整个配置文件的大小。后跟每条命令长度、命令数据
	config_read,//for wireless control
	config_write,//for spi slave
	config_write_done,
	config_read_done,
	
	//数据线
	slave_data_to_sram,
	slave_data_from_sram,
	
	master_data_to_sram,
	master_data_from_sram,
	
	//指示由哪个控制单元获得SRAM控制权限
	slave_hint,
	master_hint,
	
	//指示缓冲区大小和状态
	fifo_i_empty,
	fifo_i_full,
	fifo_i_count,
	
	fifo_o_empty,
	fifo_o_full,
	fifo_o_count,
	
	//SRAM引脚
	mem_addr,
	Dout,
	CE_n,
	OE_n,
	WE_n,
	LB_n,
	UB_n,
	nUsing,
	count,
	Current_State,
	opcode,
	//用于输出当前状态
	SRAM_Ctrl_Status
);
output [7:0] SRAM_Ctrl_Status;
assign SRAM_Ctrl_Status=Current_State;

output[7:0] count;
assign count={4'b000,slave_write,slave_read,master_write,master_read};
output nUsing;
output Current_State;
output opcode;

input clk;

output wireless_control_need_reset;
input slave_read;
input slave_write;
input master_read;
input master_write;

input config_read;//for wireless control
input config_write;//for spi slave
input config_write_done;
input config_read_done;

input [15:0] slave_data_to_sram;
output reg [15:0] slave_data_from_sram;
input [15:0] master_data_to_sram;
output reg [15:0] master_data_from_sram;

output reg slave_hint;
output reg master_hint;

//CONFIGURE
reg wireless_control_need_reset=0;//

//SRAM的引脚
output reg [17:0]	mem_addr;
inout[15:0]	   Dout;
output reg	CE_n=0;
output reg	OE_n=1;
output reg	WE_n=1;
output reg	LB_n=0;
output reg	UB_n=0;

	//指示缓冲区大小和状态
output reg	fifo_i_empty=1;
output reg	fifo_i_full=0;
output reg[17:0]	fifo_i_count=0;
	
output reg	fifo_o_empty=1;
output reg	fifo_o_full=0;
output reg[17:0]	fifo_o_count=0;

//Configure Space Points
reg[16:0] config_wr_ptr=`CONFIG_START_P;
reg[16:0] config_rd_ptr=`CONFIG_START_P;


//FIFO_i缓冲区指针

reg[16:0] fifo_i_rd_ptr=`MIN_FIFO_I_PTR;
reg[16:0] fifo_i_wr_ptr=`MIN_FIFO_I_PTR;

//FIFO_o缓冲区指针


reg[16:0] fifo_o_rd_ptr=`MIN_FIFO_O_PTR;
reg[16:0] fifo_o_wr_ptr=`MIN_FIFO_O_PTR;

//负责同步互斥
reg nUsing=0;
reg [5:0] Current_State=0;
reg[15:0] data_to_sram=0;
reg link=0;
reg [15:0] data_from_sram=0;
reg [3:0] opcode=0;

assign Dout=link?data_to_sram:16'hzzzz;

always@(posedge clk)
begin
	if(!nUsing&&slave_write)
	begin
		if(!fifo_i_full)
		begin
			nUsing=1;
			Current_State=1;
		end
	end	
	
	if(!nUsing&&slave_read)
	begin
		if(!fifo_o_empty)
		begin
			nUsing=1;
			Current_State=2;
		end
	end
	
	if(!nUsing&&master_write)
	begin
		if(!fifo_o_full)
		begin
			nUsing=1;
			Current_State=3;
		end
	end
	
	if(!nUsing&&master_read)
	begin
		if(!fifo_i_empty)
		begin
			nUsing=1;
			Current_State=4;
		end
	end
	
	//configuration space
	if(!nUsing&&config_write)
	begin
		nUsing=1;
		Current_State=5;
	end
	
	if(!nUsing&&config_read)
	begin
		nUsing=1;
		Current_State=6;
	end
	
	//配置文件写完，执行复位动作，同时给WirelessControl一个复位命令
	if(!nUsing&&config_write_done)
	begin
		nUsing=1;
		Current_State=7;
	end
	
	//配置文件读取完毕，复位读指针用于CTS错误重启设备。
	if(!nUsing&&config_read_done)
	begin
		nUsing=1;
		Current_State=8;
	end
		
	
	case (Current_State)
		1:  //SPI_slave模块写请求
		begin
			opcode=1;
			data_to_sram=slave_data_to_sram;
			mem_addr[16:0]=fifo_i_wr_ptr;
			fifo_i_wr_ptr=fifo_i_wr_ptr+1;
			fifo_i_count=fifo_i_count+1;
			if(fifo_i_wr_ptr>`MAX_FIFO_I_PTR)
				fifo_i_wr_ptr=`MIN_FIFO_I_PTR;
			Current_State=10;	
		end
		
		2: //SPI_slave模块读请求
		begin
			opcode=2;
			mem_addr[16:0]=fifo_o_rd_ptr;
			fifo_o_rd_ptr=fifo_o_rd_ptr+1;
			fifo_o_count=fifo_o_count-1;
			if(fifo_o_rd_ptr>`MAX_FIFO_O_PTR)
				fifo_o_rd_ptr=`MIN_FIFO_O_PTR;
			Current_State=11;
		end
		
		3: //SPI_master模块写请求
		begin
			opcode=3;
			data_to_sram=master_data_to_sram;
			mem_addr[16:0]=fifo_o_wr_ptr;
			fifo_o_wr_ptr=fifo_o_wr_ptr+1;
			fifo_o_count=fifo_o_count+1;
			if(fifo_o_wr_ptr > `MAX_FIFO_O_PTR)
				fifo_o_wr_ptr = `MIN_FIFO_O_PTR;
			Current_State=10;	
		end
		
		4://SPI_master模块读请求
		begin
			opcode=4;
			mem_addr[16:0]=fifo_i_rd_ptr;
			fifo_i_rd_ptr=fifo_i_rd_ptr+1;
			fifo_i_count=fifo_i_count-1;
			if(fifo_i_rd_ptr > `MAX_FIFO_I_PTR)
				fifo_i_rd_ptr = `MIN_FIFO_I_PTR;
			Current_State=11;
		end
		
		5://SPI_slave写配置数据
		begin
			opcode=5;	
			data_to_sram=slave_data_to_sram;
			mem_addr=config_wr_ptr;
			config_wr_ptr=config_wr_ptr+1;
			Current_State=10;	
		end
		
		6://读配置w
		begin
			opcode=6;
			mem_addr=config_rd_ptr;
			config_rd_ptr=config_rd_ptr+1;
			Current_State=11;	
		end
		
		7://复位。配置文件写完，执行复位动作，同时给WirelessControl一个复位命令
		begin
			config_wr_ptr=`CONFIG_START_P;
			config_rd_ptr=`CONFIG_START_P;
			fifo_i_rd_ptr=`MIN_FIFO_I_PTR;
			fifo_i_wr_ptr=`MIN_FIFO_I_PTR;
			fifo_o_rd_ptr=`MIN_FIFO_O_PTR;
			fifo_o_wr_ptr=`MIN_FIFO_O_PTR;

			fifo_i_count=0;
			fifo_o_count=0;
			Current_State=15;
		end
		
		8://配置文件读取完毕，复位读指针用于CTS错误重启设备。
		begin
			config_wr_ptr=`CONFIG_START_P;
			config_rd_ptr=`CONFIG_START_P;

			Current_State=17;
		end
		
		10: //写SRAM
		begin
			WE_n<=0;
			CE_n<=0;
			LB_n<=0;
			UB_n<=0;
			link<=1;
			Current_State=12;
		end
		
		11: //读SRAM
		begin
			WE_n<=1;
			CE_n<=0;
			OE_n<=0;
			LB_n<=0;
			UB_n<=0;
			Current_State=12;
		end
		
		12: //读写完成
		begin
			WE_n<=1;
			CE_n<=0;
			OE_n<=1;
			data_from_sram<=Dout;
			link<=0;
			Current_State=13;
		end
		
		13: //设置hint信号
		begin
			case(opcode)
				1:
				begin
					slave_hint=1;
				end
				2:
				begin
					slave_data_from_sram=data_from_sram;
					slave_hint=1;
				end
				3:
				begin
					master_hint=1;
				end
				4:
				begin
					master_data_from_sram=data_from_sram;
					master_hint=1;
				end
				5://configure write (SPI slave)
				begin
					slave_hint=1;
				end
				6://configure read (Wireless Control)
				begin
					master_data_from_sram=data_from_sram;
					master_hint=1;
				end
				
				
				default:
				begin
					slave_hint=0;
					master_hint=0;
				end
			endcase
			opcode=0;
			Current_State=14;
		end
		
		14: //等待一个周期之后，恢复hint信号，操作完成，给其他操作让出空间
		begin
			slave_hint=0;
			master_hint=0;
			Current_State=0;
			nUsing=0;
		end
		
		15:
		begin
			wireless_control_need_reset=1;
			Current_State=16;
		end
		16:
		begin
			wireless_control_need_reset=0;
			nUsing=0;
			Current_State=0;
		end
		17:
		begin
			nUsing=0;
			Current_State=0;
		end
	endcase
end


//监听缓冲区
//不用担心正在写入或者正在读取的情况，因为这种情况下，即使提前更改了选项，由于其他操作不能进行，而其他操作能进行时，实际数量已经与其一致了
always@(posedge clk)
begin
	
	if(fifo_i_count==`FIFO_I_SIZE)
		fifo_i_full=1;
	else
		fifo_i_full=0;
	if(fifo_i_count==0)
		fifo_i_empty=1;
	else
		fifo_i_empty=0;
	if(fifo_o_count==`FIFO_O_SIZE)
		fifo_o_full=1;
	else
		fifo_o_full=0;
	if(fifo_o_count==0)
		fifo_o_empty=1;
	else
		fifo_o_empty=0;
end

endmodule