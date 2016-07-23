`timescale 1ns / 1ps

//注意，一个地址对应两个字节输出 
`define MAX_FIFO_I_PTR  18'b011111111111110000
`define MIN_FIFO_I_PTR  18'b000000001100000010
//启动配置专用缓冲区
`define CONFIG_START_P	18'b000000000000000001
`define CONFIG_MAXEND_P	18'b000000001000000001
//给单条命令专用的缓冲区
`define CMD_START_P		18'b000000001000000001
`define CMD_MAXEND_P		18'b000000001100000000

`define FIFO_I_SIZE (`MAX_FIFO_I_PTR-`MIN_FIFO_I_PTR+1)

`define MAX_FIFO_O_PTR 	18'b111111111111110000
`define MIN_FIFO_O_PTR 	18'b100000000000000000

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
	//单条命令格式：第一个字节为长度，第二个字节填充0，后续跟命令实体
	cmd_read,//for wireless control
	cmd_write,//for spi slave
	
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
	SRAM_Ctrl_Status,
	//开始收包标识，用于CRC错误后的回溯。
	Pkt_Start_flag,
	Crc_Error_Rollback
);
output [7:0] SRAM_Ctrl_Status;
assign SRAM_Ctrl_Status=Current_State;

output[7:0] count;
assign count={4'b000,slave_write,slave_read,master_write,master_read};
output Current_State;
output opcode;

input clk;

input Pkt_Start_flag;
input Crc_Error_Rollback;

output wireless_control_need_reset;
input slave_read;
input slave_write;
input master_read;
input master_write;

input config_read;//for wireless control
input config_write;//for spi slave
input config_write_done;
input config_read_done;

input cmd_read;//for wireless control
input cmd_write;//for spi slave

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
output reg	CE_n=0; //always selected
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

//配置专用缓冲区指针
reg[17:0] config_wr_ptr=`CONFIG_START_P;
reg[17:0] config_rd_ptr=`CONFIG_START_P;

//CMD专用缓冲区指针
reg[17:0] cmd_wr_ptr=`CMD_START_P;
reg[17:0] cmd_rd_ptr=`CMD_START_P;

//FIFO_i缓冲区指针

reg[17:0] fifo_i_rd_ptr=`MIN_FIFO_I_PTR;
reg[17:0] fifo_i_wr_ptr=`MIN_FIFO_I_PTR;


//FIFO_o缓冲区指针
reg[17:0] fifo_o_rd_ptr=`MIN_FIFO_O_PTR;
reg[17:0] fifo_o_wr_ptr=`MIN_FIFO_O_PTR;
reg[17:0] fifo_o_wr_ptr_tmp;//用于CRC错误的回溯机制

//负责同步互斥
output reg nUsing=0;
reg [4:0] Current_State=0;
reg[15:0] data_to_sram=0;
reg link=0;
reg [15:0] data_from_sram=0;
reg [3:0] opcode=0;

assign Dout=link?data_to_sram:16'hzzzz;

always@(posedge clk)
begin
	if(Pkt_Start_flag)
	begin
		fifo_o_wr_ptr_tmp=fifo_o_wr_ptr;
	end
	if(Crc_Error_Rollback)
	begin
		fifo_o_wr_ptr=fifo_o_wr_ptr_tmp;
	end

	case (Current_State)
		0:
		begin
			if(!nUsing&&slave_write)
			begin
				if(!fifo_i_full)
				begin
					nUsing=1;
					Current_State=1;
				end
			end	
			else if(!nUsing&&slave_read)
			begin
				if(!fifo_o_empty)
				begin
					nUsing=1;
					Current_State=2;
				end
			end
			else if(!nUsing&&master_write)
			begin
				if(!fifo_o_full)
				begin
					nUsing=1;
					Current_State=3;
				end
			end	
			else if(!nUsing&&master_read)
			begin
				if(!fifo_i_empty)
				begin
					nUsing=1;
					Current_State=4;
				end
			end
			//configuration space
			else if(!nUsing&&config_write)
			begin
				nUsing=1;
				Current_State=5;
			end
			else if(!nUsing&&config_read)
			begin
				nUsing=1;
				Current_State=6;
			end
			//配置文件写完，执行复位动作，同时给WirelessControl一个复位命令
			else if(!nUsing&&config_write_done)
			begin
				nUsing=1;
				Current_State=7;
			end
			//配置文件读取完毕，复位读指针用于CTS错误重启设备。
			else if(!nUsing&&config_read_done)
			begin
				nUsing=1;
				Current_State=8;
			end
			//单条命令的处理
			else if(!nUsing&&cmd_write)
			begin
				nUsing=1;
				Current_State=9;
			end
			else if(!nUsing&&cmd_read)
			begin
				nUsing=1;
				Current_State=10;
			end

		end	
	
	
		1:  //SPI_slave模块写请求
		begin
			opcode=1;
			data_to_sram=slave_data_to_sram;
			mem_addr[17:0]=fifo_i_wr_ptr[17:0];
			fifo_i_wr_ptr=fifo_i_wr_ptr+1;
			fifo_i_count=fifo_i_count+1;
			if(fifo_i_wr_ptr>`MAX_FIFO_I_PTR)
				fifo_i_wr_ptr=`MIN_FIFO_I_PTR;
			Current_State=20;	
		end
		
		2: //SPI_slave模块读请求
		begin
			opcode=2;
			mem_addr[17:0]=fifo_o_rd_ptr[17:0];
			fifo_o_rd_ptr=fifo_o_rd_ptr+1;
			fifo_o_count=fifo_o_count-1;
			if(fifo_o_rd_ptr>`MAX_FIFO_O_PTR)
				fifo_o_rd_ptr=`MIN_FIFO_O_PTR;
			Current_State=21;
		end
		
		3: //SPI_master模块写请求
		begin
			opcode=3;
			data_to_sram=master_data_to_sram;
			mem_addr[17:0]=fifo_o_wr_ptr[17:0];
			fifo_o_wr_ptr=fifo_o_wr_ptr+1;
			fifo_o_count=fifo_o_count+1;
			if(fifo_o_wr_ptr > `MAX_FIFO_O_PTR)
				fifo_o_wr_ptr = `MIN_FIFO_O_PTR;
			Current_State=20;	
		end
		
		4://SPI_master模块读请求
		begin
			opcode=4;
			mem_addr[17:0]=fifo_i_rd_ptr[17:0];
			fifo_i_rd_ptr=fifo_i_rd_ptr+1;
			fifo_i_count=fifo_i_count-1;
			if(fifo_i_rd_ptr > `MAX_FIFO_I_PTR)
				fifo_i_rd_ptr = `MIN_FIFO_I_PTR;
			Current_State=21;
		end
		
		5://SPI_slave写配置数据
		begin
			opcode=5;	
			data_to_sram=slave_data_to_sram;
			mem_addr[17:0]=config_wr_ptr[17:0];
			config_wr_ptr=config_wr_ptr+1;
			Current_State=20;	
		end
		
		6://读配置w
		begin
			opcode=6;
			mem_addr[17:0]=config_rd_ptr[17:0];
			config_rd_ptr=config_rd_ptr+1;
			Current_State=21;	
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
			Current_State=25;
		end
		
		8://配置文件读取完毕，复位读指针用于CTS错误重启设备。
		begin
			config_wr_ptr=`CONFIG_START_P;
			config_rd_ptr=`CONFIG_START_P;

			Current_State=27;
		end
		
		9://单条CMD的写入
		begin
			opcode=7;
			data_to_sram=slave_data_to_sram;
			mem_addr[17:0]=cmd_wr_ptr[17:0];
			cmd_wr_ptr=cmd_wr_ptr+1;
			if(cmd_wr_ptr > `CMD_MAXEND_P)
				cmd_wr_ptr = `CMD_START_P;
			Current_State=20;	
		end
		10://单条CMD的读取
		begin
			opcode=8;
			mem_addr[17:0]=cmd_rd_ptr[17:0];
			cmd_rd_ptr=cmd_rd_ptr+1;
			if(cmd_rd_ptr > `CMD_MAXEND_P)
				cmd_rd_ptr = `CMD_START_P;
			Current_State=21;	
		end
		
		20: //写SRAM
		begin
			WE_n<=0;
			//CE_n<=0;
			LB_n<=0;
			UB_n<=0;
			link<=1;
			Current_State=19;
		end
		
		21: //读SRAM
		begin
			WE_n<=1;
			//CE_n<=0;
			OE_n<=0;
			LB_n<=0;
			UB_n<=0;
			Current_State=19;
		end
		
		19:
		begin
			Current_State=22;
		end
		
		22: //读写完成
		begin
			data_from_sram<=Dout;
			
			Current_State=23;
		end
		
		23: //设置hint信号
		begin
			WE_n<=1;
			//CE_n<=0;
			OE_n<=1;
			link<=0;
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
				7://CMD write
				begin
					slave_hint=1;
				end
				8://CMD read
				begin
					master_data_from_sram=data_from_sram;
					master_hint=1;
				end				
			endcase
			opcode=0;
			Current_State=24;
		end
		24: //恢复hint信号，操作完成，给其他操作让出空间
		begin
			slave_hint=0;
			master_hint=0;
			Current_State=0;
			nUsing=0;
		end
		
		25:
		begin
			wireless_control_need_reset=1;
			Current_State=26;
		end
		26:
		begin
			wireless_control_need_reset=0;
			nUsing=0;
			Current_State=0;
		end
		27:
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