#include <SPI.h>
#include "api.h"
#include <stdio.h>

void setup() {
  // put your setup code here, to run once:
Serial.begin(9600);

  // initialize SPI:
  SPI.begin();
  SPI.setDataMode(SPI_MODE0);
  SPI.setBitOrder(MSBFIRST);
  SPI.setClockDivider(SPI_CLOCK_DIV2); // 8 MHz / 8 = 1 MHz
  delay(600);

  Serial.println("SPI is initialized");
  
//pinMode(5, INPUT);
//digitalWrite(5, HIGH);
  pinMode(CS, OUTPUT);
  digitalWrite(CS, HIGH);
  //pinMode(PROG_B, OUTPUT);
  //digitalWrite(PROG_B, HIGH); //disable fpga
  pinMode(MUX, OUTPUT);
  digitalWrite(MUX, HIGH);
  sleep(1);
  Serial.println("BEGIN");
  //exit(0);
  
}

void loop() {
/*
  while(1){
    digitalWrite(CS, LOW);
    SPI.transfer(0xaa);
    //delay(1);
    digitalWrite(CS, HIGH);
    delay(0.5);
  }
*/
  
  readMD_ID();
  chip_erase();

  FILE *fp;
  int count=0, sum=0;
  unsigned char file_buffer[256];
  unsigned char addr[3] = { 0x00, 0x00, 0x00}; //高位==>低位 0x123456

  if((fp=fopen("/home/root/total_link.bin","r"))==NULL){
    Serial.println("File dosn't exist!");
    exit(0);
  }
  /********************************FOR DEBUG *****************************/
//  unsigned char addrx[3] = { 0x00, 0x00, 0x00};
//  unsigned char tester_buf[400000];
//  rd2print(addrx, 256);
//  
//  FILE * fpt = fopen("/home/root/readfromspiflash.bin", "w");
//  //rd(addrx, tester_buf, 340604);
//  //fwrite(tester_buf, 1, 340604, fpt);
//  fclose(fpt);
//  
//  exit(0);
  /***********************************************************************/
  

  while ((count = fread(file_buffer,1,256,fp)) > 0) {
    sum+=count;
    for (int i=0; i<256; i++){
      Serial.print(file_buffer[i], HEX);
    }
    Serial.println();
    pp(addr, file_buffer, count);
    if (0 > rd4cmp(addr, file_buffer, count)){
      Serial.println("rd cmp ERROR!");
      exit(0);
    }
    if (count == 256){
     if(addr[1] < 0xff)
       addr[1] += 1;
     else {
       addr[1] = 0;
       addr[0] += 1;
     }
    } else {
      if(addr[2] < (0xff - count))
         addr[2] += count;
      else {
         addr[2] = count - (0xff - count);
         if(addr[1] < 0xff)
           addr[1] += 1;
         else {
           addr[1] = 0;
           addr[0] += 1;
         }
       }
    }
    /*
    Serial.print("addr: 0x");
    Serial.print(addr[0], HEX);
    Serial.print(" ");
    Serial.print(addr[1], HEX);
    Serial.print(" ");
    Serial.print(addr[2], HEX);
    Serial.println();
    */
  }
  Serial.print("SUM: ");
  Serial.println(sum);
  
  //pp(addr, data, 4);
  //rd(addr, 4);
  digitalWrite(MUX, LOW);
  //digitalWrite(PROG_B, HIGH);
  exit(0);
  // put your main code here, to run repeatedly:
/* if(digitalRead(5)==1) {
   Serial.print(++i);
   Serial.println("1"); 
 }
*/
}
