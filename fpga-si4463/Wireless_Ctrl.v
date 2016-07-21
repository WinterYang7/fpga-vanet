module Wireless_Ctrl(
	clk,
	
	//SRAM接口
	Need_reset_from_sram,
	Config_read_sram,
	Config_read_sram_done,
	Cmd_read_sram,
	
	//有单条命令等待被发送
	Cmd_waiting,
	
	SRAM_read,
	SRAM_write,
	SRAM_full,
	SRAM_hint,
	SRAM_empty,
	SRAM_count,
	Data_to_sram,
	Data_from_sram,
	SRAM_AlmostFull, //这个信号实际由TotalLink是实现，可以将其添加到SRAM中，当只剩256个字节空间时，改信号置1
	
	//Si4463接口
	Si4463_int,
	Si4463_reset,
	
	//SPI_master接口
	Data_to_master,
	Data_from_master,
	master_mem_addr,
	master_read_n,
	master_write_n,
	master_reset_n,
	master_rrdy,
	master_trdy,
	master_tmt,
	master_spi_sel,
	
	//接收完一个帧后的脉冲信号
	//frame_recved_int,
	
	//FLAGS
	Pkt_Start_flag,
	Crc_Error_Rollback,
	Pkt_Received_flag,
	
	//用于指示当前状态的LED
	led,
	Si4463_Ph_Status_1,
	tx_done,//for DUBUG
	wireless_debug,
	packets_incoming
);
input clk;
output [7:0] Si4463_Ph_Status_1;
assign Si4463_Ph_Status_1[7:0]=Main_Current_State[7:0];
//assign Si4463_Ph_Status_1[7]=spi_op_done_main;
//assign Si4463_Ph_Status_1[4:0]=Irq_Current_State[4:0];//Spi_Current_State;
//assign Si4463_Ph_Status_1[7:5]=packets_incoming[3:0];

output reg [3:0] led=4'b0000;

output tx_done;
output wireless_debug;//for DUBUG
assign wireless_debug=tx_state[0];

//output [3:0] led;
//assign led=Main_Current_State[3:0];
output [3:0]packets_incoming;

//与SPI_SLAVE的接口
output reg Pkt_Received_flag=0;

//SRAM接口
output reg Pkt_Start_flag=0;
output reg Crc_Error_Rollback=0;

input Need_reset_from_sram;
output Config_read_sram;
output Config_read_sram_done;

output reg Cmd_read_sram=0;
input Cmd_waiting;


output	SRAM_read;
output	SRAM_write;
input	SRAM_full;
input	SRAM_hint;
input	SRAM_empty;
input[17:0]	SRAM_count;
output[15:0]	Data_to_sram;
input[15:0]	Data_from_sram;
input SRAM_AlmostFull;
//output reg frame_recved_int=0;
	
	//Si4463接口
input	Si4463_int;
output	Si4463_reset;
	
	//SPI_master接口
output[15:0]	Data_to_master;
input[15:0]	Data_from_master;
output[2:0]	master_mem_addr;
output	master_read_n;
output	master_reset_n;
input	master_rrdy;
input	master_trdy;
input	master_tmt;
output	master_spi_sel;
output master_write_n;


reg reset_n=1'b1;

//RSSI：for LBT listen before send
reg [7:0] Si4463_RSSI_Curr=0;
reg [7:0] Si4463_RSSI_RecvPacket=0;
wire[7:0] Si4463_RSSI_RecvPacket_wire;
assign Si4463_RSSI_RecvPacket_wire=Si4463_RSSI_RecvPacket;
`define RSSI_THRESHOLD 8'ha0

//config from SRAM
reg [15:0] config_len;

reg [7:0] config_cmd_len;
reg [7:0] config_cmd_len_next;
reg config_cmd_start_flag;
reg [15:0] config_count;
reg [7:0] config_count_percmd;

//单条命令的处理
reg [7:0] cmd_len;
reg [7:0] cmd_count;

//中断处理函数的信号
reg [4:0] Irq_Current_State=0;

reg [2:0] Syncirq_Current_State=3;
reg tx_done; //置1表示发送完成
wire tx_done_wire;
assign tx_done_wire=tx_done;
`define SYNC_IRQ_TIMEOUT 30//ms

//reg tx_flag; //是发送完成中断

reg [3:0] packets_incoming; //指示射频模块收到包但还未收到接收数据包的中断
wire[3:0] packets_incoming_wire;
assign packets_incoming_wire[3:0]=packets_incoming[3:0];

reg [7:0] Si4463_Ph_Status=0;
reg [7:0] Si4463_Modem_Status=0;
reg [7:0] frame_len;
reg irq_dealing;
wire irq_dealing_wire;
assign irq_dealing_wire=irq_dealing;

reg[7:0] Data_Recv_Pos=0;



//////接口
/*
	main_data_len[]   主进程需要发送的字节数
	int_data_len[]    中断进程需要发送的字节数
	
	Main_Start_data[79:0]  启动配置的数组
	spi_cmd[]   需要进行的操作
				1 main程序启动配置和gteCTS
				2 发送数据帧
				3 int接收数据帧
				4 int 获取中断状态
				5 main程序从SRAM中读取数据，唯一的用途是获取需要发送的数据
				6 int读快速寄存器
				7 int写SRAM
				8 读指定长度的RX FIFO
	spi_Using  bool值，代表spi模块是否正在被使用
	spi_start  bool值，设置为1，代表准备开始发送或接收数据
*/
reg [127:0] Main_Cmd_Data=0;  //主程序中的命令缓冲，包括启动配置和GetCTS
reg [31:0] Int_Cmd_Data=0;   //中断程序中的命令缓冲，主要是查看寄存器状态和GetCTS
reg [79:0] Main_Return_Data=0;  //返回数据的缓冲区
reg [79:0] Int_Return_Data=0;   //要接收的数据长度
reg [7:0] Main_Data_len=0;  //要发送的数据长度
reg [4:0] Main_Return_len=0;  //GetCTS后返回的数据长度
reg [7:0] Int_Data_len=0;
reg [3:0] Int_Return_len=0;
reg [3:0] Main_Cmd;   //主函数中的命令
reg [3:0] Int_Cmd;	//中断函数中的命令
reg Main_start=0;  //Main表示想要开始发送数据，需要提前检查Spi_Using
reg Int_start=0;   //Int表示想要开始发送数据，需要提前检查Spi_Using
reg[31:0] Main_Data_Check=0;


reg [127:0] spi_cmd_data;
reg [7:0] spi_data_len=0;
reg [4:0] spi_return_len=0;
reg [3:0] spi_cmd=0;
reg spi_Using=0;
wire spi_Using_wire;
assign spi_Using_wire=spi_Using;

reg[7:0] recv_pkt_len=0;
wire[7:0] recv_pkt_len_wire;
assign recv_pkt_len_wire=recv_pkt_len;

reg spi_start=0; //主要是监听Main_start和Int_start脉冲，当任意一个脉冲为1时，置1
reg [7:0] Sended_count=0; //已经发送的字节数

reg spi_op_done=0;//用于指示spi的操作是否已经完成
reg spi_main_flag=0;
reg spi_int_flag=0;
wire spi_op_done_main; 
wire spi_op_done_int;
assign spi_op_done_main=spi_main_flag?spi_op_done:1'b0;
assign spi_op_done_int=spi_int_flag?spi_op_done:1'b0;
reg run_once_flag;

reg spi_op_fifo_flag=0;  //用于指示发送帧时，发送的第一个命令

///与SPI_master的连线
reg [15:0] Data_to_master;
wire [15:0] Data_from_master;
//reg [15:0] Data_from_master_reg;
reg [2:0] master_mem_addr=0; 
reg master_write_n=1;
reg master_read_n=1;
reg master_reset_n=1;
wire master_spi_sel;
wire master_trdy;
wire master_rrdy;
wire master_tmt;

assign master_spi_sel=1;

//与SRAM的连线
reg SRAM_read=0;
reg SRAM_write=0;
wire SRAM_full; //说明FIFO_o已满
wire SRAM_empty; //说明FIFO_i已空
wire [17:0] SRAM_count;  //说明FIFO_o中的数据个数
reg [15:0] Data_to_sram;
wire [15:0] Data_from_sram;
reg [15:0] Data_from_sram_reg=0;
wire SRAM_hint;
reg Byte_flag=0;
reg Byte_flag_config=0;
reg GetCTS_flag=0;

wire Need_reset_from_sram;
reg Config_read_sram=0;
reg Config_read_sram_done=0;

reg [15:0] master_control_reg;

assign master_spi_sel=1;

reg [5:0] Spi_Current_State;
reg Ended_flag;
reg frame_len_flag; //标志着接收包时第一个字节，即包的长度


