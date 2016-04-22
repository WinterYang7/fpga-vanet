

module Wireless_Ctrl(
	clk,
	
	//SRAM接口
	SRAM_read,
	SRAM_write,
	SRAM_full,
	SRAM_hint,
	SRAM_empty,
	SRAM_count,
	Data_to_sram,
	Data_from_sram,
	
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
	frame_recved_int,
	
	//用于指示当前状态的LED
	led,
	Si4463_Ph_Status_1
);
input clk;
output reg[7:0] Si4463_Ph_Status_1;
//assign Si4463_Ph_Status_1=Main_Current_State;
output reg [3:0] led=4'b0000;

	//SRAM接口
output	SRAM_read;
output	SRAM_write;
input	SRAM_full;
input	SRAM_hint;
input	SRAM_empty;
input[10:0]	SRAM_count;
output[15:0]	Data_to_sram;
input[15:0]	Data_from_sram;
output reg frame_recved_int=0;
	
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


reg reset_n=1;


//中断处理函数的信号
reg [3:0] Irq_Current_State=0;
reg [3:0] Recv_Current_State=0;
reg tx_done=0; //置1表示发送完成
reg rx_start=0;
reg tx_flag=0; //是发送完成中断
reg rx_flag=0;
reg packet_incoming=0; //指示射频模块收到包但还未收到接收数据包的中断
reg [7:0] Si4463_Ph_Status=0;
reg [7:0] Si4463_Modem_Status=0;
reg [7:0] frame_len;


/////延时函数1///////////////
reg delay_start=0;
reg[31:0] delay_count=0;
reg[7:0] delay_mtime=8'h00;
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
		if(delay_count==delay_mtime*20000) //20000可以算1ms
			delay_int<=1'b1;
	end
end

/////延时函数2///////////////
reg delay_start_2=0;
reg[31:0] delay_count_2=0;
reg[7:0] delay_mtime_2=8'h00;
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
		if(delay_count_2==delay_mtime_2*20000) //20000可以算1ms
			delay_int_2<=1'b1;
	end
end


//////接口
/*
	main_data_len[]   主进程需要发送的字节数
	int_data_len[]    中断进程需要发送的字节数
	
	Main_Start_data[79:0]  启动配置的数组
	spi_cmd[]   需要进行的操作
				1 main程序启动配置和gteCTS
				2 main发送数据帧
				3 int接收数据帧
				4 int 获取中断状态
				5 main程序从SRAM中读取数据，唯一的用途是获取需要发送的数据
				6 int读快速寄存器
	spi_Using  bool值，代表spi模块是否正在被使用
	spi_start  bool值，设置为1，代表准备开始发送或接收数据
*/
reg [127:0] Main_Cmd_Data;  //主程序中的命令缓冲，包括启动配置和GetCTS
reg [31:0] Int_Cmd_Data;   //中断程序中的命令缓冲，主要是查看寄存器状态和GetCTS
reg [79:0] Main_Return_Data;  //返回数据的缓冲区
reg [79:0] Int_Return_Data;   //要接收的数据长度
reg [7:0] Main_Data_len;  //要发送的数据长度
reg [4:0] Main_Return_len;  //GetCTS后返回的数据长度
reg [7:0] Int_Data_len;
reg [3:0] Int_Return_len;
reg [2:0] Main_Cmd;   //主函数中的命令
reg [2:0] Int_Cmd;	//中断函数中的命令
reg Main_start;  //Main表示想要开始发送数据，需要提前检查Spi_Using
reg Int_start;   //Int表示想要开始发送数据，需要提前检查Spi_Using
reg[31:0] Main_Data_Check=0;


reg [127:0] spi_cmd_data;
reg [7:0] spi_data_len=0;
reg [4:0] spi_return_len=0;
reg [2:0] spi_cmd=0;
reg spi_Using=0;
reg spi_start=0; //主要是监听Main_start和Int_start脉冲，当任意一个脉冲为1时，置1
reg [7:0] Sended_count=0; //已经发送的字节数
reg spi_op_done=0; //用于指示spi的操作是否已经完成
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
wire [10:0] SRAM_count;  //说明FIFO_o中的数据个数
reg [15:0] Data_to_sram;
wire [15:0] Data_from_sram;
reg [15:0] Data_from_sram_reg=0;
wire SRAM_hint;
reg Byte_flag=0;
reg GetCTS_flag=0;


reg [15:0] master_control_reg;

assign master_spi_sel=1;

reg [5:0] Spi_Current_State;
reg Ended_flag;
reg frame_len_flag; //标志着接收包时第一个字节，即包的长度
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
		GetCTS_flag=0;
		Byte_flag=0;
		spi_op_fifo_flag=1;
		Ended_flag=0;
	end
