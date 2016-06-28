module Wireless_Ctrl(
	clk,
	
	//SRAM�ӿ�
	Need_reset_from_sram,
	Config_read_sram,
	Config_read_sram_done,
	
	SRAM_read,
	SRAM_write,
	SRAM_full,
	SRAM_hint,
	SRAM_empty,
	SRAM_count,
	Data_to_sram,
	Data_from_sram,
	SRAM_AlmostFull, //����ź�ʵ����TotalLink��ʵ�֣����Խ�����ӵ�SRAM�У���ֻʣ256���ֽڿռ�ʱ�����ź���1
	
	//Si4463�ӿ�
	Si4463_int,
	Si4463_reset,
	
	//SPI_master�ӿ�
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
	
	//������һ��֡��������ź�
	//frame_recved_int,
	
	//FLAGS
	
	
	//����ָʾ��ǰ״̬��LED
	led,
	Si4463_Ph_Status_1,
	wireless_debug//for DUBUG
);
input clk;
output [7:0] Si4463_Ph_Status_1;
assign Si4463_Ph_Status_1=Main_Current_State;
//assign Si4463_Ph_Status_1=Irq_Current_State;
output reg [3:0] led=4'b0000;

output [1:0] wireless_debug;//for DUBUG
assign wireless_debug[0]=tx_done;//irq_dealing_wire;//packets_incoming[0];//;
assign wireless_debug[1]=tx_flag;//tx_state[0];//;//rx_start_wire;//packets_incoming[1];//
//output [3:0] led;
//assign led=Main_Current_State[3:0];
//SRAM�ӿ�
input Need_reset_from_sram;
output Config_read_sram;
output Config_read_sram_done;

output	SRAM_read;
output	SRAM_write;
input	SRAM_full;
input	SRAM_hint;
input	SRAM_empty;
input[17:0]	SRAM_count;
output[15:0]	Data_to_sram;
input[15:0]	Data_from_sram;
input SRAM_AlmostFull;
//output reg frame_recved_int=0;
	
	//Si4463�ӿ�
input	Si4463_int;
output	Si4463_reset;
	
	//SPI_master�ӿ�
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


reg reset_n=1'b1;

//RSSI��for LBT listen before send
reg [7:0] Si4463_RSSI_Curr=0;
reg [7:0] Si4463_RSSI_RecvPacket=0;
`define RSSI_THRESHOLD 8'ha0

//config from SRAM
reg [15:0] config_len;

reg [7:0] config_cmd_len;
reg [7:0] config_cmd_len_next;
reg config_cmd_start_flag;
reg [15:0] config_count;
reg [7:0] config_count_percmd;

//�жϴ��������ź�
reg [4:0] Irq_Current_State=0;

reg [2:0] Syncirq_Current_State=3;
reg tx_done; //��1��ʾ�������
wire tx_done_wire;
assign tx_done_wire=tx_done;
`define SYNC_IRQ_TIMEOUT 10//ms

reg tx_flag; //�Ƿ�������ж�

reg [3:0] packets_incoming; //ָʾ��Ƶģ���յ�������δ�յ��������ݰ����ж�
wire[3:0] packets_incoming_wire;
assign packets_incoming_wire[3:0]=packets_incoming[3:0];

reg [7:0] Si4463_Ph_Status=0;
reg [7:0] Si4463_Modem_Status=0;
reg [7:0] frame_len;
reg irq_dealing;
wire irq_dealing_wire;
assign irq_dealing_wire=irq_dealing;

/**
* α�������������255��״̬
* http://www.cnblogs.com/BitArt/archive/2012/12/22/2827005.html
*/

reg          load=1;     /*load seed to rand_num,active high */
reg [7:0]    seed=8'b10110110;     
reg [7:0]    rand_num;  /*random number output*/
wire[7:0]	 rand_num_wire;
assign rand_num_wire=rand_num;

always@(posedge clk or negedge reset_n)
begin
    if(!reset_n)
        rand_num    <=8'b0;
    else if(load)
        rand_num <=seed;    /*load the initial value when load is active*/
    else
        begin
            rand_num[0] <= rand_num[7];
            rand_num[1] <= rand_num[0];
            rand_num[2] <= rand_num[1];
            rand_num[3] <= rand_num[2];
            rand_num[4] <= rand_num[3]^rand_num[7];
            rand_num[5] <= rand_num[4]^rand_num[7];
            rand_num[6] <= rand_num[5]^rand_num[7];
            rand_num[7] <= rand_num[6];
        end
            
end


/////��ʱ����1///////////////
reg delay_start=0;
reg[31:0] delay_count=0;
reg[7:0] delay_mtime=0;
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
		if(delay_count==delay_mtime*20000) //20000������1ms
			delay_int<=1'b1;
	end
end

/////��ʱ����2///////////////
reg delay_start_2=0;
reg[31:0] delay_count_2=0;
reg[7:0] delay_mtime_2=0;
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
		if(delay_count_2==delay_mtime_2*20000) //20000������1ms
			delay_int_2<=1'b1;
	end
end

/////��ʱ����3///////////////
reg delay_start_3=0;
reg[31:0] delay_count_3=0;
reg[7:0] delay_mtime_3=0;
reg delay_int_3=0;

always@(posedge clk)
begin
	if(!delay_start_3)
	begin
		delay_count_3<=0;
		delay_int_3<=1'b0;
	end
	else
	begin
		delay_count_3<=delay_count_3+1'b1;
		if(delay_count_3==delay_mtime_3*200) //��������������ʹ��
			delay_int_3<=1'b1;
	end
end

/////��ʱ����4///////////////
reg delay_start_4=0;
reg[31:0] delay_count_4=0;
reg[7:0] delay_mtime_4=0;
reg delay_int_4=0;

always@(posedge clk)
begin
	if(!delay_start_4)
	begin
		delay_count_4<=0;
		delay_int_4<=1'b0;
	end
	else
	begin
		delay_count_4<=delay_count_4+1'b1;
		if(delay_count_4==delay_mtime_4*20000) //20000������1ms
			delay_int_4<=1'b1;
	end
