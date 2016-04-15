

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
output[7:0] Si4463_Ph_Status_1;
assign Si4463_Ph_Status_1=SRAM_count[7:0];
output reg[3:0] led=4'b0000;
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




/////延时函数///////////////
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
reg[15:0] Main_Data_Check=0;


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
//分别在两个地方保证接收到的数据就是需要的数据
// 1. CTS,由于CTS后面跟着需要的数据，所以后面的数据可以确认为需要的数据
// 2. 只是发送命令时，返回的数据无所谓了 
// 3. 在接收数据后，发送0x77命令，放弃第一个接收到的数据(无效数据),在发送下一个数据前，射频有足够时间能够准备返回来的数据，所以返回的也是有效数据
always@(posedge clk)  //这里最好监视Main_start和Int_start信号
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
				default:
				begin
					spi_start=0;
					Spi_Current_State=0;
					spi_Using=0;
					spi_start=0;
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
				if(spi_cmd==2||spi_cmd==3 ||Ended_flag) //发送和接收数据帧不需要GetCTS
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
				if(master_rrdy)
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
				Sended_count=0;
				Spi_Current_State=33; 
			end
			31: //由可能需要告知射频模块需要接收的数据个数,不过不是非常必要
			begin
				if(!Byte_flag)
				begin
					Data_to_sram[15:8]=Data_from_master[7:0];
					Sended_count=Sended_count+1'b1;
					if(Sended_count<Int_Data_len)
					begin
						Byte_flag=~Byte_flag;
						Spi_Current_State=22;
					end
					else
					begin
						if(!SRAM_empty)
						begin
							Data_to_sram[7:0]=8'h00;
							SRAM_write=1;
							Spi_Current_State=32;
						end
						else
							Spi_Current_State=31;
					end
				end
				else
				begin
					if(!SRAM_empty)
					begin
						Data_to_sram[7:0]=Data_from_master[7:0];
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
					SRAM_write=0;
				if(Sended_count<Int_Data_len)
					Spi_Current_State=22;
				else
					Spi_Current_State=12;	
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
					Main_Data_Check=Data_from_sram;
					spi_Using=0;
					spi_start=0;
					spi_op_done=1;
					Spi_Current_State=0;
				end
			end
		
			
		endcase
	end
end

reg GPS_sync_time=1'b1;  ////需要接GPS同步时钟
reg [7:0] Main_Current_State=8'hFA;
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
		led=SRAM_count[3:0];
		case(Main_Current_State) 
		250:
		begin
			Si4463_reset=1;
			delay_start=1;
			delay_mtime=10;
			if(delay_int)
			begin
				delay_start=0;
				Main_Current_State=249;
			end
		end
		249:
		begin
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
				Main_Current_State=0;
			end
		end
		
	////////////reset()函数，启动射频模块
		0:
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
	
	/*
// Command:                  RF_POWER_UP
// Description:              Command to power-up the device and select the operational mode and functionality.
*/
		12:
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
	/*
// Command:                  RF_GPIO_PIN_CFG
// Description:              Configures the GPIO pins.
*/	
		15:
		begin
			Main_Cmd_Data[7:0]=8'h13;
			Main_Cmd_Data[15:8]=8'h1B;
			Main_Cmd_Data[23:16]=8'h23;
			Main_Cmd_Data[31:24]=8'h21;
			Main_Cmd_Data[39:32]=8'h20;
			Main_Cmd_Data[47:40]=8'h00;
			Main_Cmd_Data[55:48]=8'h00;
			Main_Cmd_Data[63:56]=8'h00;
			Main_Data_len=8;
			Main_Return_len=0;
			Main_Cmd=1;
			Main_start=1;
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
				Main_Current_State=19;
			end
		end
		
	/*
// Set properties:           RF_GLOBAL_XO_TUNE_2
// Number of properties:     2
// Group ID:                 0x00
// Start ID:                 0x00
// Default values:           0x40, 0x00,
// Descriptions:
//   GLOBAL_XO_TUNE - Configure the internal capacitor frequency tuning bank for the crystal oscillator.
//   GLOBAL_CLK_CFG - Clock configuration options.
*/	
		19:
		begin
			Main_Cmd_Data[7:0]=8'h11;
			Main_Cmd_Data[15:8]=8'h00;
			Main_Cmd_Data[23:16]=8'h02;
			Main_Cmd_Data[31:24]=8'h00;
			Main_Cmd_Data[39:32]=8'h52;
			Main_Cmd_Data[47:40]=8'h00;
			Main_Data_len=6;
			Main_Return_len=0;
			Main_Cmd=1;
			Main_start=1;
			Main_Current_State=20;
		end
		20:
		begin
			Main_start=0;
			Main_Current_State=21;
		end
		21:
		begin
			if(spi_op_done)
			begin
				Main_Current_State=22;
			end
		end
/*
// Set properties:           RF_GLOBAL_CONFIG_1
// Number of properties:     1
// Group ID:                 0x00
// Start ID:                 0x03
// Default values:           0x20,
// Descriptions:
//   GLOBAL_CONFIG - Global configuration settings.
*/		
		22:
		begin
			Main_Cmd_Data[7:0]=8'h11;
			Main_Cmd_Data[15:8]=8'h00;
			Main_Cmd_Data[23:16]=8'h01;
			Main_Cmd_Data[31:24]=8'h03;
			Main_Cmd_Data[39:32]=8'h60;
			Main_Data_len=5;
			Main_Return_len=0;
			Main_Cmd=1;
			Main_start=1;
			Main_Current_State=23;
		end
		23:
		begin
			Main_start=0;
			Main_Current_State=24;
		end
		24:
		begin
			if(spi_op_done)
			begin
				Main_Current_State=25;
			end
		end
/*
// Set properties:           RF_INT_CTL_ENABLE_2
// Number of properties:     2
// Group ID:                 0x01
// Start ID:                 0x00
// Default values:           0x04, 0x00,
// Descriptions:
//   INT_CTL_ENABLE - This property provides for global enabling of the three interrupt groups (Chip, Modem and Packet Handler) in order to generate HW interrupts at the NIRQ pin.
//   INT_CTL_PH_ENABLE - Enable individual interrupt sources within the Packet Handler Interrupt Group to generate a HW interrupt on the NIRQ output pin.
*/		
		25:
		begin
			Main_Cmd_Data[7:0]=8'h11;
			Main_Cmd_Data[15:8]=8'h01;
			Main_Cmd_Data[23:16]=8'h02;
			Main_Cmd_Data[31:24]=8'h00;
			Main_Cmd_Data[39:32]=8'h01;
			Main_Cmd_Data[47:40]=8'h30;
			Main_Data_len=6;
			Main_Return_len=0;
			Main_Cmd=1;
			Main_start=1;
			Main_Current_State=26;
		end
		26:
		begin
			Main_start=0;
			Main_Current_State=27;
		end
		27:
		begin
			if(spi_op_done)
			begin
				Main_Current_State=28;
			end
		end
/*
// Set properties:           RF_FRR_CTL_A_MODE_4
// Number of properties:     4
// Group ID:                 0x02
// Start ID:                 0x00
// Default values:           0x01, 0x02, 0x09, 0x00,
// Descriptions:
//   FRR_CTL_A_MODE - Fast Response Register A Configuration.
//   FRR_CTL_B_MODE - Fast Response Register B Configuration.
//   FRR_CTL_C_MODE - Fast Response Register C Configuration.
//   FRR_CTL_D_MODE - Fast Response Register D Configuration.
*/		
		28:
		begin
			Main_Cmd_Data[7:0]=8'h11;
			Main_Cmd_Data[15:8]=8'h02;
			Main_Cmd_Data[23:16]=8'h04;
			Main_Cmd_Data[31:24]=8'h00;
			Main_Cmd_Data[39:32]=8'h04;
			Main_Cmd_Data[47:40]=8'h06;
			Main_Cmd_Data[55:48]=8'h00;
			Main_Cmd_Data[63:56]=8'h00;
			Main_Data_len=8;
			Main_Return_len=0;
			Main_Cmd=1;
			Main_start=1;
			Main_Current_State=29;
		end
		29:
		begin
			Main_start=0;
			Main_Current_State=30;
		end
		30:
		begin
			if(spi_op_done)
			begin
				Main_Current_State=31;
			end
		end
