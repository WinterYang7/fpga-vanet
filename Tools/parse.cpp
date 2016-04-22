#define  _CRT_SECURE_NO_WARNINGS
#include<stdio.h>
//#include<Windows.h>
#include"config.h"
#include"spi_api.h"

static unsigned char config_table[] = RADIO_CONFIGURATION_DATA_ARRAY;


int state = 12;
FILE* fp;

void setRFParameters(void)  //…Ë÷√RF≤Œ ˝
{
	int i;
	int j = 0;
	int k = 0;

	fprintf(fp, "//===setRFParameters(void)====\n");
	while ((i = config_table[j]) != 0)
	{
		j += 1;
		fprintf(fp,"%d:\n", state);
		state += 1;
		fprintf(fp, "begin\n");
		for (k = 0; k<i; k++)
		{
			fprintf(fp, "\tMain_Cmd_Data[%d:%d]=8'h%02x;\n", (k + 1) * 8 - 1, k * 8, config_table[j + k]);
		}
		fprintf(fp, "\tMain_Cmd=1;\n");
		fprintf(fp, "\tMain_start=1;\n");
		fprintf(fp, "\tMain_Data_len=%d;\n", i);
		fprintf(fp, "\tMain_Return_len=0;\n");
		fprintf(fp, "\tMain_Current_State=%d;\n", state);
		fprintf(fp, "end\n");

		fprintf(fp, "%d:\n", state);
		state += 1;
		fprintf(fp, "begin\n");
		fprintf(fp, "\tMain_start=0;\n");
		fprintf(fp, "\tMain_Current_State=%d;\n", state);
		fprintf(fp, "end\n");

		fprintf(fp, "%d:\n", state);
		state += 1;
		fprintf(fp, "begin\n");
		fprintf(fp, "\tif(spi_op_done)\n");
		fprintf(fp, "\tbegin\n");
		fprintf(fp, "\t\tMain_Current_State=%d;\n", state);
		fprintf(fp, "\tend\n");
		fprintf(fp, "end\n");
		j += i;
	}
}

void set_frr_ctl(void) {
	fprintf(fp, "//===set_frr_ctl(void)====\n");
	int k = 0;
	fprintf(fp,"%d:\n", state);
	state += 1;
	fprintf(fp, "begin\n");
	fprintf(fp, "\tMain_Cmd_Data[%d:%d]=8'h%02x;\n", (k + 1) * 8 - 1, k * 8, 0x11);
	k++;
	fprintf(fp, "\tMain_Cmd_Data[%d:%d]=8'h%02x;\n", (k + 1) * 8 - 1, k * 8, 0x02);
	k++;
	fprintf(fp, "\tMain_Cmd_Data[%d:%d]=8'h%02x;\n", (k + 1) * 8 - 1, k * 8, 0x04);
	k++;
	fprintf(fp, "\tMain_Cmd_Data[%d:%d]=8'h%02x;\n", (k + 1) * 8 - 1, k * 8, 0x00);
	k++;
	fprintf(fp, "\tMain_Cmd_Data[%d:%d]=8'h%02x;\n", (k + 1) * 8 - 1, k * 8, 0x04);
	k++;
	fprintf(fp, "\tMain_Cmd_Data[%d:%d]=8'h%02x;\n", (k + 1) * 8 - 1, k * 8, 0x02);
	k++;
	fprintf(fp, "\tMain_Cmd_Data[%d:%d]=8'h%02x;\n", (k + 1) * 8 - 1, k * 8, 0x09);
	k++;
	fprintf(fp, "\tMain_Cmd_Data[%d:%d]=8'h%02x;\n", (k + 1) * 8 - 1, k * 8, 0x00);
	k++;
	fprintf(fp, "\tMain_Cmd=1;\n");
	fprintf(fp, "\tMain_start=1;\n");
	fprintf(fp, "\tMain_Data_len=%d;\n", k);
	fprintf(fp, "\tMain_Return_len=0;\n");
	fprintf(fp, "\tMain_Current_State=%d;\n", state);
	fprintf(fp, "end\n");

	fprintf(fp, "%d:\n", state);
	state += 1;
	fprintf(fp, "begin\n");
	fprintf(fp, "\tMain_start=0;\n");
	fprintf(fp, "\tMain_Current_State=%d;\n", state);
	fprintf(fp, "end\n");

	fprintf(fp, "%d:\n", state);
	state += 1;
	fprintf(fp, "begin\n");
	fprintf(fp, "\tif(spi_op_done)\n");
	fprintf(fp, "\tbegin\n");
	fprintf(fp, "\t\tMain_Current_State=%d;\n", state);
	fprintf(fp, "\tend\n");
	fprintf(fp, "end\n");
}

