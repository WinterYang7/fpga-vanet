module Slave_Ctrl(
	clk,
	
	//与CPU的接口
	mosi,
	miso,
	sclk,
	//signal_int,
	
	//与SRAM的接口
	SRAM_read,
	SRAM_write,
	SRAM_hint,
	Data_to_sram,
	Data_from_sram,
	SRAM_full,
	SRAM_empty,
	SRAM_count,
	
	Config_write_sram,
	Config_write_sram_done,	

	Cmd_write_sram,
	Cmd_write_sram_done,
	
	//帧接收中断,与wireless_ctrl连接
	//frame_recved_int,
	Pkt_Received_int,
	
	//与CPU连接的中断
	cpu_recv_int,
	
	Spi_Current_State_1,
	Spi_rrdy,
	Spi_trdy,
	Data_from_spi,
	
	//用于输出当前状态
	Slave_Ctrl_Status,
	Slave_Ctrl_Debug
);
output [7:0] Slave_Ctrl_Status;
assign Slave_Ctrl_Status[5:0]=Spi_Current_State;
assign Slave_Ctrl_Status[6]=0;
//assign Slave_Ctrl_Status[7]=Pkt_Received_int;
//assign Slave_Ctrl_Status[2:0]=Irq_Current_State[2:0];
assign Slave_Ctrl_Status[7] = Pkt_Received_int;

output [1:0] Slave_Ctrl_Debug;//for DUBUG
//assign Slave_Ctrl_Debug=Irq_Current_State[1:0];

output Data_from_spi;
output Spi_trdy;
output Spi_rrdy;
input	clk;
//input frame_recved_int;
input Pkt_Received_int;
output reg cpu_recv_int=1'b1;
output  [7:0] Spi_Current_State_1;	
//assign Spi_Current_State_1={3'b000,Spi_Current_State};
	//与CPU的接口
input	mosi;
output	miso;
input	sclk;
//output	signal_int;
	
//与SRAM的接口
output reg Config_write_sram=0;
output reg Config_write_sram_done=0;	

output reg Cmd_write_sram=0;
output reg Cmd_write_sram_done=0;

output reg	SRAM_read=0;
output reg  SRAM_write=0;
input	SRAM_hint;
output reg [15:0]	Data_to_sram;
input[15:0]	Data_from_sram;
reg[15:0] Data_from_sram_reg;
input	SRAM_full;
input	SRAM_empty;
input[17:0]	SRAM_count;

//与spi的连线
wire slave_reset_n;
assign slave_reset_n=0;
wire slave_ss_n;
assign slave_ss_n=0;

wire slave_irq; //SPI slave接到一个字节给一个脉冲
reg[7:0] slave_data_to_spi; //FPGA提供给Galileo的数据
wire[7:0] slave_data_from_spi;
reg[7:0] slave_data_from_spi_reg;
reg slave_write;
wire slave_trdy;

	spi_slave slave(
	.RESET_in(slave_reset_n),
    .CLK_in(clk),
    .SPI_CLK(sclk),
    .SPI_SS(slave_ss_n),
    .SPI_MOSI(mosi),
    .SPI_MISO(miso),
    .SPI_DONE(slave_irq),
    .DataToTx(slave_data_to_spi),
    .DataToTxLoad(slave_write),
    .DataRxd(slave_data_from_spi),
	 .readyfordata(slave_trdy)
    //.index1		: out natural range 0 to 7
    );

///////监听SPI，根据情况进行选择，循环监听命令
//为了更好地适应性，决定采用与射频模块类似的模式
/*
	CPU发送数据流 cmd::0x66+data_len+数据
	CPU接收数据流 cmd::0x77+data_len 发送完后，需要等待一段时间
				  返回：SRAM中的数据流
	获取SRAM中字节数： //这个也可以不需要，而是等到SRAM中数据到达一定值或者一个完整的包后，给CPU中断
				  另外一种方式是从SRAM中取出数据，等到取完之后，给CPU放松一个标志符0xFFFF，很可能需要两个字节
				  



*/
reg[5:0] Spi_Current_State=0;
reg[7:0] Data_len=0;
reg[7:0] Sended_count=0;
reg Byte_flag=0;
reg irq_noted=0;
//reg tx_flag=0;
//reg rx_flag=0;
reg[15:0] Config_len=0;
reg[15:0] Config_count=0;

reg[7:0] Cmd_len=0;
reg[7:0] Cmd_count=0;

//中断决策
reg[7:0] packet_len=0;
reg spi_send_end=1; //发送给CPU的数据已经发送完，说明准备接收下一个中断
wire spi_send_end_wire;
assign spi_send_end_wire=spi_send_end;
reg spi_read_sram=0; //spi读取SRAM的使能信号