/*
// Set properties:           RF_PREAMBLE_TX_LENGTH_9
// Number of properties:     9
// Group ID:                 0x10
// Start ID:                 0x00
// Default values:           0x08, 0x14, 0x00, 0x0F, 0x21, 0x00, 0x00, 0x00, 0x00,
// Descriptions:
//   PREAMBLE_TX_LENGTH - Configure length of TX Preamble.
//   PREAMBLE_CONFIG_STD_1 - Configuration of reception of a packet with a Standard Preamble pattern.
//   PREAMBLE_CONFIG_NSTD - Configuration of transmission/reception of a packet with a Non-Standard Preamble pattern.
//   PREAMBLE_CONFIG_STD_2 - Configuration of timeout periods during reception of a packet with Standard Preamble pattern.
//   PREAMBLE_CONFIG - General configuration bits for the Preamble field.
//   PREAMBLE_PATTERN_31_24 - Configuration of the bit values describing a Non-Standard Preamble pattern.
//   PREAMBLE_PATTERN_23_16 - Configuration of the bit values describing a Non-Standard Preamble pattern.
//   PREAMBLE_PATTERN_15_8 - Configuration of the bit values describing a Non-Standard Preamble pattern.
//   PREAMBLE_PATTERN_7_0 - Configuration of the bit values describing a Non-Standard Preamble pattern.
*/		
		31:
		begin
			Main_Cmd_Data[7:0]=8'h11;
			Main_Cmd_Data[15:8]=8'h10;
			Main_Cmd_Data[23:16]=8'h09;
			Main_Cmd_Data[31:24]=8'h00;
			Main_Cmd_Data[39:32]=8'h08;
			Main_Cmd_Data[47:40]=8'h14;
			Main_Cmd_Data[55:48]=8'h00;
			Main_Cmd_Data[63:56]=8'h0F;
			Main_Cmd_Data[71:64]=8'h31;
			Main_Cmd_Data[79:72]=8'h00;
			Main_Cmd_Data[87:80]=8'h00;
			Main_Cmd_Data[95:88]=8'h00;
			Main_Cmd_Data[103:96]=8'h00;
			Main_Data_len=13;
			Main_Return_len=0;
			Main_Cmd=1;
			Main_start=1;
			Main_Current_State=32;
		end
		32:
		begin
			Main_start=0;
			Main_Current_State=33;
		end
		33:
		begin
			if(spi_op_done)
			begin
				Main_Current_State=34;
			end
		end
		
/*
// Set properties:           RF_SYNC_CONFIG_5
// Number of properties:     5
// Group ID:                 0x11
// Start ID:                 0x00
// Default values:           0x01, 0x2D, 0xD4, 0x2D, 0xD4,
// Descriptions:
//   SYNC_CONFIG - Sync Word configuration bits.
//   SYNC_BITS_31_24 - Sync word.
//   SYNC_BITS_23_16 - Sync word.
//   SYNC_BITS_15_8 - Sync word.
//   SYNC_BITS_7_0 - Sync word.
*/		
		34:
		begin
			Main_Cmd_Data[7:0]=8'h11;
			Main_Cmd_Data[15:8]=8'h11;
			Main_Cmd_Data[23:16]=8'h05;
			Main_Cmd_Data[31:24]=8'h00;
			Main_Cmd_Data[39:32]=8'h01;
			Main_Cmd_Data[47:40]=8'hB4;
			Main_Cmd_Data[55:48]=8'h2B;
			Main_Cmd_Data[63:56]=8'h00;
			Main_Cmd_Data[71:64]=8'h00;
			Main_Data_len=9;
			Main_Return_len=0;
			Main_Cmd=1;
			Main_start=1;
			Main_Current_State=35;
		end
		35:
		begin
			Main_start=0;
			Main_Current_State=36;
		end
		36:
		begin
			if(spi_op_done)
			begin
				Main_Current_State=37;
			end
		end
/*
// Set properties:           RF_PKT_CRC_CONFIG_7
// Number of properties:     7
// Group ID:                 0x12
// Start ID:                 0x00
// Default values:           0x00, 0x01, 0x08, 0xFF, 0xFF, 0x00, 0x00,
// Descriptions:
//   PKT_CRC_CONFIG - Select a CRC polynomial and seed.
//   PKT_WHT_POLY_15_8 - 16-bit polynomial value for the PN Generator (e.g., for Data Whitening)
//   PKT_WHT_POLY_7_0 - 16-bit polynomial value for the PN Generator (e.g., for Data Whitening)
//   PKT_WHT_SEED_15_8 - 16-bit seed value for the PN Generator (e.g., for Data Whitening)
//   PKT_WHT_SEED_7_0 - 16-bit seed value for the PN Generator (e.g., for Data Whitening)
//   PKT_WHT_BIT_NUM - Selects which bit of the LFSR (used to generate the PN / data whitening sequence) is used as the output bit for data scrambling.
//   PKT_CONFIG1 - General configuration bits for transmission or reception of a packet.
*/		
		37:
		begin
			Main_Cmd_Data[7:0]=8'h11;
			Main_Cmd_Data[15:8]=8'h12;
			Main_Cmd_Data[23:16]=8'h07;
			Main_Cmd_Data[31:24]=8'h00;
			Main_Cmd_Data[39:32]=8'h84;
			Main_Cmd_Data[47:40]=8'h00;
			Main_Cmd_Data[55:48]=8'h30;
			Main_Cmd_Data[63:56]=8'hFF;
			Main_Cmd_Data[71:64]=8'hFF;
			Main_Cmd_Data[79:72]=8'h00;
			Main_Cmd_Data[87:80]=8'h02;
			Main_Data_len=11;
			Main_Return_len=0;
			Main_Cmd=1;
			Main_start=1;
			Main_Current_State=38;
		end
		38:
		begin
			Main_start=0;
			Main_Current_State=39;
		end
		39:
		begin
			if(spi_op_done)
			begin
				Main_Current_State=40;
			end
		end
/*
// Set properties:           RF_PKT_LEN_12
// Number of properties:     12
// Group ID:                 0x12
// Start ID:                 0x08
// Default values:           0x00, 0x00, 0x00, 0x30, 0x30, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
// Descriptions:
//   PKT_LEN - Configuration bits for reception of a variable length packet.
//   PKT_LEN_FIELD_SOURCE - Field number containing the received packet length byte(s).
//   PKT_LEN_ADJUST - Provides for adjustment/offset of the received packet length value (in order to accommodate a variety of methods of defining total packet length).
//   PKT_TX_THRESHOLD - TX FIFO almost empty threshold.
//   PKT_RX_THRESHOLD - RX FIFO Almost Full threshold.
//   PKT_FIELD_1_LENGTH_12_8 - Unsigned 13-bit Field 1 length value.
//   PKT_FIELD_1_LENGTH_7_0 - Unsigned 13-bit Field 1 length value.
//   PKT_FIELD_1_CONFIG - General data processing and packet configuration bits for Field 1.
//   PKT_FIELD_1_CRC_CONFIG - Configuration of CRC control bits across Field 1.
//   PKT_FIELD_2_LENGTH_12_8 - Unsigned 13-bit Field 2 length value.
//   PKT_FIELD_2_LENGTH_7_0 - Unsigned 13-bit Field 2 length value.
//   PKT_FIELD_2_CONFIG - General data processing and packet configuration bits for Field 2.
*/	
		40:
		begin
			Main_Cmd_Data[7:0]=8'h11;
			Main_Cmd_Data[15:8]=8'h12;
			Main_Cmd_Data[23:16]=8'h0C;
			Main_Cmd_Data[31:24]=8'h08;
			Main_Cmd_Data[39:32]=8'h00;
			Main_Cmd_Data[47:40]=8'h00;
			Main_Cmd_Data[55:48]=8'h00;
			Main_Cmd_Data[63:56]=8'h40;
			Main_Cmd_Data[71:64]=8'h40;
			Main_Cmd_Data[79:72]=8'h00;
			Main_Cmd_Data[87:80]=8'h40;
			Main_Cmd_Data[95:88]=8'h04;
			Main_Cmd_Data[103:96]=8'h80;
			Main_Cmd_Data[111:104]=8'h00;
			Main_Cmd_Data[119:112]=8'h00;
			Main_Cmd_Data[127:120]=8'h00;
			Main_Data_len=16;
			Main_Return_len=0;
			Main_Cmd=1;
			Main_start=1;
			Main_Current_State=41;
		end
		41:
		begin
			Main_start=0;
			Main_Current_State=42;
		end
		42:
		begin
			if(spi_op_done)
			begin
				Main_Current_State=43;
			end
		end
