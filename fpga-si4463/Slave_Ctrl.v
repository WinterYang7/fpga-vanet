module Slave_Ctrl(
	clk,
	
	//��CPU�Ľӿ�
	mosi,
	miso,
	sclk,
	//signal_int,
	
	//��SRAM�Ľӿ�
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

	
	//֡�����ж�,��wireless_ctrl����
	//frame_recved_int,
	
	//��CPU���ӵ��ж�
	cpu_recv_int,
	
	Spi_Current_State_1,
	Spi_rrdy,
	Spi_trdy,
	Data_from_spi,
	
	//���������ǰ״̬
	Slave_Ctrl_Status,
	Slave_Ctrl_Debug
);
output [7:0] Slave_Ctrl_Status;
assign Slave_Ctrl_Status[5:0]=Spi_Current_State;
assign Slave_Ctrl_Status[6]=slave_trdy;
assign Slave_Ctrl_Status[7]=Irq_Current_State[2];
output [1:0] Slave_Ctrl_Debug;//for DUBUG
assign Slave_Ctrl_Debug=Irq_Current_State[1:0];

output Data_from_spi;
output Spi_trdy;
output Spi_rrdy;
input	clk;
//input frame_recved_int;
output reg cpu_recv_int=1'b1;
output  [7:0] Spi_Current_State_1;	
//assign Spi_Current_State_1={3'b000,Spi_Current_State};
	//��CPU�Ľӿ�
input	mosi;
output	miso;
input	sclk;
//output	signal_int;
	
//��SRAM�Ľӿ�
output reg Config_write_sram=0;
output reg Config_write_sram_done=0;	

output reg	SRAM_read=0;
output reg  SRAM_write=0;
input	SRAM_hint;
output reg [15:0]	Data_to_sram;
input[15:0]	Data_from_sram;
reg[15:0] Data_from_sram_reg;
input	SRAM_full;
input	SRAM_empty;
input[17:0]	SRAM_count;

//��spi������
wire slave_reset_n;
assign slave_reset_n=0;
wire slave_ss_n;
assign slave_ss_n=0;

wire slave_irq; //SPI slave�ӵ�һ���ֽڸ�һ������
reg[7:0] slave_data_to_spi; //FPGA�ṩ��Galileo������
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

