`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date:    13:21:22 03/17/2016 
// Design Name: 
// Module Name:    master_test 
// Project Name: 
// Target Devices: 
// Tool versions: 
// Description: 
//
// Dependencies: 
//
// Revision: 
// Revision 0.01 - File Created
// Additional Comments: 
//
//////////////////////////////////////////////////////////////////////////////////
module Master_Test(
		MISO,
		MOSI,
		SCLK,
		SS_n,
		
		clk,
		

    );

	 
	 input MISO;
	 output MOSI;
	 output SCLK;
	 output SS_n;

	 
	 input clk;
	 
	 wire [15:0] data_to_spi;
	 reg [15:0] data_to_spi_reg;
	 wire [15:0] data_from_spi;
	 reg [15:0] data_from_spi_reg;
	 
	 reg [2:0] mem_addr;
	 
	 reg read_n=1;
	 reg write_n=1;
	 
	 wire reset_n;
	 assign reset_n=1;
	 
	 wire spi_select;
	 assign spi_select=1;
	 
	 wire trdy;
	 wire rrdy;
	  
	 spi_master master(
					 .MISO(MISO),
                     .clk(clk),
                     .data_from_cpu(data_to_spi),
                     .mem_addr(mem_addr),
                     .read_n(read_n),
                     .reset_n(reset_n),
                     .spi_select(spi_select),
                     .write_n(write_n),

                    // outputs:
                     .MOSI(MOSI),
                     .SCLK(SCLK),
                     .SS_n(SS_n),
                     .data_to_cpu(data_from_spi),
                     .dataavailable(rrdy),
                     //.endofpacket,
                     //.irq,
                     .readyfordata(trdy)
							);
							

	
	reg [3:0] cnt_clk_1m;
	reg clk_1m;
	
	always@(posedge clk)
	begin
		if(cnt_clk_1m<13)
			cnt_clk_1m<=cnt_clk_1m+1;
		else
		begin
			cnt_clk_1m<=0;
			clk_1m<=~clk_1m;
		end
	end
	
	reg cnt_en;
	reg [3:0] cnt;
	reg [3:0] cnt_max;
	
	always@(posedge clk_1m)
	begin
		if(!cnt_en)
			cnt<=0;
		else
		begin
			if(cnt_en)
			begin
				if(cnt<cnt_max)
					cnt<=cnt+1;
				else
					cnt<=0;
			end
		end
	end
	
	reg [1:0] Write_state=0;
	reg [1:0] Read_state=0;
	
	reg [1:0] Begin_state=0;
	
	assign data_to_spi=data_to_spi_reg;
	always@(posedge clk)
	begin
		if(Begin_state==0)
		begin
			write_n<=0;
			mem_addr<=3'b011;
			data_to_spi_reg<=16'h0400;
			Begin_state<=1;
		end
		if(Begin_state==1)
		begin
			write_n<=1;
			Begin_state<=2;
		end
		if(Begin_state==2)
		begin
			Begin_state<=3;
		end
		
		
		if(Write_state==0 & Begin_state==3)
		begin
			if(trdy)
			begin
				write_n<=0;
				mem_addr<=3'b001;
				//data_to_spi<=data_to_spi_reg;
				data_to_spi_reg<=16'H0012;
				Write_state<=1;
			end
		end
		if(Write_state==1)
		begin
			write_n<=1;
			Write_state<=2;
		end
		
		if(Write_state==2)
		begin
			cnt_en<=1;
			cnt_max<=6;
			
			if(cnt==6)
			begin
				cnt_en<=0;
				Write_state<=0;
			end
		end
		
		if(Read_state==0)
		begin
			if(rrdy&&!trdy)
			begin
				read_n<=0;
				mem_addr<=0;
				Read_state<=1;
			end
		end
		if(Read_state==1)
		begin
			read_n<=1;
			data_from_spi_reg<=data_from_spi;
			Read_state<=2;
		end
		if(Read_state==2)
		begin
			Read_state<=0;
		end
	end
	
endmodule