/*
// Set properties:           RF_PKT_FIELD_2_CRC_CONFIG_12
// Number of properties:     12
// Group ID:                 0x12
// Start ID:                 0x14
// Default values:           0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
// Descriptions:
//   PKT_FIELD_2_CRC_CONFIG - Configuration of CRC control bits across Field 2.
//   PKT_FIELD_3_LENGTH_12_8 - Unsigned 13-bit Field 3 length value.
//   PKT_FIELD_3_LENGTH_7_0 - Unsigned 13-bit Field 3 length value.
//   PKT_FIELD_3_CONFIG - General data processing and packet configuration bits for Field 3.
//   PKT_FIELD_3_CRC_CONFIG - Configuration of CRC control bits across Field 3.
//   PKT_FIELD_4_LENGTH_12_8 - Unsigned 13-bit Field 4 length value.
//   PKT_FIELD_4_LENGTH_7_0 - Unsigned 13-bit Field 4 length value.
//   PKT_FIELD_4_CONFIG - General data processing and packet configuration bits for Field 4.
//   PKT_FIELD_4_CRC_CONFIG - Configuration of CRC control bits across Field 4.
//   PKT_FIELD_5_LENGTH_12_8 - Unsigned 13-bit Field 5 length value.
//   PKT_FIELD_5_LENGTH_7_0 - Unsigned 13-bit Field 5 length value.
//   PKT_FIELD_5_CONFIG - General data processing and packet configuration bits for Field 5.
*/		
		43:
		begin
			Main_Cmd_Data[7:0]=8'h11;
			Main_Cmd_Data[15:8]=8'h12;
			Main_Cmd_Data[23:16]=8'h0C;
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
			Main_Data_len=16;
			Main_Return_len=0;
			Main_Cmd=1;
			Main_start=1;
			Main_Current_State=44;
		end
		44:
		begin
			Main_start=0;
			Main_Current_State=45;
		end
		45:
		begin
			if(spi_op_done)
			begin
				Main_Current_State=46;
			end
		end
/*
// Set properties:           RF_PKT_FIELD_5_CRC_CONFIG_12
// Number of properties:     12
// Group ID:                 0x12
// Start ID:                 0x20
// Default values:           0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
// Descriptions:
//   PKT_FIELD_5_CRC_CONFIG - Configuration of CRC control bits across Field 5.
//   PKT_RX_FIELD_1_LENGTH_12_8 - Unsigned 13-bit RX Field 1 length value.
//   PKT_RX_FIELD_1_LENGTH_7_0 - Unsigned 13-bit RX Field 1 length value.
//   PKT_RX_FIELD_1_CONFIG - General data processing and packet configuration bits for RX Field 1.
//   PKT_RX_FIELD_1_CRC_CONFIG - Configuration of CRC control bits across RX Field 1.
//   PKT_RX_FIELD_2_LENGTH_12_8 - Unsigned 13-bit RX Field 2 length value.
//   PKT_RX_FIELD_2_LENGTH_7_0 - Unsigned 13-bit RX Field 2 length value.
//   PKT_RX_FIELD_2_CONFIG - General data processing and packet configuration bits for RX Field 2.
//   PKT_RX_FIELD_2_CRC_CONFIG - Configuration of CRC control bits across RX Field 2.
//   PKT_RX_FIELD_3_LENGTH_12_8 - Unsigned 13-bit RX Field 3 length value.
//   PKT_RX_FIELD_3_LENGTH_7_0 - Unsigned 13-bit RX Field 3 length value.
//   PKT_RX_FIELD_3_CONFIG - General data processing and packet configuration bits for RX Field 3.
*/		
		46:
		begin
			Main_Cmd_Data[7:0]=8'h11;
			Main_Cmd_Data[15:8]=8'h12;
			Main_Cmd_Data[23:16]=8'h0C;
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
			Main_Data_len=16;
			Main_Return_len=0;
			Main_Cmd=1;
			Main_start=1;
			Main_Current_State=47;
		end
		47:
		begin
			Main_start=0;
			Main_Current_State=48;
		end
		48:
		begin
			if(spi_op_done)
			begin
				Main_Current_State=49;
			end
		end
		
/*
// Set properties:           RF_PKT_RX_FIELD_3_CRC_CONFIG_9
// Number of properties:     9
// Group ID:                 0x12
// Start ID:                 0x2C
// Default values:           0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
// Descriptions:
//   PKT_RX_FIELD_3_CRC_CONFIG - Configuration of CRC control bits across RX Field 3.
//   PKT_RX_FIELD_4_LENGTH_12_8 - Unsigned 13-bit RX Field 4 length value.
//   PKT_RX_FIELD_4_LENGTH_7_0 - Unsigned 13-bit RX Field 4 length value.
//   PKT_RX_FIELD_4_CONFIG - General data processing and packet configuration bits for RX Field 4.
//   PKT_RX_FIELD_4_CRC_CONFIG - Configuration of CRC control bits across RX Field 4.
//   PKT_RX_FIELD_5_LENGTH_12_8 - Unsigned 13-bit RX Field 5 length value.
//   PKT_RX_FIELD_5_LENGTH_7_0 - Unsigned 13-bit RX Field 5 length value.
//   PKT_RX_FIELD_5_CONFIG - General data processing and packet configuration bits for RX Field 5.
//   PKT_RX_FIELD_5_CRC_CONFIG - Configuration of CRC control bits across RX Field 5.
*/		
		49:
		begin
			Main_Cmd_Data[7:0]=8'h11;
			Main_Cmd_Data[15:8]=8'h12;
			Main_Cmd_Data[23:16]=8'h09;
			Main_Cmd_Data[31:24]=8'h2C;
			Main_Cmd_Data[39:32]=8'h00;
			Main_Cmd_Data[47:40]=8'h00;
			Main_Cmd_Data[55:48]=8'h00;
			Main_Cmd_Data[63:56]=8'h00;
			Main_Cmd_Data[71:64]=8'h00;
			Main_Cmd_Data[79:72]=8'h00;
			Main_Cmd_Data[87:80]=8'h00;
			Main_Cmd_Data[95:88]=8'h00;
			Main_Cmd_Data[103:96]=8'h00;
			Main_Data_len=13;
			Main_Return_len=0;
			Main_Cmd=1;
			Main_start=1;
			Main_Current_State=50;
		end
		50:
		begin
			Main_start=0;
			Main_Current_State=51;
		end
		51:
		begin
			if(spi_op_done)
			begin
				Main_Current_State=52;
			end
		end
		
/*
// Set properties:           RF_MODEM_MOD_TYPE_12
// Number of properties:     12
// Group ID:                 0x20
// Start ID:                 0x00
// Default values:           0x02, 0x80, 0x07, 0x0F, 0x42, 0x40, 0x01, 0xC9, 0xC3, 0x80, 0x00, 0x06,
// Descriptions:
//   MODEM_MOD_TYPE - Selects the type of modulation. In TX mode, additionally selects the source of the modulation.
//   MODEM_MAP_CONTROL - Controls polarity and mapping of transmit and receive bits.
//   MODEM_DSM_CTRL - Miscellaneous control bits for the Delta-Sigma Modulator (DSM) in the PLL Synthesizer.
//   MODEM_DATA_RATE_2 - Unsigned 24-bit value used to determine the TX data rate
//   MODEM_DATA_RATE_1 - Unsigned 24-bit value used to determine the TX data rate
//   MODEM_DATA_RATE_0 - Unsigned 24-bit value used to determine the TX data rate
//   MODEM_TX_NCO_MODE_3 - TX Gaussian filter oversampling ratio and Byte 3 of unsigned 26-bit TX Numerically Controlled Oscillator (NCO) modulus.
//   MODEM_TX_NCO_MODE_2 - TX Gaussian filter oversampling ratio and Byte 3 of unsigned 26-bit TX Numerically Controlled Oscillator (NCO) modulus.
//   MODEM_TX_NCO_MODE_1 - TX Gaussian filter oversampling ratio and Byte 3 of unsigned 26-bit TX Numerically Controlled Oscillator (NCO) modulus.
//   MODEM_TX_NCO_MODE_0 - TX Gaussian filter oversampling ratio and Byte 3 of unsigned 26-bit TX Numerically Controlled Oscillator (NCO) modulus.
//   MODEM_FREQ_DEV_2 - 17-bit unsigned TX frequency deviation word.
//   MODEM_FREQ_DEV_1 - 17-bit unsigned TX frequency deviation word.
*/		
		52:
		begin
			Main_Cmd_Data[7:0]=8'h11;
			Main_Cmd_Data[15:8]=8'h20;
			Main_Cmd_Data[23:16]=8'h0C;
			Main_Cmd_Data[31:24]=8'h00;
			Main_Cmd_Data[39:32]=8'h03;
			Main_Cmd_Data[47:40]=8'h00;
			Main_Cmd_Data[55:48]=8'h07;
			Main_Cmd_Data[63:56]=8'h3D;
			Main_Cmd_Data[71:64]=8'h09;
			Main_Cmd_Data[79:72]=8'h00;
			Main_Cmd_Data[87:80]=8'h01;
			Main_Cmd_Data[95:88]=8'hC9;
			Main_Cmd_Data[103:96]=8'hC3;
			Main_Cmd_Data[111:104]=8'h80;
			Main_Cmd_Data[119:112]=8'h00;
			Main_Cmd_Data[127:120]=8'h05;
			Main_Data_len=16;
			Main_Return_len=0;
			Main_Cmd=1;
			Main_start=1;
			Main_Current_State=53;
		end
		53:
		begin
			Main_start=0;
			Main_Current_State=54;
		end
		54:
		begin
			if(spi_op_done)
			begin
				Main_Current_State=55;
			end
		end
		