void Function_set_tran_property(){
	fprintf(fp, "//===Function_set_tran_property()====\n");
	int k = 0;
	fprintf(fp,"%d:\n", state);
	state += 1;
	fprintf(fp, "begin\n");
	fprintf(fp, "\tMain_Cmd_Data[%d:%d]=8'h%02x;\n", (k + 1) * 8 - 1, k * 8, CMD_SET_PROPERTY);
	k++;
	fprintf(fp, "\tMain_Cmd_Data[%d:%d]=8'h%02x;\n", (k + 1) * 8 - 1, k * 8, PROP_PKT_GROUP);
	k++;
	fprintf(fp, "\tMain_Cmd_Data[%d:%d]=8'h%02x;\n", (k + 1) * 8 - 1, k * 8, 0x01);
	k++;
	fprintf(fp, "\tMain_Cmd_Data[%d:%d]=8'h%02x;\n", (k + 1) * 8 - 1, k * 8, PROP_PKT_CONFIG1);
	k++;
	fprintf(fp, "\tMain_Cmd_Data[%d:%d]=8'h%02x;\n", (k + 1) * 8 - 1, k * 8, 0x80);
	k++;
	fprintf(fp, "\tMain_Cmd=1;\n");
	fprintf(fp, "\tMain_start=1;\n");
	fprintf(fp, "\tMain_Data_len=%d;\n", k);
	fprintf(fp, "\tMain_Return_len=0;\n");
	fprintf(fp, "\tMain_Current_State=%d;\n", state);
	fprintf(fp, "end\n");

	fprintf(fp, "%d:\n", state);
	state += 1;
	fprintf(fp, "begin\n");
	fprintf(fp, "\tMain_start=0;\n");
	fprintf(fp, "\tMain_Current_State=%d;\n", state);
	fprintf(fp, "end\n");

	fprintf(fp, "%d:\n", state);
	state += 1;
	fprintf(fp, "begin\n");
	fprintf(fp, "\tif(spi_op_done)\n");
	fprintf(fp, "\tbegin\n");
	fprintf(fp, "\t\tMain_Current_State=%d;\n", state);
	fprintf(fp, "\tend\n");
	fprintf(fp, "end\n");




	k = 0;
	fprintf(fp,"%d:\n", state);
	state += 1;
	fprintf(fp, "begin\n");
	fprintf(fp, "\tMain_Cmd_Data[%d:%d]=8'h%02x;\n", (k + 1) * 8 - 1, k * 8, CMD_SET_PROPERTY);
	k++;
	fprintf(fp, "\tMain_Cmd_Data[%d:%d]=8'h%02x;\n", (k + 1) * 8 - 1, k * 8, PROP_PKT_GROUP);
	k++;
	fprintf(fp, "\tMain_Cmd_Data[%d:%d]=8'h%02x;\n", (k + 1) * 8 - 1, k * 8, 0x03);
	k++;
	fprintf(fp, "\tMain_Cmd_Data[%d:%d]=8'h%02x;\n", (k + 1) * 8 - 1, k * 8, PROP_PKT_LEN);
	k++;
	fprintf(fp, "\tMain_Cmd_Data[%d:%d]=8'h%02x;\n", (k + 1) * 8 - 1, k * 8, 0x02);
	k++;
	fprintf(fp, "\tMain_Cmd_Data[%d:%d]=8'h%02x;\n", (k + 1) * 8 - 1, k * 8, 0x01);
	k++;
	fprintf(fp, "\tMain_Cmd_Data[%d:%d]=8'h%02x;\n", (k + 1) * 8 - 1, k * 8, 0x00);
	k++;
	fprintf(fp, "\tMain_Cmd=1;\n");
	fprintf(fp, "\tMain_start=1;\n");
	fprintf(fp, "\tMain_Data_len=%d;\n", k);
	fprintf(fp, "\tMain_Return_len=0;\n");
	fprintf(fp, "\tMain_Current_State=%d;\n", state);
	fprintf(fp, "end\n");

	fprintf(fp, "%d:\n", state);
	state += 1;
	fprintf(fp, "begin\n");
	fprintf(fp, "\tMain_start=0;\n");
	fprintf(fp, "\tMain_Current_State=%d;\n", state);
	fprintf(fp, "end\n");

	fprintf(fp, "%d:\n", state);
	state += 1;
	fprintf(fp, "begin\n");
	fprintf(fp, "\tif(spi_op_done)\n");
	fprintf(fp, "\tbegin\n");
	fprintf(fp, "\t\tMain_Current_State=%d;\n", state);
	fprintf(fp, "\tend\n");
	fprintf(fp, "end\n");



	k = 0;
	fprintf(fp,"%d:\n", state);
	state += 1;
	fprintf(fp, "begin\n");
	fprintf(fp, "\tMain_Cmd_Data[%d:%d]=8'h%02x;\n", (k + 1) * 8 - 1, k * 8, CMD_SET_PROPERTY);
	k++;
	fprintf(fp, "\tMain_Cmd_Data[%d:%d]=8'h%02x;\n", (k + 1) * 8 - 1, k * 8, PROP_PKT_GROUP);
	k++;
	fprintf(fp, "\tMain_Cmd_Data[%d:%d]=8'h%02x;\n", (k + 1) * 8 - 1, k * 8, 0x04);
	k++;
	fprintf(fp, "\tMain_Cmd_Data[%d:%d]=8'h%02x;\n", (k + 1) * 8 - 1, k * 8, PROP_PKT_FIELD_1_LENGTH_12_8);
	k++;
	fprintf(fp, "\tMain_Cmd_Data[%d:%d]=8'h%02x;\n", (k + 1) * 8 - 1, k * 8, 0x00);
	k++;
	fprintf(fp, "\tMain_Cmd_Data[%d:%d]=8'h%02x;\n", (k + 1) * 8 - 1, k * 8, 0x00);
	k++;
	fprintf(fp, "\tMain_Cmd_Data[%d:%d]=8'h%02x;\n", (k + 1) * 8 - 1, k * 8, 0x00);
	k++;
	fprintf(fp, "\tMain_Cmd_Data[%d:%d]=8'h%02x;\n", (k + 1) * 8 - 1, k * 8, 0xA0);
	k++;
	fprintf(fp, "\tMain_Cmd=1;\n");
	fprintf(fp, "\tMain_start=1;\n");
	fprintf(fp, "\tMain_Data_len=%d;\n", k);
	fprintf(fp, "\tMain_Return_len=0;\n");
	fprintf(fp, "\tMain_Current_State=%d;\n", state);
	fprintf(fp, "end\n");

	fprintf(fp, "%d:\n", state);
	state += 1;
	fprintf(fp, "begin\n");
	fprintf(fp, "\tMain_start=0;\n");
	fprintf(fp, "\tMain_Current_State=%d;\n", state);
	fprintf(fp, "end\n");

	fprintf(fp, "%d:\n", state);
	state += 1;
	fprintf(fp, "begin\n");
	fprintf(fp, "\tif(spi_op_done)\n");
	fprintf(fp, "\tbegin\n");
	fprintf(fp, "\t\tMain_Current_State=%d;\n", state);
	fprintf(fp, "\tend\n");
	fprintf(fp, "end\n");




k = 0;
fprintf(fp,"%d:\n", state);
state += 1;
fprintf(fp, "begin\n");
fprintf(fp, "\tMain_Cmd_Data[%d:%d]=8'h%02x;\n", (k + 1) * 8 - 1, k * 8, CMD_SET_PROPERTY);
k++;
fprintf(fp, "\tMain_Cmd_Data[%d:%d]=8'h%02x;\n", (k + 1) * 8 - 1, k * 8, PROP_PKT_GROUP);
k++;
fprintf(fp, "\tMain_Cmd_Data[%d:%d]=8'h%02x;\n", (k + 1) * 8 - 1, k * 8, 0x04);
k++;
fprintf(fp, "\tMain_Cmd_Data[%d:%d]=8'h%02x;\n", (k + 1) * 8 - 1, k * 8, PROP_PKT_RX_FIELD_1_LENGTH_12_8);
k++;
fprintf(fp, "\tMain_Cmd_Data[%d:%d]=8'h%02x;\n", (k + 1) * 8 - 1, k * 8, 0x00);
k++;
fprintf(fp, "\tMain_Cmd_Data[%d:%d]=8'h%02x;\n", (k + 1) * 8 - 1, k * 8, 0x01);
k++;
fprintf(fp, "\tMain_Cmd_Data[%d:%d]=8'h%02x;\n", (k + 1) * 8 - 1, k * 8, 0x00);
k++;
fprintf(fp, "\tMain_Cmd_Data[%d:%d]=8'h%02x;\n", (k + 1) * 8 - 1, k * 8, 0x80);
k++;
fprintf(fp, "\tMain_Cmd=1;\n");
fprintf(fp, "\tMain_start=1;\n");
fprintf(fp, "\tMain_Data_len=%d;\n", k);
fprintf(fp, "\tMain_Return_len=0;\n");
fprintf(fp, "\tMain_Current_State=%d;\n", state);
fprintf(fp, "end\n");

fprintf(fp, "%d:\n", state);
state += 1;
fprintf(fp, "begin\n");
fprintf(fp, "\tMain_start=0;\n");
fprintf(fp, "\tMain_Current_State=%d;\n", state);
fprintf(fp, "end\n");

fprintf(fp, "%d:\n", state);
state += 1;
fprintf(fp, "begin\n");
fprintf(fp, "\tif(spi_op_done)\n");
fprintf(fp, "\tbegin\n");
fprintf(fp, "\t\tMain_Current_State=%d;\n", state);
fprintf(fp, "\tend\n");
fprintf(fp, "end\n");



k = 0;
fprintf(fp,"%d:\n", state);
state += 1;
fprintf(fp, "begin\n");
fprintf(fp, "\tMain_Cmd_Data[%d:%d]=8'h%02x;\n", (k + 1) * 8 - 1, k * 8, CMD_SET_PROPERTY);
k++;
fprintf(fp, "\tMain_Cmd_Data[%d:%d]=8'h%02x;\n", (k + 1) * 8 - 1, k * 8, PROP_PKT_GROUP);
k++;
fprintf(fp, "\tMain_Cmd_Data[%d:%d]=8'h%02x;\n", (k + 1) * 8 - 1, k * 8, 0x04);
k++;
fprintf(fp, "\tMain_Cmd_Data[%d:%d]=8'h%02x;\n", (k + 1) * 8 - 1, k * 8, PROP_PKT_RX_FIELD_2_LENGTH_12_8);
k++;
fprintf(fp, "\tMain_Cmd_Data[%d:%d]=8'h%02x;\n", (k + 1) * 8 - 1, k * 8, 0x00);
k++;
fprintf(fp, "\tMain_Cmd_Data[%d:%d]=8'h%02x;\n", (k + 1) * 8 - 1, k * 8, MAX_PACKET_LENGTH);
k++;
fprintf(fp, "\tMain_Cmd_Data[%d:%d]=8'h%02x;\n", (k + 1) * 8 - 1, k * 8, 0x00);
k++;
fprintf(fp, "\tMain_Cmd_Data[%d:%d]=8'h%02x;\n", (k + 1) * 8 - 1, k * 8, 0x00);
k++;
fprintf(fp, "\tMain_Cmd=1;\n");
fprintf(fp, "\tMain_start=1;\n");
fprintf(fp, "\tMain_Data_len=%d;\n", k);
fprintf(fp, "\tMain_Return_len=0;\n");
fprintf(fp, "\tMain_Current_State=%d;\n", state);
fprintf(fp, "end\n");

fprintf(fp, "%d:\n", state);
state += 1;
fprintf(fp, "begin\n");
fprintf(fp, "\tMain_start=0;\n");
fprintf(fp, "\tMain_Current_State=%d;\n", state);
fprintf(fp, "end\n");

fprintf(fp, "%d:\n", state);
state += 1;
fprintf(fp, "begin\n");
fprintf(fp, "\tif(spi_op_done)\n");
fprintf(fp, "\tbegin\n");
fprintf(fp, "\t\tMain_Current_State=%d;\n", state);
fprintf(fp, "\tend\n");
fprintf(fp, "end\n");

// Configure CRC polynomial and seed
//	abApi_Write[0] = CMD_SET_PROPERTY;        // Use property command
//	abApi_Write[1] = PROP_PKT_GROUP;        // Select property group
//	abApi_Write[2] = 1;               // Number of properties to be written
//	abApi_Write[3] = PROP_PKT_CRC_CONFIG;     // Specify property
//	abApi_Write[4] = 0x83;              // CRC seed: all `1`s, poly: No. 3, 16bit, Baicheva-16
//	spi_write_cmd(5,abApi_Write);        // Send command to the radio IC
//	vApi_WaitforCTS();                // Wait for CTS

k = 0;
fprintf(fp,"%d:\n", state);
state += 1;
fprintf(fp, "begin\n");
fprintf(fp, "\tMain_Cmd_Data[%d:%d]=8'h%02x;\n", (k + 1) * 8 - 1, k * 8, CMD_SET_PROPERTY);
k++;
fprintf(fp, "\tMain_Cmd_Data[%d:%d]=8'h%02x;\n", (k + 1) * 8 - 1, k * 8, PROP_PKT_GROUP);
k++;
fprintf(fp, "\tMain_Cmd_Data[%d:%d]=8'h%02x;\n", (k + 1) * 8 - 1, k * 8, 0x02);
k++;
fprintf(fp, "\tMain_Cmd_Data[%d:%d]=8'h%02x;\n", (k + 1) * 8 - 1, k * 8, PROP_PKT_TX_THRESHOLD);
k++;
fprintf(fp, "\tMain_Cmd_Data[%d:%d]=8'h%02x;\n", (k + 1) * 8 - 1, k * 8, TX_THRESHOLD);
k++;
fprintf(fp, "\tMain_Cmd_Data[%d:%d]=8'h%02x;\n", (k + 1) * 8 - 1, k * 8, RX_THRESHOLD);
k++;
fprintf(fp, "\tMain_Cmd=1;\n");
fprintf(fp, "\tMain_start=1;\n");
fprintf(fp, "\tMain_Data_len=%d;\n", k);
fprintf(fp, "\tMain_Return_len=0;\n");
fprintf(fp, "\tMain_Current_State=%d;\n", state);
fprintf(fp, "end\n");

fprintf(fp, "%d:\n", state);
state += 1;
fprintf(fp, "begin\n");
fprintf(fp, "\tMain_start=0;\n");
fprintf(fp, "\tMain_Current_State=%d;\n", state);
fprintf(fp, "end\n");

fprintf(fp, "%d:\n", state);
state += 1;
fprintf(fp, "begin\n");
fprintf(fp, "\tif(spi_op_done)\n");
fprintf(fp, "\tbegin\n");
fprintf(fp, "\t\tMain_Current_State=%d;\n", state);
fprintf(fp, "\tend\n");
fprintf(fp, "end\n");
//	vApi_WaitforCTS();					// Wait for CTS

k = 0;
fprintf(fp,"%d:\n", state);
state += 1;
fprintf(fp, "begin\n");
fprintf(fp, "\tMain_Cmd_Data[%d:%d]=8'h%02x;\n", (k + 1) * 8 - 1, k * 8, CMD_SET_PROPERTY);
k++;
fprintf(fp, "\tMain_Cmd_Data[%d:%d]=8'h%02x;\n", (k + 1) * 8 - 1, k * 8, 0x00);
k++;
fprintf(fp, "\tMain_Cmd_Data[%d:%d]=8'h%02x;\n", (k + 1) * 8 - 1, k * 8, 0x01);
k++;
fprintf(fp, "\tMain_Cmd_Data[%d:%d]=8'h%02x;\n", (k + 1) * 8 - 1, k * 8, 0x03);
k++;
fprintf(fp, "\tMain_Cmd_Data[%d:%d]=8'h%02x;\n", (k + 1) * 8 - 1, k * 8, 0x70);
k++;
fprintf(fp, "\tMain_Cmd=1;\n");
fprintf(fp, "\tMain_start=1;\n");
fprintf(fp, "\tMain_Data_len=%d;\n", k);
fprintf(fp, "\tMain_Return_len=0;\n");
fprintf(fp, "\tMain_Current_State=%d;\n", state);
fprintf(fp, "end\n");

fprintf(fp, "%d:\n", state);
state += 1;
fprintf(fp, "begin\n");
fprintf(fp, "\tMain_start=0;\n");
fprintf(fp, "\tMain_Current_State=%d;\n", state);
fprintf(fp, "end\n");

fprintf(fp, "%d:\n", state);
state += 1;
fprintf(fp, "begin\n");
fprintf(fp, "\tif(spi_op_done)\n");
fprintf(fp, "\tbegin\n");
fprintf(fp, "\t\tMain_Current_State=%d;\n", state);
fprintf(fp, "\tend\n");
fprintf(fp, "end\n");
}

int main()
{
	fp = fopen("data.txt", "w");
	setRFParameters();
	//set_frr_ctl();
	//Function_set_tran_property();
	fclose(fp);
	getchar();
	return 0;
}
