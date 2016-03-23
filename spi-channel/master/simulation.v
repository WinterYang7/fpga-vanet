`timescale 1ns / 1ps

////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer:
//
// Create Date:   17:00:08 03/17/2016
// Design Name:   Master_Test
// Module Name:   C:/Users/TM/Desktop/FPGA/SpiLink/SpiLink/simulation.v
// Project Name:  SpiLink
// Target Device:  
// Tool versions:  
// Description: 
//
// Verilog Test Fixture created by ISE for module: Master_Test
//
// Dependencies:
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
////////////////////////////////////////////////////////////////////////////////

module simulation;

	// Inputs
	reg MISO;
	reg clk;

	// Outputs
	wire MOSI;
	wire SCLK;
	wire SS_n;
	

	// Instantiate the Unit Under Test (UUT)
	Master_Test uut (
		.MISO(MISO), 
		.MOSI(MOSI), 
		.SCLK(SCLK), 
		.SS_n(SS_n), 
		.clk(clk), 
		
	);

	initial begin
		// Initialize Inputs
		MISO = 0;
		clk = 0;

		// Wait 100 ns for global reset to finish
		#100;
        
		// Add stimulus here

	end
      
endmodule

