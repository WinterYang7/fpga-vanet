

module Wireless_Ctrl(
	clk,
	
	//SRAM�ӿ�
	SRAM_read,
	SRAM_write,
	SRAM_full,
	SRAM_hint,
	SRAM_empty,
	SRAM_count,
	Data_to_sram,
	Data_from_sram,
	
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
	frame_recved_int,
	
	//����ָʾ��ǰ״̬��LED
	led,
	Si4463_Ph_Status_1
);
input clk;
output [7:0] Si4463_Ph_Status_1;
assign Si4463_Ph_Status_1={4'b000,Irq_Current_State};
output reg [3:0] led=4'b0000;

	//SRAM�ӿ�
output	SRAM_read;
output	SRAM_write;
input	SRAM_full;
input	SRAM_hint;
input	SRAM_empty;
input[10:0]	SRAM_count;
output[15:0]	Data_to_sram;
input[15:0]	Data_from_sram;
output reg frame_recved_int=0;
	
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


reg reset_n=1;


//�жϴ��������ź�
reg [3:0] Irq_Current_State=0;
reg [3:0] Recv_Current_State=0;
reg tx_done=0; //��1��ʾ�������
reg rx_start=0;
reg tx_flag=0; //�Ƿ�������ж�
reg rx_flag=0;
reg packet_incoming=0; //ָʾ��Ƶģ���յ�������δ�յ��������ݰ����ж�
reg [7:0] Si4463_Ph_Status=0;
reg [7:0] Si4463_Modem_Status=0;
reg [7:0] frame_len;
reg irq_dealing=0;


/////��ʱ����1///////////////
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
		if(delay_count==delay_mtime*20000) //20000������1ms
			delay_int<=1'b1;
	end
end

/////��ʱ����2///////////////
reg delay_start_2=0;
reg[31:0] delay_count_2=0;
reg[7:0] delay_mtime_2=8'h00;
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
	spi_Using  boolֵ������spiģ���Ƿ����ڱ�ʹ��
	spi_start  boolֵ������Ϊ1������׼����ʼ���ͻ��������
*/
reg [127:0] Main_Cmd_Data;  //�������е�����壬�����������ú�GetCTS
reg [31:0] Int_Cmd_Data;   //�жϳ����е�����壬��Ҫ�ǲ鿴�Ĵ���״̬��GetCTS
reg [79:0] Main_Return_Data;  //�������ݵĻ�����
reg [79:0] Int_Return_Data;   //Ҫ���յ����ݳ���
reg [7:0] Main_Data_len;  //Ҫ���͵����ݳ���
reg [4:0] Main_Return_len;  //GetCTS�󷵻ص����ݳ���
reg [7:0] Int_Data_len;
reg [3:0] Int_Return_len;
reg [2:0] Main_Cmd;   //�������е�����
reg [2:0] Int_Cmd;	//�жϺ����е�����
reg Main_start;  //Main��ʾ��Ҫ��ʼ�������ݣ���Ҫ��ǰ���Spi_Using
reg Int_start;   //Int��ʾ��Ҫ��ʼ�������ݣ���Ҫ��ǰ���Spi_Using
reg[31:0] Main_Data_Check=0;


reg [127:0] spi_cmd_data;
reg [7:0] spi_data_len=0;
reg [4:0] spi_return_len=0;
reg [2:0] spi_cmd=0;
reg spi_Using=0;
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
wire [10:0] SRAM_count;  //˵��FIFO_o�е����ݸ���
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
reg frame_len_flag; //��־�Ž��հ�ʱ��һ���ֽڣ������ĳ���
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
				if(!Byte_flag)
				begin
					Data_to_sram[15:8]=Data_from_master[7:0];
					if(frame_len_flag) //���յ��ĵ�һ���ֽ�Ϊ���ȣ�����������
					begin
						Byte_flag=~Byte_flag;
						frame_len_flag=0;
						Sended_count=0;
						spi_data_len=Data_from_master[7:0];
						Spi_Current_State=22;
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
			
			33: //���ͽ����������������֮�󣬿�����Ҫ�ȴ�һ��ʱ��������Ƶ׼�����ݣ���������֮����˵
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
				Spi_Current_State=37;
			end
			37:
			begin
				if(SRAM_hint)
				begin
					SRAM_read=0;
					Main_Data_Check[31:16]=Data_from_sram; //��ȡ����0x66 0x00
					Spi_Current_State=38;
				end
			end
			38:
			begin
				SRAM_read=1;
				Spi_Current_State=39;
			end
			39:
			begin
				if(SRAM_hint)
				begin
					SRAM_read=0;
					Main_Data_Check[15:0]=Data_from_sram; //��ȡ���ݳ���
					spi_Using=0;
					spi_start=0;
					spi_op_done=1;
					Spi_Current_State=0;
				end
			end
			
			//��ȡ���ټĴ���
			40:
			begin
				Data_to_master={8'h00,Int_Cmd_Data[7:0]};
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
		endcase
	end
end
end

reg GPS_sync_time=1'b1;  ////��Ҫ��GPSͬ��ʱ��
reg [7:0] Main_Current_State=8'h00;
reg Si4463_reset=1'b1; //��������������wireless_ctrl��λʱ������Ϊ0
wire Si4463_int;
reg [2:0] tx_state=3'b000;  //0ΪĬ�ϣ�1��ʾrx, 2��ʾtx_tune��3��ʾtx
reg[7:0] Data_Len_to_Send=8'h00;
reg enable_irq=1'b0; //��ʼ����ɺ󣬲��������жϺ���
reg enable_irq_sending=1'b1; //��������ʱ���ж�����Ч��
`define RX 3'b001
`define TX_TUNE 3'b010
`define TX 3'b011

always@(posedge clk)
begin
		case(Main_Current_State) 
		0:
		begin
			Si4463_reset=1;
			delay_start=1;
			delay_mtime=10;
			reset_n=0;
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
		
	////////setRFParameters(),������Ƶģ�����(��ʼ����Ƶģ���ϵĸ��ּĴ���)
	
//===setRFParameters(void)====
12:
begin
	Main_Cmd_Data[7:0]=8'h02;
	Main_Cmd_Data[15:8]=8'h01;
	Main_Cmd_Data[23:16]=8'h00;
	Main_Cmd_Data[31:24]=8'h01;
	Main_Cmd_Data[39:32]=8'hc9;
	Main_Cmd_Data[47:40]=8'hc3;
	Main_Cmd_Data[55:48]=8'h80;
	Main_Cmd=1;
	Main_start=1;
	Main_Data_len=7;
	Main_Return_len=0;
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
15:
begin
	Main_Cmd_Data[7:0]=8'h13;
	Main_Cmd_Data[15:8]=8'h1b;
	Main_Cmd_Data[23:16]=8'h23;
	Main_Cmd_Data[31:24]=8'h21;
	Main_Cmd_Data[39:32]=8'h20;
	Main_Cmd_Data[47:40]=8'h00;
	Main_Cmd_Data[55:48]=8'h00;
	Main_Cmd_Data[63:56]=8'h00;
	Main_Cmd=1;
	Main_start=1;
	Main_Data_len=8;
	Main_Return_len=0;
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
		Main_Current_State=18;
	end
end
18:
begin
	Main_Cmd_Data[7:0]=8'h11;
	Main_Cmd_Data[15:8]=8'h00;
	Main_Cmd_Data[23:16]=8'h02;
	Main_Cmd_Data[31:24]=8'h00;
	Main_Cmd_Data[39:32]=8'h52;
	Main_Cmd_Data[47:40]=8'h00;
	Main_Cmd=1;
	Main_start=1;
	Main_Data_len=6;
	Main_Return_len=0;
	Main_Current_State=19;
end
19:
begin
	Main_start=0;
	Main_Current_State=20;
end
20:
begin
	if(spi_op_done)
	begin
		Main_Current_State=21;
	end
end
21:
begin
	Main_Cmd_Data[7:0]=8'h11;
	Main_Cmd_Data[15:8]=8'h00;
	Main_Cmd_Data[23:16]=8'h01;
	Main_Cmd_Data[31:24]=8'h03;
	Main_Cmd_Data[39:32]=8'h60;
	Main_Cmd=1;
	Main_start=1;
	Main_Data_len=5;
	Main_Return_len=0;
	Main_Current_State=22;
end
22:
begin
	Main_start=0;
	Main_Current_State=23;
end
23:
begin
	if(spi_op_done)
	begin
		Main_Current_State=24;
	end
end
24:
begin
	Main_Cmd_Data[7:0]=8'h11;
	Main_Cmd_Data[15:8]=8'h01;
	Main_Cmd_Data[23:16]=8'h03;
	Main_Cmd_Data[31:24]=8'h00;
	Main_Cmd_Data[39:32]=8'h03;
	Main_Cmd_Data[47:40]=8'h30;
	Main_Cmd_Data[55:48]=8'h01;
	Main_Cmd=1;
	Main_start=1;
	Main_Data_len=6;
	Main_Return_len=0;
	Main_Current_State=25;
end
25:
begin
	Main_start=0;
	Main_Current_State=26;
end
26:
begin
	if(spi_op_done)
	begin
		Main_Current_State=27;
	end
end
27:
begin
	Main_Cmd_Data[7:0]=8'h11;
	Main_Cmd_Data[15:8]=8'h02;
	Main_Cmd_Data[23:16]=8'h04;
	Main_Cmd_Data[31:24]=8'h00;
	Main_Cmd_Data[39:32]=8'h04;
	Main_Cmd_Data[47:40]=8'h06;
	Main_Cmd_Data[55:48]=8'h00;
	Main_Cmd_Data[63:56]=8'h00;
	Main_Cmd=1;
	Main_start=1;
	Main_Data_len=8;
	Main_Return_len=0;
	Main_Current_State=28;
end
28:
begin
	Main_start=0;
	Main_Current_State=29;
end
29:
begin
	if(spi_op_done)
	begin
		Main_Current_State=30;
	end
end
30:
begin
	Main_Cmd_Data[7:0]=8'h11;
	Main_Cmd_Data[15:8]=8'h10;
	Main_Cmd_Data[23:16]=8'h09;
	Main_Cmd_Data[31:24]=8'h00;
	Main_Cmd_Data[39:32]=8'h08;
	Main_Cmd_Data[47:40]=8'h14;
	Main_Cmd_Data[55:48]=8'h00;
	Main_Cmd_Data[63:56]=8'h0f;
	Main_Cmd_Data[71:64]=8'h31;
	Main_Cmd_Data[79:72]=8'h00;
	Main_Cmd_Data[87:80]=8'h00;
	Main_Cmd_Data[95:88]=8'h00;
	Main_Cmd_Data[103:96]=8'h00;
	Main_Cmd=1;
	Main_start=1;
	Main_Data_len=13;
	Main_Return_len=0;
	Main_Current_State=31;
end
31:
begin
	Main_start=0;
	Main_Current_State=32;
end
32:
begin
	if(spi_op_done)
	begin
		Main_Current_State=33;
	end
end
33:
begin
	Main_Cmd_Data[7:0]=8'h11;
	Main_Cmd_Data[15:8]=8'h11;
	Main_Cmd_Data[23:16]=8'h05;
	Main_Cmd_Data[31:24]=8'h00;
	Main_Cmd_Data[39:32]=8'h01;
	Main_Cmd_Data[47:40]=8'hb4;
	Main_Cmd_Data[55:48]=8'h2b;
	Main_Cmd_Data[63:56]=8'h00;
	Main_Cmd_Data[71:64]=8'h00;
	Main_Cmd=1;
	Main_start=1;
	Main_Data_len=9;
	Main_Return_len=0;
	Main_Current_State=34;
end
34:
begin
	Main_start=0;
	Main_Current_State=35;
end
35:
begin
	if(spi_op_done)
	begin
		Main_Current_State=36;
	end
end
36:
begin
	Main_Cmd_Data[7:0]=8'h11;
	Main_Cmd_Data[15:8]=8'h12;
	Main_Cmd_Data[23:16]=8'h07;
	Main_Cmd_Data[31:24]=8'h00;
	Main_Cmd_Data[39:32]=8'h84;
	Main_Cmd_Data[47:40]=8'h00;
	Main_Cmd_Data[55:48]=8'h30;
	Main_Cmd_Data[63:56]=8'hff;
	Main_Cmd_Data[71:64]=8'hff;
	Main_Cmd_Data[79:72]=8'h00;
	Main_Cmd_Data[87:80]=8'h02;
	Main_Cmd=1;
	Main_start=1;
	Main_Data_len=11;
	Main_Return_len=0;
	Main_Current_State=37;
end
37:
begin
	Main_start=0;
	Main_Current_State=38;
end
38:
begin
	if(spi_op_done)
	begin
		Main_Current_State=39;
	end
end
39:
begin
	Main_Cmd_Data[7:0]=8'h11;
	Main_Cmd_Data[15:8]=8'h12;
	Main_Cmd_Data[23:16]=8'h0c;
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
	Main_Cmd=1;
	Main_start=1;
	Main_Data_len=16;
	Main_Return_len=0;
	Main_Current_State=40;
end
40:
begin
	Main_start=0;
	Main_Current_State=41;
end
41:
begin
	if(spi_op_done)
	begin
		Main_Current_State=42;
	end
end
42:
begin
	Main_Cmd_Data[7:0]=8'h11;
	Main_Cmd_Data[15:8]=8'h12;
	Main_Cmd_Data[23:16]=8'h0c;
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
	Main_Cmd=1;
	Main_start=1;
	Main_Data_len=16;
	Main_Return_len=0;
	Main_Current_State=43;
end
43:
begin
	Main_start=0;
	Main_Current_State=44;
end
44:
begin
	if(spi_op_done)
	begin
		Main_Current_State=45;
	end
end
45:
begin
	Main_Cmd_Data[7:0]=8'h11;
	Main_Cmd_Data[15:8]=8'h12;
	Main_Cmd_Data[23:16]=8'h0c;
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
	Main_Cmd=1;
	Main_start=1;
	Main_Data_len=16;
	Main_Return_len=0;
	Main_Current_State=46;
end
46:
begin
	Main_start=0;
	Main_Current_State=47;
end
47:
begin
	if(spi_op_done)
	begin
		Main_Current_State=48;
	end
end
48:
begin
	Main_Cmd_Data[7:0]=8'h11;
	Main_Cmd_Data[15:8]=8'h12;
	Main_Cmd_Data[23:16]=8'h09;
	Main_Cmd_Data[31:24]=8'h2c;
	Main_Cmd_Data[39:32]=8'h00;
	Main_Cmd_Data[47:40]=8'h00;
	Main_Cmd_Data[55:48]=8'h00;
	Main_Cmd_Data[63:56]=8'h00;
	Main_Cmd_Data[71:64]=8'h00;
	Main_Cmd_Data[79:72]=8'h00;
	Main_Cmd_Data[87:80]=8'h00;
	Main_Cmd_Data[95:88]=8'h00;
	Main_Cmd_Data[103:96]=8'h00;
	Main_Cmd=1;
	Main_start=1;
	Main_Data_len=13;
	Main_Return_len=0;
	Main_Current_State=49;
end
49:
begin
	Main_start=0;
	Main_Current_State=50;
end
50:
begin
	if(spi_op_done)
	begin
		Main_Current_State=51;
	end
end
51:
begin
	Main_Cmd_Data[7:0]=8'h11;
	Main_Cmd_Data[15:8]=8'h20;
	Main_Cmd_Data[23:16]=8'h0c;
	Main_Cmd_Data[31:24]=8'h00;
	Main_Cmd_Data[39:32]=8'h03;
	Main_Cmd_Data[47:40]=8'h00;
	Main_Cmd_Data[55:48]=8'h07;
	Main_Cmd_Data[63:56]=8'h3d;
	Main_Cmd_Data[71:64]=8'h09;
	Main_Cmd_Data[79:72]=8'h00;
	Main_Cmd_Data[87:80]=8'h01;
	Main_Cmd_Data[95:88]=8'hc9;
	Main_Cmd_Data[103:96]=8'hc3;
	Main_Cmd_Data[111:104]=8'h80;
	Main_Cmd_Data[119:112]=8'h00;
	Main_Cmd_Data[127:120]=8'h05;
	Main_Cmd=1;
	Main_start=1;
	Main_Data_len=16;
	Main_Return_len=0;
	Main_Current_State=52;
end
52:
begin
	Main_start=0;
	Main_Current_State=53;
end
53:
begin
	if(spi_op_done)
	begin
		Main_Current_State=54;
	end
end
54:
begin
	Main_Cmd_Data[7:0]=8'h11;
	Main_Cmd_Data[15:8]=8'h20;
	Main_Cmd_Data[23:16]=8'h01;
	Main_Cmd_Data[31:24]=8'h0c;
	Main_Cmd_Data[39:32]=8'h76;
	Main_Cmd=1;
	Main_start=1;
	Main_Data_len=5;
	Main_Return_len=0;
	Main_Current_State=55;
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
		Main_Current_State=57;
	end
end
57:
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
	Main_Cmd=1;
	Main_start=1;
	Main_Data_len=12;
	Main_Return_len=0;
	Main_Current_State=58;
end
58:
begin
	Main_start=0;
	Main_Current_State=59;
end
59:
begin
	if(spi_op_done)
	begin
		Main_Current_State=60;
	end
end
60:
begin
	Main_Cmd_Data[7:0]=8'h11;
	Main_Cmd_Data[15:8]=8'h20;
	Main_Cmd_Data[23:16]=8'h09;
	Main_Cmd_Data[31:24]=8'h22;
	Main_Cmd_Data[39:32]=8'h00;
	Main_Cmd_Data[47:40]=8'h4b;
	Main_Cmd_Data[55:48]=8'h06;
	Main_Cmd_Data[63:56]=8'hd3;
	Main_Cmd_Data[71:64]=8'ha0;
	Main_Cmd_Data[79:72]=8'h07;
	Main_Cmd_Data[87:80]=8'hff;
	Main_Cmd_Data[95:88]=8'h02;
	Main_Cmd_Data[103:96]=8'h00;
	Main_Cmd=1;
	Main_start=1;
	Main_Data_len=13;
	Main_Return_len=0;
	Main_Current_State=61;
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
		Main_Current_State=63;
	end
end
63:
begin
	Main_Cmd_Data[7:0]=8'h11;
	Main_Cmd_Data[15:8]=8'h20;
	Main_Cmd_Data[23:16]=8'h07;
	Main_Cmd_Data[31:24]=8'h2c;
	Main_Cmd_Data[39:32]=8'h00;
	Main_Cmd_Data[47:40]=8'h23;
	Main_Cmd_Data[55:48]=8'h8f;
	Main_Cmd_Data[63:56]=8'hff;
	Main_Cmd_Data[71:64]=8'h00;
	Main_Cmd_Data[79:72]=8'hb7;
	Main_Cmd_Data[87:80]=8'he0;
	Main_Cmd=1;
	Main_start=1;
	Main_Data_len=11;
	Main_Return_len=0;
	Main_Current_State=64;
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
		Main_Current_State=66;
	end
end
66:
begin
	Main_Cmd_Data[7:0]=8'h11;
	Main_Cmd_Data[15:8]=8'h20;
	Main_Cmd_Data[23:16]=8'h01;
	Main_Cmd_Data[31:24]=8'h35;
	Main_Cmd_Data[39:32]=8'he2;
	Main_Cmd=1;
	Main_start=1;
	Main_Data_len=5;
	Main_Return_len=0;
	Main_Current_State=67;
end
67:
begin
	Main_start=0;
	Main_Current_State=68;
end
68:
begin
	if(spi_op_done)
	begin
		Main_Current_State=69;
	end
end
69:
begin
	Main_Cmd_Data[7:0]=8'h11;
	Main_Cmd_Data[15:8]=8'h20;
	Main_Cmd_Data[23:16]=8'h09;
	Main_Cmd_Data[31:24]=8'h38;
	Main_Cmd_Data[39:32]=8'h22;
	Main_Cmd_Data[47:40]=8'h08;
	Main_Cmd_Data[55:48]=8'h08;
	Main_Cmd_Data[63:56]=8'h00;
	Main_Cmd_Data[71:64]=8'h1a;
	Main_Cmd_Data[79:72]=8'h06;
	Main_Cmd_Data[87:80]=8'h66;
	Main_Cmd_Data[95:88]=8'h00;
	Main_Cmd_Data[103:96]=8'h28;
	Main_Cmd=1;
	Main_start=1;
	Main_Data_len=13;
	Main_Return_len=0;
	Main_Current_State=70;
end
70:
begin
	Main_start=0;
	Main_Current_State=71;
end
71:
begin
	if(spi_op_done)
	begin
		Main_Current_State=72;
	end
end
72:
begin
	Main_Cmd_Data[7:0]=8'h11;
	Main_Cmd_Data[15:8]=8'h20;
	Main_Cmd_Data[23:16]=8'h09;
	Main_Cmd_Data[31:24]=8'h42;
	Main_Cmd_Data[39:32]=8'ha4;
	Main_Cmd_Data[47:40]=8'h03;
	Main_Cmd_Data[55:48]=8'hd6;
	Main_Cmd_Data[63:56]=8'h03;
	Main_Cmd_Data[71:64]=8'h00;
	Main_Cmd_Data[79:72]=8'h1a;
	Main_Cmd_Data[87:80]=8'h01;
	Main_Cmd_Data[95:88]=8'h80;
	Main_Cmd_Data[103:96]=8'h55;
	Main_Cmd=1;
	Main_start=1;
	Main_Data_len=13;
	Main_Return_len=0;
	Main_Current_State=73;
end
73:
begin
	Main_start=0;
	Main_Current_State=74;
end
74:
begin
	if(spi_op_done)
	begin
		Main_Current_State=75;
	end
end
75:
begin
	Main_Cmd_Data[7:0]=8'h11;
	Main_Cmd_Data[15:8]=8'h20;
	Main_Cmd_Data[23:16]=8'h01;
	Main_Cmd_Data[31:24]=8'h4c;
	Main_Cmd_Data[39:32]=8'h00;
	Main_Cmd=1;
	Main_start=1;
	Main_Data_len=5;
	Main_Return_len=0;
	Main_Current_State=76;
end
76:
begin
	Main_start=0;
	Main_Current_State=77;
end
77:
begin
	if(spi_op_done)
	begin
		Main_Current_State=78;
	end
end
78:
begin
	Main_Cmd_Data[7:0]=8'h11;
	Main_Cmd_Data[15:8]=8'h20;
	Main_Cmd_Data[23:16]=8'h01;
	Main_Cmd_Data[31:24]=8'h4e;
	Main_Cmd_Data[39:32]=8'h40;
	Main_Cmd=1;
	Main_start=1;
	Main_Data_len=5;
	Main_Return_len=0;
	Main_Current_State=79;
end
79:
begin
	Main_start=0;
	Main_Current_State=80;
end
80:
begin
	if(spi_op_done)
	begin
		Main_Current_State=81;
	end
end
81:
begin
	Main_Cmd_Data[7:0]=8'h11;
	Main_Cmd_Data[15:8]=8'h20;
	Main_Cmd_Data[23:16]=8'h01;
	Main_Cmd_Data[31:24]=8'h51;
	Main_Cmd_Data[39:32]=8'h0a;
	Main_Cmd=1;
	Main_start=1;
	Main_Data_len=5;
	Main_Return_len=0;
	Main_Current_State=82;
end
82:
begin
	Main_start=0;
	Main_Current_State=83;
end
83:
begin
	if(spi_op_done)
	begin
		Main_Current_State=84;
	end
end
84:
begin
	Main_Cmd_Data[7:0]=8'h11;
	Main_Cmd_Data[15:8]=8'h21;
	Main_Cmd_Data[23:16]=8'h0c;
	Main_Cmd_Data[31:24]=8'h00;
	Main_Cmd_Data[39:32]=8'h23;
	Main_Cmd_Data[47:40]=8'h17;
	Main_Cmd_Data[55:48]=8'hf4;
	Main_Cmd_Data[63:56]=8'hc2;
	Main_Cmd_Data[71:64]=8'h88;
	Main_Cmd_Data[79:72]=8'h50;
	Main_Cmd_Data[87:80]=8'h21;
	Main_Cmd_Data[95:88]=8'hff;
	Main_Cmd_Data[103:96]=8'hec;
	Main_Cmd_Data[111:104]=8'he6;
	Main_Cmd_Data[119:112]=8'he8;
	Main_Cmd_Data[127:120]=8'hee;
	Main_Cmd=1;
	Main_start=1;
	Main_Data_len=16;
	Main_Return_len=0;
	Main_Current_State=85;
end
85:
begin
	Main_start=0;
	Main_Current_State=86;
end
86:
begin
	if(spi_op_done)
	begin
		Main_Current_State=87;
	end
end
87:
begin
	Main_Cmd_Data[7:0]=8'h11;
	Main_Cmd_Data[15:8]=8'h21;
	Main_Cmd_Data[23:16]=8'h0c;
	Main_Cmd_Data[31:24]=8'h0c;
	Main_Cmd_Data[39:32]=8'hf6;
	Main_Cmd_Data[47:40]=8'hfb;
	Main_Cmd_Data[55:48]=8'h05;
	Main_Cmd_Data[63:56]=8'hc0;
	Main_Cmd_Data[71:64]=8'hff;
	Main_Cmd_Data[79:72]=8'h0f;
	Main_Cmd_Data[87:80]=8'h23;
	Main_Cmd_Data[95:88]=8'h17;
	Main_Cmd_Data[103:96]=8'hf4;
	Main_Cmd_Data[111:104]=8'hc2;
	Main_Cmd_Data[119:112]=8'h88;
	Main_Cmd_Data[127:120]=8'h50;
	Main_Cmd=1;
	Main_start=1;
	Main_Data_len=16;
	Main_Return_len=0;
	Main_Current_State=88;
end
88:
begin
	Main_start=0;
	Main_Current_State=89;
end
89:
begin
	if(spi_op_done)
	begin
		Main_Current_State=90;
	end
end
90:
begin
	Main_Cmd_Data[7:0]=8'h11;
	Main_Cmd_Data[15:8]=8'h21;
	Main_Cmd_Data[23:16]=8'h0c;
	Main_Cmd_Data[31:24]=8'h18;
	Main_Cmd_Data[39:32]=8'h21;
	Main_Cmd_Data[47:40]=8'hff;
	Main_Cmd_Data[55:48]=8'hec;
	Main_Cmd_Data[63:56]=8'he6;
	Main_Cmd_Data[71:64]=8'he8;
	Main_Cmd_Data[79:72]=8'hee;
	Main_Cmd_Data[87:80]=8'hf6;
	Main_Cmd_Data[95:88]=8'hfb;
	Main_Cmd_Data[103:96]=8'h05;
	Main_Cmd_Data[111:104]=8'hc0;
	Main_Cmd_Data[119:112]=8'hff;
	Main_Cmd_Data[127:120]=8'h0f;
	Main_Cmd=1;
	Main_start=1;
	Main_Data_len=16;
	Main_Return_len=0;
	Main_Current_State=91;
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
93:
begin
	Main_Cmd_Data[7:0]=8'h11;
	Main_Cmd_Data[15:8]=8'h22;
	Main_Cmd_Data[23:16]=8'h04;
	Main_Cmd_Data[31:24]=8'h00;
	Main_Cmd_Data[39:32]=8'h08;
	Main_Cmd_Data[47:40]=8'h7f;
	Main_Cmd_Data[55:48]=8'h00;
	Main_Cmd_Data[63:56]=8'h5d;
	Main_Cmd=1;
	Main_start=1;
	Main_Data_len=8;
	Main_Return_len=0;
	Main_Current_State=94;
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
		Main_Current_State=96;
	end
end
96:
begin
	Main_Cmd_Data[7:0]=8'h11;
	Main_Cmd_Data[15:8]=8'h23;
	Main_Cmd_Data[23:16]=8'h07;
	Main_Cmd_Data[31:24]=8'h00;
	Main_Cmd_Data[39:32]=8'h01;
	Main_Cmd_Data[47:40]=8'h05;
	Main_Cmd_Data[55:48]=8'h0b;
	Main_Cmd_Data[63:56]=8'h05;
	Main_Cmd_Data[71:64]=8'h02;
	Main_Cmd_Data[79:72]=8'h00;
	Main_Cmd_Data[87:80]=8'h03;
	Main_Cmd=1;
	Main_start=1;
	Main_Data_len=11;
	Main_Return_len=0;
	Main_Current_State=97;
end
97:
begin
	Main_start=0;
	Main_Current_State=98;
end
98:
begin
	if(spi_op_done)
	begin
		Main_Current_State=99;
	end
end
99:
begin
	Main_Cmd_Data[7:0]=8'h11;
	Main_Cmd_Data[15:8]=8'h30;
	Main_Cmd_Data[23:16]=8'h0c;
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
	Main_Cmd=1;
	Main_start=1;
	Main_Data_len=16;
	Main_Return_len=0;
	Main_Current_State=100;
end
100:
begin
	Main_start=0;
	Main_Current_State=101;
end
101:
begin
	if(spi_op_done)
	begin
		Main_Current_State=102;
	end
end
102:
begin
	Main_Cmd_Data[7:0]=8'h11;
	Main_Cmd_Data[15:8]=8'h40;
	Main_Cmd_Data[23:16]=8'h08;
	Main_Cmd_Data[31:24]=8'h00;
	Main_Cmd_Data[39:32]=8'h38;
	Main_Cmd_Data[47:40]=8'h0d;
	Main_Cmd_Data[55:48]=8'hdd;
	Main_Cmd_Data[63:56]=8'hdd;
	Main_Cmd_Data[71:64]=8'h44;
	Main_Cmd_Data[79:72]=8'h44;
	Main_Cmd_Data[87:80]=8'h20;
	Main_Cmd_Data[95:88]=8'hfe;
	Main_Cmd=1;
	Main_start=1;
	Main_Data_len=12;
	Main_Return_len=0;
	Main_Current_State=103;
end
103:
begin
	Main_start=0;
	Main_Current_State=104;
end
104:
begin
	if(spi_op_done)
	begin
		Main_Current_State=105;
	end
end




		//===set_frr_ctl(void)====
		105:
		begin
			Main_Cmd_Data[7:0]=8'h11;
			Main_Cmd_Data[15:8]=8'h02;
			Main_Cmd_Data[23:16]=8'h04;
			Main_Cmd_Data[31:24]=8'h00;
			Main_Cmd_Data[39:32]=8'h04;
			Main_Cmd_Data[47:40]=8'h06;
			Main_Cmd_Data[55:48]=8'h00;
			Main_Cmd_Data[63:56]=8'h00;
			Main_Cmd=1;
			Main_start=1;
			Main_Data_len=8;
			Main_Return_len=0;
			Main_Current_State=106;
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
				Main_Current_State=108;
			end
		end
		//===Function_set_tran_property()====
		108:
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
			Main_Current_State=109;
		end
		109:
		begin
			Main_start=0;
			Main_Current_State=110;
		end
		110:
		begin
			if(spi_op_done)
			begin
				Main_Current_State=111;
			end
		end
		111:
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
			Main_Current_State=112;
		end
		112:
		begin
			Main_start=0;
			Main_Current_State=113;
		end
		113:
		begin
			if(spi_op_done)
			begin
				Main_Current_State=114;
			end
		end
		114:
		begin
			Main_Cmd_Data[7:0]=8'h11;
			Main_Cmd_Data[15:8]=8'h12;
			Main_Cmd_Data[23:16]=8'h04;
			Main_Cmd_Data[31:24]=8'h0d;
			Main_Cmd_Data[39:32]=8'h00;
			Main_Cmd_Data[47:40]=8'h00;
			Main_Cmd_Data[55:48]=8'h00;
			Main_Cmd_Data[63:56]=8'ha0;
			Main_Cmd=1;
			Main_start=1;
			Main_Data_len=8;
			Main_Return_len=0;
			Main_Current_State=115;
		end
		115:
		begin
			Main_start=0;
			Main_Current_State=116;
		end
		116:
		begin
			if(spi_op_done)
			begin
				Main_Current_State=117;
			end
		end
		117:
		begin
			Main_Cmd_Data[7:0]=8'h11;
			Main_Cmd_Data[15:8]=8'h12;
			Main_Cmd_Data[23:16]=8'h04;
			Main_Cmd_Data[31:24]=8'h21;
			Main_Cmd_Data[39:32]=8'h00;
			Main_Cmd_Data[47:40]=8'h01;
			Main_Cmd_Data[55:48]=8'h00;
			Main_Cmd_Data[63:56]=8'h80;
			Main_Cmd=1;
			Main_start=1;
			Main_Data_len=8;
			Main_Return_len=0;
			Main_Current_State=118;
		end
		118:
		begin
			Main_start=0;
			Main_Current_State=119;
		end
		119:
		begin
			if(spi_op_done)
			begin
				Main_Current_State=120;
			end
		end
		120:
		begin
			Main_Cmd_Data[7:0]=8'h11;
			Main_Cmd_Data[15:8]=8'h12;
			Main_Cmd_Data[23:16]=8'h04;
			Main_Cmd_Data[31:24]=8'h25;
			Main_Cmd_Data[39:32]=8'h00;
			Main_Cmd_Data[47:40]=8'hfa;
			Main_Cmd_Data[55:48]=8'h00;
			Main_Cmd_Data[63:56]=8'h00;
			Main_Cmd=1;
			Main_start=1;
			Main_Data_len=8;
			Main_Return_len=0;
			Main_Current_State=121;
		end
		121:
		begin
			Main_start=0;
			Main_Current_State=122;
		end
		122:
		begin
			if(spi_op_done)
			begin
				Main_Current_State=123;
			end
		end
		123:
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
			Main_Current_State=124;
		end
		124:
		begin
			Main_start=0;
			Main_Current_State=125;
		end
		125:
		begin
			if(spi_op_done)
			begin
				Main_Current_State=126;
			end
		end
		126:
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
			Main_Current_State=127;
		end
		127:
		begin
			Main_start=0;
			Main_Current_State=128;
		end
		128:
		begin
			if(spi_op_done)
			begin
				Main_Current_State=160;
			end
		end

		
		//��Ҫ����FIFO
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
		
		//��鵱ǰ״̬
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
				if(Main_Return_Data[15:8]==8'h03)
				begin
					tx_state=3'b000;
					Main_Current_State=180;
				end
			end
		end
		
		
		//״̬ת��ΪRX
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
				enable_irq=1;   //��ʼ��������ж��ź�
				tx_state=`RX;
				Main_Current_State=130;
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
		130:
		begin
			led[2]=1;
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
				if(Main_Data_Check[31:24]==8'h66)
				begin
					Data_Len_to_Send=Main_Data_Check[7:0];
					if(SRAM_count*2>=Data_Len_to_Send)
					begin
						Main_Current_State=133;
					end
				end
				else
				begin
					Main_Current_State=130;
				end
			end
		end
		
		/////���SPI���ڱ�ʹ����ȴ��������������л�״̬Ϊtx_tune///////
		
		////�л�״̬0x34 05 TX_TUNE
		133:
		begin
			if(!spi_Using&&!irq_dealing&&!rx_start&&!packet_incoming)
			begin
				enable_irq_sending=0;
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
		///����FIFO
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
		
		
		//������Ҫ���͵����ݰ��ĳ���
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
		
		//////���SPI���ڱ�ʹ����ȴ�����������д����Ƶģ�黺������������
		
		139:
		begin
			if(!spi_Using)
			begin
				Main_Cmd=2;
				Main_Data_len=Data_Len_to_Send+1;  //+1����ΪҪ����0x66���������������Ϊ126,��ȥ�������ȣ���ֻʣ125�ֽ�
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
		
		
		///�ȴ�ʱ϶///////////
		200:
		begin
			if(GPS_sync_time) //����һ�����壬
			begin
				Main_Current_State=142;
			end
		end
		/////////���������ʼ��������///////////
		142:
		begin
			if(!spi_Using)
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
				enable_irq_sending=1;
				tx_state=`TX;
				Main_Current_State=145;
			end
		end
		145:
		begin
			if(tx_done)  //���ӳ�ʱ�ж�
			begin
				led[3]=~led[3];
				tx_state=`RX;
				Main_Current_State=130;
			end
			/*
			delay_start_2=1;
			delay_mtime_2=30;
			if(delay_int_2)
			begin
				tx_state=`RX;
				delay_start_2=0;
				Main_Current_State=0;
			end*/
		end
		
		default:
		begin
			Main_Current_State=8'h00;
		end
	endcase

end




/////�жϴ������///////////
always@(posedge clk)
begin
	case (Irq_Current_State)		
		/////�ȴ��жϵ���
		0:
		begin
			if(enable_irq&&enable_irq_sending&&!Si4463_int)
			begin
				rx_flag=0;  ///������ܳ�������
				tx_flag=0;
				irq_dealing=1;
				Irq_Current_State=1;
			end
		end
		/*
		9:
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
				Irq_Current_State=10;
			end
		end
		10:
		begin
			Int_start=0;
			Irq_Current_State=11;
		end
		11:
		begin
			if(spi_op_done)
			begin
				Si4463_Ph_Status=Int_Return_Data[47:40];
				if((Si4463_Ph_Status &8'h22)==8'b00100010 || (Si4463_Ph_Status&8'h22)==8'b00100000) //��������ж�
				begin
					tx_flag=1;
					Irq_Current_State=1;
				end
				if((Si4463_Ph_Status&8'h10)==8'b00010000) //�����ж�
				begin
					Irq_Current_State=1;
					rx_flag=1;
				end
				else
				begin
					Irq_Current_State=1;
				end
			end
		end*/
		//////��ȡ�ж�״̬���ж��ж�Դ
		1:
		begin
			if(!spi_Using)
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
				
				Si4463_Ph_Status=Int_Return_Data[15:8];
				Si4463_Modem_Status=Int_Return_Data[7:0];
				//Si4463_Ph_Status_1=Si4463_Ph_Status;
				/*
				if((Si4463_Ph_Status &8'h22)==8'b00100010 || (Si4463_Ph_Status&8'h22)==8'b00100000) //��������ж�
				begin
					led[0]=~led[0];
					tx_flag=1;
					Irq_Current_State=4;
				end*/
				if(tx_state==`TX)
				begin
					led[0]=~led[0];
					tx_flag=1;
					Irq_Current_State=4;
				end
				else if((Si4463_Ph_Status&8'h10)==8'b00010000) //�����ж�
				begin
					led[1]=~led[1];
					Irq_Current_State=4;
					rx_flag=1;
				end
				else if((Si4463_Modem_Status&8'h03)==8'h03)
				begin
					packet_incoming=1;
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
				begin
					Irq_Current_State=7;
				end
			end
		end
		7:
		begin
			if(rx_flag)
			begin
				packet_incoming=0;
				rx_start=1;
				irq_dealing=0;
				Irq_Current_State=0;
			end
			else if(tx_flag)
			begin
				tx_done=1;
				Irq_Current_State=8;
			end
			else
			begin
				irq_dealing=0;
				Irq_Current_State=0;
			end
		end
		8:
		begin
			if(tx_state!=`TX)
			begin
				tx_flag=0;
				tx_done=0;
				irq_dealing=0;
				Irq_Current_State=0;
			end
		end
		///����Ƿ����жϣ���tx_done Ϊ1
		///����ǽ����жϣ���ʾ�û���ʼ��������,��rx_startΪ1,������ɺ���Ϊ0/////////
		default:
		begin
			irq_dealing=0;
			Irq_Current_State=0;
		end
	endcase
	
	
	///////��������֡����/////////////////
	case (Recv_Current_State)
		0:
		begin
			if(rx_start)
			begin
				Recv_Current_State=4;
			end
		end
		/*
		1:
		begin
			if(!spi_Using)
			begin
				Int_Cmd_Data[7:0]=8'h15;
				Int_Cmd_Data[15:8]=8'h00; 
				Int_Data_len=2;
				Int_Return_len=2;
				Int_start=1;
				Int_Cmd=4;
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
				//rx_flag=0;
				Si4463_Ph_Status_1=Int_Return_Data[15:8];
				Recv_Current_State=4;
			end
		end*/
		4: //���ͽ�������   ��������еĻ������Խ�����������SPI��
		begin
			Int_Data_len=0;
			Int_Return_len=0;
			Int_start=1;
			Int_Cmd=3;
			Recv_Current_State=5;
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
				rx_start=0;
				frame_recved_int=1;
				Recv_Current_State=0;
			end
		end
		/*
		7: //����FIFO
		begin
			frame_recved_int=0;
			if(!spi_Using)
			begin
				Int_Cmd_Data[7:0]=8'h15;
				Int_Cmd_Data[15:8]=8'h03; //����ԭ����03����������Ϊ02�����һ��
				Int_Data_len=2;
				Int_Return_len=0;
				Int_start=1;
				Int_Cmd=4;
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
		end*/
		default:
		begin
			rx_start=0;
			tx_done=0;
			Recv_Current_State=0;
		end
	endcase
end


endmodule