/*
// Set properties:           RF_MODEM_FREQ_DEV_0_1
// Number of properties:     1
// Group ID:                 0x20
// Start ID:                 0x0C
// Default values:           0xD3,
// Descriptions:
//   MODEM_FREQ_DEV_0 - 17-bit unsigned TX frequency deviation word.
*/		
		55:
		begin
			Main_Cmd_Data[7:0]=8'h11;
			Main_Cmd_Data[15:8]=8'h20;
			Main_Cmd_Data[23:16]=8'h01;
			Main_Cmd_Data[31:24]=8'h0C;
			Main_Cmd_Data[39:32]=8'h76;
			
			Main_Data_len=5;
			Main_Return_len=0;
			Main_Cmd=1;
			Main_start=1;
			Main_Current_State=56;
		end
		56:
		begin
			Main_start=0;
			Main_Current_State=57;
		end
		57:
		begin
			if(spi_op_done)
			begin
				Main_Current_State=58;
			end
		end
		
	/*
// Set properties:           RF_MODEM_TX_RAMP_DELAY_8
// Number of properties:     8
// Group ID:                 0x20
// Start ID:                 0x18
// Default values:           0x01, 0x00, 0x08, 0x03, 0xC0, 0x00, 0x10, 0x20,
// Descriptions:
//   MODEM_TX_RAMP_DELAY - TX ramp-down delay setting.
//   MODEM_MDM_CTRL - MDM control.
//   MODEM_IF_CONTROL - Selects Fixed-IF, Scaled-IF, or Zero-IF mode of RX Modem operation.
//   MODEM_IF_FREQ_2 - the IF frequency setting (an 18-bit signed number).
//   MODEM_IF_FREQ_1 - the IF frequency setting (an 18-bit signed number).
//   MODEM_IF_FREQ_0 - the IF frequency setting (an 18-bit signed number).
//   MODEM_DECIMATION_CFG1 - Specifies three decimator ratios for the Cascaded Integrator Comb (CIC) filter.
//   MODEM_DECIMATION_CFG0 - Specifies miscellaneous parameters and decimator ratios for the Cascaded Integrator Comb (CIC) filter.
*/	
		58:
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
			Main_Cmd_Data[95:88]=8'h30;
			Main_Data_len=12;
			Main_Return_len=0;
			Main_Cmd=1;
			Main_start=1;
			Main_Current_State=59;
		end
		59:
		begin
			Main_start=0;
			Main_Current_State=60;
		end
		60:
		begin
			if(spi_op_done)
			begin
				Main_Current_State=61;
			end
		end
/*
// Set properties:           RF_MODEM_BCR_OSR_1_9
// Number of properties:     9
// Group ID:                 0x20
// Start ID:                 0x22
// Default values:           0x00, 0x4B, 0x06, 0xD3, 0xA0, 0x06, 0xD3, 0x02, 0xC0,
// Descriptions:
//   MODEM_BCR_OSR_1 - RX BCR/Slicer oversampling rate (12-bit unsigned number).
//   MODEM_BCR_OSR_0 - RX BCR/Slicer oversampling rate (12-bit unsigned number).
//   MODEM_BCR_NCO_OFFSET_2 - RX BCR NCO offset value (an unsigned 22-bit number).
//   MODEM_BCR_NCO_OFFSET_1 - RX BCR NCO offset value (an unsigned 22-bit number).
//   MODEM_BCR_NCO_OFFSET_0 - RX BCR NCO offset value (an unsigned 22-bit number).
//   MODEM_BCR_GAIN_1 - The unsigned 11-bit RX BCR loop gain value.
//   MODEM_BCR_GAIN_0 - The unsigned 11-bit RX BCR loop gain value.
//   MODEM_BCR_GEAR - RX BCR loop gear control.
//   MODEM_BCR_MISC1 - Miscellaneous control bits for the RX BCR loop.
*/		
		61:
		begin
			Main_Cmd_Data[7:0]=8'h11;
			Main_Cmd_Data[15:8]=8'h20;
			Main_Cmd_Data[23:16]=8'h09;
			Main_Cmd_Data[31:24]=8'h22;
			Main_Cmd_Data[39:32]=8'h00;
			Main_Cmd_Data[47:40]=8'h4B;
			Main_Cmd_Data[55:48]=8'h06;
			Main_Cmd_Data[63:56]=8'hD3;
			Main_Cmd_Data[71:64]=8'hA0;
			Main_Cmd_Data[79:72]=8'h07;
			Main_Cmd_Data[87:80]=8'hFF;
			Main_Cmd_Data[95:88]=8'h02;
			Main_Cmd_Data[103:96]=8'h00;
			Main_Data_len=13;
			Main_Return_len=0;
			Main_Cmd=1;
			Main_start=1;
			Main_Current_State=62;
		end
		62:
		begin
			Main_start=0;
			Main_Current_State=63;
		end
		63:
		begin
			if(spi_op_done)
			begin
				Main_Current_State=64;
			end
		end
	/*
// Set properties:           RF_MODEM_AFC_GEAR_7
// Number of properties:     7
// Group ID:                 0x20
// Start ID:                 0x2C
// Default values:           0x00, 0x23, 0x83, 0x69, 0x00, 0x40, 0xA0,
// Descriptions:
//   MODEM_AFC_GEAR - RX AFC loop gear control.
//   MODEM_AFC_WAIT - RX AFC loop wait time control.
//   MODEM_AFC_GAIN_1 - Sets the gain of the PLL-based AFC acquisition loop, and provides miscellaneous control bits for AFC functionality.
//   MODEM_AFC_GAIN_0 - Sets the gain of the PLL-based AFC acquisition loop, and provides miscellaneous control bits for AFC functionality.
//   MODEM_AFC_LIMITER_1 - Set the AFC limiter value.
//   MODEM_AFC_LIMITER_0 - Set the AFC limiter value.
//   MODEM_AFC_MISC - Specifies miscellaneous AFC control bits.
*/	
		64:
		begin
			Main_Cmd_Data[7:0]=8'h11;
			Main_Cmd_Data[15:8]=8'h20;
			Main_Cmd_Data[23:16]=8'h07;
			Main_Cmd_Data[31:24]=8'h2C;
			Main_Cmd_Data[39:32]=8'h00;
			Main_Cmd_Data[47:40]=8'h23;
			Main_Cmd_Data[55:48]=8'h8F;
			Main_Cmd_Data[63:56]=8'hFF;
			Main_Cmd_Data[71:64]=8'h00;
			Main_Cmd_Data[79:72]=8'hB7;
			Main_Cmd_Data[87:80]=8'hE0;
			Main_Data_len=11;
			Main_Return_len=0;
			Main_Cmd=1;
			Main_start=1;
			Main_Current_State=65;
		end
		65:
		begin
			Main_start=0;
			Main_Current_State=66;
		end
		66:
		begin
			if(spi_op_done)
			begin
				Main_Current_State=67;
			end
		end
	/*
// Set properties:           RF_MODEM_AGC_CONTROL_1
// Number of properties:     1
// Group ID:                 0x20
// Start ID:                 0x35
// Default values:           0xE0,
// Descriptions:
//   MODEM_AGC_CONTROL - Miscellaneous control bits for the Automatic Gain Control (AGC) function in the RX Chain.
*/	
		67:
		begin
			Main_Cmd_Data[7:0]=8'h11;
			Main_Cmd_Data[15:8]=8'h20;
			Main_Cmd_Data[23:16]=8'h01;
			Main_Cmd_Data[31:24]=8'h35;
			Main_Cmd_Data[39:32]=8'hE2;
			Main_Data_len=5;
			Main_Return_len=0;
			Main_Cmd=1;
			Main_start=1;
			Main_Current_State=68;
		end
		68:
		begin
			Main_start=0;
			Main_Current_State=69;
		end
		69:
		begin
			if(spi_op_done)
			begin
				Main_Current_State=70;
			end
		end