//reset_n
reg reset_n=1;
wire reset_n_wire;
assign reset_n_wire=reset_n;

////中断//////不需要等待，用户读取之后，自动清除中断
reg[2:0] Irq_Current_State=0;
reg[15:0] bufferd_pkt_count=0;
reg Counter_State=0;

always@(posedge clk)
begin

	if(!reset_n_wire)
	begin
		Irq_Current_State=0;
		SRAM_read=0;
		cpu_recv_int=1;
		bufferd_pkt_count=0;
		Counter_State=0;
	end
	
	case (Counter_State)
		0:
		begin
			if(Pkt_Received_int)
			begin
				Counter_State=1;
				
			end
		end
		1:
		begin
			Counter_State=0;
			bufferd_pkt_count=bufferd_pkt_count+1'b1;
		end
	endcase

	case (Irq_Current_State)
		0:
		begin
			if(bufferd_pkt_count>0)
			begin
				SRAM_read=1;
				Irq_Current_State=1;			
			end
		end
		1:
		begin
			if(SRAM_hint) 
			begin
				SRAM_read=0;
				
				if(Data_from_sram==16'h2DD4)
					Irq_Current_State=2;
				else
					Irq_Current_State=0;
			end
		end
		2:
		begin
			if(!SRAM_empty) //读取包长度和第一个数据
			begin
				SRAM_read=1;
				Irq_Current_State=3;
			end
		end
		3:
		begin
			if(SRAM_hint)
			begin
				SRAM_read=0;
				Data_from_sram_reg=Data_from_sram;
				packet_len=Data_from_sram_reg[15:8];
				if(packet_len==0)
					Irq_Current_State=0;
				else
					Irq_Current_State=4;
			end
		end
		4:
		begin
			//if(SRAM_count*2>=packet_len-1)//一次count计数是两个字节。
			//begin
			cpu_recv_int=0;
			Irq_Current_State=5;
			//end
		end
		5:
		begin
			if(irq_noted)
				Irq_Current_State=6;
		end
		6:
		begin
			if(spi_send_end_wire)
			begin
				cpu_recv_int=1;
				Irq_Current_State=0;
				bufferd_pkt_count=bufferd_pkt_count-1'b1;
			end
		end
		
/*		
		4:
		begin
			if(!spi_send_end_wire)
			begin
				if(spi_read_sram)
				begin
					if(!SRAM_empty)
					begin
						SRAM_read=1;
						Irq_Current_State=5;
					end
				end
			end
			else
			begin
					Irq_Current_State=0;
			end
		end
		5:
		begin
			if(SRAM_hint)
			begin
				Data_from_sram_reg=Data_from_sram;
				SRAM_read=0;
				Irq_Current_State=4;
			end
		end
	*/
/*		default:
		begin
			cpu_recv_int=1;
			Irq_Current_State=0;
		end
*/
	endcase



	case (Spi_Current_State)
		0:
		begin
			if(slave_irq)
			begin
				slave_data_from_spi_reg=slave_data_from_spi;
				Spi_Current_State=3;
			end
		end
		3:
		begin
			case(slave_data_from_spi_reg)
				8'b00010001: //写配置文件命令0x11
				begin
					//Sended_count=0;
					Byte_flag=0;
					Config_len[15:0]=16'b0;
					Config_count[15:0]=16'b0;
					Spi_Current_State=30;
				end
				8'b00010010: //写单条命令（不重启）0x12
				begin
					Byte_flag=0;
					Cmd_len[7:0]=8'b0;
					Cmd_count[7:0]=8'b0;
					Spi_Current_State=45;
				end
				
				8'b01100110: //CPU发送数据0x66
				begin
					Data_to_sram[15:8]=8'h2D;
					Sended_count=0;
					Byte_flag=0;
					//tx_flag=1;
					Spi_Current_State=4;
				end
				8'b01110111: //CPU接收数据0x77
				begin
					//rx_flag=1;
					irq_noted=1;
					Sended_count=0;
					spi_send_end=0;
					Spi_Current_State=24; 
				end
				default:
				begin
					Spi_Current_State=0;
				end
			endcase
		end
		/**
		 * 接收配置文件，配置文件第一个字节为整个配置的字节长度（两个字节宽）
		 * 30~
		 */
		30://接收配置长度
		begin
			if(slave_irq)
			begin
				slave_data_from_spi_reg=slave_data_from_spi;
				Spi_Current_State=31;
			end
		end
		31://接收配置长度
		begin
			if(!Byte_flag)
			begin
				Config_len[15:8]=slave_data_from_spi_reg;//长度第一个字节
				Byte_flag=~Byte_flag;
				Spi_Current_State=30;//接收第二个字节
			end
			else
			begin
				Config_len[7:0]=slave_data_from_spi_reg;//长度第二个字节
				Spi_Current_State=32;//开始接收配置数据
				Byte_flag=~Byte_flag;
			end
		end
		32://配置长度写入sram
		begin
			Data_to_sram[15:0]=Config_len[15:0];
			Config_write_sram=1;
			Spi_Current_State=33;
		end
		33:
		begin
			if(SRAM_hint)
			begin
				Config_write_sram=0;
				Spi_Current_State=34;
			end
		end
		34://接收配置数据
		begin
			if(slave_irq)
			begin
				slave_data_from_spi_reg=slave_data_from_spi;
				Spi_Current_State=35;
			end
		end
		35:
		begin
			if(!Byte_flag)
			begin
				Data_to_sram[15:8]=slave_data_from_spi_reg;
				Byte_flag=~Byte_flag;
				Config_count=Config_count+1'b1;
				if(Config_count>=Config_len)
				begin
					Data_to_sram[7:0]=8'b000;
					Byte_flag=~Byte_flag;
					Spi_Current_State=36;//接收完毕
				end
				else
				begin
					Spi_Current_State=34;//继续接收
				end
			end
			else
			begin
				Data_to_sram[7:0]=slave_data_from_spi_reg;
				Byte_flag=~Byte_flag;
				Config_count=Config_count+1'b1;
				Spi_Current_State=36;//接收了2个字节，写入sram
			end
		end
		36://配置数据写入sram
		begin
			Config_write_sram=1;
			Spi_Current_State=37;
		end
		37:
		begin
			if(SRAM_hint)
			begin
				Config_write_sram=0;
				if(Config_count<Config_len)
				begin
					Spi_Current_State=34; //配置数据还没有接收完毕
				end
				else
				begin
					Spi_Current_State=38;
				end
			end
		end
		38://配置文件接收完毕，给SRAM control一个复位信号，复位给Galileo的中断信号
		begin
			Config_write_sram_done=1;
			Spi_Current_State=39;
		end
		39:
		begin
			Config_write_sram_done=0;
			Spi_Current_State=40;//0;
		end
		40:
		begin
			irq_noted=0;
			Spi_Current_State=41;
		end
		41:
		begin
			reset_n=0;
			Spi_Current_State=42;
		end
		42:
		begin
			reset_n=1;
			Spi_Current_State=0;
		end
		
		/**
		 * 0x12，接收单条命令，目的是写寄存器，不重启设备
		 *       第一个字节为命令长度，后续跟命令；写入SRAM时，第一个字节为长度，后续第二个字节填充0，然后是命令实体，。
		 */
		45://接收cmd长度
		begin
			if(slave_irq)
			begin
				Cmd_len[7:0]=slave_data_from_spi[7:0];
				Spi_Current_State=46;
			end
		end
		46://配置长度写入sram
		begin
			Data_to_sram[15:8]=Cmd_len[7:0];
			Data_to_sram[7:0]=8'b0;
			Cmd_write_sram=1;
			Spi_Current_State=47;
		end
		47:
		begin
			if(SRAM_hint)
			begin
				Cmd_write_sram=0;
				Spi_Current_State=48;
			end
		end		
		48://接收CMD数据
		begin
			if(slave_irq)
			begin
				slave_data_from_spi_reg=slave_data_from_spi;
				Spi_Current_State=49;
			end
		end
		49:
		begin
			if(!Byte_flag)
			begin
				Data_to_sram[15:8]=slave_data_from_spi_reg;
				Byte_flag=~Byte_flag;
				Cmd_count=Cmd_count+1'b1;
				if(Cmd_count>=Cmd_len)
				begin
					Data_to_sram[7:0]=8'b000;
					Byte_flag=~Byte_flag;
					Spi_Current_State=50;//接收完毕
				end
				else
				begin
					Spi_Current_State=48;//继续接收
				end
			end
			else
			begin
				Data_to_sram[7:0]=slave_data_from_spi_reg;
				Byte_flag=~Byte_flag;
				Cmd_count=Cmd_count+1'b1;
				Spi_Current_State=50;//接收了2个字节，写入sram
			end
		end		
		50:
		begin
			Cmd_write_sram=1;
			Spi_Current_State=51;
		end
		51:
		begin
			if(SRAM_hint)
			begin
				Cmd_write_sram=0;
				if(Cmd_count<Cmd_len)
				begin
					Spi_Current_State=48; //配置数据还没有接收完毕
				end
				else
				begin
					Spi_Current_State=52;
				end
			end
		end
		52://cmd接收完毕，通知wireless_ctrl将该命令通过spi master发送出去
		begin
			Cmd_write_sram_done=1;
			Spi_Current_State=53;
		end
		53:
		begin
			Cmd_write_sram_done=0;
			Spi_Current_State=0;
		end


		
		4:
		begin
			if(slave_irq)
			begin
				slave_data_from_spi_reg=slave_data_from_spi;
				Spi_Current_State=6;
			end
		end
		6:
		begin
			Data_len=slave_data_from_spi_reg;
			Data_to_sram[7:0]=8'hD4;
			Spi_Current_State=7;
		end
		//将命令写入SRAM 0x2d 0xd4
		7:
		begin
			if(!SRAM_full)
			begin
				SRAM_write=1;
				Spi_Current_State=8;
			end
		end
		8:
		begin
			if(SRAM_hint)
			begin
				SRAM_write=0;
				Spi_Current_State=9;
			end
		end
		//将数据长度写入SRAM
		9: /*一个第一个长度是给控制程序识别的整体长度，第二个长度是要发送出去的数据包长度*/
		begin
			if(!SRAM_full)
			begin
				Data_to_sram={8'h00,Data_len[7:0]+1}; //+1是因为将数据长度包含在内
				SRAM_write=1;
				Spi_Current_State=10;
			end
		end
		10:
		begin
			if(SRAM_hint)
			begin
				SRAM_write=0;
				Data_to_sram[15:8]=Data_len; //将数据长度添加到数据帧头部
				Byte_flag=~Byte_flag;
				Spi_Current_State=11;
				
			end
		end
		
		//从SPI读取数据并写入SRAM
		11:
		begin
			if(slave_irq)
			begin
				slave_data_from_spi_reg=slave_data_from_spi;
				Spi_Current_State=13;
			end
		end
		13:
		begin
			if(!Byte_flag)
			begin
				Data_to_sram[15:8]=slave_data_from_spi_reg;
				Byte_flag=~Byte_flag;
				Sended_count=Sended_count+1'b1;
				Spi_Current_State=11;
				if(Sended_count>=Data_len)
				begin
					Data_to_sram[7:0]=8'b000;
					Byte_flag=~Byte_flag;
					Spi_Current_State=14;
				end
			end
			else
			begin
				Data_to_sram[7:0]=slave_data_from_spi_reg;
				Byte_flag=~Byte_flag;
				Sended_count=Sended_count+1'b1;
				Spi_Current_State=14;
			end
		end
		
		14:
		begin
			if(!SRAM_full)
			begin
				SRAM_write=1;
				Spi_Current_State=15;
			end
		end
		15:
		begin
			if(SRAM_hint)
			begin
				
				SRAM_write=0;
				if(Sended_count<Data_len)
				begin
					Spi_Current_State=11;
				end
				else
				begin
					Spi_Current_State=0;
				end
			end
		end
		
		
		
		
		////////用于向CPU发送数据/////////////////
		///从SRAM中取出数据
		24:
		begin
			if(slave_trdy)
			begin
				slave_write=1;
				slave_data_to_spi=packet_len;
				Spi_Current_State=25;
			end
		end
		25:
		begin
			slave_write=0;
			Spi_Current_State=16;
		end
		16:
		begin
			
			if(slave_trdy)
			begin
				slave_write=1;
				slave_data_to_spi=Data_from_sram_reg[7:0];
				Spi_Current_State=17;
			end
		end
		17:
		begin
			slave_write=0;
			Sended_count=Sended_count+1;
			if(Sended_count<packet_len)
				Spi_Current_State=18;
			else
			begin
				irq_noted=0;
				spi_send_end=1;
				Spi_Current_State=0;
			end
		end
		//读取数据并发送
		18:
		begin
			SRAM_read=1;
			Spi_Current_State=19;
		end
		19:
		begin
			if(SRAM_hint)
			begin
				SRAM_read=0;
				Spi_Current_State=20;
			end
		end
		20:
		begin
			if(slave_trdy)
			begin
				slave_write=1;
				slave_data_to_spi=Data_from_sram[15:8];
				Spi_Current_State=21;
			end
		end
		21:
		begin
			slave_write=0;
			Sended_count=Sended_count+1;
			if(Sended_count<packet_len)
				Spi_Current_State=22;
			else
			begin
				irq_noted=0;
				spi_send_end=1;
				Spi_Current_State=0;
			end
		end
		22:
		begin
			if(slave_trdy)
			begin
				slave_write=1;
				slave_data_to_spi=Data_from_sram[7:0];
				Spi_Current_State=23;
			end
		end
		23:
		begin
			slave_write=0;
			Sended_count=Sended_count+1;
			if(Sended_count<packet_len)
				Spi_Current_State=18;
			else
			begin
				irq_noted=0;
				spi_send_end=1;
				Spi_Current_State=0;
			end
		end
		default:
		begin
			Spi_Current_State=0;
		end
	endcase
	
end





endmodule