reg[31:0] CTScounter=0;
reg CTS_error_reset_n=1;
//分别在两个地方保证接收到的数据就是需要的数据
// 1. CTS,由于CTS后面跟着需要的数据，所以后面的数据可以确认为需要的数据
// 2. 只是发送命令时，返回的数据无所谓了 
// 3. 在接收数据后，发送0x77命令，放弃第一个接收到的数据(无效数据),在发送下一个数据前，射频有足够时间能够准备返回来的数据，所以返回的也是有效数据
always@(negedge reset_n or posedge clk)  //这里最好监视Main_start和Int_start信号
begin

	if(!reset_n)
	begin
		spi_start=0;
		spi_cmd=0;
		spi_data_len=0;
		spi_return_len=0;
		spi_cmd_data=0;
		Spi_Current_State=0;
		spi_Using=0;
		spi_op_done=0;
		//spi_op_done_main=0;
		//spi_op_done_int=0;
		GetCTS_flag=0;
		Byte_flag=0;
		spi_op_fifo_flag=1;
		Ended_flag=0;
		CTScounter=0;
		CTS_error_reset_n=1;
	end
	else
	begin
		case (Spi_Current_State)
			0:
			begin
				spi_main_flag=0;
				spi_int_flag=0;
				Spi_Current_State=54;
			end
			54:
			begin
				Spi_Current_State=53;
			end
			53:
			begin

				//run_once_flag=1;
				if(Main_start)
				begin

					spi_cmd=Main_Cmd;
					spi_data_len=Main_Data_len;
					spi_return_len=Main_Return_len;
					spi_cmd_data=Main_Cmd_Data;
					spi_Using=1;
					spi_main_flag=1;
					spi_int_flag=0;
					spi_op_done=0;
					run_once_flag=0;
					Spi_Current_State=52;
				end
				else if(Int_start)
				begin
					
					spi_cmd=Int_Cmd;
					spi_data_len=Int_Data_len;
					spi_return_len=Int_Return_len;
					spi_cmd_data=Int_Cmd_Data;
					spi_Using=1;
					spi_int_flag=1;
					spi_main_flag=0;
					spi_op_done=0;
					Spi_Current_State=52;
				end
			end
			52:
			begin	
				case (spi_cmd) //这里有点多余，可以简单删除一下
					1:
					begin
						Spi_Current_State=1;
					end
					2:
					begin
						Spi_Current_State=1;
					end
					3:
					begin
						Spi_Current_State=1;
					end
					4:
					begin
						Spi_Current_State=1;
					end
					5:
					begin
						Spi_Current_State=36;
					end
					6:
					begin
						Spi_Current_State=1;
					end
					7:
					begin
						Spi_Current_State=43;
						Sended_count=0;
					end
					8:
					begin
						Spi_Current_State=1;
					end
					/*0:
					begin
						spi_start=0;
						Spi_Current_State=0;
						spi_Using=0;
						spi_op_done_main=0;
						spi_op_done_int=0;
					end	*/
				endcase
				GetCTS_flag=0;
				Byte_flag=0;
				spi_op_fifo_flag=1;
				Ended_flag=0;
				CTScounter=0;
			end
			
			 ////////////////将片选信号拉低/////////////////////////////
			1:  //要发送的数据存放在Main_Cmd_Data
			begin
				Sended_count=0;
				master_mem_addr=3'b011;
				master_read_n=0;
				Spi_Current_State=2;
			end
			2: 
			begin
				master_read_n=1;
				Spi_Current_State=3;
			end
			3:
			begin
				master_control_reg=Data_from_master;
				Spi_Current_State=4;
			end
			4:
			begin
				master_mem_addr=3'b011;
				master_write_n=0;
				Data_to_master=master_control_reg | 16'h0400;
				Spi_Current_State=5;
			end
			5:
			begin
				master_write_n=1;
				Spi_Current_State=6;
			end
			6:
			begin
				if(!GetCTS_flag)
					Spi_Current_State=7;
				else
					Spi_Current_State=16;
			end
			
			////////////////////发送命令或者数据/////////////////////////////
			7: //准备完成，开始发送数据,判断数据源
			begin
				if(master_trdy)
				begin
					case (spi_cmd)
						1:
						begin
							Data_to_master=spi_cmd_data[7:0];
							spi_cmd_data={8'h00,spi_cmd_data[127:8]};
							Spi_Current_State=8;
						end
						2:
						begin
							Spi_Current_State=28;
						end
						3:
						begin
							Spi_Current_State=30;
						end
						8:
						begin
							Spi_Current_State=30;
						end
						4:
						begin
							Data_to_master=spi_cmd_data[7:0];
							spi_cmd_data={8'h00,spi_cmd_data[79:8]};
							Spi_Current_State=8;
						end
						6:
						begin
							Spi_Current_State=40;
						end
					endcase
					

				end
			end
			8: //发送数据
			begin
					master_write_n=0;
					master_mem_addr=3'b001;
					Spi_Current_State=9;
			end
			9:
			begin
				master_write_n=1;
				Spi_Current_State=10;
			end
			10: 
			begin
				Spi_Current_State=11;
				Sended_count=Sended_count+1'b1;
			end
			11:
			begin
				if(Sended_count<spi_data_len)
				begin
					Spi_Current_State=7;
				end
				else
				begin
					Spi_Current_State=12;
				end
			end
			
			///////////////////////////////////数据发送完，拉高片选信号，并通知用于操作已经完成//////////////////////////
			12:
			begin	
				if(master_tmt) //等待shift寄存器和tx寄存器的内容发送完
				begin
					Spi_Current_State=13;
				end
			end
			13:
			begin
				Data_to_master=master_control_reg & 16'hfbff;
				master_write_n=0;
				master_mem_addr=3'b011;
				Spi_Current_State=14;
			end
			14:
			begin
				master_write_n=1;
				Spi_Current_State=15;
			end
			15:
			begin
				if(spi_cmd==2||spi_cmd==3 || spi_cmd==8 ||Ended_flag || spi_cmd==6) //发送和接收数据帧不需要GetCTS
				begin
					spi_op_done=1;
					spi_Using=0;
					spi_start=0;
					Spi_Current_State=0;
				end
				else
				begin
					GetCTS_flag=1;
					Spi_Current_State=1;
				end
			end
			
			
			////////////////////////GetCTS函数/////////////
			16:
			begin
				if(master_trdy)
				begin
					CTScounter=CTScounter+1;
					if(CTScounter>10000)
					begin
						CTS_error_reset_n=0;
						Spi_Current_State=0;
					end
					else
					begin
						Data_to_master=16'h0044;
						master_mem_addr=3'b001;
						master_write_n=0;
						Spi_Current_State=17;
					end
				end
			end
			17:
			begin
				master_write_n=1;
				Spi_Current_State=18;
			end
			18:
			begin
				Spi_Current_State=63;
			end
			63:
			begin
				Data_to_master=16'h0000;
				master_mem_addr=3'b001;
				master_write_n=0;
				Spi_Current_State=62;
			end
			62:
			begin
				master_write_n=1;
				Spi_Current_State=61;
			end
			61:
			begin
				Spi_Current_State=19;
			end
			19:
			begin
				if(master_tmt&&master_rrdy) //用于确保接收到的是返回的第二个字节
				begin
					master_mem_addr=3'b000;
					master_read_n=0;
					Spi_Current_State=20;
				end
			end
			20:
			begin
				master_read_n=1;
				Spi_Current_State=21;
			end
			21:
			begin
				if(Data_from_master[7:0]==8'hff)
				begin
					
					if(spi_return_len>0)
					begin
						Sended_count=0;
						Spi_Current_State=22;
					end
					else
					begin
						Ended_flag=1;
						Spi_Current_State=12;
					end
				end
				else
					Spi_Current_State=12;
			end
			
			
			
			/////////////////////////////////用于接受数据/////////////////////////////////
			22:
			begin
				if(master_trdy)
				begin
					Data_to_master=16'h0000;
					master_mem_addr=3'b001;
					master_write_n=0;
					Spi_Current_State=23;
				end
			end
			23:
			begin
				master_write_n=1;
				Spi_Current_State=24;
			end
			24:
			begin
				Spi_Current_State=25;
			end
			25:
			begin
				if(master_rrdy&&master_tmt)
				begin
					master_mem_addr=3'b000;
					master_read_n=0;
					Spi_Current_State=26;
				end
			end
			26:
			begin
				master_read_n=1;
				Spi_Current_State=27;
			end
			27:
			begin	
				case (spi_cmd)
					1:
					begin
						Main_Return_Data={Main_Return_Data[71:0],8'h00};//先左移，为到来的数据提供空间
						Main_Return_Data[7:0]=Data_from_master[7:0];
						
						Sended_count=Sended_count+1'b1;
						if(Sended_count<spi_return_len)
							Spi_Current_State=22;
						else
						begin
							//spi_return_len=0;
							Ended_flag=1;
							Spi_Current_State=12;
						end
					end
					3:
					begin
						Spi_Current_State=31;
					end
					8:
					begin
						
						Spi_Current_State=51;
					end
					4:
					begin
						Int_Return_Data={Int_Return_Data[71:0],8'h00};
						Int_Return_Data[7:0]=Data_from_master[7:0];
						
						Sended_count=Sended_count+1'b1;
						if(Sended_count<spi_return_len)
							Spi_Current_State=22;
						else
						begin
							//spi_return_len=0;
							Ended_flag=1;
							Spi_Current_State=12;
						end
					end
					6:
					begin
						Int_Return_Data={Int_Return_Data[71:0],8'h00};
						Int_Return_Data[7:0]=Data_from_master[7:0];
						
						Sended_count=Sended_count+1'b1;
						if(Sended_count<spi_return_len)
							Spi_Current_State=22;
						else
						begin
							//spi_return_len=0;
							Spi_Current_State=12;
						end
					end
				endcase
			end


			
			///////////////////从SRAM中取出数据，并发送给射频模块//////////
			28: //从SRAM，即FIFO_i中读取数据
			begin
				if(spi_op_fifo_flag)
				begin
					Data_to_master=8'h66;
					spi_op_fifo_flag=0;
					Spi_Current_State=8;
				end
				else
				begin
					if(!Byte_flag&&!SRAM_empty)
					begin
						Byte_flag=~Byte_flag;
						SRAM_read=1;
						Spi_Current_State=29;
					end
					else if(Byte_flag)
					begin
						Byte_flag=~Byte_flag;
						Data_to_master={8'h00,Data_from_sram_reg[7:0]};
						Spi_Current_State=8;
					end
					else
						Spi_Current_State=28;
				end
			end
			29:
			begin
				if(SRAM_hint)
				begin
					SRAM_read=0;
					Data_from_sram_reg=Data_from_sram;
					Data_to_master={8'h00,Data_from_sram_reg[15:8]};
					Spi_Current_State=8;
				end
			end
			
			
			////////////////////////从射频模块接收数据并存放在SRAM中//////////////////
			30://从射频模块接收数据存放在FIFO_o
			begin
				frame_len_flag=1;
				Sended_count=0;
				Spi_Current_State=33; 
			end
			31:
			begin
				if(!Byte_flag) //由于SRAM要一次写两个字节，所以设置一个byte_flag作为调节。
				begin
					Data_to_sram[15:8]=Data_from_master[7:0]; //注意这一行
					if(frame_len_flag) //接收到的第一个字节为长度（不包括自身）
					begin
						//Byte_flag=~Byte_flag;
						frame_len_flag=0;
						
						if(spi_data_len!=0)
						begin
							recv_pkt_len=Data_from_master[7:0];
						end
						else
						begin
							spi_data_len=Data_from_master[7:0]; //处理数据包长度小于RX_THRESHOLD时的情况，即直接产生了RX中断。
						end
						Data_to_sram[15:8]=Data_to_sram[15:8]+1'b1; //多了一个字节存RSSI，这条指令覆盖掉了前一条。
						Data_to_sram[7:0]=Si4463_RSSI_RecvPacket_wire;
						//Spi_Current_State=22;
						//SRAM_write=1;//写入SRAM
						Spi_Current_State=50;
					end
					else
					begin
						Sended_count=Sended_count+1'b1;
						if(Sended_count<spi_data_len)
						begin
							Byte_flag=~Byte_flag;
							Spi_Current_State=22;
						end
						else //if(Sended_count<spi_data_len)
						begin
							if(!SRAM_full)
							begin
								Data_to_sram[7:0]=8'h00;
								SRAM_write=1;
								Spi_Current_State=32;
							end
							else
								Spi_Current_State=31;
						end
					end
				end
				else //if(!Byte_flag)
				begin
					Data_to_sram[7:0]=Data_from_master[7:0];
					if(!SRAM_full)
					begin
						Sended_count=Sended_count+1'b1;
						Byte_flag=~Byte_flag;
						SRAM_write=1;
						Spi_Current_State=32;
					end
					else
						Spi_Current_State=31;
				end								
			end
			
			50:
			begin
				SRAM_write=1;//写入SRAM
				Spi_Current_State=32;
			end
			
			51:
			begin
				if(!Byte_flag) //由于SRAM要一次写两个字节，所以设置一个byte_flag作为调节。
				begin
					Data_to_sram[15:8]=Data_from_master[7:0]; //注意这一行
					Sended_count=Sended_count+1'b1;
					if(Sended_count<spi_data_len)
					begin
						Byte_flag=~Byte_flag;
						Spi_Current_State=22;
					end
					else //if(Sended_count<spi_data_len)
					begin
						if(!SRAM_full)
						begin
							Data_to_sram[7:0]=8'h00;
							SRAM_write=1;
							Spi_Current_State=32;
						end
						else
							Spi_Current_State=51;
					end
				end
				else //if(!Byte_flag)
				begin
					Data_to_sram[7:0]=Data_from_master[7:0];
					if(!SRAM_full)
					begin
						Sended_count=Sended_count+1'b1;
						Byte_flag=~Byte_flag;
						SRAM_write=1;
						Spi_Current_State=32;
					end
					else
						Spi_Current_State=51;
				end											
			end
			
			32:
			begin
				if(SRAM_hint)
				begin
					SRAM_write=0;
					if(Sended_count<spi_data_len)
						Spi_Current_State=22;
					else
						Spi_Current_State=12;
				end
			end			
			33: //发送接收数据命令
			begin //单数发送数据命令不需要，因为射频可以立即准备好
				master_mem_addr=3'b001;
				master_write_n=0;
				Data_to_master=8'h77;
				Spi_Current_State=34;
			end
			34:
			begin
				master_write_n=1;
				Spi_Current_State=35;
			end
			35:
			begin
				if(master_tmt) //用于确保接收到的第一个数据就是有效数据
				begin
					Spi_Current_State=22;
				end
			end

			
			
			36: //cmd=5;
			begin
				SRAM_read=1;
				Spi_Current_State=39;
			end
			/*
			37:
			begin
				if(SRAM_hint)
				begin
					SRAM_read=0;
					Main_Data_Check[31:16]=Data_from_sram; //读取命令0x2d 0xd4
					Spi_Current_State=38;
				end
			end
			38:
			begin
				SRAM_read=1;
				Spi_Current_State=39;
			end*/
			39:
			begin
				if(SRAM_hint)
				begin
					SRAM_read=0;
					Main_Data_Check[15:0]=Data_from_sram; //读取两个字节
					spi_Using=0;
					spi_start=0;
					spi_op_done=1;
					Spi_Current_State=0;
				end
			end
			
			//读取快速寄存器 cmd=6
			40:
			begin
				Data_to_master={8'h00,spi_cmd_data[7:0]};
				master_write_n=0;
				master_mem_addr=3'b001;
				Spi_Current_State=41;
			end
			41:
			begin
				master_write_n=1;
				Spi_Current_State=42;
			end
			42:
			begin
				Spi_Current_State=22;
			end
			
			//int写SRAM cmd=7
			43:
			begin
				if(Sended_count<spi_data_len)
				begin
					SRAM_write=1;
					Data_to_sram=spi_cmd_data[15:0];
					Spi_Current_State=44;
				end
				else
				begin
					spi_Using=0;
					spi_start=0;
					spi_op_done=1;
					Spi_Current_State=0;
				end
			end
			44:
			begin
				if(SRAM_hint)
				begin
					SRAM_write=0;
					Sended_count=Sended_count+2;
					spi_cmd_data={16'h0000,spi_cmd_data[79:16]};
					Spi_Current_State=43;
				end
			end
		endcase
	end
end

reg GPS_sync_time=1'b1;  ////需要接GPS同步时钟
reg [7:0] Main_Current_State=255;
reg Si4463_reset=1'b1; //当程序启动或者wireless_ctrl置位时，设置为0
wire Si4463_int;
output reg [2:0] tx_state;  //0为默认，1表示rx, 2表示tx_tune，3表示tx
wire[2:0] tx_state_wire;
assign tx_state_wire[2:0]=tx_state[2:0];

//Variable packet lens
reg[7:0] Data_Len_to_Send=8'h00;

reg[7:0] Data_Sending_Pos=8'h00;

reg[7:0] Data_Sending_Remain;
reg Data_Sending_Remain_flag=0;
wire Data_Sending_Remain_flag_wire;
assign Data_Sending_Remain_flag_wire=Data_Sending_Remain_flag;
reg TX_fifo_almost_empty_flag=0;
wire TX_fifo_almost_empty_flag_wire;
assign TX_fifo_almost_empty_flag_wire=TX_fifo_almost_empty_flag;
reg RX_fifo_almost_full_flag=0;
wire RX_fifo_almost_full_flag_wire;
assign RX_fifo_almost_full_flag_wire=RX_fifo_almost_full_flag;

`define MAX_FIFO_SIZE 64
`define TX_THRESHOLD 40
`define RX_THRESHOLD 40


reg enable_irq=1'b0; //初始化完成后，才允许触发中断函数
`define RX 3'b001
`define TX_WAIT 3'b010
`define TX 3'b100


/**
 * 主函数()，程序开始时先配置射频模块 状态为0-130
 * 配置完成后，开始循环发送数据 状态为130-145
 **/
always@(posedge clk or negedge CTS_error_reset_n)
begin
	if(!CTS_error_reset_n || Need_reset_from_sram)
	begin
		Main_Current_State=0;
		config_cmd_start_flag=0;
		reset_n=0;
	end
	else
	begin
		case(Main_Current_State) 
		255:
		begin
		end
		
		0:
		begin
			led[3]=1'b0;
			enable_irq=0;
			tx_state=3'b000;
			Main_start=0;
			delay_start_2=0;
			
			Si4463_reset=1;
			delay_start=1;
			delay_mtime=10;
			led[2]=1'b0;
			if(delay_int)
			begin
				delay_start=0;
				Main_Current_State=249;
			end
		end
		249:
		begin
			reset_n=1;
			Si4463_reset=0;
			Main_Current_State=248;
		end
		248:
		begin
			Main_Current_State=247;
		end
		247:
		begin
			delay_start=1;
			delay_mtime=20;
			if(delay_int)
			begin
				delay_start=0;
				Main_Current_State=250;
			end
		end
		
	////////////reset()函数，启动射频模块
		250:
		begin
			Config_read_sram=1;
			
			Main_Current_State=1;
			config_count[15:0]=16'b0;
		end
		1:
		begin
			if(SRAM_hint)
			begin
				Config_read_sram=0;
				config_len[15:0]=Data_from_sram; //读取两个字节的长度（整个配置的长度）
				Byte_flag_config=0;
				config_cmd_start_flag=0;
				Main_Current_State=2;
			end
		end
		2://命令循环
		begin
			Config_read_sram=1;
			Main_Current_State=3;
		end
		3://1.判断一条命令是否完毕并发送；
		begin
			if(SRAM_hint)
			begin
				Config_read_sram=0;
				if(!config_cmd_start_flag)
				begin
					config_cmd_len=Data_from_sram[15:8];//第一个字节是长度
					config_cmd_start_flag=1;
					Main_Cmd_Data[7:0]=Data_from_sram[7:0];
					config_count_percmd=1'b1;//已有一个字节
					Byte_flag_config=0;
					if(config_cmd_len==1'b1)
					begin
						config_cmd_start_flag=0;
						Main_Current_State=4;//发送已经取出的命令
					end
					else
					begin
						Main_Current_State=2;//取出后续字节
					end

				end
				else //if(!config_cmd_start_flag)
				begin
					//一条命令还没有完毕，只需判断是有一个字节还是二个字节
					//Main_Cmd_Data[(config_count_percmd*8+7):(config_count_percmd*8)]=Data_from_sram[15:8];
					Main_Cmd_Data[(config_count_percmd*8) +:8]=Data_from_sram[15:8];
					config_count_percmd=config_count_percmd+1'b1;
					if(config_count_percmd==config_cmd_len)
					begin
						//一条命令完毕，第二个字节是下一条命令的长度
						Byte_flag_config=~Byte_flag_config;
						config_cmd_len_next=Data_from_sram[7:0];
						config_cmd_start_flag=1;
						Main_Current_State=4;//发送已经取出的命令
					end
					else
					begin
						//这次取出的两个字节都是本条命令的
						//Main_Cmd_Data[(config_count_percmd*8+7):(config_count_percmd*8)]=Data_from_sram[7:0];
						Main_Cmd_Data[(config_count_percmd*8) +:8]=Data_from_sram[7:0];
						config_count_percmd=config_count_percmd+1'b1;
						Byte_flag_config=0;
						if(config_count_percmd==config_cmd_len)
						begin
							//一条命令完毕
							
							config_cmd_start_flag=0;
							Main_Current_State=4;//发送已经取出的命令
						end
						else
						begin
							Main_Current_State=2;//本命令还未结束，取下两个字节。
						end
					end ////end else		
				end  ////end else
			end ////end if(!config_cmd_start_flag)
		end ////end case
		4: //1.先发送已经完成的命令 2.判断整个配置是否读取完毕。
		begin
			Main_Data_len=config_cmd_len;
			Main_Return_len=0;
			Main_Cmd=1;
			Main_start=1;
			Main_Current_State=5;
		end
		5:
		begin
			
			Main_Current_State=6;
		end
		6:
		begin
			if(spi_op_done_main)
			begin
				Main_start=0;
				config_count_percmd=0;
				if(Byte_flag_config==1'b1)
				begin
					config_cmd_len=config_cmd_len_next;
				end
				//config_len=config_len-config_cmd_len-1'b1;//发完了一条命令（还有1字节的长度，所以要加1）
				config_count=config_count+config_cmd_len+1'b1;
				//if(!config_len)
				if(config_count>=config_len)
				begin
					//读取配置文件完毕，提示SRAM重置config读取指针
					Config_read_sram_done=1;
					Main_Current_State=7;
				end
				else
				begin
					Main_Current_State=2;
				end
			end
		end
		7:
		begin
			Config_read_sram_done=0;
			Main_Current_State=8;
		end

		//===set_frr_ctl(void)====
		8:
		begin
			Main_Cmd_Data[7:0]=8'h11;
			Main_Cmd_Data[15:8]=8'h02;
			Main_Cmd_Data[23:16]=8'h04;
			Main_Cmd_Data[31:24]=8'h00;
			Main_Cmd_Data[39:32]=8'h04; //INT_PH_PEND
			Main_Cmd_Data[47:40]=8'h06; //INT_MODEM_PEND
			Main_Cmd_Data[55:48]=8'h0a; //LATCHED_RSSI
			Main_Cmd_Data[63:56]=8'h00;
			Main_Cmd=1;
			Main_start=1;
			Main_Data_len=8;
			Main_Return_len=0;
			Main_Current_State=9;
		end
		9:
		begin
			if(spi_op_done_main)
			begin
				Main_start=0;
				//Main_Current_State=11;
				Main_Current_State=14;
			end
		end
		//===Function_set_tran_property()====
/*		11:
		begin
			Main_Cmd_Data[7:0]=8'h11;
			Main_Cmd_Data[15:8]=8'h12;
			Main_Cmd_Data[23:16]=8'h01;
			Main_Cmd_Data[31:24]=8'h06;
			Main_Cmd_Data[39:32]=8'h80;
			Main_Cmd=1;
			Main_start=1;
			Main_Data_len=5;
			Main_Return_len=0;
			Main_Current_State=12;
		end
		12:
		begin
			
			Main_Current_State=13;
		end
		13:
		begin
			if(spi_op_done_main)
			begin
				Main_start=0;
				Main_Current_State=14;
			end
		end */
		14:
		begin
			Main_Cmd_Data[7:0]=8'h11;
			Main_Cmd_Data[15:8]=8'h12;
			Main_Cmd_Data[23:16]=8'h03;
			Main_Cmd_Data[31:24]=8'h08;
			Main_Cmd_Data[39:32]=8'h0a;
			Main_Cmd_Data[47:40]=8'h01;
			Main_Cmd_Data[55:48]=8'h00;
			Main_Cmd=1;
			Main_start=1;
			Main_Data_len=7;
			Main_Return_len=0;
			Main_Current_State=15;
		end
		15:
		begin
			if(spi_op_done_main)
			begin
				Main_start=0;
				Main_Current_State=16;
			end
		end
		16:
		begin
			Main_Cmd_Data[7:0]=8'h11;
			Main_Cmd_Data[15:8]=8'h12;
			Main_Cmd_Data[23:16]=8'h01;
			Main_Cmd_Data[31:24]=8'h10;
			Main_Cmd_Data[39:32]=8'ha2;//CRC
			Main_Cmd=1;
			Main_start=1;
			Main_Data_len=5;
			Main_Return_len=0;
			Main_Current_State=17;
		end
		17:
		begin
			if(spi_op_done_main)
			begin
				Main_start=0;
				Main_Current_State=18;
			end
		end
		18:
		begin
			Main_Cmd_Data[7:0]=8'h11;
			Main_Cmd_Data[15:8]=8'h12;
			Main_Cmd_Data[23:16]=8'h02;
			Main_Cmd_Data[31:24]=8'h21;
			Main_Cmd_Data[39:32]=8'h00;
			Main_Cmd_Data[47:40]=8'h01;
			//Main_Cmd_Data[55:48]=8'h00;
			//Main_Cmd_Data[63:56]=8'h82;//CRC
			Main_Cmd=1;
			Main_start=1;
			Main_Data_len=6;
			Main_Return_len=0;
			Main_Current_State=19;
		end
		19:
		begin
			if(spi_op_done_main)
			begin
				Main_start=0;
				Main_Current_State=20;
			end
		end
		20:
		begin
			Main_Cmd_Data[7:0]=8'h11;
			Main_Cmd_Data[15:8]=8'h12;
			Main_Cmd_Data[23:16]=8'h01;
			Main_Cmd_Data[31:24]=8'h24;//PKT_RX_FIELD_1_CRC_CONFIG
			Main_Cmd_Data[39:32]=8'h82;//CRC
			Main_Cmd=1;
			Main_start=1;
			Main_Data_len=5;
			Main_Return_len=0;
			Main_Current_State=21;		
		end
		21:
		begin
			if(spi_op_done_main)
			begin
				Main_start=0;
				Main_Current_State=22;
			end		
		end
		22:
		begin
			Main_Cmd_Data[7:0]=8'h11;
			Main_Cmd_Data[15:8]=8'h12;
			Main_Cmd_Data[23:16]=8'h02;
			Main_Cmd_Data[31:24]=8'h25;
			Main_Cmd_Data[39:32]=8'h00;
			Main_Cmd_Data[47:40]=8'hfa;
			//Main_Cmd_Data[55:48]=8'h00;
			//Main_Cmd_Data[63:56]=8'h0a;//CRC
			Main_Cmd=1;
			Main_start=1;
			Main_Data_len=6;
			Main_Return_len=0;
			Main_Current_State=23;
		end
		23:
		begin
			if(spi_op_done_main)
			begin
				Main_start=0;
				Main_Current_State=24;
			end
		end
		24:
		begin
			Main_Cmd_Data[7:0]=8'h11;
			Main_Cmd_Data[15:8]=8'h12;
			Main_Cmd_Data[23:16]=8'h01;
			Main_Cmd_Data[31:24]=8'h28;//PKT_RX_FIELD_2_CRC_CONFIG
			Main_Cmd_Data[39:32]=8'h0a;//CRC
			Main_Cmd=1;
			Main_start=1;
			Main_Data_len=5;
			Main_Return_len=0;
			Main_Current_State=25;				
		end
		25:
		begin
			if(spi_op_done_main)
			begin
				Main_start=0;
				Main_Current_State=26;
			end
		end
		26://PKT_TX_THRESHOLD
		begin
			Main_Cmd_Data[7:0]=8'h11;
			Main_Cmd_Data[15:8]=8'h12;
			Main_Cmd_Data[23:16]=8'h02;
			Main_Cmd_Data[31:24]=8'h0b;
			Main_Cmd_Data[39:32]=`TX_THRESHOLD;//8'h23;
			Main_Cmd_Data[47:40]=`RX_THRESHOLD;//8'h30;
			Main_Cmd=1;
			Main_start=1;
			Main_Data_len=6;
			Main_Return_len=0;
			Main_Current_State=27;
		end
		27:
		begin
			
			Main_Current_State=28;
		end
		28:
		begin
			if(spi_op_done_main)
			begin
				Main_start=0;
				Main_Current_State=29;
			end
		end
		29://GLOBAL_CONFIG
		begin
			Main_Cmd_Data[7:0]=8'h11;
			Main_Cmd_Data[15:8]=8'h00;
			Main_Cmd_Data[23:16]=8'h01;
			Main_Cmd_Data[31:24]=8'h03;
			Main_Cmd_Data[39:32]=8'h60;//SPLIT_FIFO
			Main_Cmd=1;
			Main_start=1;
			Main_Data_len=5;
			Main_Return_len=0;
			Main_Current_State=30;
		end
		30:
		begin
			
			Main_Current_State=31;
		end
		31:
		begin
			if(spi_op_done_main)
			begin
				Main_start=0;
				Main_Current_State=32;
			end
		end
		32: //循环校验 CRC
		begin
			Main_Cmd_Data[7:0]=8'h11;
			Main_Cmd_Data[15:8]=8'h12;
			Main_Cmd_Data[23:16]=8'h01;
			Main_Cmd_Data[31:24]=8'h00;
			Main_Cmd_Data[39:32]=8'h83;
			Main_Cmd=1;
			Main_start=1;
			Main_Data_len=5;
			Main_Return_len=0;
			Main_Current_State=33;
		end
		33:
		begin
			
			Main_Current_State=34;
		end
		34:
		begin
			if(spi_op_done_main)
			begin
				Main_start=0;
				Main_Current_State=40;
			end
		end
		
		/*
		157:
		begin
			Main_Cmd_Data[7:0]=8'h11;
			Main_Cmd_Data[15:8]=8'h30;
			Main_Cmd_Data[23:16]=8'h0c;
			Main_Cmd_Data[31:24]=8'h00;
			Main_Cmd_Data[39:32]=8'haa;//1
			Main_Cmd_Data[47:40]=8'hff;
			Main_Cmd_Data[55:48]=8'h41;
			Main_Cmd_Data[63:56]=8'h0F;//2
			Main_Cmd_Data[71:64]=8'hff;
			Main_Cmd_Data[79:72]=8'h02;
			Main_Cmd_Data[87:80]=8'h55;//3
			Main_Cmd_Data[95:88]=8'hff;
			Main_Cmd_Data[103:96]=8'h03;
			Main_Cmd_Data[111:104]=8'hf0;//4
			Main_Cmd_Data[119:112]=8'hff;
			Main_Cmd_Data[127:120]=8'h04;
			Main_Cmd=1;
			Main_start=1;
			Main_Data_len=16;
			Main_Return_len=0;
			Main_Current_State=158;
		end
		158:
		begin
			Main_start=0;
			Main_Current_State=159;
		end
		159:
		begin
			if(spi_op_done)
			begin
				Main_Current_State=160;
			end
		end*/

		
		//需要重置FIFO
		40:
		begin
			Main_Cmd_Data[7:0]=8'h15;
			Main_Cmd_Data[15:8]=8'h03;
			Main_Data_len=2;
			Main_Return_len=0;
			Main_Cmd=1;
			Main_start=1;
			Main_Current_State=41;
		end
		41:
		begin
			
			Main_Current_State=42;
		end
		42:
		begin
			if(spi_op_done_main)
			begin
				Main_start=0;
				Main_Current_State=50;
			end
		end
		
		//检查当前状态是否为Ready
		50:
		begin
			Main_Cmd_Data[7:0]=8'h33;
			Main_Cmd_Data[15:8]=8'h00;
			Main_Data_len=2;
			Main_Return_len=2;
			Main_Cmd=1;
			Main_start=1;
			Main_Current_State=51;
		end
		51:
		begin
			
			Main_Current_State=52;
		end
		52:
		begin
			
			if(spi_op_done_main)
			begin
				Main_start=0;
				if(Main_Return_Data[15:8]==8'h03)
				begin
					tx_state=3'b000;
					Main_Current_State=54;
				end
				else
				begin
					Main_Current_State=53;
					config_cmd_start_flag=0;
					Config_read_sram_done=1;
				end
			end
		end
		53:
		begin
			Config_read_sram_done=0;
			reset_n=0;
			Main_Current_State=0;
		end
		
		//状态转化为RX
		54:
		begin
			if(!spi_Using_wire)
			begin
				Main_Cmd_Data[7:0]=8'h32;
				Main_Cmd_Data[15:8]=8'h00;
				Main_Cmd_Data[23:16]=8'h00;
				Main_Cmd_Data[31:24]=8'h00;
				Main_Cmd_Data[39:32]=8'h00;
				Main_Cmd_Data[47:40]=8'h00;
				Main_Cmd_Data[55:48]=8'h06;
				Main_Cmd_Data[63:56]=8'h06;
				Main_Data_len=8;
				Main_Return_len=0;
				Main_Cmd=1;
				Main_start=1;
				Main_Current_State=55;
			end
		end
		55:
		begin
			
			Main_Current_State=56;
		end
		56:
		begin
			if(spi_op_done_main)
			begin
				Main_start=0;
				enable_irq=1;   //开始允许监听中断信号
				led[2]=1;
				tx_state=`RX;
				Main_Current_State=60;
			end
		end
		
		/*
		183:
		begin
			Main_Cmd_Data[7:0]=8'h33;
			Main_Cmd_Data[15:8]=8'h00;
			Main_Data_len=2;
			Main_Return_len=2;
			Main_Cmd=1;
			Main_start=1;
			Main_Current_State=184;
		end
		184:
		begin
			Main_start=0;
			Main_Current_State=185;
		end
		185:
		begin
			
			if(spi_op_done)
			begin
				//Si4463_Ph_Status_1=Main_Return_Data[15:8];
				if(Main_Return_Data[15:8]==8'h08)
				begin
					tx_state=`RX;
					Main_Current_State=186;
				end
			end
		end
		
		186:
		begin
			Main_Cmd_Data[7:0]=8'h20;
				Main_Cmd_Data[15:8]=8'hFB;
				Main_Cmd_Data[23:16]=8'h7F;
				Main_Cmd_Data[31:24]=8'h7F;
				Main_start=1;
				Main_Cmd=1;
				Main_Data_len=4;
				Main_Return_len=8;
				Main_Current_State=187;
		end
		187:
		begin
			Main_start=0;
			Main_Current_State=188;
		end
		188:
		begin
			if(spi_op_done)
			begin
				Si4463_Ph_Status_1=Main_Return_Data[47:40];
				Main_Current_State=189;
			end
		end
		189:
		begin
				Main_Cmd_Data[7:0]=8'h15;
				Main_Cmd_Data[15:8]=8'h00;

				Main_start=1;
				Main_Cmd=1;
				Main_Data_len=2;
				Main_Return_len=2;
				Main_Current_State=190;
		end
		190:
		begin
			Main_start=0;
			Main_Current_State=191;
		end
		191:
		begin
			if(spi_op_done)
			begin
				//Si4463_Ph_Status_1=Main_Return_Data[47:40];
				Main_Current_State=186;
			end
		end*/
		
		///////////////////////////////////启动完成，开始发送数据/////////////////////////
		//////////////////////////////////////////////////////////////////////////////
		
		
		////判断是否有数据及数据帧长度,如果想要读取数据包长度，可以另外设置一条命令，从SPI中读取SRAM
		////判断是否有待发送的命令
		60:
		begin
			if(Cmd_waiting)
			begin
				Cmd_read_sram=1;
				cmd_count=0;
				Main_Current_State=61;
			end
			else if(!SRAM_empty&&!spi_Using_wire&&!irq_dealing_wire&&packets_incoming_wire==0)
			begin
//				enable_irq=0;//关闭中断
				Main_Cmd=5; //read from sram
				Main_start=1;
				Main_Current_State=62;
			end
		end
		61:
		begin
			if(SRAM_hint)
			begin
				//Cmd_waiting读出一条命令的长度
				Cmd_read_sram=0;
				cmd_len=Data_from_sram[15:8];//只有第一个字节有效，第二个字节是0填充
				if(cmd_len==0)
					Main_Current_State=0;
				else
					Main_Current_State=67;
			end
		end
		67:
		begin
			Cmd_read_sram=1;
			Main_Current_State=68;
		end
		68:
		begin
			if(SRAM_hint)
			begin
				Cmd_read_sram=0;
				
				Main_Cmd_Data[(cmd_count*8) +:8]=Data_from_sram[15:8];
				cmd_count=cmd_count+1'b1;
				if(cmd_count==cmd_len)
					Main_Current_State=69;//发送命令
				else
				begin
					Main_Cmd_Data[(cmd_count*8) +:8]=Data_from_sram[7:0];
					cmd_count=cmd_count+1'b1;
					if(cmd_count==cmd_len)
						Main_Current_State=69;//发送命令
					else
						Main_Current_State=67;//继续读取
				end
			end
		end
		69:
		begin
			Main_Data_len=cmd_len;
			Main_Return_len=0;
			Main_Cmd=1;
			Main_start=1;
			Main_Current_State=77;
		end
		77:
		begin
			if(spi_op_done_main)
			begin
				Main_start=0;
				Main_Current_State=60;
			end
		end
		
		62:
		begin
			if(spi_op_done_main)
			begin
				Main_start=0;
				if(Main_Data_Check[15:0]==16'h2dd4)
				begin
					Main_Current_State=63;
				end
				else
				begin
					Main_Current_State=60;
				end
			end
		end
		63:
		begin
			if(!SRAM_empty&&!spi_Using_wire)
			begin
				Main_Cmd=5;
				Main_start=1;
				Main_Current_State=64;
			end
		end
		64:
		begin
			
			Main_Current_State=65;
		end
		65:
		begin
			if(spi_op_done_main)
			begin
				Main_start=0;
				Data_Len_to_Send=Main_Data_Check[7:0];
				Main_Current_State=66;
			end
		end
		66:
		begin
			if(SRAM_count*2>=Data_Len_to_Send)
			begin
//					enable_irq=1;//开启中断
				Main_Current_State=70;
			end	
		end
		
		//设置需要发送的数据包的长度
		70:
		begin
			if(!spi_Using_wire)
			begin
				Main_Cmd_Data[7:0]=8'h11;
				Main_Cmd_Data[15:8]=8'h12;
				Main_Cmd_Data[23:16]=8'h01;
				Main_Cmd_Data[31:24]=8'h0E;
				Main_Cmd_Data[39:32]=Data_Len_to_Send; //已经包含了数据长度的一个字节
				Main_Data_len=5;
				Main_Return_len=0;
				Main_Cmd=1;
				Main_start=1;
				Main_Current_State=71;
			end
		end
		71:
		begin
			
			Main_Current_State=72;
		end
		72:
		begin
			if(spi_op_done_main)
			begin
				Main_start=0;
				Main_Current_State=73;
			end
		end
		//////如果SPI正在被使用则等待，否则将数据写入射频模块缓冲区//////
		73:
		begin

			if(`MAX_FIFO_SIZE > Data_Len_to_Send)
			begin
				Main_Data_len=Data_Len_to_Send+1; //+1是因为SPI控制模块中把0x66命令的一个字节也算进去了
				Data_Sending_Pos=Data_Len_to_Send;
				Data_Sending_Remain_flag=0;
			end
			else
			begin
				Main_Data_len=`MAX_FIFO_SIZE+1; //没有发送完的数据会在后面继续发送，给一个未完全发送的标识
				Data_Sending_Pos=`MAX_FIFO_SIZE;
				Data_Sending_Remain_flag=1;
			end
			Main_Current_State=74;
		end
		74:
		begin
			if(!spi_Using_wire&&!spi_Using_wire&&!irq_dealing_wire&&packets_incoming_wire==0)
			begin
//				enable_irq=0;//关闭中断
				Main_Cmd=2;
				//Main_Data_len=Data_Len_to_Send+1;  
				Main_Return_len=0;
				Main_start=1;
				Main_Current_State=75;
			end
		end
		75:
		begin
			
			Main_Current_State=76;
		end
		76:
		begin
			if(spi_op_done_main)
			begin
				Main_start=0;
//				enable_irq=1;//开启中断
				Main_Current_State=80;
			end
		end
		
		//CCA,LBT,...//
		80:
		begin
			if(!spi_Using_wire&&!irq_dealing_wire&&packets_incoming_wire==0)
			begin
				Main_Cmd=1;
				Main_Cmd_Data[7:0]=8'h22; //GET_MODEM_STATUS
				Main_Cmd_Data[15:8]=8'hff;
				Main_Data_len=2;
				Main_Return_len=3;//only needs 3byte (third is CURR_RSSI)
				Main_start=1;
				Main_Current_State=81;	
			end
		end
		81:
		begin
			
			Main_Current_State=82;
		end
		82:
		begin
			if(spi_op_done_main)
			begin
				Main_start=0;
				Si4463_RSSI_Curr=Main_Return_Data[7:0]; //CURR_RSSI (Reverse sequence of addr 返回3字节，用[7:0]取得最后一个字节)
				if(Si4463_RSSI_Curr>`RSSI_THRESHOLD)
				begin
					delay_mtime_3=rand_num_wire;
					delay_start_3=1;
					Main_Current_State=83;
				end
				else
				begin
					Main_Current_State=90; //开始发送
				end
			end
		end
		83:
		begin
			if(delay_int_3)
			begin
				delay_start_3=0;
				Main_Current_State=80;
			end			
		end
		
		
		/////////发送命令，开始发送数据///////////
		90:
		begin
			if(!spi_Using_wire&&!irq_dealing_wire&&packets_incoming_wire==0)
			begin
				Main_Cmd=1;
				Main_start=1;
				Main_Data_len=5;
				Main_Return_len=0;
				Main_Cmd_Data[7:0]=8'h31;
				Main_Cmd_Data[15:8]=8'h00;
//				if(!Data_Sending_Remain_flag)
//				begin
					Main_Cmd_Data[23:16]=8'h60; //RX_TUNE
//				end
//				else
//				begin
//					Main_Cmd_Data[23:16]=8'h50; //5	TX_TUNE
//				end
				Main_Cmd_Data[31:24]=8'h00;
				Main_Cmd_Data[39:32]=8'h00;
				Main_Current_State=91;
			end
		end
		91:
		begin
			
			Main_Current_State=92;
		end
		92:
		begin
			if(spi_op_done_main)
			begin				
				Main_start=0;
				if(!Data_Sending_Remain_flag)
				begin
					tx_state=`TX;
				end
				else
				begin
					tx_state=`TX_WAIT;
				end
				Main_Current_State=93;
			end
		end
		93:
		begin
			if(Data_Sending_Remain_flag && TX_fifo_almost_empty_flag_wire)
			begin
				Data_Sending_Remain=Data_Len_to_Send-Data_Sending_Pos;
				Main_Current_State=100;			
			end
			else if(tx_done_wire)  //增加超时判断
			begin
				led[3]=~led[3];
				delay_start_2=0;
				//tx_state=`RX;
				Main_Current_State=95;
			end	
			else
			begin
				delay_start_2=1;
				delay_mtime_2=30;
				if(delay_int_2)
				begin
					tx_state=3'b000;
					delay_start_2=0;
					Main_Current_State=0;
				end
				else
				begin
					Main_Current_State=93;
				end
			end
		end
		100:
		begin
			if(Data_Sending_Remain <= `TX_THRESHOLD)
			begin
				//写入剩余的数据
				Main_Data_len=Data_Sending_Remain+1; //+1是因为SPI控制模块中把0x66命令的一个字节也算进去了
				Data_Sending_Pos=Data_Len_to_Send;
				Data_Sending_Remain_flag=0;
			end
			else
			begin
				Main_Data_len=`TX_THRESHOLD+1; //+1是因为SPI控制模块中把0x66命令的一个字节也算进去了
				Data_Sending_Pos=Data_Sending_Pos+`TX_THRESHOLD;
			end
			Main_Current_State=101;
		end
		101:
		begin
			if(!spi_Using_wire)
			begin
				Main_Cmd=2;
				Main_Return_len=0;
				Main_start=1;
				Main_Current_State=102;
			end			
		end
		102:
		begin
			
			Main_Current_State=103;
		end
		103:
		begin
			if(spi_op_done_main)
			begin
				Main_start=0;
				if(!Data_Sending_Remain_flag)
				begin
					tx_state=`TX;
				end
				else
				begin
					tx_state=`TX_WAIT;
				end
				Main_Current_State=93;
			end
		end	
		
		
		
		
		95:
		begin
			//切换到RX状态
			if(!spi_Using_wire)
			begin
				Main_Cmd_Data[7:0]=8'h32;
				Main_Data_len=1;
				Main_Return_len=0;
				Main_Cmd=1;
				Main_start=1;
				Main_Current_State=96;
			end
		end
		96:
		begin
			
			Main_Current_State=97;
		end
		97:
		begin
			if(spi_op_done_main)
			begin
				Main_start=0;
				tx_state=`RX;
				Main_Current_State=60;
			end
		end		

		
		
/*
		///等待时隙///////////
		200:
		begin
			if(GPS_sync_time) //这是一个脉冲，
			begin
				Main_Current_State=142;
			end
		end
*/
		/////////发送命令，开始发送数据///////////
	endcase
	end
end




/////中断处理程序///////////
/*
 *包括中断的检测和接收处理函数
 *中断函数负责检测中断，查询中断状态，以及给发送函数和接收处理函数信号，通知其中断到达，
 *接收函数，负责接收数据，只有一条接收数据的命令
*/
always@(posedge clk or negedge reset_n)
begin
	if(!reset_n)
	begin
		Irq_Current_State=0;

		Syncirq_Current_State=3;

		//tx_flag=0;
		tx_done=0;
		irq_dealing=0;

		Int_start=0;
		//led[0]=1'b0;
		//led[1]=1'b0;
		packets_incoming=0;
		Data_Recv_Pos=0;
		TX_fifo_almost_empty_flag=0;
		RX_fifo_almost_full_flag=0;
	end
	else
	begin
		case (Irq_Current_State)		
			/////等待中断到来
			0:
			begin
				if(enable_irq&&!Si4463_int) //1.初始化完成后才允许中断 2.如果正在发送准备数据，此时不允许接收中断 3.中断信号低电平有效
				begin
					irq_dealing=1;
					Irq_Current_State=1;
				end
			end
			1://获取中断码同时清中断
			begin
				if(!spi_Using_wire)
				begin
					Int_Cmd_Data[7:0]=8'h20;
					Int_Cmd_Data[15:8]=8'h00;
					Int_Cmd_Data[23:16]=8'h00;
					Int_Cmd_Data[31:24]=8'h00;
					Int_start=1;
					Int_Cmd=4;
					Int_Data_len=4;
					Int_Return_len=8;
					Irq_Current_State=2;
				end
			end
			2:
			begin
				
				Irq_Current_State=3;
			end
			3:
			begin
				if(spi_op_done_int)
				begin
					Int_start=0;
					Si4463_Ph_Status=Int_Return_Data[47:40];//PH_PEND
					Si4463_Modem_Status=Int_Return_Data[31:24];
					//加两个中断源：TX_FIFO_ALMOST_EMPTY_PEND; RX_FIFO_ALMOST_FULL_PEND
					if(((Si4463_Ph_Status &8'h32)==8'b00000010) && (tx_state_wire!=`RX) &&(Data_Sending_Remain_flag_wire))//TX_FIFO_ALMOST_EMPTY_PEND
					begin
						TX_fifo_almost_empty_flag=1;
						Irq_Current_State=25;
					end
					
					else if((Si4463_Ph_Status &8'h20)==8'b00100000)
					begin
						Irq_Current_State=4;//发送完成中断
					end
					
					else if((Si4463_Ph_Status&8'h08)==8'b00001000) //CRC_ERROR
					begin
						led[0]=~led[0];
						//重置fifo并进入RX状态
						//最后irq_dealing=0;
						//需要有一个回溯SRAM指针的动作，否则前面已经写入了一部分数据了。
						if(packets_incoming>1)//保证回滚时前面有错误的数据写入了SRAM
							Crc_Error_Rollback=1;
						Irq_Current_State=16;
					end
					
					else if(((Si4463_Ph_Status &8'h31)==8'b00000001) && (tx_state_wire==`RX))//RX_FIFO_ALMOST_FULL_PEND
					begin
						RX_fifo_almost_full_flag=1;
						if(packets_incoming==0)
						begin
							//出错了，没收到中断头就收到了RX_FIFO_ALMOST_FULL_PEND。需要进行错误处理。
							//重置fifo并进入RX状态
							//最后irq_dealing=0;
							Irq_Current_State=16;
						end
						else if(packets_incoming==1)
						begin
							packets_incoming=packets_incoming+1'b1;
							Irq_Current_State=6;
						end
						else
						begin
							packets_incoming=packets_incoming+1'b1;
							Irq_Current_State=27;
						end
						
					end

					else if((Si4463_Ph_Status&8'h10)==8'b00010000) //接收中断
					begin
						led[1]=~led[1];
						RX_fifo_almost_full_flag=0;
						if(packets_incoming==0)
						begin
						//出错，没有收到同步头
							Irq_Current_State=16;
						end
						else if(packets_incoming==1)
						begin
							Irq_Current_State=6;
						end
						else
						begin
							Irq_Current_State=13;
						end
					end
					else if((Si4463_Modem_Status&8'h03)==8'h03) //收到同步头时产生的中断，虽然也可以使用前导码，但是效果并不好，因为射频模块容易被其他设备的发送的前导码干扰
					begin
						packets_incoming=1'b1;
						Data_Recv_Pos=0;
						Syncirq_Current_State=0;
						
						Irq_Current_State=0;
					end
					else
					begin
						Irq_Current_State=0;
						irq_dealing=0;
					end
				end
			end
			4://处理发送中断
			begin
				tx_done=1;
				Irq_Current_State=5;
			end
			5:
			begin
				if(tx_state_wire==`RX) //等待主函数切换为RX状态
				begin
					//tx_flag=0;
					tx_done=0;
					irq_dealing=0;
					Irq_Current_State=0;
				end
			end			
			6://处理接收中断：
			begin
				if(!SRAM_AlmostFull) //剩余的SRAM空间足以容纳一个数据包
				begin
					Pkt_Start_flag=1;
					Irq_Current_State=7;
				end
				else //否则直接放弃改数据包，首先清空FIFO
				begin
					Irq_Current_State=16;
				end
			end
			7://获取该数据包的RSSI值
			begin
				if(!spi_Using_wire)
				begin
					Int_Cmd_Data[7:0]=8'h53; //FRR_C_READ for RSSI LATCHED of SYNC
					Int_start=1;
					Int_Cmd=6;
					Int_Data_len=1;
					Int_Return_len=1;
					Irq_Current_State=8;
				end
			end
			8:
			begin
				Pkt_Start_flag=0;
				
				Irq_Current_State=9;
			end
			9:
			begin
				if(spi_op_done_int)
				begin
					Int_start=0;
					Si4463_RSSI_RecvPacket=Int_Return_Data[7:0];
					Irq_Current_State=10;
				end
			end
			10://写入两个字节的标志位
			begin
				Int_Cmd_Data[7:0]=8'hd4;
				Int_Cmd_Data[15:8]=8'h2d; 
				Int_Data_len=2;
				Int_Return_len=0;
				Int_start=1;
				Int_Cmd=7;
				Irq_Current_State=11;
			end
			11:
			begin
				
				Irq_Current_State=12;
			end
			12:
			begin
				if(spi_op_done_int)
				begin
					Int_start=0;
					Irq_Current_State=13;
				end
			end
			13: //发送接收命令，但是如果直接读取数据，可能会出错，因为如果SRAM已经满则，可能会导致阻塞到接收数据的模块，导致用户无法发送数据。
			begin    //这里涉及缓冲区已满时接收数据的丢弃策略
				if(RX_fifo_almost_full_flag)
				begin
					Int_Data_len=`RX_THRESHOLD-2;//由于SPI_master的cmd=3流程中读取第一个字节（长度）没有算在Int_Data_len上，
														  //所以任然读取`RX_THRESHOLD长度的FIFO在极特殊的情况下会产生FIFO_UNDERRUN的错误（担心）。
														  //减2保证最后一位不会被填充0（还有一个字节的RSSI）
					Data_Recv_Pos=Data_Recv_Pos+`RX_THRESHOLD-1; //对应上一行的解释，这里减1是因为要把报文长度的一个字节算在里面。
					Int_Return_len=0;
					Int_start=1;
					Int_Cmd=3;
					Irq_Current_State=14;//直接结束这次中断处理					
				end
				else if(packets_incoming==1)
				begin
					Int_Data_len=0;//处理数据包长度小于RX_THRESHOLD时的情况，即直接产生了RX中断。
					Int_Return_len=0;
					Int_start=1;
					Int_Cmd=3;
					Irq_Current_State=14;
				end
				else
				begin
					//取出最后剩下的报文部分0<len<RX_THRESHOLD
					Int_Data_len=recv_pkt_len_wire-Data_Recv_Pos+1;
					Int_Return_len=0;
					Int_start=1;
					Int_Cmd=8;
					Irq_Current_State=14;
				end
			end
			14:
			begin
				
				Irq_Current_State=15;
			end
			15:
			begin
				if(spi_op_done_int)
				begin	
					Int_start=0;
					if(!RX_fifo_almost_full_flag)
						Irq_Current_State=19;
					else
						Irq_Current_State=30;
					
				end
			end
			16: //重置FIFO
			begin			
				if(!spi_Using_wire)
				begin
					Int_Cmd_Data[7:0]=8'h15;
					Int_Cmd_Data[15:8]=8'h03; 
					Int_Data_len=2;
					Int_Return_len=0;
					Int_start=1;
					Int_Cmd=4;
					Irq_Current_State=17;
				end
			end
			17:
			begin
				Crc_Error_Rollback=0;
				
				Irq_Current_State=18;
			end
			18:
			begin
				if(spi_op_done_int)
				begin
					Int_start=0;
					Irq_Current_State=20;
				end
			end			

			19:
			begin
				Pkt_Received_flag=1;//给SPI_slave一个脉冲信号说明收到一个完整数据包
				Irq_Current_State=20;
			end
			20://转换到Rx状态
			begin
				Pkt_Received_flag=0;
				Int_Cmd_Data[7:0]=8'h32; 
				Int_Data_len=1;
				Int_Return_len=0;
				Int_start=1;
				Int_Cmd=4;
				Irq_Current_State=21;
			end
			21:
			begin
				if(spi_op_done_int)
				begin	
					Int_start=0;
					//rx_start=0;
					//packets_incoming=0;
					//frame_recved_int=1;
					Irq_Current_State=22;
				end
			end
			22://查看状态转化是否成功
			begin
				Int_Cmd_Data[7:0]=8'h33;
				Int_Data_len=1;
				Int_Return_len=2;
				Int_start=1;
				Int_Cmd=4;
				Irq_Current_State=23;
			end
			23:
			begin
				
				Irq_Current_State=24;
			end
			24:
			begin
				if(spi_op_done_int)
				begin
					Int_start=0;
					if(Int_Return_Data[15:8]==8'h08)
					begin
						packets_incoming=0;
						//frame_recved_int=1;
						Syncirq_Current_State=3;
						irq_dealing=0;//完成中断流程
						Irq_Current_State=0;
					end
					else
					begin
						Irq_Current_State=19;
					end		
				end
			end
			//
			25:
			begin
				Irq_Current_State=26;//脉冲持续一个周期
			end
			26:
			begin
				irq_dealing=0;//完成中断流程
				TX_fifo_almost_empty_flag=0;
				Irq_Current_State=0;
			end
			27://读RX_THRESHOLD长度的RX_FIFO
			begin
				Int_Data_len=`RX_THRESHOLD;
				Int_Return_len=0;
				Int_start=1;
				Int_Cmd=8;
				Data_Recv_Pos=Data_Recv_Pos+`RX_THRESHOLD;
				Irq_Current_State=28;
			end
			28:
			begin
				
				Irq_Current_State=29;
			end
			29:
			begin
				if(spi_op_done_int)
				begin		
					Int_start=0;
					Irq_Current_State=30;
					
				end
			end
			30:
			begin
				RX_fifo_almost_full_flag=0;
				irq_dealing=0;//完成中断流程
				Irq_Current_State=0;
			end
		endcase
		
		///////检测同步头中断后没有收包中断/////
		/* 清空FIFO，重新进入RX状态，最后清除packets_incoming*/
		case (Syncirq_Current_State)
			0:
			begin
				if(packets_incoming)
				begin
					delay_start_4=1;
					delay_mtime_4=`SYNC_IRQ_TIMEOUT;
					if(delay_int_4)
					begin
						
						delay_start_4=0;
						Syncirq_Current_State=1;
					end
				end
			end
			1://恢复状态
			begin
				Irq_Current_State=16;
				Syncirq_Current_State=3;
			end
			3:
			begin
				delay_start_4=0;
			end
		endcase
	end//if(!reset_n)
end

/**
* 伪随机数产生器，255个状态
* http://www.cnblogs.com/BitArt/archive/2012/12/22/2827005.html
*/

reg          load=1;     /*load seed to rand_num,active high */
reg [7:0]    seed=8'b10110110;     
reg [7:0]    rand_num;  /*random number output*/
wire[7:0]	 rand_num_wire;
assign rand_num_wire=rand_num;

always@(posedge clk or negedge reset_n)
begin
    if(!reset_n)
        rand_num    <=8'b0;
    else if(load)
        rand_num <=seed;    /*load the initial value when load is active*/
    else
        begin
            rand_num[0] <= rand_num[7];
            rand_num[1] <= rand_num[0];
            rand_num[2] <= rand_num[1];
            rand_num[3] <= rand_num[2];
            rand_num[4] <= rand_num[3]^rand_num[7];
            rand_num[5] <= rand_num[4]^rand_num[7];
            rand_num[6] <= rand_num[5]^rand_num[7];
            rand_num[7] <= rand_num[6];
        end
            
end


`define CLK_COUNT_PER_MS 100000
/////延时函数1///////////////
reg delay_start=0;
reg[31:0] delay_count=0;
reg[7:0] delay_mtime=0;
reg delay_int=0;


always@(posedge clk)
begin
	if(!delay_start)
	begin
		delay_count<=0;
		delay_int<=1'b0;
	end
	else
	begin
		delay_count<=delay_count+1'b1;
		if(delay_count==delay_mtime*`CLK_COUNT_PER_MS)
			delay_int<=1'b1;
	end
end

/////延时函数2///////////////
reg delay_start_2=0;
reg[31:0] delay_count_2=0;
reg[7:0] delay_mtime_2=0;
reg delay_int_2=0;

always@(posedge clk)
begin
	if(!delay_start_2)
	begin
		delay_count_2<=0;
		delay_int_2<=1'b0;
	end
	else
	begin
		delay_count_2<=delay_count_2+1'b1;
		if(delay_count_2==delay_mtime_2*`CLK_COUNT_PER_MS) 
			delay_int_2<=1'b1;
	end
end

/////延时函数3///////////////
reg delay_start_3=0;
reg[31:0] delay_count_3=0;
reg[7:0] delay_mtime_3=0;
reg delay_int_3=0;

always@(posedge clk)
begin
	if(!delay_start_3)
	begin
		delay_count_3<=0;
		delay_int_3<=1'b0;
	end
	else
	begin
		delay_count_3<=delay_count_3+1'b1;
		if(delay_count_3==delay_mtime_3*1000) //配合随机数生成器使用
			delay_int_3<=1'b1;
	end
end

/////延时函数4///////////////
reg delay_start_4=0;
reg[31:0] delay_count_4=0;
reg[7:0] delay_mtime_4=0;
reg delay_int_4=0;

always@(posedge clk)
begin
	if(!delay_start_4)
	begin
		delay_count_4<=0;
		delay_int_4<=1'b0;
	end
	else
	begin
		delay_count_4<=delay_count_4+1'b1;
		if(delay_count_4==delay_mtime_4*`CLK_COUNT_PER_MS) 
			delay_int_4<=1'b1;
	end
end

endmodule
