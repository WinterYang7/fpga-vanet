module LinkTest(
		MOSI,
		MISO,
		SCLK,
		SS_n,
		
		clk,
		
		ledr
		//data_from_spi_reg,
		
		//wr_int,
	);

input MOSI;
output MISO;
input SCLK;
input SS_n;
input clk;

wire rd_int;
wire wr_int;
output wire ledr;

assign ledr=SCLK;

wire[15:0] data_from_spi;
reg[15:0] data_from_spi_reg;
wire[15:0] data_to_spi;
reg[15:0] data_to_spi_reg;

	SPI_slave spi(
		.clk(clk), 
		.SCK(SCLK), 
		.MOSI(MOSI), 
		.MISO(MISO), 
		.ss_n(SS_n), 
		
		.data_read(rd_int),					
		.byte_data_received(data_from_spi),			
		
		.byte_sent_int(wr_int),
	//byte_received, 
		.byte_data_tosent(data_to_spi)
	);

always@(posedge clk or posedge rd_int)
  begin
		if(rd_int)
		  begin
				data_from_spi_reg=data_from_spi;
		  end

  end

assign data_to_spi=data_to_spi_reg;
always@(posedge clk or posedge wr_int)
  begin
		if(wr_int)
		  begin
			data_to_spi_reg=data_from_spi_reg+1;
		  end
  end
endmodule