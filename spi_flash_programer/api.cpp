#include <SPI.h>

#include "api.h"

#include <string.h>
void enable_write(void){
  digitalWrite(CS, LOW);
  SPI.transfer(0x06);
  digitalWrite(CS, HIGH);
}

void wait_for_write(void)
{
  byte statreg = 0x1;
  while((statreg & 0x1) == 0x1) {
    // Wait for the chip.
    digitalWrite(CS, LOW);
    SPI.transfer(0x05);
    statreg = SPI.transfer(0x00);
    digitalWrite(CS, HIGH);
  }  
}

void readMD_ID(void){
  char ret[3] = {0,0,0};
  
  digitalWrite(CS, LOW);
  SPI.transfer(0x90);
  SPI.transfer(0x00);
  SPI.transfer(0x00);
  SPI.transfer(0x00);
  ret[0] = SPI.transfer(0x00);
  ret[1] = SPI.transfer(0x00);
  Serial.println("Read Manufacturer / Device ID :");
  for (int i = 0; i < 2; i++) {
    Serial.print(ret[i], HEX);
    Serial.print(" ");
  }
  Serial.println();
  digitalWrite(CS, HIGH);
}

/* Page program (02h) */
void pp(unsigned char addr[3], unsigned char* data, int size) {
  if (size > 256) {
    Serial.println("pp: data size > 256!");
    return;
  }
  if (size == 256 && addr[2] != 0x00){
    Serial.println("pp: data size is 256 and addr is error!");
    return;
  }
  wait_for_write();
  enable_write();
  
  Serial.print("addr: 0x");
  Serial.print(addr[0], HEX);
  Serial.print(" ");
  Serial.print(addr[1], HEX);
  Serial.print(" ");
  Serial.print(addr[2], HEX);
  Serial.println();
  
  digitalWrite(CS, LOW);
  SPI.transfer(0x02);
//  if(addr[0] < 0x10)
//    SPI.transfer(0x
  SPI.transfer(addr[0]);
  SPI.transfer(addr[1]);
  SPI.transfer(addr[2]);
  for (int i = 0; i < size; i++) {
    SPI.transfer(data[i]);
  } 
  digitalWrite(CS, HIGH);
  //wait_for_write();
  //delay(5);
  
}
/* Read data (03h) */
void rd(unsigned char addr[3], unsigned char * buf, unsigned int size) {
  wait_for_write();
  digitalWrite(CS, LOW);
  SPI.transfer(0x03);
  SPI.transfer(addr[0]);
  SPI.transfer(addr[1]);
  SPI.transfer(addr[2]);
  Serial.println("rd len:");
  Serial.println(size);
  for (int i = 0; i < size; i++) {
    buf[i] = SPI.transfer(0x00);
     //Serial.print(SPI.transfer(0x00), HEX);
     //Serial.print(" ");
  }
  //Serial.println();
  digitalWrite(CS, HIGH);
}

void rd2print(unsigned char addr[3], int size) {
  wait_for_write();
  digitalWrite(CS, LOW);
  SPI.transfer(0x03);
  SPI.transfer(addr[0]);
  SPI.transfer(addr[1]);
  SPI.transfer(addr[2]);
  Serial.println("rd: data:");
  for (int i = 0; i < size; i++) {
     Serial.print(SPI.transfer(0x00), HEX);
     Serial.print(" ");
  }
  Serial.println();
  digitalWrite(CS, HIGH);
}

int rd4cmp(unsigned char addr[3], unsigned char * data, int size) {
  wait_for_write();
  digitalWrite(CS, LOW);
  SPI.transfer(0x03);
  SPI.transfer(addr[0]);
  SPI.transfer(addr[1]);
  SPI.transfer(addr[2]);
  for (int i = 0; i < size; i++) {
     if (data[i] != SPI.transfer(0x00)) {
       return -1;
     }
  }
  return 1;
  digitalWrite(CS, HIGH);
}

/* Chip Erase (CE) (C7h) */
void chip_erase(void){
  enable_write();
  wait_for_write();
  digitalWrite(CS, LOW);
  SPI.transfer(0xC7);
  digitalWrite(CS, HIGH);
  Serial.println("CHIP ERASE WAITING!...");
  //sleep(26);
  wait_for_write();
  Serial.println("CHIP ERASE DONE!");
}
