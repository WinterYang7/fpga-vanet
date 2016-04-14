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
	frame_recved_int,
	
	//与CPU连接的中断
	cpu_recv_int,
	
	Spi_Current_State,
	Spi_rrdy,
	Spi_trdy,
	Data_from_spi
	
	
);
output Data_from_spi;
output Spi_trdy;
output Spi_rrdy;
input	clk;
input frame_recved_int;
output reg cpu_recv_int;
output Spi_Current_State;	
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

/////SPI_slave连线
reg Spi_read_n=1;
reg Spi_write_n=1;
reg[2:0] Spi_mem_addr=0;
reg[15:0] Data_to_spi;
wire [15:0] Data_from_spi;
reg[7:0]  Data_from_spi_reg;
wire Spi_rrdy;
wire Spi_trdy;
//wire Spi_tmt;
wire Spi_reset;
assign Spi_reset=1;
wire Spi_sel;
assign Spi_sel=1;

spi_slave spi(
	               
	.MOSI(mosi),
	.SCLK(sclk),
	.clk(clk),
	.data_from_cpu(Data_to_spi),
	.mem_addr(Spi_mem_addr),
	.read_n(Spi_read_n),
	.reset_n(Spi_reset),
	.spi_select(Spi_sel),
	.write_n(Spi_write_n),

	.MISO(miso),
	.data_to_cpu(Data_from_spi),
	.dataavailable(Spi_rrdy),
	//.endofpacket,
	//.irq,
	.readyfordata(Spi_trdy)
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
//reg tx_flag=0;
//reg rx_flag=0;

always@(posedge clk)
begin
	case (Spi_Current_State)
		0:
		begin
			if(Spi_rrdy)
			begin
				Spi_read_n=0;
				Spi_mem_addr=3'b000;
				Spi_Current_State=1;
			end
		end
		1:
		begin
			Spi_read_n=1;
			Spi_Current_State=2;
		end
		2:
		begin
			Data_from_spi_reg=Data_from_spi[7:0];
			Spi_Current_State=3;
		end
		3:
		begin
			case(Data_from_spi_reg)
				8'b01100110: //CPU发送数据
				begin
					Data_to_sram[15:8]=Data_from_spi_reg;  //保存命令和长度，交给Wireless_Ctrl处理发送
					Sended_count=0;
					Byte_flag=0;
					//tx_flag=1;
					Spi_Current_State=4;
				end
				8'h01110111: //CPU接收数据
				begin
					//rx_flag=1;
					Spi_Current_State=16; 
				end
				default:
				begin
					Spi_Current_State=0;
				end
			endcase
		end
		4:
		begin
			if(Spi_rrdy)
			begin
				Spi_read_n=0;
				Spi_mem_addr=3'b000;
				Spi_Current_State=5;
			end
		end
		5:
		begin
			Spi_read_n=1;
			Spi_Current_State=6;
		end
		6:
		begin
			Data_len=Data_from_spi[7:0];
			Data_to_sram[7:0]=Data_from_spi[7:0]+8'h02;
			Spi_Current_State=7;
		end
		//将命令和数据长度写入SRAM
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
				Data_to_sram={8'h00,Data_len[7:0]};
				SRAM_write=1;
				Spi_Current_State=10;
			end
		end
		10:
		begin
			if(SRAM_hint)
			begin
				SRAM_write=0;
				Spi_Current_State=11;
			end
		end
		//从SPI读取数据并写入SRAM
		11:
		begin
			if(Spi_rrdy)
			begin
				Spi_read_n=0;
				Spi_mem_addr=3'b000;
				Spi_Current_State=12;
			end
		end
		12:
		begin
			Spi_read_n=1;
			Spi_Current_State=13;
		end
		13:
		begin
			if(!Byte_flag)
			begin
				Data_to_sram[15:8]=Data_from_spi[7:0];
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
				Data_to_sram[7:0]=Data_from_spi[7:0];
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
		16:
		begin
			if(!SRAM_empty)
			begin
				SRAM_read=1;
				Spi_Current_State=17;
			end
		end

		17:
		begin
			if(SRAM_hint)
			begin
				SRAM_read=0;
				Data_from_sram_reg=Data_from_sram;
				Data_len=Data_from_sram_reg[15:8];
				if(Spi_trdy)
				begin
					Spi_write_n=0;
					Spi_mem_addr=3'b001;
					Data_to_spi={8'h00,Data_len};
					Sended_count=0;
					Spi_Current_State=18;
					Byte_flag=0;
				end
			end
		end
		18:
		begin
			Spi_write_n=1;
			Spi_Current_State=19;
		end
		19:
		begin
			Spi_Current_State=20;
		end
		//发送第一个数据
		20:
		begin
			if(Spi_trdy)
			begin
				Data_to_spi={8'h00,Data_from_sram_reg[7:0]};

				Spi_Current_State=21;
				Spi_write_n=0;
				Spi_mem_addr=3'b001;
			end
		end
		21:
		begin
			Spi_write_n=1;
			Spi_Current_State=22;
		end
		22:
		begin
			Sended_count=Sended_count+1'b1;
			Spi_Current_State=23;
		end
		//取出数据并开始发送
		23:
		begin
			if(Sended_count<Data_len)
			begin
				if(!SRAM_empty)
				begin
					SRAM_read=1;
					Spi_Current_State=24;
				end
			end
			else
			begin
				Spi_Current_State=0;
			end
		end
		24:
		begin
			if(SRAM_hint)
			begin
				Data_from_sram_reg=Data_from_sram;
				Spi_Current_State=25;
			end
		end
		25:
		begin
			Data_to_spi={8'h00,Data_from_sram_reg[15:8]};
			Spi_write_n=0;
			Spi_mem_addr=3'b001;
			Spi_Current_State=26;
		end
		26:
		begin
			Spi_write_n=1;
			Spi_Current_State=27;
		end
		27:
		begin
			Sended_count=Sended_count+1'b1;
			if(Sended_count<Data_len)
			begin
				Spi_Current_State=28;
			end
			else
				Spi_Current_State=0;
		end
		28:
		begin
			Data_to_spi={8'h00,Data_from_sram_reg[7:0]};
			Spi_write_n=0;
			Spi_mem_addr=3'b001;
			Spi_Current_State=29;
		end
		29:
		begin
			Spi_write_n=1;
			Spi_Current_State=30;
		end
		30:
		begin
			Spi_Current_State=23;
		end
		default:
		begin
			Spi_Current_State=0;
		end
	endcase

end

/////延时函数///////////////
reg delay_start=0;
reg[31:0] delay_count=0;
reg[7:0] delay_mtime=0;
reg delay_int=0;

always@(posedge clk)
begin
	if(!delay_start)
	begin
		delay_count<=0;
		delay_int<=0;
	end
	else
	begin
		delay_count<=delay_count+1'b1;
		if(delay_count==delay_mtime*50)
			delay_int<=1;
	end
end

////中断函数//////
reg[2:0] Int_Current_State=0;

always@(posedge clk)
begin
	case (Int_Current_State)
		0:
		begin
			if(frame_recved_int)
			begin
				Int_Current_State=1;
			end
		end
		1:
		begin
			cpu_recv_int=1;
			delay_start=1;
			delay_mtime=1;
			Int_Current_State=2;
		end
		2:
		begin
			if(delay_int)
			begin
				delay_start=0;
				cpu_recv_int=0;
				Int_Current_State=3;
			end
		end
		3:
		begin
			Int_Current_State=0;
		end
		default:
		begin
			cpu_recv_int=0;
			Int_Current_State=0;
		end
	endcase
end

endmodule