/*
// Set properties:           RF_MODEM_AGC_WINDOW_SIZE_9
// Number of properties:     9
// Group ID:                 0x20
// Start ID:                 0x38
// Default values:           0x11, 0x10, 0x10, 0x0B, 0x1C, 0x40, 0x00, 0x00, 0x2B,
// Descriptions:
//   MODEM_AGC_WINDOW_SIZE - Specifies the size of the measurement and settling windows for the AGC algorithm.
//   MODEM_AGC_RFPD_DECAY - Sets the decay time of the RF peak detectors.
//   MODEM_AGC_IFPD_DECAY - Sets the decay time of the IF peak detectors.
//   MODEM_FSK4_GAIN1 - Specifies the gain factor of the secondary branch in 4(G)FSK ISI-suppression.
//   MODEM_FSK4_GAIN0 - Specifies the gain factor of the primary branch in 4(G)FSK ISI-suppression.
//   MODEM_FSK4_TH1 - 16 bit 4(G)FSK slicer threshold.
//   MODEM_FSK4_TH0 - 16 bit 4(G)FSK slicer threshold.
//   MODEM_FSK4_MAP - 4(G)FSK symbol mapping code.
//   MODEM_OOK_PDTC - Configures the attack and decay times of the OOK Peak Detector.
*/		
		70:
		begin
			Main_Cmd_Data[7:0]=8'h11;
			Main_Cmd_Data[15:8]=8'h20;
			Main_Cmd_Data[23:16]=8'h09;
			Main_Cmd_Data[31:24]=8'h38;
			Main_Cmd_Data[39:32]=8'h22;
			Main_Cmd_Data[47:40]=8'h08;
			Main_Cmd_Data[55:48]=8'h08;
			Main_Cmd_Data[63:56]=8'h00;
			Main_Cmd_Data[71:64]=8'h1A;
			Main_Cmd_Data[79:72]=8'h06;
			Main_Cmd_Data[87:80]=8'h66;
			Main_Cmd_Data[95:88]=8'h00;
			Main_Cmd_Data[103:96]=8'h28;
			Main_Data_len=13;
			Main_Return_len=0;
			Main_Cmd=1;
			Main_start=1;
			Main_Current_State=71;
		end
		71:
		begin
			Main_start=0;
			Main_Current_State=72;
		end
		72:
		begin
			if(spi_op_done)
			begin
				Main_Current_State=73;
			end
		end
/*
// Set properties:           RF_MODEM_OOK_CNT1_9
// Number of properties:     9
// Group ID:                 0x20
// Start ID:                 0x42
// Default values:           0xA4, 0x03, 0x56, 0x02, 0x00, 0xA3, 0x02, 0x80, 0xFF,
// Descriptions:
//   MODEM_OOK_CNT1 - OOK control.
//   MODEM_OOK_MISC - Selects the detector(s) used for demodulation of an OOK signal, or for demodulation of a (G)FSK signal when using the asynchronous demodulator.
//   MODEM_RAW_SEARCH - Defines and controls the search period length for the Moving Average and Min-Max detectors.
//   MODEM_RAW_CONTROL - Defines gain and enable controls for raw / nonstandard mode.
//   MODEM_RAW_EYE_1 - 11 bit eye-open detector threshold.
//   MODEM_RAW_EYE_0 - 11 bit eye-open detector threshold.
//   MODEM_ANT_DIV_MODE - Antenna diversity mode settings.
//   MODEM_ANT_DIV_CONTROL - Specifies controls for the Antenna Diversity algorithm.
//   MODEM_RSSI_THRESH - Configures the RSSI threshold.
*/		
		73:
		begin
			Main_Cmd_Data[7:0]=8'h11;
			Main_Cmd_Data[15:8]=8'h20;
			Main_Cmd_Data[23:16]=8'h09;
			Main_Cmd_Data[31:24]=8'h42;
			Main_Cmd_Data[39:32]=8'hA4;
			Main_Cmd_Data[47:40]=8'h03;
			Main_Cmd_Data[55:48]=8'hD6;
			Main_Cmd_Data[63:56]=8'h03;
			Main_Cmd_Data[71:64]=8'h00;
			Main_Cmd_Data[79:72]=8'h1A;
			Main_Cmd_Data[87:80]=8'h01;
			Main_Cmd_Data[95:88]=8'h80;
			Main_Cmd_Data[103:96]=8'h55;
			Main_Data_len=13;
			Main_Return_len=0;
			Main_Cmd=1;
			Main_start=1;
			Main_Current_State=74;
		end
		74:
		begin
			Main_start=0;
			Main_Current_State=75;
		end
		75:
		begin
			if(spi_op_done)
			begin
				Main_Current_State=76;
			end
		end
	/*
// Set properties:           RF_MODEM_RSSI_CONTROL_1
// Number of properties:     1
// Group ID:                 0x20
// Start ID:                 0x4C
// Default values:           0x01,
// Descriptions:
//   MODEM_RSSI_CONTROL - Control of the averaging modes and latching time for reporting RSSI value(s).
*/	
		76:
		begin
			Main_Cmd_Data[7:0]=8'h11;
			Main_Cmd_Data[15:8]=8'h20;
			Main_Cmd_Data[23:16]=8'h01;
			Main_Cmd_Data[31:24]=8'h4C;
			Main_Cmd_Data[39:32]=8'h00;
			Main_Data_len=5;
			Main_Return_len=0;
			Main_Cmd=1;
			Main_start=1;
			Main_Current_State=77;
		end
		77:
		begin
			Main_start=0;
			Main_Current_State=78;
		end
		78:
		begin
			if(spi_op_done)
			begin
				Main_Current_State=79;
			end
		end
	/*
// Set properties:           RF_MODEM_RSSI_COMP_1
// Number of properties:     1
// Group ID:                 0x20
// Start ID:                 0x4E
// Default values:           0x32,
// Descriptions:
//   MODEM_RSSI_COMP - RSSI compensation value.
*/	
		79:
		begin
			Main_Cmd_Data[7:0]=8'h11;
			Main_Cmd_Data[15:8]=8'h20;
			Main_Cmd_Data[23:16]=8'h01;
			Main_Cmd_Data[31:24]=8'h4E;
			Main_Cmd_Data[39:32]=8'h40;
			Main_Data_len=5;
			Main_Return_len=0;
			Main_Cmd=1;
			Main_start=1;
			Main_Current_State=80;
		end
		80:
		begin
			Main_start=0;
			Main_Current_State=81;
		end
		81:
		begin
			if(spi_op_done)
			begin
				Main_Current_State=82;
			end
		end