end

//////�ӿ�
/*
	main_data_len[]   ��������Ҫ���͵��ֽ���
	int_data_len[]    �жϽ�����Ҫ���͵��ֽ���
	
	Main_Start_data[79:0]  �������õ�����
	spi_cmd[]   ��Ҫ���еĲ���
				1 main�����������ú�gteCTS
				2 main��������֡
				3 int��������֡
				4 int ��ȡ�ж�״̬
				5 main�����SRAM�ж�ȡ���ݣ�Ψһ����;�ǻ�ȡ��Ҫ���͵�����
				6 int�����ټĴ���
				7 intдSRAM
	spi_Using  boolֵ������spiģ���Ƿ����ڱ�ʹ��
	spi_start  boolֵ������Ϊ1������׼����ʼ���ͻ��������
*/
reg [127:0] Main_Cmd_Data=0;  //�������е�����壬�����������ú�GetCTS
reg [31:0] Int_Cmd_Data=0;   //�жϳ����е�����壬��Ҫ�ǲ鿴�Ĵ���״̬��GetCTS
reg [79:0] Main_Return_Data=0;  //�������ݵĻ�����
reg [79:0] Int_Return_Data=0;   //Ҫ���յ����ݳ���
reg [7:0] Main_Data_len=0;  //Ҫ���͵����ݳ���
reg [4:0] Main_Return_len=0;  //GetCTS�󷵻ص����ݳ���
reg [7:0] Int_Data_len=0;
reg [3:0] Int_Return_len=0;
reg [2:0] Main_Cmd;   //�������е�����
reg [2:0] Int_Cmd;	//�жϺ����е�����
reg Main_start=0;  //Main��ʾ��Ҫ��ʼ�������ݣ���Ҫ��ǰ���Spi_Using
reg Int_start=0;   //Int��ʾ��Ҫ��ʼ�������ݣ���Ҫ��ǰ���Spi_Using
reg[31:0] Main_Data_Check=0;


reg [127:0] spi_cmd_data;
reg [7:0] spi_data_len=0;
reg [4:0] spi_return_len=0;
reg [2:0] spi_cmd=0;
reg spi_Using=0;
wire spi_Using_wire;
assign spi_Using_wire=spi_Using;

reg spi_start=0; //��Ҫ�Ǽ���Main_start��Int_start���壬������һ������Ϊ1ʱ����1
reg [7:0] Sended_count=0; //�Ѿ����͵��ֽ���
reg spi_op_done=0; //����ָʾspi�Ĳ����Ƿ��Ѿ����
reg spi_op_fifo_flag=0;  //����ָʾ����֡ʱ�����͵ĵ�һ������

///��SPI_master������
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

//��SRAM������
reg SRAM_read=0;
reg SRAM_write=0;
wire SRAM_full; //˵��FIFO_o����
wire SRAM_empty; //˵��FIFO_i�ѿ�
wire [17:0] SRAM_count;  //˵��FIFO_o�е����ݸ���
reg [15:0] Data_to_sram;
wire [15:0] Data_from_sram;
reg [15:0] Data_from_sram_reg=0;
wire SRAM_hint;
reg Byte_flag=0;
reg Byte_flag_config=0;
reg GetCTS_flag=0;

wire Need_reset_from_sram;
reg Config_read_sram=0;
reg Config_read_sram_done=0;

reg [15:0] master_control_reg;

assign master_spi_sel=1;

reg [5:0] Spi_Current_State;
reg Ended_flag;
reg frame_len_flag; //��־�Ž��հ�ʱ��һ���ֽڣ������ĳ���


