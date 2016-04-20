`timescale 1ns / 1ps


`define MAX_FIFO_I_PTR 18'b000000100000000000
`define MIN_FIFO_I_PTR 18'b000000000000000000
`define FIFO_I_SIZE (`MAX_FIFO_I_PTR-`MIN_FIFO_I_PTR+1)

`define MAX_FIFO_O_PTR 18'b000001000000000000
`define MIN_FIFO_O_PTR 18'b000000100000000001
`define FIFO_O_SIZE (`MAX_FIFO_O_PTR-`MIN_FIFO_O_PTR+1)

module SRAM_ctrl(
	clk,
	
	//��SRAM��д�Ŀ����ź�
	slave_read,
	slave_write,
	master_read,
	master_write,
	
	//������
	slave_data_to_sram,
	slave_data_from_sram,
	
	master_data_to_sram,
	master_data_from_sram,
	
	//ָʾ���ĸ����Ƶ�Ԫ���SRAM����Ȩ��
	slave_hint,
	master_hint,
	
	//ָʾ��������С��״̬
	fifo_i_empty,
	fifo_i_full,
	fifo_i_count,
	
	fifo_o_empty,
	fifo_o_full,
	fifo_o_count,
	
	//SRAM����
	mem_addr,
	Dout,
	CE_n,
	OE_n,
	WE_n,
	LB_n,
	UB_n,
	nUsing,
	count,
	Current_State,
	opcode
	
    );
	 output[7:0] count;
	 assign count={4'b000,slave_write,slave_read,master_write,master_read};
output nUsing;
output Current_State;
output opcode;

input clk;
input slave_read;
input slave_write;
input master_read;
input master_write;

input [15:0] slave_data_to_sram;
output reg [15:0] slave_data_from_sram;
input [15:0] master_data_to_sram;
output reg [15:0] master_data_from_sram;

output reg slave_hint;
output reg master_hint;

//SRAM������
output reg [17:0]	mem_addr;
inout[15:0]	   Dout;
output reg	CE_n=0;
output reg	OE_n=1;
output reg	WE_n=1;
output reg	LB_n=0;
output reg	UB_n=0;

	//ָʾ��������С��״̬
output reg	fifo_i_empty=1;
output reg	fifo_i_full=0;
output reg[10:0]	fifo_i_count=0;
	
output reg	fifo_o_empty=1;
output reg	fifo_o_full=0;
output reg[10:0]	fifo_o_count=0;

//FIFO_i������ָ��

reg[17:0] fifo_i_rd_ptr=`MIN_FIFO_I_PTR;
reg[17:0] fifo_i_wr_ptr=`MIN_FIFO_I_PTR;

//FIFO_o������ָ��


reg[17:0] fifo_o_rd_ptr=`MIN_FIFO_O_PTR;
reg[17:0] fifo_o_wr_ptr=`MIN_FIFO_O_PTR;

//����ͬ������
reg nUsing=0;
reg [3:0] Current_State=0;
reg[15:0] data_to_sram=0;
reg link=0;
reg [15:0] data_from_sram=0;
reg [2:0] opcode=0;

assign Dout=link?data_to_sram:16'hzzzz;

always@(posedge clk)
begin
	if(!nUsing&&slave_write)
	begin
		if(!fifo_i_full)
		begin
			nUsing=1;
			Current_State=1;
		end
	end	
	
	if(!nUsing&&slave_read)
	begin
		if(!fifo_o_empty)
		begin
			nUsing=1;
			Current_State=2;
		end
	end
	
	if(!nUsing&&master_write)
	begin
		if(!fifo_o_full)
		begin
			nUsing=1;
			Current_State=3;
		end
	end
	
	if(!nUsing&&master_read)
	begin
		if(!fifo_i_empty)
		begin
			nUsing=1;
			Current_State=4;
		end
	end
	
	case (Current_State)
		1:  //SPI_slaveģ��д����
		begin
			opcode=1;
			data_to_sram=slave_data_to_sram;
			mem_addr=fifo_i_wr_ptr;
			fifo_i_wr_ptr=fifo_i_wr_ptr+1;
			fifo_i_count=fifo_i_count+1;
			if(fifo_i_wr_ptr>`MAX_FIFO_I_PTR)
				fifo_i_wr_ptr=`MIN_FIFO_I_PTR;
			Current_State=10;	
		end
		
		2: //SPI_slaveģ�������
		begin
			opcode=2;
			mem_addr=fifo_o_rd_ptr;
			fifo_o_rd_ptr=fifo_o_rd_ptr+1;
			fifo_o_count=fifo_o_count-1;
			if(fifo_o_rd_ptr>`MAX_FIFO_O_PTR)
				fifo_o_rd_ptr=`MIN_FIFO_O_PTR;
			Current_State=11;
		end
		
		3: //SPI_masterģ��д����
		begin
			opcode=3;
			data_to_sram=master_data_to_sram;
			mem_addr=fifo_o_wr_ptr;
			fifo_o_wr_ptr=fifo_o_wr_ptr+1;
			fifo_o_count=fifo_o_count+1;
			if(fifo_o_wr_ptr > `MAX_FIFO_O_PTR)
				fifo_o_wr_ptr = `MIN_FIFO_O_PTR;
			Current_State=10;	
		end
		
		4://SPI_masterģ�������
		begin
			opcode=4;
			mem_addr=fifo_i_rd_ptr;
			fifo_i_rd_ptr=fifo_i_rd_ptr+1;
			fifo_i_count=fifo_i_count-1;
			if(fifo_i_rd_ptr > `MAX_FIFO_I_PTR)
				fifo_i_rd_ptr = `MIN_FIFO_I_PTR;
			Current_State=11;
		end
		
		10: //дSRAM
		begin
			WE_n<=0;
			CE_n<=0;
			LB_n<=0;
			UB_n<=0;
			link<=1;
			Current_State=12;
		end
		
		11: //��SRAM
		begin
			WE_n<=1;
			CE_n<=0;
			OE_n<=0;
			LB_n<=0;
			UB_n<=0;
			Current_State=12;
		end
		
		12: //��д���
		begin
			WE_n<=1;
			CE_n<=0;
			OE_n<=1;
			data_from_sram<=Dout;
			link<=0;
			Current_State=13;
		end
		
		13: //����hint�ź�
		begin
			case(opcode)
				1:
				begin
					slave_hint=1;
				end
				2:
				begin
					slave_data_from_sram=data_from_sram;
					slave_hint=1;
				end
				3:
				begin
					master_hint=1;
				end
				4:
				begin
					master_data_from_sram=data_from_sram;
					master_hint=1;
				end
				
				default:
				begin
					slave_hint=0;
					master_hint=0;
				end
			endcase
			opcode=0;
			Current_State=14;
		end
		
		14: //�ȴ�һ������֮�󣬻ָ�hint�źţ�������ɣ������������ó��ռ�
		begin
			slave_hint=0;
			master_hint=0;
			Current_State=0;
			nUsing=0;
		end
	endcase
end


//����������
//���õ�������д��������ڶ�ȡ���������Ϊ��������£���ʹ��ǰ������ѡ����������������ܽ��У������������ܽ���ʱ��ʵ�������Ѿ�����һ����
always@(posedge clk)
begin
	
	if(fifo_i_count==`FIFO_I_SIZE)
		fifo_i_full=1;
	else
		fifo_i_full=0;
	if(fifo_i_count==0)
		fifo_i_empty=1;
	else
		fifo_i_empty=0;
	if(fifo_o_count==`FIFO_O_SIZE)
		fifo_o_full=1;
	else
		fifo_o_full=0;
	if(fifo_o_count==0)
		fifo_o_empty=1;
	else
		fifo_o_empty=0;
end

endmodule