/*
// Set properties:           RF_MODEM_CLKGEN_BAND_1
// Number of properties:     1
// Group ID:                 0x20
// Start ID:                 0x51
// Default values:           0x08,
// Descriptions:
//   MODEM_CLKGEN_BAND - Select PLL Synthesizer output divider ratio as a function of frequency band.
*/		
		82:
		begin
			Main_Cmd_Data[7:0]=8'h11;
			Main_Cmd_Data[15:8]=8'h20;
			Main_Cmd_Data[23:16]=8'h01;
			Main_Cmd_Data[31:24]=8'h51;
			Main_Cmd_Data[39:32]=8'h0A;
			Main_Data_len=5;
			Main_Return_len=0;
			Main_Cmd=1;
			Main_start=1;
			Main_Current_State=83;
		end
		83:
		begin
			Main_start=0;
			Main_Current_State=84;
		end
		84:
		begin
			if(spi_op_done)
			begin
				Main_Current_State=85;
			end
		end
	/*
// Set properties:           RF_MODEM_CHFLT_RX1_CHFLT_COE13_7_0_12
// Number of properties:     12
// Group ID:                 0x21
// Start ID:                 0x00
// Default values:           0xFF, 0xBA, 0x0F, 0x51, 0xCF, 0xA9, 0xC9, 0xFC, 0x1B, 0x1E, 0x0F, 0x01,
// Descriptions:
//   MODEM_CHFLT_RX1_CHFLT_COE13_7_0 - Filter coefficients for the first set of RX filter coefficients.
//   MODEM_CHFLT_RX1_CHFLT_COE12_7_0 - Filter coefficients for the first set of RX filter coefficients.
//   MODEM_CHFLT_RX1_CHFLT_COE11_7_0 - Filter coefficients for the first set of RX filter coefficients.
//   MODEM_CHFLT_RX1_CHFLT_COE10_7_0 - Filter coefficients for the first set of RX filter coefficients.
//   MODEM_CHFLT_RX1_CHFLT_COE9_7_0 - Filter coefficients for the first set of RX filter coefficients.
//   MODEM_CHFLT_RX1_CHFLT_COE8_7_0 - Filter coefficients for the first set of RX filter coefficients.
//   MODEM_CHFLT_RX1_CHFLT_COE7_7_0 - Filter coefficients for the first set of RX filter coefficients.
//   MODEM_CHFLT_RX1_CHFLT_COE6_7_0 - Filter coefficients for the first set of RX filter coefficients.
//   MODEM_CHFLT_RX1_CHFLT_COE5_7_0 - Filter coefficients for the first set of RX filter coefficients.
//   MODEM_CHFLT_RX1_CHFLT_COE4_7_0 - Filter coefficients for the first set of RX filter coefficients.
//   MODEM_CHFLT_RX1_CHFLT_COE3_7_0 - Filter coefficients for the first set of RX filter coefficients.
//   MODEM_CHFLT_RX1_CHFLT_COE2_7_0 - Filter coefficients for the first set of RX filter coefficients.
*/	
		85:
		begin
			Main_Cmd_Data[7:0]=8'h11;
			Main_Cmd_Data[15:8]=8'h21;
			Main_Cmd_Data[23:16]=8'h0C;
			Main_Cmd_Data[31:24]=8'h00;
			Main_Cmd_Data[39:32]=8'h23;
			Main_Cmd_Data[47:40]=8'h17;
			Main_Cmd_Data[55:48]=8'hF4;
			Main_Cmd_Data[63:56]=8'hC2;
			Main_Cmd_Data[71:64]=8'h88;
			Main_Cmd_Data[79:72]=8'h50;
			Main_Cmd_Data[87:80]=8'h21;
			Main_Cmd_Data[95:88]=8'hFF;
			Main_Cmd_Data[103:96]=8'hEC;
			Main_Cmd_Data[111:104]=8'hE6;
			Main_Cmd_Data[119:112]=8'hE8;
			Main_Cmd_Data[127:120]=8'hEE;
			Main_Data_len=16;
			Main_Return_len=0;
			Main_Cmd=1;
			Main_start=1;
			Main_Current_State=86;
		end
		86:
		begin
			Main_start=0;
			Main_Current_State=87;
		end
		87:
		begin
			if(spi_op_done)
			begin
				Main_Current_State=88;
			end
		end
/*
// Set properties:           RF_MODEM_CHFLT_RX1_CHFLT_COE1_7_0_12
// Number of properties:     12
// Group ID:                 0x21
// Start ID:                 0x0C
// Default values:           0xFC, 0xFD, 0x15, 0xFF, 0x00, 0x0F, 0xFF, 0xC4, 0x30, 0x7F, 0xF5, 0xB5,
// Descriptions:
//   MODEM_CHFLT_RX1_CHFLT_COE1_7_0 - Filter coefficients for the first set of RX filter coefficients.
//   MODEM_CHFLT_RX1_CHFLT_COE0_7_0 - Filter coefficients for the first set of RX filter coefficients.
//   MODEM_CHFLT_RX1_CHFLT_COEM0 - Filter coefficients for the first set of RX filter coefficients.
//   MODEM_CHFLT_RX1_CHFLT_COEM1 - Filter coefficients for the first set of RX filter coefficients.
//   MODEM_CHFLT_RX1_CHFLT_COEM2 - Filter coefficients for the first set of RX filter coefficients.
//   MODEM_CHFLT_RX1_CHFLT_COEM3 - Filter coefficients for the first set of RX filter coefficients.
//   MODEM_CHFLT_RX2_CHFLT_COE13_7_0 - Filter coefficients for the second set of RX filter coefficients.
//   MODEM_CHFLT_RX2_CHFLT_COE12_7_0 - Filter coefficients for the second set of RX filter coefficients.
//   MODEM_CHFLT_RX2_CHFLT_COE11_7_0 - Filter coefficients for the second set of RX filter coefficients.
//   MODEM_CHFLT_RX2_CHFLT_COE10_7_0 - Filter coefficients for the second set of RX filter coefficients.
//   MODEM_CHFLT_RX2_CHFLT_COE9_7_0 - Filter coefficients for the second set of RX filter coefficients.
//   MODEM_CHFLT_RX2_CHFLT_COE8_7_0 - Filter coefficients for the second set of RX filter coefficients.
*/		
		88:
		begin
			Main_Cmd_Data[7:0]=8'h11;
			Main_Cmd_Data[15:8]=8'h21;
			Main_Cmd_Data[23:16]=8'h0C;
			Main_Cmd_Data[31:24]=8'h0C;
			Main_Cmd_Data[39:32]=8'hF6;
			Main_Cmd_Data[47:40]=8'hFB;
			Main_Cmd_Data[55:48]=8'h05;
			Main_Cmd_Data[63:56]=8'hC0;
			Main_Cmd_Data[71:64]=8'hFF;
			Main_Cmd_Data[79:72]=8'h0F;
			Main_Cmd_Data[87:80]=8'h23;
			Main_Cmd_Data[95:88]=8'h17;
			Main_Cmd_Data[103:96]=8'hF4;
			Main_Cmd_Data[111:104]=8'hC2;
			Main_Cmd_Data[119:112]=8'h88;
			Main_Cmd_Data[127:120]=8'h50;
			Main_Data_len=16;
			Main_Return_len=0;
			Main_Cmd=1;
			Main_start=1;
			Main_Current_State=89;
		end
		89:
		begin
			Main_start=0;
			Main_Current_State=90;
		end
		90:
		begin
			if(spi_op_done)
			begin
				Main_Current_State=91;
			end
		end
/*
// Set properties:           RF_MODEM_CHFLT_RX2_CHFLT_COE7_7_0_12
// Number of properties:     12
// Group ID:                 0x21
// Start ID:                 0x18
// Default values:           0xB8, 0xDE, 0x05, 0x17, 0x16, 0x0C, 0x03, 0x00, 0x15, 0xFF, 0x00, 0x00,
// Descriptions:
//   MODEM_CHFLT_RX2_CHFLT_COE7_7_0 - Filter coefficients for the second set of RX filter coefficients.
//   MODEM_CHFLT_RX2_CHFLT_COE6_7_0 - Filter coefficients for the second set of RX filter coefficients.
//   MODEM_CHFLT_RX2_CHFLT_COE5_7_0 - Filter coefficients for the second set of RX filter coefficients.
//   MODEM_CHFLT_RX2_CHFLT_COE4_7_0 - Filter coefficients for the second set of RX filter coefficients.
//   MODEM_CHFLT_RX2_CHFLT_COE3_7_0 - Filter coefficients for the second set of RX filter coefficients.
//   MODEM_CHFLT_RX2_CHFLT_COE2_7_0 - Filter coefficients for the second set of RX filter coefficients.
//   MODEM_CHFLT_RX2_CHFLT_COE1_7_0 - Filter coefficients for the second set of RX filter coefficients.
//   MODEM_CHFLT_RX2_CHFLT_COE0_7_0 - Filter coefficients for the second set of RX filter coefficients.
//   MODEM_CHFLT_RX2_CHFLT_COEM0 - Filter coefficients for the second set of RX filter coefficients.
//   MODEM_CHFLT_RX2_CHFLT_COEM1 - Filter coefficients for the second set of RX filter coefficients.
//   MODEM_CHFLT_RX2_CHFLT_COEM2 - Filter coefficients for the second set of RX filter coefficients.
//   MODEM_CHFLT_RX2_CHFLT_COEM3 - Filter coefficients for the second set of RX filter coefficients.
*/		
		91:
		begin
			Main_Cmd_Data[7:0]=8'h11;
			Main_Cmd_Data[15:8]=8'h21;
			Main_Cmd_Data[23:16]=8'h0C;
			Main_Cmd_Data[31:24]=8'h18;
			Main_Cmd_Data[39:32]=8'h21;
			Main_Cmd_Data[47:40]=8'hFF;
			Main_Cmd_Data[55:48]=8'hEC;
			Main_Cmd_Data[63:56]=8'hE6;
			Main_Cmd_Data[71:64]=8'hE8;
			Main_Cmd_Data[79:72]=8'hEE;
			Main_Cmd_Data[87:80]=8'hF6;
			Main_Cmd_Data[95:88]=8'hFB;
			Main_Cmd_Data[103:96]=8'h05;
			Main_Cmd_Data[111:104]=8'hC0;
			Main_Cmd_Data[119:112]=8'hFF;
			Main_Cmd_Data[127:120]=8'h0F;
			Main_Data_len=16;
			Main_Return_len=0;
			Main_Cmd=1;
			Main_start=1;
			Main_Current_State=92;
		end
		92:
		begin
			Main_start=0;
			Main_Current_State=93;
		end
		93:
		begin
			if(spi_op_done)
			begin
				Main_Current_State=94;
			end
		end
