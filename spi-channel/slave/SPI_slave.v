

module SPI_slave(
	clk, 
	SCK, 
	MOSI, 
	MISO, 
	ss_n, 
	pkg_flag,
	data_read,					
	byte_data_received,			
	byte_sent_request,
	byte_sent_int,
	//byte_received, 
	byte_data_tosent
);

input clk;
input SCK,  MOSI;
input byte_sent_request;	// From FPGA
input ss_n;
output MISO;
output pkg_flag;
output byte_sent_int;		// To FIFO
//output byte_received;		// Like data ready signal	  
output data_read;			// 数据准备好的信号--add by wuqiong 2100906
input [15:0] byte_data_tosent;    //要发送的数据
output [15:0] byte_data_received;   //接收到的数据

integer count =0,count1 =0,count2 =16,count3=0;
integer rd_flag =0;			// add by wuqiong 20101022;

wire byte_sent_int;
assign byte_sent_int = (count2==16) && (rd_flag == 1) && (bitcnt==4'b1111); //--update by wuqiong 20101124     这个条件表示一次SPI读完成，同时一次SPI写完成，而且SPI读进来的上一个有效命令是"09bb"
// ~byte_sent_request &&  --update by wuqiong 20101105
//&& (byte_data_received==16'h0000)&& (bitcnt==4'b1111) --update by wuqiong 20101021
// (count2==0);--update by wuqiong 20101016
//(bitcnt==4'b0000); --update by wuqiong 20101015
//assign byte_sent_int = ~byte_sent_request && (bitcnt==4'b0000); --update by wuqiong 20100928
wire pkg_flag;
//assign pkg_flag = (count3>0);   //update by wuqiong 20101013
assign pkg_flag= ~byte_sent_request;  //update by wuqiong 20100928//update by wuqiong 20101016

// sync SCK to the FPGA clock using a 3-bits shift register
reg [2:0] SCKr;  always @(posedge clk) SCKr <= {SCKr[1:0], SCK};
wire SCK_risingedge = (SCKr[2:1]==2'b01);  // now we can detect SCK rising edges
wire SCK_fallingedge = (SCKr[2:1]==2'b10);  // and falling edges

// same thing for SSEL
reg [2:0] SSELr;  always @(posedge clk) SSELr <= {SSELr[1:0], SSEL};
wire SSEL_active = ~SSELr[1];  // SSEL is active low
wire SSEL_startmessage = (SSELr[2:1]==2'b10);  // message starts at falling edge
wire SSEL_endmessage = (SSELr[2:1]==2'b01);  // message stops at rising edge

// and for MOSI
reg [1:0] MOSIr;  always @(posedge clk) MOSIr <= {MOSIr[0], MOSI};
wire MOSI_data = MOSIr[1];
wire SSEL = 0; //~ss_n; update by wuqiong 20101014

// we handle SPI in 8-bits format, so we need a 3 bits counter to count the bits as they come in
//
reg [3:0] bitcnt;			 
reg [3:0] bitcnt1;
				
wire data_read;	// high when 16 byte has been received		 
assign data_read = (count1>0); 

reg byte_received=0;  // high when a byte has been received
reg [15:0] byte_data_received = 16'hFFFF;
reg [15:0] byte_data_received1;		   
reg MISO;//add by wuqiong 20101015
reg [15:0] byte_data_sent;
reg [15:0] byte_data_sent1=16'h0000;//add by wuqiong 20101022
reg [15:0] byte_data_sent2=16'h0000;

//add for storing rd_data
always @(posedge clk) 
begin
	if(byte_sent_int)
	begin
		byte_data_sent1 <= byte_data_sent2;
		byte_data_sent2 <= byte_data_tosent;
	end
end

//add for contrling to read FIFO_o
always @(posedge clk)
begin
   //if(byte_data_received1 == 16'h09bb)rd_flag <= 1;		
   //if(byte_data_received1 == 16'h09ee)rd_flag <= 0;	
   rd_flag<=1;
end

//////////////////////////
//SPI Read From MOSI
//////////////////////////
always @(posedge clk)	 
begin		  
	count1<=0;
	if(~SSEL_active)	
	begin
		bitcnt <= 4'b0000;
		count <=0;	   
		count1<=0;
	end
	if(SSEL_active)
	//begin		  
		if(SCK_risingedge)
		begin
			bitcnt <= bitcnt + 4'b0001;	 			
			if(count<16) 
			begin
				byte_data_received1 <= {byte_data_received1[14:0], MOSI_data};	
				count <= count +1;				   
			    // implement a shift-left register (since we receive the data MSB first) 			     	   
			end
			if(count==16) 
			begin
				count <= 1;	 
				count1 <= 1;//enable  data_read add by wuqiong 20100907
				byte_data_received1 <= {15'b000000000000000, MOSI_data};
			end 	
        end
     //end
end  
  
always @(posedge clk) 
byte_received <= SSEL_active && SCK_risingedge && (bitcnt==4'b1111) ;	   //update by wuqiong 20100907

always @(negedge byte_received )  
byte_data_received <= byte_data_received1;


////////////////////////////////////////////
//SPI Write to MISO
////////////////////////////////////////////

always @(posedge clk)  
begin 
	if(~SSEL_active)	
	begin  
		count2<=16; 
		count3<=0;
		byte_data_sent<=16'h0000;//update by wuqiong 20101015
	end
	if(SSEL_active)
	//begin		
		if(byte_sent_int)       //byte_sent_int --update by wuqiong 20101022 last     				 
		begin
			byte_data_sent <= byte_data_sent1;  // first byte sent in a message is the message count  
			count3<=1; //update by wuqiong 20101022
			count2<=0;
		end
    	if(count3==1)
    	//begin	
			if(SCK_risingedge)
			begin 	    		   	 			
				if(count2<16) 
				//if  (byte_data_received == 4'h0000) //update by wuqiong 20101015//update by wuqiong 20101018
				begin
					MISO = byte_data_sent[15];//update by wuqiong 20101018
					byte_data_sent <={byte_data_sent[14:0], 1'b0};	
					count2 <= count2 +1;
				end
		        if(count2==16) 					
				begin
					count3<=0;	  			      //update by wuqiong 20101015 enable  byte_sent_int
					count2<=0;					  //
				end
			end
		//end
	//end 
end	 

//assign miso = byte_data_sent[15];  // send MSB first
// we assume that there is only one slave on the SPI bus
// so we don't bother with a tri-state buffer for MISO
// otherwise we would need to tri-state MISO when SSEL is inactive

endmodule