reg[31:0] CTScounter=0;
reg CTS_error_reset_n=1;
//�ֱ��������ط���֤���յ������ݾ�����Ҫ������
// 1. CTS,����CTS���������Ҫ�����ݣ����Ժ�������ݿ���ȷ��Ϊ��Ҫ������
// 2. ֻ�Ƿ�������ʱ�����ص���������ν�� 
// 3. �ڽ������ݺ󣬷���0x77���������һ�����յ�������(��Ч����),�ڷ�����һ������ǰ����Ƶ���㹻ʱ���ܹ�׼�������������ݣ����Է��ص�Ҳ����Ч����
always@(negedge reset_n or posedge clk)  //������ü���Main_start��Int_start�ź�
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
		CTScounter=0;
		CTS_error_reset_n=1;
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
			case (spi_cmd) //�����е���࣬���Լ�ɾ��һ��
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
				7:
				begin
					Spi_Current_State=43;
					spi_Using=1;
					spi_op_done=0;
					Sended_count=0;
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
			CTScounter=0;
		end
	end
	
	if(spi_Using&&spi_start)
	begin

		case (Spi_Current_State)
		
		    ////////////////��Ƭѡ�ź�����/////////////////////////////
			1:  //Ҫ���͵����ݴ����Main_Cmd_Data
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
			
			////////////////////���������������/////////////////////////////
			7: //׼����ɣ���ʼ��������,�ж�����Դ
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
			8: //��������
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
			
			///////////////////////////////////���ݷ����꣬����Ƭѡ�źţ���֪ͨ���ڲ����Ѿ����//////////////////////////
			12:
			begin	
				if(master_tmt) //�ȴ�shift�Ĵ�����tx�Ĵ��������ݷ�����
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
				if(spi_cmd==2||spi_cmd==3 ||Ended_flag || spi_cmd==6) //���ͺͽ�������֡����ҪGetCTS
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
			
			
			////////////////////////GetCTS����/////////////
			16:
			begin
				if(master_trdy)
				begin
					CTScounter=CTScounter+1;
					if(CTScounter>10000)
					begin
						CTS_error_reset_n=0;
						Spi_Current_State=0;
					end
					else
					begin
						Data_to_master=16'h0044;
						master_mem_addr=3'b001;
						master_write_n=0;
						Spi_Current_State=17;
					end
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
				if(master_tmt&&master_rrdy) //����ȷ�����յ����Ƿ��صĵڶ����ֽ�
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
				if(Data_from_master[7:0]==8'hff)
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
			
			
			
			/////////////////////////////////���ڽ�������/////////////////////////////////
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
						Main_Return_Data={Main_Return_Data[71:0],8'h00};//�����ƣ�Ϊ�����������ṩ�ռ�
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


			
			///////////////////��SRAM��ȡ�����ݣ������͸���Ƶģ��//////////
			28: //��SRAM����FIFO_i�ж�ȡ����
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
			
			
			////////////////////////����Ƶģ��������ݲ������SRAM��//////////////////
			30://����Ƶģ��������ݴ����FIFO_o
			begin
				frame_len_flag=1;
				Spi_Current_State=33; 
			end
			31:
			begin
				if(!Byte_flag) //����SRAMҪһ��д�����ֽڣ���������һ��byte_flag��Ϊ���ڡ�
				begin
					Data_to_sram[15:8]=Data_from_master[7:0]; //ע����һ��
					if(frame_len_flag) //���յ��ĵ�һ���ֽ�Ϊ���ȣ�����������
					begin
						//Byte_flag=~Byte_flag;
						frame_len_flag=0;
						Sended_count=0;
						spi_data_len=Data_from_master[7:0];
						Data_to_sram[15:8]=Data_to_sram[15:8]+1'b1; //����һ���ֽڴ�RSSI������ָ��ǵ���ǰһ����
						Data_to_sram[7:0]=Si4463_RSSI_RecvPacket;
						//Spi_Current_State=22;
						//SRAM_write=1;//д��SRAM
						Spi_Current_State=50;
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
			
			50:
			begin
				SRAM_write=1;//д��SRAM
				Spi_Current_State=32;
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
			33: //���ͽ�����������
			begin //�����������������Ҫ����Ϊ��Ƶ��������׼����
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
				if(master_tmt) //����ȷ�����յ��ĵ�һ�����ݾ�����Ч����
				begin
					Spi_Current_State=22;
				end
			end

			
			
			36: //cmd=5;
			begin
				SRAM_read=1;
				Spi_Current_State=39;
			end
			/*
			37:
			begin
				if(SRAM_hint)
				begin
					SRAM_read=0;
					Main_Data_Check[31:16]=Data_from_sram; //��ȡ����0x2d 0xd4
					Spi_Current_State=38;
				end
			end
			38:
			begin
				SRAM_read=1;
				Spi_Current_State=39;
			end*/
			39:
			begin
				if(SRAM_hint)
				begin
					SRAM_read=0;
					Main_Data_Check[15:0]=Data_from_sram; //��ȡ�����ֽ�
					spi_Using=0;
					spi_start=0;
					spi_op_done=1;
					Spi_Current_State=0;
				end
			end
			
			//��ȡ���ټĴ��� cmd=6
			40:
			begin
				Data_to_master={8'h00,spi_cmd_data[7:0]};
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
			
			//intдSRAM cmd=7
			43:
			begin
				if(Sended_count<spi_data_len)
				begin
					SRAM_write=1;
					Data_to_sram=spi_cmd_data[15:0];
					Spi_Current_State=44;
				end
				else
				begin
					spi_Using=0;
					spi_start=0;
					spi_op_done=1;
					Spi_Current_State=0;
				end
			end
			44:
			begin
				if(SRAM_hint)
				begin
					SRAM_write=0;
					Sended_count=Sended_count+2;
					spi_cmd_data={16'h0000,spi_cmd_data[79:16]};
					Spi_Current_State=43;
				end
			end
		endcase
	end
end
end

reg GPS_sync_time=1'b1;  ////��Ҫ��GPSͬ��ʱ��
reg [7:0] Main_Current_State=255;
reg Si4463_reset=1'b1; //��������������wireless_ctrl��λʱ������Ϊ0
wire Si4463_int;
reg [2:0] tx_state;  //0ΪĬ�ϣ�1��ʾrx, 2��ʾtx_tune��3��ʾtx
wire[2:0] tx_state_wire;
assign tx_state_wire[2:0]=tx_state[2:0];

reg[7:0] Data_Len_to_Send=8'h00;
reg enable_irq=1'b0; //��ʼ����ɺ󣬲��������жϺ���
reg enable_irq_sending=1'b1; //��������ʱ���ж�����Ч��
`define RX 3'b001
`define TX_TUNE 3'b010
`define TX 3'b100


/**
 * ������()������ʼʱ��������Ƶģ�� ״̬Ϊ0-130
 * ������ɺ󣬿�ʼѭ���������� ״̬Ϊ130-145
 **/
always@(posedge clk or negedge CTS_error_reset_n)
begin
if(!CTS_error_reset_n || Need_reset_from_sram)
begin
	Main_Current_State=0;
	config_cmd_start_flag=0;
	reset_n=0;
end
else
begin
		case(Main_Current_State) 
		255:
		begin
		end
		
		0:
		begin
			led[3]=1'b0;
			enable_irq=0;
			enable_irq_sending=1'b1;
			tx_state=3'b000;
			Main_start=0;
			delay_start_2=0;
			
			Si4463_reset=1;
			delay_start=1;
			delay_mtime=10;
			led[2]=1'b0;
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
		
	////////////reset()������������Ƶģ��
		250:
		begin
			Config_read_sram=1;
			
			Main_Current_State=1;
			config_count[15:0]=16'b0;
		end
		1:
		begin
			if(SRAM_hint)
			begin
				Config_read_sram=0;
				config_len[15:0]=Data_from_sram; //��ȡ�����ֽڵĳ��ȣ��������õĳ��ȣ�
				Byte_flag_config=0;
				config_cmd_start_flag=0;
				Main_Current_State=2;
			end
		end
		2://����ѭ��
		begin
			Config_read_sram=1;
			Main_Current_State=3;
		end
		3://1.�ж�һ�������Ƿ���ϲ����ͣ�
		begin
			if(SRAM_hint)
			begin
				Config_read_sram=0;
				if(!config_cmd_start_flag)
				begin
					config_cmd_len=Data_from_sram[15:8];//��һ���ֽ��ǳ���
					config_cmd_start_flag=1;
					Main_Cmd_Data[7:0]=Data_from_sram[7:0];
					config_count_percmd=1'b1;//����һ���ֽ�
					Byte_flag_config=0;
					if(config_cmd_len==1'b1)
					begin
						config_cmd_start_flag=0;
						Main_Current_State=4;//�����Ѿ�ȡ��������
					end
					else
					begin
						Main_Current_State=2;//ȡ�������ֽ�
					end

				end
				else //if(!config_cmd_start_flag)
				begin
					//һ�����û����ϣ�ֻ���ж�����һ���ֽڻ��Ƕ����ֽ�
					//Main_Cmd_Data[(config_count_percmd*8+7):(config_count_percmd*8)]=Data_from_sram[15:8];
					Main_Cmd_Data[(config_count_percmd*8) +:8]=Data_from_sram[15:8];
					config_count_percmd=config_count_percmd+1'b1;
					if(config_count_percmd==config_cmd_len)
					begin
						//һ��������ϣ��ڶ����ֽ�����һ������ĳ���
						Byte_flag_config=~Byte_flag_config;
						config_cmd_len_next=Data_from_sram[7:0];
						config_cmd_start_flag=1;
						Main_Current_State=4;//�����Ѿ�ȡ��������
					end
					else
					begin
						//���ȡ���������ֽڶ��Ǳ��������
						//Main_Cmd_Data[(config_count_percmd*8+7):(config_count_percmd*8)]=Data_from_sram[7:0];
						Main_Cmd_Data[(config_count_percmd*8) +:8]=Data_from_sram[7:0];
						config_count_percmd=config_count_percmd+1'b1;
						Byte_flag_config=0;
						if(config_count_percmd==config_cmd_len)
						begin
							//һ���������
							
							config_cmd_start_flag=0;
							Main_Current_State=4;//�����Ѿ�ȡ��������
						end
						else
						begin
							Main_Current_State=2;//�����δ������ȡ�������ֽڡ�
						end
					end ////end else		
				end  ////end else
			end ////end if(!config_cmd_start_flag)
		end ////end case
		4: //1.�ȷ����Ѿ���ɵ����� 2.�ж����������Ƿ��ȡ��ϡ�
		begin
			Main_Data_len=config_cmd_len;
			Main_Return_len=0;
			Main_Cmd=1;
			Main_start=1;
			Main_Current_State=5;
		end
		5:
		begin
			Main_start=0;
			Main_Current_State=6;
		end
		6:
		begin
			if(spi_op_done)
			begin
				config_count_percmd=0;
				if(Byte_flag_config==1'b1)
				begin
					config_cmd_len=config_cmd_len_next;
				end
				//config_len=config_len-config_cmd_len-1'b1;//������һ���������1�ֽڵĳ��ȣ�����Ҫ��1��
				config_count=config_count+config_cmd_len+1'b1;
				//if(!config_len)
				if(config_count>=config_len)
				begin
					//��ȡ�����ļ���ϣ���ʾSRAM����config��ȡָ��
					Config_read_sram_done=1;
					Main_Current_State=7;
				end
				else
				begin
					Main_Current_State=2;
				end
			end
		end
		7:
		begin
			Config_read_sram_done=0;
			Main_Current_State=8;
		end

		//===set_frr_ctl(void)====
		8:
		begin
			Main_Cmd_Data[7:0]=8'h11;
			Main_Cmd_Data[15:8]=8'h02;
			Main_Cmd_Data[23:16]=8'h04;
			Main_Cmd_Data[31:24]=8'h00;
			Main_Cmd_Data[39:32]=8'h04; //INT_PH_PEND
			Main_Cmd_Data[47:40]=8'h06; //INT_MODEM_PEND
			Main_Cmd_Data[55:48]=8'h0a; //LATCHED_RSSI
			Main_Cmd_Data[63:56]=8'h00;
			Main_Cmd=1;
			Main_start=1;
			Main_Data_len=8;
			Main_Return_len=0;
			Main_Current_State=9;
		end
		9:
		begin
			Main_start=0;
			Main_Current_State=10;
		end
		10:
		begin
			if(spi_op_done)
			begin
				Main_Current_State=11;
			end
		end
		//===Function_set_tran_property()====
		11:
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
			Main_Current_State=12;
		end
		12:
		begin
			Main_start=0;
			Main_Current_State=13;
		end
		13:
		begin
			if(spi_op_done)
			begin
				Main_Current_State=14;
			end
		end
		14:
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
			Main_Current_State=15;
		end
		15:
		begin
			Main_start=0;
			Main_Current_State=16;
		end
		16:
		begin
			if(spi_op_done)
			begin
				Main_Current_State=17;
			end
		end
		17:
		begin
			Main_Cmd_Data[7:0]=8'h11;
			Main_Cmd_Data[15:8]=8'h12;
			Main_Cmd_Data[23:16]=8'h04;
			Main_Cmd_Data[31:24]=8'h0d;
			Main_Cmd_Data[39:32]=8'h00;
			Main_Cmd_Data[47:40]=8'h00;
			Main_Cmd_Data[55:48]=8'h00;
			Main_Cmd_Data[63:56]=8'ha2;
			Main_Cmd=1;
			Main_start=1;
			Main_Data_len=8;
			Main_Return_len=0;
			Main_Current_State=18;
		end
		18:
		begin
			Main_start=0;
			Main_Current_State=19;
		end
		19:
		begin
			if(spi_op_done)
			begin
				Main_Current_State=20;
			end
		end
		20:
		begin
			Main_Cmd_Data[7:0]=8'h11;
			Main_Cmd_Data[15:8]=8'h12;
			Main_Cmd_Data[23:16]=8'h04;
			Main_Cmd_Data[31:24]=8'h21;
			Main_Cmd_Data[39:32]=8'h00;
			Main_Cmd_Data[47:40]=8'h01;
			Main_Cmd_Data[55:48]=8'h00;
			Main_Cmd_Data[63:56]=8'h82;
			Main_Cmd=1;
			Main_start=1;
			Main_Data_len=8;
			Main_Return_len=0;
			Main_Current_State=21;
		end
		21:
		begin
			Main_start=0;
			Main_Current_State=22;
		end
		22:
		begin
			if(spi_op_done)
			begin
				Main_Current_State=23;
			end
		end
		23:
		begin
			Main_Cmd_Data[7:0]=8'h11;
			Main_Cmd_Data[15:8]=8'h12;
			Main_Cmd_Data[23:16]=8'h04;
			Main_Cmd_Data[31:24]=8'h25;
			Main_Cmd_Data[39:32]=8'h00;
			Main_Cmd_Data[47:40]=8'hfa;
			Main_Cmd_Data[55:48]=8'h00;
			Main_Cmd_Data[63:56]=8'h0a;
			Main_Cmd=1;
			Main_start=1;
			Main_Data_len=8;
			Main_Return_len=0;
			Main_Current_State=24;
		end
		24:
		begin
			Main_start=0;
			Main_Current_State=25;
		end
		25:
		begin
			if(spi_op_done)
			begin
				Main_Current_State=26;
			end
		end
		26:
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
			Main_Current_State=27;
		end
		27:
		begin
			Main_start=0;
			Main_Current_State=28;
		end
		28:
		begin
			if(spi_op_done)
			begin
				Main_Current_State=29;
			end
		end
		29:
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
			Main_Current_State=30;
		end
		30:
		begin
			Main_start=0;
			Main_Current_State=31;
		end
		31:
		begin
			if(spi_op_done)
			begin
				Main_Current_State=32;
			end
		end
		32: //ѭ��У�� CRC
		begin
			Main_Cmd_Data[7:0]=8'h11;
			Main_Cmd_Data[15:8]=8'h12;
			Main_Cmd_Data[23:16]=8'h01;
			Main_Cmd_Data[31:24]=8'h00;
			Main_Cmd_Data[39:32]=8'h83;
			Main_Cmd=1;
			Main_start=1;
			Main_Data_len=5;
			Main_Return_len=0;
			Main_Current_State=33;
		end
		33:
		begin
			Main_start=0;
			Main_Current_State=34;
		end
		34:
		begin
			if(spi_op_done)
			begin
				Main_Current_State=40;
			end
		end
		
		/*
		157:
		begin
			Main_Cmd_Data[7:0]=8'h11;
			Main_Cmd_Data[15:8]=8'h30;
			Main_Cmd_Data[23:16]=8'h0c;
			Main_Cmd_Data[31:24]=8'h00;
			Main_Cmd_Data[39:32]=8'haa;//1
			Main_Cmd_Data[47:40]=8'hff;
			Main_Cmd_Data[55:48]=8'h41;
			Main_Cmd_Data[63:56]=8'h0F;//2
			Main_Cmd_Data[71:64]=8'hff;
			Main_Cmd_Data[79:72]=8'h02;
			Main_Cmd_Data[87:80]=8'h55;//3
			Main_Cmd_Data[95:88]=8'hff;
			Main_Cmd_Data[103:96]=8'h03;
			Main_Cmd_Data[111:104]=8'hf0;//4
			Main_Cmd_Data[119:112]=8'hff;
			Main_Cmd_Data[127:120]=8'h04;
			Main_Cmd=1;
			Main_start=1;
			Main_Data_len=16;
			Main_Return_len=0;
			Main_Current_State=158;
		end
		158:
		begin
			Main_start=0;
			Main_Current_State=159;
		end
		159:
		begin
			if(spi_op_done)
			begin
				Main_Current_State=160;
			end
		end*/

		
		//��Ҫ����FIFO
		40:
		begin
			Main_Cmd_Data[7:0]=8'h15;
			Main_Cmd_Data[15:8]=8'h03;
			Main_Data_len=2;
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
				Main_Current_State=50;
			end
		end
		
		//��鵱ǰ״̬
		50:
		begin
			Main_Cmd_Data[7:0]=8'h33;
			Main_Cmd_Data[15:8]=8'h00;
			Main_Data_len=2;
			Main_Return_len=2;
			Main_Cmd=1;
			Main_start=1;
			Main_Current_State=51;
		end
		51:
		begin
			Main_start=0;
			Main_Current_State=52;
		end
		52:
		begin
			
			if(spi_op_done)
			begin
				if(Main_Return_Data[15:8]==8'h03)
				begin
					tx_state=3'b000;
					Main_Current_State=54;
				end
				else
				begin
					Main_Current_State=53;
					config_cmd_start_flag=0;
					Config_read_sram_done=1;
				end
			end
		end
		53:
		begin
			Config_read_sram_done=0;
			reset_n=0;
			Main_Current_State=0;
		end
		
		//״̬ת��ΪRX
		54:
		begin
			if(!spi_Using_wire)
			begin
				Main_Cmd_Data[7:0]=8'h32;
				Main_Cmd_Data[15:8]=8'h00;
				Main_Cmd_Data[23:16]=8'h00;
				Main_Cmd_Data[31:24]=8'h00;
				Main_Cmd_Data[39:32]=8'h00;
				Main_Cmd_Data[47:40]=8'h00;
				Main_Cmd_Data[55:48]=8'h06;
				Main_Cmd_Data[63:56]=8'h06;
				Main_Data_len=8;
				Main_Return_len=0;
				Main_Cmd=1;
				Main_start=1;
				Main_Current_State=55;
			end
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
				enable_irq=1;   //��ʼ��������ж��ź�
				tx_state=`RX;
				Main_Current_State=60;
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
		
		///////////////////////////////////������ɣ���ʼ�������ݡ�������������������������������
		//////////////////////////////////////////////////////////////////////////////
		
		
		////�ж��Ƿ������ݼ�����֡����,�����Ҫ��ȡ���ݰ����ȣ�������������һ�������SPI�ж�ȡSRAM
		60:
		begin
			led[2]=1;
			if(!SRAM_empty&&!spi_Using_wire)
			begin
				Main_Cmd=5; //read from sram
				Main_start=1;
				Main_Current_State=61;
			end
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
				if(Main_Data_Check[15:0]==16'h2dd4)
				begin
					Main_Current_State=63;
				end
				else
				begin
					Main_Current_State=60;
				end
			end
		end
		63:
		begin
			if(!SRAM_empty&&!spi_Using_wire)
			begin
				Main_Cmd=5;
				Main_start=1;
				Main_Current_State=64;
			end
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
				Data_Len_to_Send=Main_Data_Check[7:0];
				if(SRAM_count*2>=Data_Len_to_Send)
				begin
					Main_Current_State=70;
				end	
			end
		end

		//CCA,LBT,...//
		70:
		begin
			if(!spi_Using_wire&&!irq_dealing_wire&&packets_incoming_wire==0)
			begin
				Main_Cmd=1;
				Main_Cmd_Data[7:0]=8'h22; //GET_MODEM_STATUS
				Main_Cmd_Data[15:8]=8'hff;
				Main_Data_len=2;
				Main_Return_len=3;//only needs 3byte (third is CURR_RSSI)
				Main_start=1;
				Main_Current_State=71;	
			end
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
				Si4463_RSSI_Curr=Main_Return_Data[7:0]; //CURR_RSSI (Reverse sequence of addr ����3�ֽڣ���[7:0]ȡ�����һ���ֽ�)
				if(Si4463_RSSI_Curr>`RSSI_THRESHOLD)
				begin
					delay_mtime_3=rand_num_wire;
					delay_start_3=1;
					Main_Current_State=73;
				end
				else
				begin
					Main_Current_State=80;
				end
			end
		end
		73:
		begin
			if(delay_int_3)
			begin
				delay_start_3=0;
				Main_Current_State=70;
			end			
		end
				
		/////���SPI���ڱ�ʹ����ȴ��������������л�״̬Ϊtx_tune///////
		
		////�л�״̬0x34 05 TX_TUNE
		80:
		begin
			if(!spi_Using_wire&&!irq_dealing_wire&&packets_incoming_wire==0)
			begin
				enable_irq_sending=0;
				Main_Cmd=1;
				Main_Cmd_Data[7:0]=8'h34;
				Main_Cmd_Data[15:8]=8'h05;
				Main_start=1;
				Main_Data_len=2;
				Main_Return_len=0;
				Main_Current_State=81;
			end
		end
		81:
		begin
			Main_start=0;
			Main_Current_State=82;
		end
		82:
		begin
			if(spi_op_done)
			begin
				tx_state=`TX_TUNE;
				Main_Current_State=83;
			end
		end
		///����FIFO
		83: //0x15 03
		begin
			if(!spi_Using_wire)
			begin
				Main_Cmd=1;
				Main_Cmd_Data[7:0]=8'h15;
				Main_Cmd_Data[15:8]=8'h03;
				Main_start=1;
				Main_Data_len=2;
				Main_Return_len=0;
				Main_Current_State=84;
			end
		end
		84:
		begin
			Main_start=0;
			Main_Current_State=85;
		end
		85:
		begin
			if(spi_op_done)
				Main_Current_State=90;
		end
		
		
		//������Ҫ���͵����ݰ��ĳ���
		90:
		begin
			if(!spi_Using_wire)
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
				Main_Current_State=91;
			end
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
		
		//////���SPI���ڱ�ʹ����ȴ�����������д����Ƶģ�黺������������
		
		93:
		begin
			if(!spi_Using_wire)
			begin
				Main_Cmd=2;
				Main_Data_len=Data_Len_to_Send+1;  //+1����ΪҪ����0x66���������������Ϊ126,��ȥ�������ȣ���ֻʣ125�ֽ�
				Main_Return_len=0;
				Main_start=1;
				Main_Current_State=94;
			end
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
				Main_Current_State=100;
			end
		end
		
/*
		///�ȴ�ʱ϶///////////
		200:
		begin
			if(GPS_sync_time) //����һ�����壬
			begin
				Main_Current_State=142;
			end
		end
*/
		/////////���������ʼ��������///////////
		100:
		begin
			if(!spi_Using_wire)
			begin
				Main_Cmd=1;
				Main_start=1;
				Main_Data_len=5;
				Main_Return_len=0;
				Main_Cmd_Data[7:0]=8'h31;
				Main_Cmd_Data[15:8]=8'h00;
				Main_Cmd_Data[23:16]=8'h60; //RX_TUNE
				Main_Cmd_Data[31:24]=8'h00;
				Main_Cmd_Data[39:32]=8'h00;
				Main_Current_State=101;
			end
		end
		101:
		begin
			Main_start=0;
			tx_state=`TX;
			Main_Current_State=102;
		end
		102:
		begin
			if(spi_op_done)
			begin
				enable_irq_sending=1;
				
				Main_Current_State=103;
			end
		end
		103:
		begin
			if(tx_done_wire)  //���ӳ�ʱ�ж�
			begin
				led[3]=~led[3];
				delay_start_2=0;
				//tx_state=`RX;
				Main_Current_State=105;
			end	
			else
			begin
				Main_Current_State=104;
			end
		end
		104:
		begin
		
			delay_start_2=1;
			delay_mtime_2=30;
			if(delay_int_2)
			begin
				tx_state=3'b000;
				delay_start_2=0;
				Main_Current_State=0;
			end
			else
			begin
				Main_Current_State=103;
			end
		end
		105:
		begin
			//�л���RX״̬
			if(!spi_Using_wire)
			begin
				Main_Cmd_Data[7:0]=8'h32;
				Main_Data_len=1;
				Main_Return_len=0;
				Main_Cmd=1;
				Main_start=1;
				Main_Current_State=106;
			end
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
				tx_state=`RX;
				Main_Current_State=60;
			end
		end
		
//		default:
//		begin
//			Main_Current_State=8'h00;
//		end
	endcase
end
end




/////�жϴ������///////////
/*
 *�����жϵļ��ͽ��մ�����
 *�жϺ����������жϣ���ѯ�ж�״̬���Լ������ͺ����ͽ��մ������źţ�֪ͨ���жϵ��
 *���պ���������������ݣ�ֻ��һ���������ݵ�����
*/
always@(posedge clk or negedge reset_n)
begin
	if(!reset_n)
	begin
		Irq_Current_State=0;

		Syncirq_Current_State=3;

		tx_flag=0;
		tx_done=0;
		irq_dealing=0;

		Int_start=0;
		//led[0]=1'b0;
		//led[1]=1'b0;
		packets_incoming=0;
	end
	else
	begin
		case (Irq_Current_State)		
			/////�ȴ��жϵ���
			0:
			begin
				if(enable_irq&&enable_irq_sending&&!Si4463_int) //1.��ʼ����ɺ�������ж� 2.������ڷ���׼�����ݣ���ʱ����������ж� 3.�ж��źŵ͵�ƽ��Ч
				begin
					if(tx_state_wire==`TX) //��������жϣ������ǰ��״̬Ϊ����״̬����ôĬ��Ϊ��ǰ״̬Ϊ������ɵ��ж�
					begin
						//led[0]=~led[0];
						tx_flag=1;
					end
					else
					begin
						tx_flag=0;
					end
					irq_dealing=1;
					Irq_Current_State=1;
				end
			end
			1://��ȡ�ж���ͬʱ���ж�
			begin
				if(!spi_Using_wire)
				begin
					Int_Cmd_Data[7:0]=8'h20;
					Int_Cmd_Data[15:8]=8'h00;
					Int_Cmd_Data[23:16]=8'h00;
					Int_Cmd_Data[31:24]=8'h00;
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
					Si4463_Ph_Status=Int_Return_Data[47:40];//PH_PEND
					Si4463_Modem_Status=Int_Return_Data[31:24];
					if(tx_flag==1)
					begin
						Irq_Current_State=4;//Ĭ�Ϸ��ͺ����������ж�
					end
					else if((Si4463_Ph_Status&8'h08)==8'b00001000) //CRC_ERROR
					begin
						led[0]=~led[0];
						//����fifo������RX״̬
						//���irq_dealing=0;
						Irq_Current_State=16;
					end
					else if((Si4463_Ph_Status&8'h10)==8'b00010000) //�����ж�
					begin
						led[1]=~led[1];
						Irq_Current_State=6;
					end
					else if((Si4463_Modem_Status&8'h03)==8'h03) //�յ�ͬ��ͷʱ�������жϣ���ȻҲ����ʹ��ǰ���룬����Ч�������ã���Ϊ��Ƶģ�����ױ������豸�ķ��͵�ǰ�������
					begin
						packets_incoming=packets_incoming+1'b1;
						Syncirq_Current_State=0;
						
						Irq_Current_State=0;
					end
					else
					begin
						Irq_Current_State=0;
						irq_dealing=0;
					end
				end
			end
			4://�������ж�
			begin
				tx_done=1;
				Irq_Current_State=5;
			end
			5:
			begin
				if(tx_state_wire==`RX) //�ȴ��������л�ΪRX״̬
				begin
					tx_flag=0;
					tx_done=0;
					irq_dealing=0;
					Irq_Current_State=0;
				end
			end			
			6://��������жϣ�
			begin
				if(!SRAM_AlmostFull) //ʣ���SRAM�ռ���������һ�����ݰ�
				begin
					Irq_Current_State=7;
				end
				else //����ֱ�ӷ��������ݰ����������FIFO
				begin
					Irq_Current_State=16;
				end
			end
			7://��ȡ�����ݰ���RSSIֵ
			begin
				if(!spi_Using_wire)
				begin
					Int_Cmd_Data[7:0]=8'h53; //FRR_C_READ for RSSI LATCHED of SYNC
					Int_start=1;
					Int_Cmd=6;
					Int_Data_len=1;
					Int_Return_len=1;
					Irq_Current_State=8;
				end
			end
			8:
			begin
				Int_start=0;
				Irq_Current_State=9;
			end
			9:
			begin
				if(spi_op_done)
				begin
					Si4463_RSSI_RecvPacket=Int_Return_Data[7:0];
					Irq_Current_State=10;
				end
			end
			10://д�������ֽڵı�־λ
			begin
				Int_Cmd_Data[7:0]=8'hd4;
				Int_Cmd_Data[15:8]=8'h2d; 
				Int_Data_len=2;
				Int_Return_len=0;
				Int_start=1;
				Int_Cmd=7;
				Irq_Current_State=11;
			end
			11:
			begin
				Int_start=0;
				Irq_Current_State=12;
			end
			12:
			begin
				if(spi_op_done)
				begin	
					Irq_Current_State=13;
				end
			end
			13: //���ͽ�������������ֱ�Ӷ�ȡ���ݣ����ܻ������Ϊ���SRAM�Ѿ����򣬿��ܻᵼ���������������ݵ�ģ�飬�����û��޷��������ݡ�
			begin    //�����漰����������ʱ�������ݵĶ�������
				Int_Data_len=0;
				Int_Return_len=0;
				Int_start=1;
				Int_Cmd=3;
				Irq_Current_State=14;
			end
			14:
			begin
				Int_start=0;
				Irq_Current_State=15;
			end
			15:
			begin
				if(spi_op_done)
				begin		
					//rx_start=0;
					//frame_recved_int=1;
					if(packets_incoming==1)
					begin
						Irq_Current_State=16;
					end
					else
					begin
						Irq_Current_State=16;
					end
				end
			end
			
			16: //����FIFO
			begin			
				if(!spi_Using_wire)
				begin
					Int_Cmd_Data[7:0]=8'h15;
					Int_Cmd_Data[15:8]=8'h03; 
					Int_Data_len=2;
					Int_Return_len=0;
					Int_start=1;
					Int_Cmd=4;
					Irq_Current_State=17;
				end
			end
			17:
			begin
				Int_start=0;
				Irq_Current_State=18;
			end
			18:
			begin
				if(spi_op_done)
				begin
					Irq_Current_State=19;
				end
			end
			19://ת����Rx״̬
			begin
				Int_Cmd_Data[7:0]=8'h32; 
				Int_Data_len=1;
				Int_Return_len=0;
				Int_start=1;
				Int_Cmd=4;
				Irq_Current_State=20;
			end
			20:
			begin
				Int_start=0;
				Irq_Current_State=21;
			end
			21:
			begin
				if(spi_op_done)
				begin			
					//rx_start=0;
					//packets_incoming=0;
					//frame_recved_int=1;
					Irq_Current_State=22;
				end
			end
			22://�鿴״̬ת���Ƿ�ɹ�
			begin
				Int_Cmd_Data[7:0]=8'h33;
				Int_Data_len=1;
				Int_Return_len=2;
				Int_start=1;
				Int_Cmd=4;
				Irq_Current_State=23;
			end
			23:
			begin
				Int_start=0;
				Irq_Current_State=24;
			end
			24:
			begin
				if(spi_op_done)
				begin				
					if(Int_Return_Data[15:8]==8'h08)
					begin
						packets_incoming=0;
						//frame_recved_int=1;
						Syncirq_Current_State=3;
						irq_dealing=0;//����ж�����
						Irq_Current_State=0;
					end
					else
					begin
						Irq_Current_State=19;
					end		
				end
			end
		endcase
		
		///////���ͬ��ͷ�жϺ�û���հ��ж�/////
		/* ���FIFO�����½���RX״̬��������packets_incoming*/
		case (Syncirq_Current_State)
			0:
			begin
				if(packets_incoming)
				begin
					delay_start_4=1;
					delay_mtime_4=`SYNC_IRQ_TIMEOUT;
					if(delay_int_4)
					begin
						
						delay_start_4=0;
						Syncirq_Current_State=1;
					end
				end
			end
			1://�ָ�״̬
			begin
				Irq_Current_State=16;
				Syncirq_Current_State=3;
			end
			3:
			begin
				delay_start_4=0;
			end
		endcase
	end//if(!reset_n)
end
endmodule

/*	
			
			0:
			begin
				if(enable_irq&&enable_irq_sending&&!Si4463_int) //1.��ʼ����ɺ�������ж� 2.������ڷ���׼�����ݣ���ʱ����������ж� 3.�ж��źŵ͵�ƽ��Ч
				begin
					if(tx_state_wire==`TX) //��������жϣ������ǰ��״̬Ϊ����״̬����ôĬ��Ϊ��ǰ״̬Ϊ������ɵ��ж�
					begin
						//led[0]=~led[0];
						tx_flag=1;
						rx_flag=~tx_flag;
						irq_dealing=1;
						Irq_Current_State=4;
					end
					else
					begin
						tx_flag=0;
						rx_flag=tx_flag;  ///������ܳ�������
						irq_dealing=1;
						Irq_Current_State=1;
					end
				end
			end
	
			//////��ȡ�ж�״̬���ж��ж�Դ
			1:
			begin
				if(!spi_Using_wire)
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
					
					Si4463_Ph_Status=Int_Return_Data[15:8]; //PH_PEND״̬
					Si4463_Modem_Status=Int_Return_Data[7:0];
					//Si4463_Ph_Status_1=Si4463_Ph_Status;
	
					if((Si4463_Ph_Status&8'h08)==8'b00001000) //CRC_ERROR
					begin
						led[0]=~led[0];
						
						Irq_Current_State=9;
					end
					else if((Si4463_Ph_Status&8'h10)==8'b00010000) //�����ж�
					begin
						led[1]=~led[1];
						Irq_Current_State=4;
						rx_flag=1;
					end
					else if((Si4463_Modem_Status&8'h03)==8'h03) //�յ�ͬ��ͷʱ�������жϣ���ȻҲ����ʹ��ǰ���룬����Ч�������ã���Ϊ��Ƶģ�����ױ������豸�ķ��͵�ǰ�������
					begin
						packets_incoming=packets_incoming+1'b1;
						Syncirq_Current_State=0;
						Irq_Current_State=4;
					end
					else
					begin
						Irq_Current_State=4;
					end
				end
			end
			
			4: //����ж�
			begin
				if(!spi_Using_wire)
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
					if(!Si4463_int) //����ж�û���������ôѭ������ж�
						Irq_Current_State=4;
					else
					begin
						Irq_Current_State=7;
					end
				end
			end
			7:
			begin
				if(rx_flag)  //����ǽ��������ж�
				begin
					rx_start=1;
					irq_dealing=0;
					Irq_Current_State=0;
				end
				else if(tx_flag) //����Ƿ�������ж�
				begin
					tx_done=1;
					Irq_Current_State=8;
				end
				else //�����жϼ��жϴ���
				begin
					irq_dealing=0;
					Irq_Current_State=0;
				end
			end
			8:
			begin
				if(tx_state_wire==`RX) //�ȴ��������л�Ϊ����״̬
				begin

					tx_flag=0;
					tx_done=0;
					irq_dealing=0;
					Irq_Current_State=0;
				end
			end
			
			9://CRC ERROR! ���жϣ���FIFO�����½���RX
			
			
			
			///����Ƿ����жϣ���tx_done Ϊ1
			///����ǽ����жϣ���ʾ�û���ʼ��������,��rx_startΪ1,������ɺ���Ϊ0/////////
//			default:
//			begin
//				irq_dealing=0;
//				Irq_Current_State=0;
//			end
		endcase
*/