else
begin
	if(Main_start&&!spi_Using)
	begin
		spi_start=1;
		spi_cmd=Main_Cmd;
		spi_data_len=Main_Data_len;
		spi_return_len=Main_Return_len;
		spi_cmd_data=Main_Cmd_Data;
	end
	if(Int_start&&!spi_Using)
	begin
		spi_start=1;
		spi_cmd=Int_Cmd;
		spi_data_len=Int_Data_len;
		spi_return_len=Int_Return_len;
		spi_cmd_data=Int_Cmd_Data;
	end

	if(!spi_Using&&spi_start)
	begin
		if(Spi_Current_State==0)
		begin	
			case (spi_cmd) //这里有点多余，可以简单删除一下
				1:
				begin
					Spi_Current_State=1;
					spi_Using=1;
					spi_op_done=0;
				end
				2:
				begin
					Spi_Current_State=1;
					spi_Using=1;
					spi_op_done=0;
				end
				3:
				begin
					Spi_Current_State=1;
					spi_Using=1;
					spi_op_done=0;
				end
				4:
				begin
					Spi_Current_State=1;
					spi_Using=1;
					spi_op_done=0;
				end
				5:
				begin
					spi_Using=1;
					Spi_Current_State=36;
					spi_op_done=0;
				end
				6:
				begin
					Spi_Current_State=1;
					spi_Using=1;
					spi_op_done=0;
				end
				default:
				begin
					spi_start=0;
					Spi_Current_State=0;
					spi_Using=0;
					spi_op_done=0;
				end
			endcase
			GetCTS_flag=0;
			Byte_flag=0;
			spi_op_fifo_flag=1;
			Ended_flag=0;
		end
	end
	
	if(spi_Using&&spi_start)
	begin

		case (Spi_Current_State)
		
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
				if(spi_cmd==2||spi_cmd==3 ||Ended_flag || spi_cmd==6) //发送和接收数据帧不需要GetCTS
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
				
					Data_to_master=16'h0044;
					master_mem_addr=3'b001;
					master_write_n=0;
					Spi_Current_State=17;
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
				if(Data_from_master[7:0]==16'h00ff)
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
				Spi_Current_State=33; 
			end
			31:
			begin
				if(!Byte_flag)
				begin
					Data_to_sram[15:8]=Data_from_master[7:0];
					if(frame_len_flag) //接收到的第一个字节为长度（不包括自身）
					begin
						Byte_flag=~Byte_flag;
						frame_len_flag=0;
						Sended_count=0;
						spi_data_len=Data_from_master[7:0];
						Spi_Current_State=22;
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
			
			33: //发送接收数据命令，发送完之后，可能需要等待一段时间来给射频准备数据，不过测试之后再说
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
				Spi_Current_State=37;
			end
			37:
			begin
				if(SRAM_hint)
				begin
					SRAM_read=0;
					Main_Data_Check[31:16]=Data_from_sram; //读取命令0x66 0x00
					Spi_Current_State=38;
				end
			end
			38:
			begin
				SRAM_read=1;
				Spi_Current_State=39;
			end
			39:
			begin
				if(SRAM_hint)
				begin
					SRAM_read=0;
					Main_Data_Check[15:0]=Data_from_sram; //读取数据长度
					spi_Using=0;
					spi_start=0;
					spi_op_done=1;
					Spi_Current_State=0;
				end
			end
			
			//读取快速寄存器
			40:
			begin
				Data_to_master={8'h00,Int_Cmd_Data[7:0]};
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
		endcase
	end
end
end

reg GPS_sync_time=1'b1;  ////需要接GPS同步时钟
reg [7:0] Main_Current_State=8'h00;
reg Si4463_reset=1'b1; //当程序启动或者wireless_ctrl置位时，设置为0
wire Si4463_int;
reg [2:0] tx_state=3'b000;  //0为默认，1表示rx, 2表示tx_tune，3表示tx
reg[7:0] Data_Len_to_Send=8'h00;
reg enable_irq=1'b0; //初始化完成后，才允许触发中断函数
`define RX 3'b001
`define TX_TUNE 3'b010
`define TX 3'b011

always@(posedge clk)
begin
		case(Main_Current_State) 
		0:
		begin
			Si4463_reset=1;
			delay_start=1;
			delay_mtime=10;
			reset_n=0;
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
			Main_Cmd_Data[7:0]=8'h02;
			Main_Cmd_Data[15:8]=8'h01;
			Main_Cmd_Data[23:16]=8'h00;
			Main_Cmd_Data[31:24]=8'h01;
			Main_Cmd_Data[39:32]=8'hC9;
			Main_Cmd_Data[47:40]=8'hC3;
			Main_Cmd_Data[55:48]=8'h80;
			Main_Data_len=7;
			Main_Return_len=0;
			Main_Cmd=1;
			Main_start=1;
			Main_Current_State=1;
		end
		1:
		begin
			Main_start=0;
			Main_Current_State=2;
		end
		2:
		begin
			
			if(spi_op_done)
			begin
				//delay_start=1;
				//delay_mtime=20;
				//if(delay_int)
				//begin
					//delay_start=0;
					Main_Current_State=6;
				//end
				
			end
		end
	
/*	
		3:
		begin
			Main_Cmd_Data[7:0]=8'h02;
			Main_Cmd_Data[15:8]=8'h01;
			Main_Cmd_Data[23:16]=8'h00;
			Main_Cmd_Data[31:24]=8'h01;
			Main_Cmd_Data[39:32]=8'hC9;
			Main_Cmd_Data[47:40]=8'hC3;
			Main_Cmd_Data[55:48]=8'h80;
			Main_Data_len=7;
			Main_Return_len=1;
			Main_Cmd=1;
			Main_start=1;
			Main_Current_State=4;
		end
		
		4:
		begin
			Main_start=0;
			Main_Current_State=5;
		end
		5:
		begin
			if(spi_op_done)
			begin
				
				Main_Current_State=6;
			end
		end*/
		
		6:
		begin
			Main_Cmd_Data[7:0]=8'h01;
			Main_Data_len=1;
			Main_Return_len=9;
			Main_Cmd=1;
			Main_start=1;
			Main_Current_State=7;
		end
		7:
		begin
			Main_start=0;
			Main_Current_State=8;
		end
		8:
		begin
			if(spi_op_done)
			begin
				Main_Current_State=9;
			end
		end
		
		9:
		begin
			Main_Cmd_Data[7:0]=8'h20;
			Main_Cmd_Data[15:8]=8'h00;
			Main_Cmd_Data[23:16]=8'h00;
			Main_Cmd_Data[31:24]=8'h00;
			Main_Data_len=4;
			Main_Return_len=9;
			Main_Cmd=1;
			Main_start=1;
			Main_Current_State=10;
		end
		10:
		begin
			Main_start=0;
			Main_Current_State=11;
		end
		11:
		begin
		
			if(spi_op_done)
			begin
				Main_Current_State=12;
			end
		end
		
	////////setRFParameters(),设置射频模块参数(初始化射频模块上的各种寄存器)
	
		//===setRFParameters(void)====
		12:
		begin
			Main_Cmd_Data[7:0]=8'h02;
			Main_Cmd_Data[15:8]=8'h01;
			Main_Cmd_Data[23:16]=8'h00;
			Main_Cmd_Data[31:24]=8'h01;
			Main_Cmd_Data[39:32]=8'hc9;
			Main_Cmd_Data[47:40]=8'hc3;
			Main_Cmd_Data[55:48]=8'h80;
			Main_Cmd=1;
			Main_start=1;
			Main_Data_len=7;
			Main_Return_len=0;
			Main_Current_State=13;
		end
		13:
		begin
			Main_start=0;
			Main_Current_State=14;
		end
		14:
		begin
			if(spi_op_done)
			begin
				Main_Current_State=15;
			end
		end
		15:
		begin
			Main_Cmd_Data[7:0]=8'h13;
			Main_Cmd_Data[15:8]=8'h00;
			Main_Cmd_Data[23:16]=8'h00;
			Main_Cmd_Data[31:24]=8'h21;
			Main_Cmd_Data[39:32]=8'h20;
			Main_Cmd_Data[47:40]=8'h00;
			Main_Cmd_Data[55:48]=8'h00;
			Main_Cmd_Data[63:56]=8'h00;
			Main_Cmd=1;
			Main_start=1;
			Main_Data_len=8;
			Main_Return_len=0;
			Main_Current_State=16;
		end
		16:
		begin
			Main_start=0;
			Main_Current_State=17;
		end
		17:
		begin
			if(spi_op_done)
			begin
				Main_Current_State=18;
			end
		end
		18:
		begin
			Main_Cmd_Data[7:0]=8'h11;
			Main_Cmd_Data[15:8]=8'h00;
			Main_Cmd_Data[23:16]=8'h02;
			Main_Cmd_Data[31:24]=8'h00;
			Main_Cmd_Data[39:32]=8'h52;
			Main_Cmd_Data[47:40]=8'h00;
			Main_Cmd=1;
			Main_start=1;
			Main_Data_len=6;
			Main_Return_len=0;
			Main_Current_State=19;
		end
		19:
		begin
			Main_start=0;
			Main_Current_State=20;
		end
		20:
		begin
			if(spi_op_done)
			begin
				Main_Current_State=21;
			end
		end
		21:
		begin
			Main_Cmd_Data[7:0]=8'h11;
			Main_Cmd_Data[15:8]=8'h00;
			Main_Cmd_Data[23:16]=8'h01;
			Main_Cmd_Data[31:24]=8'h03;
			Main_Cmd_Data[39:32]=8'h60;
			Main_Cmd=1;
			Main_start=1;
			Main_Data_len=5;
			Main_Return_len=0;
			Main_Current_State=22;
		end
		22:
		begin
			Main_start=0;
			Main_Current_State=23;
		end
		23:
		begin
			if(spi_op_done)
			begin
				Main_Current_State=24;
			end
		end
		24:
		begin
			Main_Cmd_Data[7:0]=8'h11;
			Main_Cmd_Data[15:8]=8'h01;
			Main_Cmd_Data[23:16]=8'h03;
			Main_Cmd_Data[31:24]=8'h00;
			Main_Cmd_Data[39:32]=8'h03;
			Main_Cmd_Data[47:40]=8'h30;
			Main_Cmd_Data[55:48]=8'h01;
			Main_Cmd=1;
			Main_start=1;
			Main_Data_len=7;
			Main_Return_len=0;
			Main_Current_State=25;
		end
		25:
		begin
			Main_start=0;
			Main_Current_State=26;
		end
		26:
		begin
			if(spi_op_done)
			begin
				Main_Current_State=27;
			end
		end
		27:
		begin
			Main_Cmd_Data[7:0]=8'h11;
			Main_Cmd_Data[15:8]=8'h02;
			Main_Cmd_Data[23:16]=8'h04;
			Main_Cmd_Data[31:24]=8'h00;
			Main_Cmd_Data[39:32]=8'h04;
			Main_Cmd_Data[47:40]=8'h06;
			Main_Cmd_Data[55:48]=8'h00;
			Main_Cmd_Data[63:56]=8'h00;
			Main_Cmd=1;
			Main_start=1;
			Main_Data_len=8;
			Main_Return_len=0;
			Main_Current_State=28;
		end
		28:
		begin
			Main_start=0;
			Main_Current_State=29;
		end
		29:
		begin
			if(spi_op_done)
			begin
				Main_Current_State=30;
			end
		end
		30:
		begin
			Main_Cmd_Data[7:0]=8'h11;
			Main_Cmd_Data[15:8]=8'h10;
			Main_Cmd_Data[23:16]=8'h09;
			Main_Cmd_Data[31:24]=8'h00;
			Main_Cmd_Data[39:32]=8'h05;
			Main_Cmd_Data[47:40]=8'h14;
			Main_Cmd_Data[55:48]=8'h00;
			Main_Cmd_Data[63:56]=8'h0f;
			Main_Cmd_Data[71:64]=8'h31;
			Main_Cmd_Data[79:72]=8'h00;
			Main_Cmd_Data[87:80]=8'h00;
			Main_Cmd_Data[95:88]=8'h00;
			Main_Cmd_Data[103:96]=8'h00;
			Main_Cmd=1;
			Main_start=1;
			Main_Data_len=13;
			Main_Return_len=0;
			Main_Current_State=31;
		end
		31:
		begin
			Main_start=0;
			Main_Current_State=32;
		end
		32:
		begin
			if(spi_op_done)
			begin
				Main_Current_State=33;
			end
		end
		33:
		begin
			Main_Cmd_Data[7:0]=8'h11;
			Main_Cmd_Data[15:8]=8'h11;
			Main_Cmd_Data[23:16]=8'h05;
			Main_Cmd_Data[31:24]=8'h00;
			Main_Cmd_Data[39:32]=8'h01;
			Main_Cmd_Data[47:40]=8'hb4;
			Main_Cmd_Data[55:48]=8'h2b;
			Main_Cmd_Data[63:56]=8'h00;
			Main_Cmd_Data[71:64]=8'h00;
			Main_Cmd=1;
			Main_start=1;
			Main_Data_len=9;
			Main_Return_len=0;
			Main_Current_State=34;
		end
		34:
		begin
			Main_start=0;
			Main_Current_State=35;
		end
		35:
		begin
			if(spi_op_done)
			begin
				Main_Current_State=36;
			end
		end
		36:
		begin
			Main_Cmd_Data[7:0]=8'h11;
			Main_Cmd_Data[15:8]=8'h12;
			Main_Cmd_Data[23:16]=8'h07;
			Main_Cmd_Data[31:24]=8'h00;
			Main_Cmd_Data[39:32]=8'h84;
			Main_Cmd_Data[47:40]=8'h01;
			Main_Cmd_Data[55:48]=8'h08;
			Main_Cmd_Data[63:56]=8'hff;
			Main_Cmd_Data[71:64]=8'hff;
			Main_Cmd_Data[79:72]=8'h00;
			Main_Cmd_Data[87:80]=8'h02;
			Main_Cmd=1;
			Main_start=1;
			Main_Data_len=11;
			Main_Return_len=0;
			Main_Current_State=37;
		end
		37:
		begin
			Main_start=0;
			Main_Current_State=38;
		end
		38:
		begin
			if(spi_op_done)
			begin
				Main_Current_State=39;
			end
		end
		39:
		begin
			Main_Cmd_Data[7:0]=8'h11;
			Main_Cmd_Data[15:8]=8'h12;
			Main_Cmd_Data[23:16]=8'h0c;
			Main_Cmd_Data[31:24]=8'h08;
			Main_Cmd_Data[39:32]=8'h2a;
			Main_Cmd_Data[47:40]=8'h01;
			Main_Cmd_Data[55:48]=8'h00;
			Main_Cmd_Data[63:56]=8'h30;
			Main_Cmd_Data[71:64]=8'h30;
			Main_Cmd_Data[79:72]=8'h00;
			Main_Cmd_Data[87:80]=8'h01;
			Main_Cmd_Data[95:88]=8'h04;
			Main_Cmd_Data[103:96]=8'h80;
			Main_Cmd_Data[111:104]=8'h00;
			Main_Cmd_Data[119:112]=8'h07;
			Main_Cmd_Data[127:120]=8'h00;
			Main_Cmd=1;
			Main_start=1;
			Main_Data_len=16;
			Main_Return_len=0;
			Main_Current_State=40;
		end
		40:
		begin
			Main_start=0;
			Main_Current_State=41;
		end
		41:
		begin
			if(spi_op_done)
			begin
				Main_Current_State=42;
			end
		end
		42:
		begin
			Main_Cmd_Data[7:0]=8'h11;
			Main_Cmd_Data[15:8]=8'h12;
			Main_Cmd_Data[23:16]=8'h0c;
			Main_Cmd_Data[31:24]=8'h14;
			Main_Cmd_Data[39:32]=8'h00;
			Main_Cmd_Data[47:40]=8'h00;
			Main_Cmd_Data[55:48]=8'h00;
			Main_Cmd_Data[63:56]=8'h00;
			Main_Cmd_Data[71:64]=8'h00;
			Main_Cmd_Data[79:72]=8'h00;
			Main_Cmd_Data[87:80]=8'h00;
			Main_Cmd_Data[95:88]=8'h00;
			Main_Cmd_Data[103:96]=8'h00;
			Main_Cmd_Data[111:104]=8'h00;
			Main_Cmd_Data[119:112]=8'h00;
			Main_Cmd_Data[127:120]=8'h00;
			Main_Cmd=1;
			Main_start=1;
			Main_Data_len=16;
			Main_Return_len=0;
			Main_Current_State=43;
		end
		43:
		begin
			Main_start=0;
			Main_Current_State=44;
		end
		44:
		begin
			if(spi_op_done)
			begin
				Main_Current_State=45;
			end
		end
		45:
		begin
			Main_Cmd_Data[7:0]=8'h11;
			Main_Cmd_Data[15:8]=8'h12;
			Main_Cmd_Data[23:16]=8'h0c;
			Main_Cmd_Data[31:24]=8'h20;
			Main_Cmd_Data[39:32]=8'h00;
			Main_Cmd_Data[47:40]=8'h00;
			Main_Cmd_Data[55:48]=8'h00;
			Main_Cmd_Data[63:56]=8'h00;
			Main_Cmd_Data[71:64]=8'h00;
			Main_Cmd_Data[79:72]=8'h00;
			Main_Cmd_Data[87:80]=8'h00;
			Main_Cmd_Data[95:88]=8'h00;
			Main_Cmd_Data[103:96]=8'h00;
			Main_Cmd_Data[111:104]=8'h00;
			Main_Cmd_Data[119:112]=8'h00;
			Main_Cmd_Data[127:120]=8'h00;
			Main_Cmd=1;
			Main_start=1;
			Main_Data_len=16;
			Main_Return_len=0;
			Main_Current_State=46;
		end
		46:
		begin
			Main_start=0;
			Main_Current_State=47;
		end
		47:
		begin
			if(spi_op_done)
			begin
				Main_Current_State=48;
			end
		end
		48:
		begin
			Main_Cmd_Data[7:0]=8'h11;
			Main_Cmd_Data[15:8]=8'h12;
			Main_Cmd_Data[23:16]=8'h09;
			Main_Cmd_Data[31:24]=8'h2c;
			Main_Cmd_Data[39:32]=8'h00;
			Main_Cmd_Data[47:40]=8'h00;
			Main_Cmd_Data[55:48]=8'h00;
			Main_Cmd_Data[63:56]=8'h00;
			Main_Cmd_Data[71:64]=8'h00;
			Main_Cmd_Data[79:72]=8'h00;
			Main_Cmd_Data[87:80]=8'h00;
			Main_Cmd_Data[95:88]=8'h00;
			Main_Cmd_Data[103:96]=8'h00;
			Main_Cmd=1;
			Main_start=1;
			Main_Data_len=13;
			Main_Return_len=0;
			Main_Current_State=49;
		end
		49:
		begin
			Main_start=0;
			Main_Current_State=50;
		end
		50:
		begin
			if(spi_op_done)
			begin
				Main_Current_State=51;
			end
		end
		51:
		begin
			Main_Cmd_Data[7:0]=8'h11;
			Main_Cmd_Data[15:8]=8'h20;
			Main_Cmd_Data[23:16]=8'h0c;
			Main_Cmd_Data[31:24]=8'h00;
			Main_Cmd_Data[39:32]=8'h03;
			Main_Cmd_Data[47:40]=8'h00;
			Main_Cmd_Data[55:48]=8'h07;
			Main_Cmd_Data[63:56]=8'h3d;
			Main_Cmd_Data[71:64]=8'h09;
			Main_Cmd_Data[79:72]=8'h00;
			Main_Cmd_Data[87:80]=8'h09;
			Main_Cmd_Data[95:88]=8'hc9;
			Main_Cmd_Data[103:96]=8'hc3;
			Main_Cmd_Data[111:104]=8'h80;
			Main_Cmd_Data[119:112]=8'h00;
			Main_Cmd_Data[127:120]=8'h05;
			Main_Cmd=1;
			Main_start=1;
			Main_Data_len=16;
			Main_Return_len=0;
			Main_Current_State=52;
		end
		52:
		begin
			Main_start=0;
			Main_Current_State=53;
		end
		53:
		begin
			if(spi_op_done)
			begin
				Main_Current_State=54;
			end
		end
		54:
		begin
			Main_Cmd_Data[7:0]=8'h11;
			Main_Cmd_Data[15:8]=8'h20;
			Main_Cmd_Data[23:16]=8'h01;
			Main_Cmd_Data[31:24]=8'h0c;
			Main_Cmd_Data[39:32]=8'h76;
			Main_Cmd=1;
			Main_start=1;
			Main_Data_len=5;
			Main_Return_len=0;
			Main_Current_State=55;
		end
		55:
		begin
			Main_start=0;
			Main_Current_State=56;
		end
		56:
		begin
			if(spi_op_done)
			begin
				Main_Current_State=57;
			end
		end
		57:
		begin
			Main_Cmd_Data[7:0]=8'h11;
			Main_Cmd_Data[15:8]=8'h20;
			Main_Cmd_Data[23:16]=8'h08;
			Main_Cmd_Data[31:24]=8'h18;
			Main_Cmd_Data[39:32]=8'h01;
			Main_Cmd_Data[47:40]=8'h00;
			Main_Cmd_Data[55:48]=8'h08;
			Main_Cmd_Data[63:56]=8'h03;
			Main_Cmd_Data[71:64]=8'h80;
			Main_Cmd_Data[79:72]=8'h00;
			Main_Cmd_Data[87:80]=8'h00;
			Main_Cmd_Data[95:88]=8'h20;
			Main_Cmd=1;
			Main_start=1;
			Main_Data_len=12;
			Main_Return_len=0;
			Main_Current_State=58;
		end
		58:
		begin
			Main_start=0;
			Main_Current_State=59;
		end
		59:
		begin
			if(spi_op_done)
			begin
				Main_Current_State=60;
			end
		end
		60:
		begin
			Main_Cmd_Data[7:0]=8'h11;
			Main_Cmd_Data[15:8]=8'h20;
			Main_Cmd_Data[23:16]=8'h09;
			Main_Cmd_Data[31:24]=8'h22;
			Main_Cmd_Data[39:32]=8'h00;
			Main_Cmd_Data[47:40]=8'h4b;
			Main_Cmd_Data[55:48]=8'h06;
			Main_Cmd_Data[63:56]=8'hd3;
			Main_Cmd_Data[71:64]=8'ha0;
			Main_Cmd_Data[79:72]=8'h07;
			Main_Cmd_Data[87:80]=8'hff;
			Main_Cmd_Data[95:88]=8'h02;
			Main_Cmd_Data[103:96]=8'h00;
			Main_Cmd=1;
			Main_start=1;
			Main_Data_len=13;
			Main_Return_len=0;
			Main_Current_State=61;
		end
		61:
		begin
			Main_start=0;
			Main_Current_State=62;
		end
		62:
		begin
			if(spi_op_done)
			begin
				Main_Current_State=63;
			end
		end
		63:
		begin
			Main_Cmd_Data[7:0]=8'h11;
			Main_Cmd_Data[15:8]=8'h20;
			Main_Cmd_Data[23:16]=8'h07;
			Main_Cmd_Data[31:24]=8'h2c;
			Main_Cmd_Data[39:32]=8'h00;
			Main_Cmd_Data[47:40]=8'h23;
			Main_Cmd_Data[55:48]=8'h8d;
			Main_Cmd_Data[63:56]=8'ha7;
			Main_Cmd_Data[71:64]=8'h00;
			Main_Cmd_Data[79:72]=8'h7c;
			Main_Cmd_Data[87:80]=8'he0;
			Main_Cmd=1;
			Main_start=1;
			Main_Data_len=11;
			Main_Return_len=0;
			Main_Current_State=64;
		end
		64:
		begin
			Main_start=0;
			Main_Current_State=65;
		end
		65:
		begin
			if(spi_op_done)
			begin
				Main_Current_State=66;
			end
		end
		66:
		begin
			Main_Cmd_Data[7:0]=8'h11;
			Main_Cmd_Data[15:8]=8'h20;
			Main_Cmd_Data[23:16]=8'h01;
			Main_Cmd_Data[31:24]=8'h35;
			Main_Cmd_Data[39:32]=8'he2;
			Main_Cmd=1;
			Main_start=1;
			Main_Data_len=5;
			Main_Return_len=0;
			Main_Current_State=67;
		end
		67:
		begin
			Main_start=0;
			Main_Current_State=68;
		end
		68:
		begin
			if(spi_op_done)
			begin
				Main_Current_State=69;
			end
		end
		69:
		begin
			Main_Cmd_Data[7:0]=8'h11;
			Main_Cmd_Data[15:8]=8'h20;
			Main_Cmd_Data[23:16]=8'h09;
			Main_Cmd_Data[31:24]=8'h38;
			Main_Cmd_Data[39:32]=8'h11;
			Main_Cmd_Data[47:40]=8'h10;
			Main_Cmd_Data[55:48]=8'h10;
			Main_Cmd_Data[63:56]=8'h00;
			Main_Cmd_Data[71:64]=8'h1a;
			Main_Cmd_Data[79:72]=8'h0c;
			Main_Cmd_Data[87:80]=8'hcd;
			Main_Cmd_Data[95:88]=8'h00;
			Main_Cmd_Data[103:96]=8'h28;
			Main_Cmd=1;
			Main_start=1;
			Main_Data_len=13;
			Main_Return_len=0;
			Main_Current_State=70;
		end
		70:
		begin
			Main_start=0;
			Main_Current_State=71;
		end
		71:
		begin
			if(spi_op_done)
			begin
				Main_Current_State=72;
			end
		end
		72:
		begin
			Main_Cmd_Data[7:0]=8'h11;
			Main_Cmd_Data[15:8]=8'h20;
			Main_Cmd_Data[23:16]=8'h09;
			Main_Cmd_Data[31:24]=8'h42;
			Main_Cmd_Data[39:32]=8'ha4;
			Main_Cmd_Data[47:40]=8'h03;
			Main_Cmd_Data[55:48]=8'hd6;
			Main_Cmd_Data[63:56]=8'h03;
			Main_Cmd_Data[71:64]=8'h00;
			Main_Cmd_Data[79:72]=8'h33;
			Main_Cmd_Data[87:80]=8'h01;
			Main_Cmd_Data[95:88]=8'h80;
			Main_Cmd_Data[103:96]=8'hff;
			Main_Cmd=1;
			Main_start=1;
			Main_Data_len=13;
			Main_Return_len=0;
			Main_Current_State=73;
		end
		73:
		begin
			Main_start=0;
			Main_Current_State=74;
		end
		74:
		begin
			if(spi_op_done)
			begin
				Main_Current_State=75;
			end
		end
		75:
		begin
			Main_Cmd_Data[7:0]=8'h11;
			Main_Cmd_Data[15:8]=8'h20;
			Main_Cmd_Data[23:16]=8'h01;
			Main_Cmd_Data[31:24]=8'h4c;
			Main_Cmd_Data[39:32]=8'h00;
			Main_Cmd=1;
			Main_start=1;
			Main_Data_len=5;
			Main_Return_len=0;
			Main_Current_State=76;
		end
		76:
		begin
			Main_start=0;
			Main_Current_State=77;
		end
		77:
		begin
			if(spi_op_done)
			begin
				Main_Current_State=78;
			end
		end
		78:
		begin
			Main_Cmd_Data[7:0]=8'h11;
			Main_Cmd_Data[15:8]=8'h20;
			Main_Cmd_Data[23:16]=8'h01;
			Main_Cmd_Data[31:24]=8'h4e;
			Main_Cmd_Data[39:32]=8'h40;
			Main_Cmd=1;
			Main_start=1;
			Main_Data_len=5;
			Main_Return_len=0;
			Main_Current_State=79;
		end
		79:
		begin
			Main_start=0;
			Main_Current_State=80;
		end
		80:
		begin
			if(spi_op_done)
			begin
				Main_Current_State=81;
			end
		end
		81:
		begin
			Main_Cmd_Data[7:0]=8'h11;
			Main_Cmd_Data[15:8]=8'h20;
			Main_Cmd_Data[23:16]=8'h01;
			Main_Cmd_Data[31:24]=8'h51;
			Main_Cmd_Data[39:32]=8'h0a;
			Main_Cmd=1;
			Main_start=1;
			Main_Data_len=5;
			Main_Return_len=0;
			Main_Current_State=82;
		end
		82:
		begin
			Main_start=0;
			Main_Current_State=83;
		end
		83:
		begin
			if(spi_op_done)
			begin
				Main_Current_State=84;
			end
		end
		84:
		begin
			Main_Cmd_Data[7:0]=8'h11;
			Main_Cmd_Data[15:8]=8'h21;
			Main_Cmd_Data[23:16]=8'h0c;
			Main_Cmd_Data[31:24]=8'h00;
			Main_Cmd_Data[39:32]=8'h39;
			Main_Cmd_Data[47:40]=8'h2b;
			Main_Cmd_Data[55:48]=8'h00;
			Main_Cmd_Data[63:56]=8'hc3;
			Main_Cmd_Data[71:64]=8'h7f;
			Main_Cmd_Data[79:72]=8'h3f;
			Main_Cmd_Data[87:80]=8'h0c;
			Main_Cmd_Data[95:88]=8'hec;
			Main_Cmd_Data[103:96]=8'hdc;
			Main_Cmd_Data[111:104]=8'hdc;
			Main_Cmd_Data[119:112]=8'he3;
			Main_Cmd_Data[127:120]=8'hed;
			Main_Cmd=1;
			Main_start=1;
			Main_Data_len=16;
			Main_Return_len=0;
			Main_Current_State=85;
		end
		85:
		begin
			Main_start=0;
			Main_Current_State=86;
		end
		86:
		begin
			if(spi_op_done)
			begin
				Main_Current_State=87;
			end
		end
		87:
		begin
			Main_Cmd_Data[7:0]=8'h11;
			Main_Cmd_Data[15:8]=8'h21;
			Main_Cmd_Data[23:16]=8'h0c;
			Main_Cmd_Data[31:24]=8'h0c;
			Main_Cmd_Data[39:32]=8'hf6;
			Main_Cmd_Data[47:40]=8'hfd;
			Main_Cmd_Data[55:48]=8'h15;
			Main_Cmd_Data[63:56]=8'hc0;
			Main_Cmd_Data[71:64]=8'hff;
			Main_Cmd_Data[79:72]=8'h0f;
			Main_Cmd_Data[87:80]=8'h39;
			Main_Cmd_Data[95:88]=8'h2b;
			Main_Cmd_Data[103:96]=8'h00;
			Main_Cmd_Data[111:104]=8'hc3;
			Main_Cmd_Data[119:112]=8'h7f;
			Main_Cmd_Data[127:120]=8'h3f;
			Main_Cmd=1;
			Main_start=1;
			Main_Data_len=16;
			Main_Return_len=0;
			Main_Current_State=88;
		end
		88:
		begin
			Main_start=0;
			Main_Current_State=89;
		end
		89:
		begin
			if(spi_op_done)
			begin
				Main_Current_State=90;
			end
		end
		90:
		begin
			Main_Cmd_Data[7:0]=8'h11;
			Main_Cmd_Data[15:8]=8'h21;
			Main_Cmd_Data[23:16]=8'h0c;
			Main_Cmd_Data[31:24]=8'h18;
			Main_Cmd_Data[39:32]=8'h0c;
			Main_Cmd_Data[47:40]=8'hec;
			Main_Cmd_Data[55:48]=8'hdc;
			Main_Cmd_Data[63:56]=8'hdc;
			Main_Cmd_Data[71:64]=8'he3;
			Main_Cmd_Data[79:72]=8'hed;
			Main_Cmd_Data[87:80]=8'hf6;
			Main_Cmd_Data[95:88]=8'hfd;
			Main_Cmd_Data[103:96]=8'h15;
			Main_Cmd_Data[111:104]=8'hc0;
			Main_Cmd_Data[119:112]=8'hff;
			Main_Cmd_Data[127:120]=8'h0f;
			Main_Cmd=1;
			Main_start=1;
			Main_Data_len=16;
			Main_Return_len=0;
			Main_Current_State=91;
		end
		91:
		begin
			Main_start=0;
			Main_Current_State=92;
		end
		92:
		begin
			if(spi_op_done)
			begin
				Main_Current_State=93;
			end
		end
		93:
		begin
			Main_Cmd_Data[7:0]=8'h11;
			Main_Cmd_Data[15:8]=8'h22;
			Main_Cmd_Data[23:16]=8'h04;
			Main_Cmd_Data[31:24]=8'h00;
			Main_Cmd_Data[39:32]=8'h08;
			Main_Cmd_Data[47:40]=8'h7f;
			Main_Cmd_Data[55:48]=8'h00;
			Main_Cmd_Data[63:56]=8'h5d;
			Main_Cmd=1;
			Main_start=1;
			Main_Data_len=8;
			Main_Return_len=0;
			Main_Current_State=94;
		end
		94:
		begin
			Main_start=0;
			Main_Current_State=95;
		end
		95:
		begin
			if(spi_op_done)
			begin
				Main_Current_State=96;
			end
		end
		96:
		begin
			Main_Cmd_Data[7:0]=8'h11;
			Main_Cmd_Data[15:8]=8'h23;
			Main_Cmd_Data[23:16]=8'h07;
			Main_Cmd_Data[31:24]=8'h00;
			Main_Cmd_Data[39:32]=8'h01;
			Main_Cmd_Data[47:40]=8'h05;
			Main_Cmd_Data[55:48]=8'h0b;
			Main_Cmd_Data[63:56]=8'h05;
			Main_Cmd_Data[71:64]=8'h02;
			Main_Cmd_Data[79:72]=8'h00;
			Main_Cmd_Data[87:80]=8'h03;
			Main_Cmd=1;
			Main_start=1;
			Main_Data_len=11;
			Main_Return_len=0;
			Main_Current_State=97;
		end
		97:
		begin
			Main_start=0;
			Main_Current_State=98;
		end
		98:
		begin
			if(spi_op_done)
			begin
				Main_Current_State=99;
			end
		end
		99:
		begin
			Main_Cmd_Data[7:0]=8'h11;
			Main_Cmd_Data[15:8]=8'h30;
			Main_Cmd_Data[23:16]=8'h0c;
			Main_Cmd_Data[31:24]=8'h00;
			Main_Cmd_Data[39:32]=8'h00;
			Main_Cmd_Data[47:40]=8'h00;
			Main_Cmd_Data[55:48]=8'h00;
			Main_Cmd_Data[63:56]=8'h00;
			Main_Cmd_Data[71:64]=8'h00;
			Main_Cmd_Data[79:72]=8'h00;
			Main_Cmd_Data[87:80]=8'h00;
			Main_Cmd_Data[95:88]=8'h00;
			Main_Cmd_Data[103:96]=8'h00;
			Main_Cmd_Data[111:104]=8'h00;
			Main_Cmd_Data[119:112]=8'h00;
			Main_Cmd_Data[127:120]=8'h00;
			Main_Cmd=1;
			Main_start=1;
			Main_Data_len=16;
			Main_Return_len=0;
			Main_Current_State=100;
		end
		100:
		begin
			Main_start=0;
			Main_Current_State=101;
		end
		101:
		begin
			if(spi_op_done)
			begin
				Main_Current_State=102;
			end
		end
		102:
		begin
			Main_Cmd_Data[7:0]=8'h11;
			Main_Cmd_Data[15:8]=8'h40;
			Main_Cmd_Data[23:16]=8'h08;
			Main_Cmd_Data[31:24]=8'h00;
			Main_Cmd_Data[39:32]=8'h3b;
			Main_Cmd_Data[47:40]=8'h08;
			Main_Cmd_Data[55:48]=8'h00;
			Main_Cmd_Data[63:56]=8'h00;
			Main_Cmd_Data[71:64]=8'h44;
			Main_Cmd_Data[79:72]=8'h44;
			Main_Cmd_Data[87:80]=8'h20;
			Main_Cmd_Data[95:88]=8'hfe;
			Main_Cmd=1;
			Main_start=1;
			Main_Data_len=12;
			Main_Return_len=0;
			Main_Current_State=103;
		end
		103:
		begin
			Main_start=0;
			Main_Current_State=104;
		end
		104:
		begin
			if(spi_op_done)
			begin
				Main_Current_State=105;
			end
		end


		//===set_frr_ctl(void)====
		105:
		begin
			Main_Cmd_Data[7:0]=8'h11;
			Main_Cmd_Data[15:8]=8'h02;
			Main_Cmd_Data[23:16]=8'h04;
			Main_Cmd_Data[31:24]=8'h00;
			Main_Cmd_Data[39:32]=8'h04;
			Main_Cmd_Data[47:40]=8'h06;
			Main_Cmd_Data[55:48]=8'h00;
			Main_Cmd_Data[63:56]=8'h00;
			Main_Cmd=1;
			Main_start=1;
			Main_Data_len=8;
			Main_Return_len=0;
			Main_Current_State=106;
		end
		106:
		begin
			Main_start=0;
			Main_Current_State=107;
		end
		107:
		begin
			if(spi_op_done)
			begin
				Main_Current_State=108;
			end
		end
		//===Function_set_tran_property()====
		108:
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
			Main_Current_State=109;
		end
		109:
		begin
			Main_start=0;
			Main_Current_State=110;
		end
		110:
		begin
			if(spi_op_done)
			begin
				Main_Current_State=111;
			end
		end
		111:
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
			Main_Current_State=112;
		end
		112:
		begin
			Main_start=0;
			Main_Current_State=113;
		end
		113:
		begin
			if(spi_op_done)
			begin
				Main_Current_State=114;
			end
		end
		114:
		begin
			Main_Cmd_Data[7:0]=8'h11;
			Main_Cmd_Data[15:8]=8'h12;
			Main_Cmd_Data[23:16]=8'h04;
			Main_Cmd_Data[31:24]=8'h0d;
			Main_Cmd_Data[39:32]=8'h00;
			Main_Cmd_Data[47:40]=8'h00;
			Main_Cmd_Data[55:48]=8'h00;
			Main_Cmd_Data[63:56]=8'ha0;
			Main_Cmd=1;
			Main_start=1;
			Main_Data_len=8;
			Main_Return_len=0;
			Main_Current_State=115;
		end
		115:
		begin
			Main_start=0;
			Main_Current_State=116;
		end
		116:
		begin
			if(spi_op_done)
			begin
				Main_Current_State=117;
			end
		end
		117:
		begin
			Main_Cmd_Data[7:0]=8'h11;
			Main_Cmd_Data[15:8]=8'h12;
			Main_Cmd_Data[23:16]=8'h04;
			Main_Cmd_Data[31:24]=8'h21;
			Main_Cmd_Data[39:32]=8'h00;
			Main_Cmd_Data[47:40]=8'h01;
			Main_Cmd_Data[55:48]=8'h00;
			Main_Cmd_Data[63:56]=8'h80;
			Main_Cmd=1;
			Main_start=1;
			Main_Data_len=8;
			Main_Return_len=0;
			Main_Current_State=118;
		end
		118:
		begin
			Main_start=0;
			Main_Current_State=119;
		end
		119:
		begin
			if(spi_op_done)
			begin
				Main_Current_State=120;
			end
		end
		120:
		begin
			Main_Cmd_Data[7:0]=8'h11;
			Main_Cmd_Data[15:8]=8'h12;
			Main_Cmd_Data[23:16]=8'h04;
			Main_Cmd_Data[31:24]=8'h25;
			Main_Cmd_Data[39:32]=8'h00;
			Main_Cmd_Data[47:40]=8'hfa;
			Main_Cmd_Data[55:48]=8'h00;
			Main_Cmd_Data[63:56]=8'h00;
			Main_Cmd=1;
			Main_start=1;
			Main_Data_len=8;
			Main_Return_len=0;
			Main_Current_State=121;
		end
		121:
		begin
			Main_start=0;
			Main_Current_State=122;
		end
		122:
		begin
			if(spi_op_done)
			begin
				Main_Current_State=123;
			end
		end
		123:
		begin
			Main_Cmd_Data[7:0]=8'h11;
			Main_Cmd_Data[15:8]=8'h12;
			Main_Cmd_Data[23:16]=8'h02;
			Main_Cmd_Data[31:24]=8'h0b;
			Main_Cmd_Data[39:32]=8'h23;
			Main_Cmd_Data[47:40]=8'h30;
			Main_Cmd=1;
			Main_start=1;
			Main_Data_len=6;
			Main_Return_len=0;
			Main_Current_State=124;
		end
		124:
		begin
			Main_start=0;
			Main_Current_State=125;
		end
		125:
		begin
			if(spi_op_done)
			begin
				Main_Current_State=126;
			end
		end
		126:
		begin
			Main_Cmd_Data[7:0]=8'h11;
			Main_Cmd_Data[15:8]=8'h00;
			Main_Cmd_Data[23:16]=8'h01;
			Main_Cmd_Data[31:24]=8'h03;
			Main_Cmd_Data[39:32]=8'h70;
			Main_Cmd=1;
			Main_start=1;
			Main_Data_len=5;
			Main_Return_len=0;
			Main_Current_State=127;
		end
		127:
		begin
			Main_start=0;
			Main_Current_State=128;
		end
		128:
		begin
			if(spi_op_done)
			begin
				Main_Current_State=160;
			end
		end

		
		//需要重置FIFO
		160:
		begin
			Main_Cmd_Data[7:0]=8'h15;
			Main_Cmd_Data[15:8]=8'h03;
			Main_Data_len=2;
			Main_Return_len=0;
			Main_Cmd=1;
			Main_start=1;
			Main_Current_State=161;
		end
		161:
		begin
			Main_start=0;
			Main_Current_State=162;
		end
		162:
		begin
			if(spi_op_done)
			begin
				Main_Current_State=170;
			end
		end
		
		//检查当前状态
		170:
		begin
			Main_Cmd_Data[7:0]=8'h33;
			Main_Cmd_Data[15:8]=8'h00;
			Main_Data_len=2;
			Main_Return_len=2;
			Main_Cmd=1;
			Main_start=1;
			Main_Current_State=171;
		end
		171:
		begin
			Main_start=0;
			Main_Current_State=172;
		end
		172:
		begin
			
			if(spi_op_done)
			begin
				if(Main_Return_Data[15:8]==8'h03)
				begin
					tx_state=3'b000;
					Main_Current_State=180;
				end
			end
		end
		
		
		//状态转化为RX
		180:
		begin
			if(!spi_Using)
			begin
				Main_Cmd_Data[7:0]=8'h32;
				Main_Cmd_Data[15:8]=8'h00;
				Main_Cmd_Data[23:16]=8'h00;
				Main_Cmd_Data[31:24]=8'h00;
				Main_Cmd_Data[39:32]=8'h00;
				Main_Cmd_Data[47:40]=8'h00;
				Main_Cmd_Data[55:48]=8'h08;
				Main_Cmd_Data[63:56]=8'h08;
				Main_Data_len=8;
				Main_Return_len=0;
				Main_Cmd=1;
				Main_start=1;
				Main_Current_State=181;
			end
		end
		181:
		begin
			Main_start=0;
			Main_Current_State=182;
		end
		182:
		begin
			if(spi_op_done)
			begin
				enable_irq=1;   //开始允许监听中断信号
				tx_state=`RX;
				Main_Current_State=130;
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
		
		///////////////////////////////////启动完成，开始发送数据、、、、、、、、、、、、、、、、
		//////////////////////////////////////////////////////////////////////////////
		
		
		////判断是否有数据及数据帧长度,如果想要读取数据包长度，可以另外设置一条命令，从SPI中读取SRAM
		130:
		begin
			if(!SRAM_empty&&!spi_Using)
			begin
				Main_Cmd=5;
				Main_start=1;
				Main_Current_State=131;
			end
		end
		131:
		begin
			Main_start=0;
			Main_Current_State=132;
		end
		132:
		begin
			if(spi_op_done)
			begin
				if(Main_Data_Check[31:24]==8'h66)
				begin
					Data_Len_to_Send=Main_Data_Check[7:0];
					if(SRAM_count*2>=Data_Len_to_Send)
					begin
						Main_Current_State=133;
					end
				end
				else
				begin
					Main_Current_State=130;
				end
			end
		end
		
		/////如果SPI正在被使用则等待，否则发送命令切换状态为tx_tune///////
		
		////切换状态0x34 05 TX_TUNE
		133:
		begin
			if(!spi_Using&&!rx_start&&!packet_incoming)
			begin
				Main_Cmd=1;
				Main_Cmd_Data[7:0]=8'h34;
				Main_Cmd_Data[15:8]=8'h05;
				Main_start=1;
				Main_Data_len=2;
				Main_Return_len=0;
				Main_Current_State=134;
			end
		end
		134:
		begin
			Main_start=0;
			Main_Current_State=135;
		end
		135:
		begin
			if(spi_op_done)
			begin
				tx_state=`TX_TUNE;
				Main_Current_State=136;
			end
		end
		///重置FIFO
		136: //0x15 03
		begin
			if(!spi_Using)
			begin
				Main_Cmd=1;
				Main_Cmd_Data[7:0]=8'h15;
				Main_Cmd_Data[15:8]=8'h03;
				Main_start=1;
				Main_Data_len=2;
				Main_Return_len=0;
				Main_Current_State=137;
			end
		end
		137:
		begin
			Main_start=0;
			Main_Current_State=138;
		end
		138:
		begin
			if(spi_op_done)
				Main_Current_State=200;
		end
		
		
		//设置需要发送的数据包的长度
		200:
		begin
			if(!spi_Using)
			begin
				Main_Cmd_Data[7:0]=8'h11;
				Main_Cmd_Data[15:8]=8'h12;
				Main_Cmd_Data[23:16]=8'h01;
				Main_Cmd_Data[31:24]=8'h0E;
				Main_Cmd_Data[39:32]=Data_Len_to_Send;
				
				Main_Data_len=5;
				Main_Return_len=0;
				Main_Cmd=1;
				Main_start=1;
				Main_Current_State=201;
			end
		end
		201:
		begin
			Main_start=0;
			Main_Current_State=202;
		end
		202:
		begin
			if(spi_op_done)
			begin
				Main_Current_State=139;
			end
		end
		
		//////如果SPI正在被使用则等待，否则将数据写入射频模块缓冲区、、、、
		
		139:
		begin
			if(!spi_Using)
			begin
				Main_Cmd=2;
				Main_Data_len=Data_Len_to_Send+1;  //+1是因为要发送0x66命令，导致最大包长度为126,再去掉包长度，则只剩125字节
				Main_Return_len=0;
				Main_start=1;
				Main_Current_State=140;
			end
		end
		140:
		begin
			Main_start=0;
			Main_Current_State=141;
		end
		141:
		begin
			if(spi_op_done)
			begin
				Main_Current_State=142;
			end
		end
		
		
		///等待时隙///////////
		200:
		begin
			if(GPS_sync_time) //这是一个脉冲，
			begin
				Main_Current_State=142;
			end
		end
		/////////发送命令，开始发送数据///////////
		142:
		begin
			Main_Cmd=1;
			Main_start=1;
			Main_Data_len=5;
			Main_Return_len=0;
			Main_Cmd_Data[7:0]=8'h31;
			Main_Cmd_Data[15:8]=8'h00;
			Main_Cmd_Data[23:16]=8'h80;
			Main_Cmd_Data[31:24]=8'h00;
			Main_Cmd_Data[39:32]=8'h00;
			Main_Current_State=143;
		end
		143:
		begin
			Main_start=0;
			Main_Current_State=144;
		end
		144:
		begin
			if(spi_op_done)
			begin
				tx_state=`TX;
				Main_Current_State=145;
			end
		end
		145:
		begin
			if(tx_done)  //增加超时判断
			begin
				led[3]=~led[3];
				tx_state=`RX;
				Main_Current_State=130;
			end
			delay_start_2=1;
			delay_mtime_2=30;
			if(delay_int)
			begin
				tx_state=`RX;
				delay_start=0;
				Main_Current_State=0;
			end
		end
		
		default:
		begin
			Main_Current_State=8'h00;
		end
	endcase

end




/////中断处理程序///////////
always@(posedge clk)
begin
	case (Irq_Current_State)		
		/////等待中断到来
		0:
		begin
			if(enable_irq&&!Si4463_int)
			begin
				rx_flag=0;  ///这里可能出现问题
				tx_flag=0;
				Irq_Current_State=1;
			end
		end
		/*
		9:
		begin
			if(!spi_Using)
			begin
				Int_Cmd_Data[7:0]=8'h20;
				Int_Cmd_Data[15:8]=8'hFB;
				Int_Cmd_Data[23:16]=8'h7F;
				Int_Cmd_Data[31:24]=8'h7F;
				Int_start=1;
				Int_Cmd=4;
				Int_Data_len=4;
				Int_Return_len=8;
				Irq_Current_State=10;
			end
		end
		10:
		begin
			Int_start=0;
			Irq_Current_State=11;
		end
		11:
		begin
			if(spi_op_done)
			begin
				Si4463_Ph_Status=Int_Return_Data[47:40];
				if((Si4463_Ph_Status &8'h22)==8'b00100010 || (Si4463_Ph_Status&8'h22)==8'b00100000) //发送完成中断
				begin
					tx_flag=1;
					Irq_Current_State=1;
				end
				if((Si4463_Ph_Status&8'h10)==8'b00010000) //接收中断
				begin
					Irq_Current_State=1;
					rx_flag=1;
				end
				else
				begin
					Irq_Current_State=1;
				end
			end
		end*/
		//////读取中断状态，判断中断源
		1:
		begin
			if(!spi_Using)
			begin
				Int_Cmd_Data[7:0]=8'h50;
				Int_start=1;
				Int_Cmd=6;
				Int_Data_len=1;
				Int_Return_len=2;
				Irq_Current_State=2;
			end
		end
		2:
		begin
			Int_start=0;
			Irq_Current_State=3;
		end
		3:
		begin
			if(spi_op_done)
			begin
				
				Si4463_Ph_Status=Int_Return_Data[15:8];
				Si4463_Modem_Status=Int_Return_Data[7:0];
				Si4463_Ph_Status_1=Si4463_Ph_Status;
				if((Si4463_Ph_Status &8'h22)==8'b00100010 || (Si4463_Ph_Status&8'h22)==8'b00100000) //发送完成中断
				begin
					led[0]=~led[0];
					tx_flag=1;
					Irq_Current_State=4;
				end
				if((Si4463_Ph_Status&8'h10)==8'b00010000) //接收中断
				begin
					led[1]=~led[1];
					Irq_Current_State=4;
					rx_flag=1;
				end
				if((Si4463_Modem_Status&8'h03)==8'h03)
				begin
					packet_incoming=1;
					Irq_Current_State=4;
				end
				else
				begin
					Irq_Current_State=4;
				end
			end
		end
		
		4: //清除中断
		begin
			if(!spi_Using)
			begin
				Int_Cmd_Data[7:0]=8'h20;
				Int_Cmd_Data[15:8]=8'h00;
				Int_Cmd_Data[23:16]=8'h00;
				Int_Cmd_Data[31:24]=8'h00;
				Int_start=1;
				Int_Cmd=4;
				Int_Data_len=4;
				Int_Return_len=0;
				Irq_Current_State=5;
			end
		end
		5:
		begin
			Int_start=0;
			Irq_Current_State=6;
		end
		6:
		begin
			if(spi_op_done)
			begin
				if(!Si4463_int)
					Irq_Current_State=4;
				else
					Irq_Current_State=7;
			end
		end
		7:
		begin
			if(rx_flag)
			begin
				packet_incoming=0;
				rx_start=1;
				Irq_Current_State=0;
			end
			if(tx_flag)
			begin
				tx_done=1;
				Irq_Current_State=8;
			end
			else
			begin
				Irq_Current_State=0;
			end
		end
		8:
		begin
			if(tx_state!=`TX)
			begin
				tx_flag=0;
				tx_done=0;
				Irq_Current_State=0;
			end
		end
		///如果是发送中断，置tx_done 为1
		///如果是接收中断，提示用户开始接收数据,置rx_start为1,接收完成后，置为0/////////
		default:
			Irq_Current_State=0;
		
	endcase
	
	
	///////接收数据帧程序/////////////////
	case (Recv_Current_State)
		0:
		begin
			if(rx_start)
			begin
				Recv_Current_State=4;
			end
		end
		/*
		1:
		begin
			if(!spi_Using)
			begin
				Int_Cmd_Data[7:0]=8'h15;
				Int_Cmd_Data[15:8]=8'h00; 
				Int_Data_len=2;
				Int_Return_len=2;
				Int_start=1;
				Int_Cmd=4;
				Recv_Current_State=2;
			end
		end
		2:
		begin
			Int_start=0;
			Recv_Current_State=3;
		end
		3:
		begin
			if(spi_op_done)
			begin			
				//rx_flag=0;
				//Si4463_Ph_Status_1=Int_Return_Data[15:8];
				Recv_Current_State=4;
			end
		end*/
		4: //发送接收命令   ，如果不行的话，可以将这个命令放在SPI中
		begin
			Int_Data_len=0;
			Int_Return_len=0;
			Int_start=1;
			Int_Cmd=3;
			Recv_Current_State=5;
		end
		5:
		begin
			Int_start=0;
			Recv_Current_State=6;
		end
		6:
		begin
			if(spi_op_done)
			begin			
				rx_start=0;
				frame_recved_int=1;
				Recv_Current_State=0;
			end
		end
		/*
		7: //重置FIFO
		begin
			frame_recved_int=0;
			if(!spi_Using)
			begin
				Int_Cmd_Data[7:0]=8'h15;
				Int_Cmd_Data[15:8]=8'h03; //这里原来是03，但是我认为02会更好一点
				Int_Data_len=2;
				Int_Return_len=0;
				Int_start=1;
				Int_Cmd=4;
				Recv_Current_State=8;
			end
		end
		8:
		begin
			Int_start=0;
			Recv_Current_State=9;
		end
		9:
		begin
			if(spi_op_done)
			begin
				rx_start=0;
				Recv_Current_State=0;
			end
		end*/
		default:
		begin
			rx_start=0;
			tx_done=0;
			Recv_Current_State=0;
		end
	endcase
end


endmodule