/*
// Set properties:           RF_PA_MODE_4
// Number of properties:     4
// Group ID:                 0x22
// Start ID:                 0x00
// Default values:           0x08, 0x7F, 0x00, 0x5D,
// Descriptions:
//   PA_MODE - Selects the PA operating mode, and selects resolution of PA power adjustment (i.e., step size).
//   PA_PWR_LVL - Configuration of PA output power level.
//   PA_BIAS_CLKDUTY - Configuration of the PA Bias and duty cycle of the TX clock source.
//   PA_TC - Configuration of PA ramping parameters.
*/		
		94:
		begin
			Main_Cmd_Data[7:0]=8'h11;
			Main_Cmd_Data[15:8]=8'h22;
			Main_Cmd_Data[23:16]=8'h04;
			Main_Cmd_Data[31:24]=8'h00;
			Main_Cmd_Data[39:32]=8'h08;
			Main_Cmd_Data[47:40]=8'h7F;
			Main_Cmd_Data[55:48]=8'h00;
			Main_Cmd_Data[63:56]=8'h5D;
			Main_Data_len=8;
			Main_Return_len=0;
			Main_Cmd=1;
			Main_start=1;
			Main_Current_State=95;
		end
		95:
		begin
			Main_start=0;
			Main_Current_State=96;
		end
		96:
		begin
			if(spi_op_done)
			begin
				Main_Current_State=97;
			end
		end
/*
// Set properties:           RF_SYNTH_PFDCP_CPFF_7
// Number of properties:     7
// Group ID:                 0x23
// Start ID:                 0x00
// Default values:           0x2C, 0x0E, 0x0B, 0x04, 0x0C, 0x73, 0x03,
// Descriptions:
//   SYNTH_PFDCP_CPFF - Feed forward charge pump current selection.
//   SYNTH_PFDCP_CPINT - Integration charge pump current selection.
//   SYNTH_VCO_KV - Gain scaling factors (Kv) for the VCO tuning varactors on both the integrated-path and feed forward path.
//   SYNTH_LPFILT3 - Value of resistor R2 in feed-forward path of loop filter.
//   SYNTH_LPFILT2 - Value of capacitor C2 in feed-forward path of loop filter.
//   SYNTH_LPFILT1 - Value of capacitors C1 and C3 in feed-forward path of loop filter.
//   SYNTH_LPFILT0 - Bias current of the active amplifier in the feed-forward loop filter.
*/		
		97:
		begin
			Main_Cmd_Data[7:0]=8'h11;
			Main_Cmd_Data[15:8]=8'h23;
			Main_Cmd_Data[23:16]=8'h07;
			Main_Cmd_Data[31:24]=8'h00;
			Main_Cmd_Data[39:32]=8'h01;
			Main_Cmd_Data[47:40]=8'h05;
			Main_Cmd_Data[55:48]=8'h0B;
			Main_Cmd_Data[63:56]=8'h05;
			Main_Cmd_Data[71:64]=8'h02;
			Main_Cmd_Data[79:72]=8'h00;
			Main_Cmd_Data[87:80]=8'h03;
			Main_Data_len=11;
			Main_Return_len=0;
			Main_Cmd=1;
			Main_start=1;
			Main_Current_State=98;
		end
		98:
		begin
			Main_start=0;
			Main_Current_State=99;
		end
		99:
		begin
			if(spi_op_done)
			begin
				Main_Current_State=100;
			end
		end