///////����SPI�������������ѡ��ѭ����������
//Ϊ�˸��õ���Ӧ�ԣ�������������Ƶģ�����Ƶ�ģʽ
/*
	CPU���������� cmd::0x66+data_len+����
	CPU���������� cmd::0x77+data_len ���������Ҫ�ȴ�һ��ʱ��
				  ���أ�SRAM�е�������
	��ȡSRAM���ֽ����� //���Ҳ���Բ���Ҫ�����ǵȵ�SRAM�����ݵ���һ��ֵ����һ�������İ��󣬸�CPU�ж�
				  ����һ�ַ�ʽ�Ǵ�SRAM��ȡ�����ݣ��ȵ�ȡ��֮�󣬸�CPU����һ����־��0xFFFF���ܿ�����Ҫ�����ֽ�
				  



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

//�жϾ���
reg[7:0] packet_len=0;
reg spi_send_end=0; //���͸�CPU�������Ѿ������꣬˵��׼��������һ���ж�
wire spi_send_end_wire;
assign spi_send_end_wire=spi_send_end;
reg spi_read_sram=0; //spi��ȡSRAM��ʹ���ź�


//reset_n
reg reset_n=1;
wire reset_n_wire;
assign reset_n_wire=reset_n;

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
				8'b00010001: //д�����ļ�����0x11
				begin
					Sended_count=0;
					Byte_flag=0;
					Config_len[15:0]=16'b0;
					Config_count[15:0]=16'b0;
					Spi_Current_State=30;
				end
				8'b01100110: //CPU��������0x66
				begin
					Data_to_sram[15:8]=8'h2D;
					Sended_count=0;
					Byte_flag=0;
					//tx_flag=1;
					Spi_Current_State=4;
				end
				8'b01110111: //CPU��������0x77
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
		 * ���������ļ��������ļ���һ���ֽ�Ϊ�������õ��ֽڳ��ȣ������ֽڿ�
		 * 30~
		 */
		30://�������ó���
		begin
			if(slave_irq)
			begin
				slave_data_from_spi_reg=slave_data_from_spi;
				Spi_Current_State=31;
			end
		end
		31://�������ó���
		begin
			if(!Byte_flag)
			begin
				Config_len[15:8]=slave_data_from_spi_reg;//���ȵ�һ���ֽ�
				Byte_flag=~Byte_flag;
				Spi_Current_State=30;//���յڶ����ֽ�
			end
			else
			begin
				Config_len[7:0]=slave_data_from_spi_reg;//���ȵڶ����ֽ�
				Spi_Current_State=32;//��ʼ������������
				Byte_flag=~Byte_flag;
			end
		end
		32://���ó���д��sram
		begin
			Data_to_sram[15:0]=Config_len[15:0];
			Config_write_sram=1;
			Spi_Current_State=33;
		end
		33:
		begin
			Config_write_sram=0;
			if(SRAM_hint)
			begin
				
				Spi_Current_State=34;
			end
		end
		34://������������
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
					Spi_Current_State=36;//�������
				end
				else
				begin
					Spi_Current_State=34;//��������
				end
			end
			else
			begin
				Data_to_sram[7:0]=slave_data_from_spi_reg;
				Byte_flag=~Byte_flag;
				Config_count=Config_count+1'b1;
				Spi_Current_State=36;//������2���ֽڣ�д��sram
			end
		end
		36://��������д��sram
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
					Spi_Current_State=34; //�������ݻ�û�н������
				end
				else
				begin
					Spi_Current_State=38;
				end
			end
		end
		38://�����ļ�������ϣ���SRAM controlһ����λ�źţ���λ��Galileo���ж��ź�
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
		//������д��SRAM 0x2d 0xd4
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
		//�����ݳ���д��SRAM
		9: /*һ����һ�������Ǹ����Ƴ���ʶ������峤�ȣ��ڶ���������Ҫ���ͳ�ȥ�����ݰ�����*/
		begin
			if(!SRAM_full)
			begin
				Data_to_sram={8'h00,Data_len[7:0]+1}; //+1����Ϊ�����ݳ��Ȱ�������
				SRAM_write=1;
				Spi_Current_State=10;
			end
		end
		10:
		begin
			if(SRAM_hint)
			begin
				SRAM_write=0;
				Data_to_sram[15:8]=Data_len; //�����ݳ�����ӵ�����֡ͷ��
				Byte_flag=~Byte_flag;
				Spi_Current_State=11;
				
			end
		end
		
		//��SPI��ȡ���ݲ�д��SRAM
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
		
		
		
		
		////////������CPU��������/////////////////
		///��SRAM��ȡ������
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
		//��ȡ���ݲ�����
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


////�жϺ���//////����Ҫ�ȴ����û���ȡ֮���Զ�����ж�
reg[2:0] Irq_Current_State=0;


always@(posedge clk)
begin
	if(!reset_n_wire)
	begin
		Irq_Current_State=0;
		SRAM_read=0;
		cpu_recv_int=1;
	end

	case (Irq_Current_State)
		0:
		begin
			if(!SRAM_empty) //��ȡǰ��ı�־�ֽ�
			begin
				SRAM_read=1;
				Irq_Current_State=6;
			end
		end
		6:
		begin
			if(SRAM_hint) 
			begin
				SRAM_read=0;
				Data_from_sram_reg=Data_from_sram;
				if(Data_from_sram_reg==16'h2DD4)
					Irq_Current_State=7;
				else
					Irq_Current_State=0;
			end
		end
		7:
		begin
			if(!SRAM_empty) //��ȡ�����Ⱥ͵�һ������
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
			if(SRAM_count*2>=packet_len-1)//һ��count�����������ֽڡ�
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
		default:
		begin
			cpu_recv_int=1;
			Irq_Current_State=0;
		end
	endcase
end

endmodule