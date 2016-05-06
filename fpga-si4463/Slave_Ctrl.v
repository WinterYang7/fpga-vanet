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
	
	//帧接收中断,与wireless_ctrl连接
	//frame_recved_int,
	
	//与CPU连接的中断
	cpu_recv_int,
	
	Spi_Current_State_1,
	Spi_rrdy,
	Spi_trdy,
	Data_from_spi
	
	
);
output Data_from_spi;
output Spi_trdy;
output Spi_rrdy;
input	clk;
//input frame_recved_int;
output reg cpu_recv_int=1'b1;
output  [7:0] Spi_Current_State_1;	
assign Spi_Current_State_1={3'b000,Spi_Current_State};
	//与CPU的接口
input	mosi;
output	miso;
input	sclk;
//output	signal_int;
	
	//与SRAM的接口
output reg	SRAM_read;
output reg  SRAM_write;
input	SRAM_hint;
output reg [15:0]	Data_to_sram;
input[15:0]	Data_from_sram;
reg[15:0] Data_from_sram_reg;
input	SRAM_full;
input	SRAM_empty;
input[10:0]	SRAM_count;

//与spi的连线
wire slave_reset_n;
assign slave_reset_n=0;
wire slave_ss_n;
assign slave_ss_n=0;

wire slave_irq;
reg[7:0] slave_data_to_spi;
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
reg[4:0] Spi_Current_State=0;
reg[7:0] Data_len=0;
reg[7:0] Sended_count=0;
reg Byte_flag=0;
reg irq_noted=0;
//reg tx_flag=0;
//reg rx_flag=0;

//中断决策
reg[7:0] packet_len=0;
reg spi_send_end=0; //发送给CPU的数据已经发送完，说明准备接收下一个中断
reg spi_read_sram=0; //spi读取SRAM的使能信号

always@(posedge clk)
begin
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
				8'b01100110: //CPU发送数据0x66
				begin
					Data_to_sram[15:8]=slave_data_from_spi_reg;  //保存命令和长度，交给Wireless_Ctrl处理发送
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
			Data_to_sram[7:0]=8'h00;
			Spi_Current_State=7;
		end
		//将命令写入SRAM 0x66 0x00
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
		9:
		begin
			if(!SRAM_full)
			begin
				Data_to_sram={8'h00,Data_len[7:0]+1};
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
			spi_read_sram=1;
			Spi_Current_State=19;
		end
		19:
		begin
			if(SRAM_hint)
			begin
				spi_read_sram=0;
				Spi_Current_State=20;
			end
		end
		20:
		begin
			if(slave_trdy)
			begin
				slave_write=1;
				slave_data_to_spi=Data_from_sram_reg[15:8];
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
				slave_data_to_spi=Data_from_sram_reg[7:0];
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


////中断函数//////不需要等待，用户读取之后，自动清除中断，但是这里有一个问题，，这里的中断也存在一个问题
reg[2:0] Irq_Current_State=0;


always@(posedge clk)
begin
	case (Irq_Current_State)
		0:
		begin
			if(!SRAM_empty)
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
				Data_from_sram_reg=Data_from_sram;
				packet_len=Data_from_sram_reg[15:8];
				if(packet_len==0)
					Irq_Current_State=0;
				else
					Irq_Current_State=2;
			end
		end
		2:
		begin
			if(SRAM_count*2>=packet_len-1)
			begin
				cpu_recv_int=0;
				Irq_Current_State=3;
			end
		end
		3:
		begin
			if(irq_noted)
			begin
				cpu_recv_int=1;
				Irq_Current_State=4;
			end
		end
		4:
		begin
			if(!spi_send_end)
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
					Irq_Current_State=0;
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
		default:
		begin
			cpu_recv_int=1;
			Irq_Current_State=0;
		end
	endcase
end

endmodule