/*
// Set properties:           RF_MATCH_VALUE_1_12
// Number of properties:     12
// Group ID:                 0x30
// Start ID:                 0x00
// Default values:           0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
// Descriptions:
//   MATCH_VALUE_1 - Match value to be compared with the result of logically AND-ing (bit-wise) the Mask 1 value with the received Match 1 byte.
//   MATCH_MASK_1 - Mask value to be logically AND-ed (bit-wise) with the Match 1 byte.
//   MATCH_CTRL_1 - Enable for Packet Match functionality, and configuration of Match Byte 1.
//   MATCH_VALUE_2 - Match value to be compared with the result of logically AND-ing (bit-wise) the Mask 2 value with the received Match 2 byte.
//   MATCH_MASK_2 - Mask value to be logically AND-ed (bit-wise) with the Match 2 byte.
//   MATCH_CTRL_2 - Configuration of Match Byte 2.
//   MATCH_VALUE_3 - Match value to be compared with the result of logically AND-ing (bit-wise) the Mask 3 value with the received Match 3 byte.
//   MATCH_MASK_3 - Mask value to be logically AND-ed (bit-wise) with the Match 3 byte.
//   MATCH_CTRL_3 - Configuration of Match Byte 3.
//   MATCH_VALUE_4 - Match value to be compared with the result of logically AND-ing (bit-wise) the Mask 4 value with the received Match 4 byte.
//   MATCH_MASK_4 - Mask value to be logically AND-ed (bit-wise) with the Match 4 byte.
//   MATCH_CTRL_4 - Configuration of Match Byte 4.
*/		
		100:
		begin
			Main_Cmd_Data[7:0]=8'h11;
			Main_Cmd_Data[15:8]=8'h30;
			Main_Cmd_Data[23:16]=8'h0C;
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
			Main_Data_len=16;
			Main_Return_len=0;
			Main_Cmd=1;
			Main_start=1;
			Main_Current_State=101;
		end
		101:
		begin
			Main_start=0;
			Main_Current_State=102;
		end
		102:
		begin
			if(spi_op_done)
			begin
				Main_Current_State=103;
			end
		end
	/*
// Set properties:           RF_FREQ_CONTROL_INTE_8
// Number of properties:     8
// Group ID:                 0x40
// Start ID:                 0x00
// Default values:           0x3C, 0x08, 0x00, 0x00, 0x00, 0x00, 0x20, 0xFF,
// Descriptions:
//   FREQ_CONTROL_INTE - Frac-N PLL Synthesizer integer divide number.
//   FREQ_CONTROL_FRAC_2 - Frac-N PLL fraction number.
//   FREQ_CONTROL_FRAC_1 - Frac-N PLL fraction number.
//   FREQ_CONTROL_FRAC_0 - Frac-N PLL fraction number.
//   FREQ_CONTROL_CHANNEL_STEP_SIZE_1 - EZ Frequency Programming channel step size.
//   FREQ_CONTROL_CHANNEL_STEP_SIZE_0 - EZ Frequency Programming channel step size.
//   FREQ_CONTROL_W_SIZE - Set window gating period (in number of crystal reference clock cycles) for counting VCO frequency during calibration.
//   FREQ_CONTROL_VCOCNT_RX_ADJ - Adjust target count for VCO calibration in RX mode.
*/	
		103:
		begin
			Main_Cmd_Data[7:0]=8'h11;
			Main_Cmd_Data[15:8]=8'h40;
			Main_Cmd_Data[23:16]=8'h08;
			Main_Cmd_Data[31:24]=8'h00;
			Main_Cmd_Data[39:32]=8'h38;
			Main_Cmd_Data[47:40]=8'h0D;
			Main_Cmd_Data[55:48]=8'hDD;
			Main_Cmd_Data[63:56]=8'hDD;
			Main_Cmd_Data[71:64]=8'h44;
			Main_Cmd_Data[79:72]=8'h44;
			Main_Cmd_Data[87:80]=8'h20;
			Main_Cmd_Data[95:88]=8'hFE;
			Main_Data_len=12;
			Main_Return_len=0;
			Main_Cmd=1;
			Main_start=1;
			Main_Current_State=104;
		end
		104:
		begin
			Main_start=0;
			Main_Current_State=105;
		end
		105:
		begin
			if(spi_op_done)
			begin
				Main_Current_State=106;
			end
		end
	////set_frr_ctl 设置快速寄存器的功能
		106:
		begin
			Main_Cmd_Data[7:0]=8'h11;
			Main_Cmd_Data[15:8]=8'h02;
			Main_Cmd_Data[23:16]=8'h04;
			Main_Cmd_Data[31:24]=8'h00;
			Main_Cmd_Data[39:32]=8'h04;
			Main_Cmd_Data[47:40]=8'h02;
			Main_Cmd_Data[55:48]=8'h09;
			Main_Cmd_Data[63:56]=8'h00;
			Main_Data_len=8;
			Main_Return_len=0;
			Main_Cmd=1;
			Main_start=1;
			Main_Current_State=107;
		end
		107:
		begin
			Main_start=0;
			Main_Current_State=108;
		end
		108:
		begin
			if(spi_op_done)
			begin
				Main_Current_State=109;
			end
		end
	
	/////Function_set_tran_property,设置射频模块上发送相关的寄存器
		109:
		begin
			Main_Cmd_Data[7:0]=8'h11;
			Main_Cmd_Data[15:8]=8'h12;
			Main_Cmd_Data[23:16]=8'h01;
			Main_Cmd_Data[31:24]=8'h06;
			Main_Cmd_Data[39:32]=8'h80;
			Main_Data_len=5;
			Main_Return_len=0;
			Main_Cmd=1;
			Main_start=1;
			Main_Current_State=110;
		end
		110:
		begin
			Main_start=0;
			Main_Current_State=111;
		end
		111:
		begin
			if(spi_op_done)
			begin
				Main_Current_State=112;
			end
		end
		
		112:
		begin
			Main_Cmd_Data[7:0]=8'h11;
			Main_Cmd_Data[15:8]=8'h12;
			Main_Cmd_Data[23:16]=8'h03;
			Main_Cmd_Data[31:24]=8'h08;
			Main_Cmd_Data[39:32]=8'h02;
			Main_Cmd_Data[47:40]=8'h01;
			Main_Cmd_Data[55:48]=8'h00;
			Main_Data_len=7;
			Main_Return_len=0;
			Main_Cmd=1;
			Main_start=1;
			Main_Current_State=113;
		end
		113:
		begin
			Main_start=0;
			Main_Current_State=114;
		end
		114:
		begin
			if(spi_op_done)
			begin
				Main_Current_State=115;
			end
		end
		
		115:
		begin
			Main_Cmd_Data[7:0]=8'h11;
			Main_Cmd_Data[15:8]=8'h12;
			Main_Cmd_Data[23:16]=8'h04;
			Main_Cmd_Data[31:24]=8'h0D;
			Main_Cmd_Data[39:32]=8'h00;
			Main_Cmd_Data[47:40]=8'h00;
			Main_Cmd_Data[55:48]=8'h00;
			Main_Cmd_Data[63:56]=8'hA0;
			Main_Data_len=8;
			Main_Return_len=0;
			Main_Cmd=1;
			Main_start=1;
			Main_Current_State=116;
		end
		116:
		begin
			Main_start=0;
			Main_Current_State=117;
		end
		117:
		begin
			if(spi_op_done)
			begin
				Main_Current_State=118;
			end
		end
		
		118:
		begin
			Main_Cmd_Data[7:0]=8'h11;
			Main_Cmd_Data[15:8]=8'h12;
			Main_Cmd_Data[23:16]=8'h04;
			Main_Cmd_Data[31:24]=8'h0D;
			Main_Cmd_Data[39:32]=8'h00;
			Main_Cmd_Data[47:40]=8'h01;
			Main_Cmd_Data[55:48]=8'h00;
			Main_Cmd_Data[63:56]=8'h80;
			Main_Data_len=8;
			Main_Return_len=0;
			Main_Cmd=1;
			Main_start=1;
			Main_Current_State=119;
		end
		119:
		begin
			Main_start=0;
			Main_Current_State=120;
		end
		120:
		begin
			if(spi_op_done)
			begin
				Main_Current_State=121;
			end
		end
		
		121:
		begin
			Main_Cmd_Data[7:0]=8'h11;
			Main_Cmd_Data[15:8]=8'h12;
			Main_Cmd_Data[23:16]=8'h04;
			Main_Cmd_Data[31:24]=8'h25;
			Main_Cmd_Data[39:32]=8'h00;
			Main_Cmd_Data[47:40]=8'hFA;  //包的最大长度为250个字节
			Main_Cmd_Data[55:48]=8'h00;
			Main_Cmd_Data[63:56]=8'h00;
			Main_Data_len=8;
			Main_Return_len=0;
			Main_Cmd=1;
			Main_start=1;
			Main_Current_State=122;
		end
		122:
		begin
			Main_start=0;
			Main_Current_State=123;
		end
		123:
		begin
			if(spi_op_done)
			begin
				Main_Current_State=124;
			end
		end
		
		124:
		begin
			Main_Cmd_Data[7:0]=8'h11;
			Main_Cmd_Data[15:8]=8'h12;
			Main_Cmd_Data[23:16]=8'h02;
			Main_Cmd_Data[31:24]=8'h0B;
			Main_Cmd_Data[39:32]=8'h23;
			Main_Cmd_Data[47:40]=8'h30;
			Main_Data_len=6;
			Main_Return_len=0;
			Main_Cmd=1;
			Main_start=1;
			Main_Current_State=125;
		end
		125:
		begin
			Main_start=0;
			Main_Current_State=126;
		end
		126:
		begin
			if(spi_op_done)
			begin
				Main_Current_State=127;
			end
		end
		
		127:
		begin
			Main_Cmd_Data[7:0]=8'h11;
			Main_Cmd_Data[15:8]=8'h00;
			Main_Cmd_Data[23:16]=8'h01;
			Main_Cmd_Data[31:24]=8'h03;
			Main_Cmd_Data[39:32]=8'h70;
			Main_Data_len=5;
			Main_Return_len=0;
			Main_Cmd=1;
			Main_start=1;
			Main_Current_State=128;
		end
		128:
		begin
			Main_start=0;
			Main_Current_State=129;
		end
		129:
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
				if(Main_Return_Data[15:8]==16'h03)
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
				if(Main_Data_Check[15:8]==8'h66)
				begin
					//led=SRAM_count[3:0];
					Data_Len_to_Send=Main_Data_Check[7:0];
					if(SRAM_count*2>=Data_Len_to_Send)
					begin
						Main_Current_State=133;
					end
				end
				else
					Main_Current_State=130;
			end
		end
		
		/////如果SPI正在被使用则等待，否则发送命令切换状态为tx_tune///////
		
		////切换状态0x34 05 TX_TUNE
		133:
		begin
			if(!spi_Using&&!rx_start)
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
				Main_Data_len=Data_Len_to_Send+1;  //目前最大为126
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
			if(tx_done)
			begin
			
				tx_state=`RX;
				Main_Current_State=130;
			end
		end
			
	endcase

end


reg [3:0] Irq_Current_State=0;
reg [3:0] Recv_Current_State=0;
reg tx_done=0; //置1表示发送完成
reg rx_start=0;
reg tx_flag=0; //是发送完成中断
reg rx_flag=0;
reg [7:0] Si4463_Ph_Status=0;
reg [7:0] frame_len;

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
		//////读取中断状态，判断中断源
		1:
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
				Si4463_Ph_Status=Int_Return_Data[47:40];
				if((Si4463_Ph_Status)==8'b00100010 || (Si4463_Ph_Status)==8'b00100000) //发送完成中断
				begin
					
					tx_flag=1;
					Irq_Current_State=4;
				end
				if((Si4463_Ph_Status&8'h10)==8'b00010000) //接收中断
				begin
					Irq_Current_State=4;
					rx_flag=1;
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
			
				Recv_Current_State=1;
			end
		end
		1:
		begin //获取射频模块中数据的长度,getPacket()
			if(!spi_Using)
			begin
				Int_Cmd_Data[7:0]=8'h16;
				Int_start=1;
				Int_Cmd=4;
				Int_Data_len=1;
				Int_Return_len=2;
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
				frame_len=Int_Return_Data[15:8];
				Recv_Current_State=4;
			end
		end
		4: //发送接收命令   ，如果不行的话，可以将这个命令放在SPI中
		begin
			if(frame_len> 128)       //128是FIFO的缓冲区长度
			begin
				if(!spi_Using)
				begin
					Int_Data_len=128;
					Int_Return_len=0;
					Int_start=1;
					Int_Cmd=3;
					Recv_Current_State=5;
				end
			end
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
				//rx_flag=0;
				frame_recved_int=1;
				Recv_Current_State=7;
			end
		end
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
				Int_Cmd=3;
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
		end
		default:
		begin
			rx_start=0;
			tx_done=0;
			Recv_Current_State=0;
		end
	endcase
end


endmodule
