#include <stdio.h>
#include <pthread.h>
#include <unistd.h>
#include <stdio.h>
//#include <iostream>
#include<cstring>
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <errno.h>

#include "i2c-gps.h"
#include "Ublox.h"

#define CMDSIZE	150

#define RFSENDPORT 8000
#define RFRECVPORT 8001
#define WIFISENDPORT 9000
#define WIFIRECVPORT 9001

#define RF_RSSI_LOC		"/home/root/d/si4463/rssi_last_pkt"
#define LOGFILE_BASE	"/home/root/"
#define RF_LOGFILE		"rflog.txt"
#define WIFI_LOGFILE	"wifilog.txt"

char mywifi_ip[30];
char myrf_ip[30];
char remotewifi_ip[30];
char remoterf_ip[30];

unsigned char gps_config_change[80] = {
  /*timepulse*/
//0xB5, 0x62, 0x06, 0x07, 0x14, 0x00, 0xA0, 0x86, 0x01, 0x00, 0x50, 0xC3, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x34, 0x03, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x93, 0x9B,
/* 10Hz, 50% */
//0xB5, 0x62, 0x06, 0x31, 0x20, 0x00, 0x00, 0x01, 0x00, 0x00,
//0x32, 0x00, 0x00, 0x00, 0x0A, 0x00, 0x00, 0x00, 0x03, 0x00,
//0x00, 0x00, 0x00, 0x00, 0x00, 0x80, 0x00, 0x00, 0x00, 0x00,
//0x00, 0x00, 0x00, 0x00, 0xAB, 0x08, 0x00, 0x00, 0xCA, 0xD2,
/* 5Hz, 50% */
0xB5, 0x62, 0x06, 0x31, 0x20,0x00,0x00,0x01,0x00,0x00,
0x00,0x00,0x00,0x00,0x05,0x00,0x00,0x00,0x01,0x00,
0x00,0x00,0x00,0x00,0x00,0x80,0x00,0x00,0x00,0x00,
0x00,0x00,0x00,0x00,0xAB,0x00,0x00,0x00,0x89,0xA2,

	//0xB5, 0x62, 0x06, 0x08, 0x06, 0x00, 0xF4, 0x01, 0x01, 0x00, 0x01, 0x00,
  //0x0B, 0x77, /*500ms*/
  //0xB5, 0x62, 0x06, 0x08, 0x06, 0x00, 0xD0, 0x07, 0x01, 0x00, 0x01, 0x00,
   //0xED, 0xBD, /*2s*/


};

void* send_tester_loop(void * parm) {
	Ublox *m8_Gps_ = (Ublox*)parm;
	struct sockaddr_in wifi_send_addr;
	int sock_wifi;
	struct sockaddr_in rf_send_addr;
	int sock_rf;

	struct sockaddr_in remote_rf_addr;
	struct sockaddr_in remote_wifi_addr;

	int ret,len ;
	char sendbuf[BUFSIZ];

	memset(&rf_send_addr, 0, sizeof(rf_send_addr));
	rf_send_addr.sin_family = AF_INET;
	rf_send_addr.sin_addr.s_addr = inet_addr(myrf_ip); //
	rf_send_addr.sin_port = htons(RFSENDPORT);

	if ((sock_rf = socket(PF_INET, SOCK_DGRAM, 0)) < 0) {
		perror("socket");
		return NULL;
	}

	if (bind(sock_rf, (struct sockaddr *) &rf_send_addr,
			sizeof(struct sockaddr)) < 0) {
		perror("bind");
		return NULL;
	}

	memset(&wifi_send_addr, 0, sizeof(wifi_send_addr));
	wifi_send_addr.sin_family = AF_INET;
	wifi_send_addr.sin_addr.s_addr = inet_addr(mywifi_ip); //
	wifi_send_addr.sin_port = htons(WIFISENDPORT);

	if ((sock_wifi = socket(PF_INET, SOCK_DGRAM, 0)) < 0) {
		perror("socket");
		return NULL;
	}

	if (bind(sock_wifi, (struct sockaddr *) &wifi_send_addr,
			sizeof(struct sockaddr)) < 0) {
		perror("bind");
		return NULL;
	}

	int on=1;
  	if(setsockopt(sock_wifi,SOL_SOCKET,SO_REUSEADDR | SO_BROADCAST,&on,sizeof(on)) <0) {
		printf("socket option  SO_REUSEADDR not support\n");
		return NULL;
	}

	memset(&remote_rf_addr, 0, sizeof(remote_rf_addr));
	remote_rf_addr.sin_family = AF_INET;
	remote_rf_addr.sin_addr.s_addr = inet_addr(remoterf_ip); //
	remote_rf_addr.sin_port = htons(RFRECVPORT);

	memset(&remote_wifi_addr, 0, sizeof(remote_wifi_addr));
	remote_wifi_addr.sin_family = AF_INET;
	remote_wifi_addr.sin_addr.s_addr = inet_addr(remotewifi_ip); //
	remote_wifi_addr.sin_port = htons(WIFIRECVPORT);

	//wait for GPS validation
	while(!m8_Gps_->datetime.valid){
		printf("waiting for GPS validation\n");
		sleep(1);
	}

	long long sn = 1;
	long long wifi_sn = 1;
	long long rf_sn = 1;
	bool rest=0;
	int pos = 0;
  	while(1){
		while(m8_Gps_->datetime.valid){
			pos = 0;
			memcpy(sendbuf+pos, &sn, sizeof(long long));
			pos += sizeof(long long);
			memcpy(sendbuf+pos, &m8_Gps_->datetime.hours, 1);
			pos += 1;
			memcpy(sendbuf+pos, &m8_Gps_->datetime.minutes, 1);
			pos += 1;
			memcpy(sendbuf+pos, &m8_Gps_->datetime.seconds, 1);
			pos += 1;
			memcpy(sendbuf+pos, &m8_Gps_->datetime.millis, 2);
			pos += 2;
			memcpy(sendbuf+pos, &m8_Gps_->longitude, sizeof(float));
			pos += sizeof(float);
			memcpy(sendbuf+pos, &m8_Gps_->latitude, sizeof(float));
			pos += sizeof(float);
			memcpy(sendbuf+pos, &m8_Gps_->speed, 2);
			pos += 2;

			/**
			 * 802.11p sending
			 */
			memcpy(sendbuf, &wifi_sn, sizeof(long long));
			wifi_sn++;
			if ((len = sendto(sock_wifi, sendbuf, pos, 0,
					(struct sockaddr *) &remote_wifi_addr, sizeof(struct sockaddr))) < 0) {
				perror("sendto");
				return NULL;
			}
			/**
			 * sub1G sending
			 */
			memcpy(sendbuf, &rf_sn, sizeof(long long));
			rf_sn++;
			if(!rest) {
				if ((len = sendto(sock_rf, sendbuf, pos, 0,
						(struct sockaddr *) &remote_rf_addr, sizeof(struct sockaddr))) < 0) {
					perror("sendto");
					return NULL;
				}
				rest = 1;
			} else {
				rest = 0;
			}

			sn++;
			usleep(1000 * 100);
		}
		pthread_testcancel();
  	}

	return NULL;

}

#define PI                      3.1415926
#define EARTH_RADIUS            6378.137        //地球近似半径
// 求弧度
float radian(float d)
{
    return d * PI / 180.0;   //角度1˚ = π / 180
}
//计算距离
float get_distance(float lat1, float lng1, float lat2, float lng2)
{
	float radLat1 = radian(lat1);
	float radLat2 = radian(lat2);
	float a = radLat1 - radLat2;
	float b = radian(lng1) - radian(lng2);

	float dst = 2 * asin((sqrt(pow(sin(a / 2), 2) + cos(radLat1) * cos(radLat2) * pow(sin(b / 2), 2) )));

    dst = dst * EARTH_RADIUS;
    dst= round(dst * 10000) / 10000;
    return dst;
}

struct dist{
	float rf_longitude, rf_latitude;
	bool rf_valid;
	float wifi_longitude, wifi_latitude;
	bool wifi_valid;
	Ublox *m8_Gps;
	pthread_mutex_t lock;
};
void* print_distance_loop(void *parm) {
	struct dist * dist_ = (struct dist *)parm;
	while(1){
		pthread_testcancel();

		system("clear");
		if(dist_->rf_valid){

			printf("RF-sub1G distance: %f\n",
					get_distance(dist_->rf_latitude, dist_->rf_longitude,
							dist_->m8_Gps->latitude, dist_->m8_Gps->longitude));
		}else{
			printf("RF-sub1G distance: ----\n");
		}
		if(dist_->wifi_valid){

			printf("802.11p distance: %f\n",
					get_distance(dist_->wifi_latitude, dist_->wifi_longitude,
							dist_->m8_Gps->latitude, dist_->m8_Gps->longitude));
		}else{
			printf("802.11p distance: ----\n");
		}
		pthread_mutex_lock(&dist_->lock);
		dist_->rf_valid=0;
		dist_->wifi_valid=0;
		pthread_mutex_unlock(&dist_->lock);


		sleep(1);
	}

}


void* recv_tester_loop(void * parm) {
	Ublox *m8_Gps_ = (Ublox*)parm;

	pthread_t disttid;
	struct dist* dist_;
	dist_ = (struct dist*)malloc(sizeof(struct dist));
	pthread_mutex_init(&dist_->lock, NULL);
	dist_->m8_Gps = m8_Gps_;
	dist_->rf_valid=0;
	dist_->wifi_valid=0;
	pthread_create(&disttid, NULL, print_distance_loop, (void*)dist_);

	//wait for GPS validation
	while(!m8_Gps_->datetime.valid){
		printf("waiting for GPS validation\n");
		usleep(500 * 1000);
	}

	/**
	 * open log files
	 */
	FILE* fp_wifi, * fp_rf;
	char logfile_name[200];
	char tmp[100];
	memset(logfile_name,0,200);
	memset(tmp,0,100);
	strcat(logfile_name, LOGFILE_BASE);
	sprintf(tmp, "%d%d%d-%d-%d-", m8_Gps_->datetime.year,
			m8_Gps_->datetime.month, m8_Gps_->datetime.day,
			m8_Gps_->datetime.hours, m8_Gps_->datetime.minutes);
	strcat(logfile_name, tmp);

	sprintf(tmp, WIFI_LOGFILE);
	strcat(logfile_name, tmp);

	printf("LOG FILE: %s\n", logfile_name);
	fp_wifi = fopen(logfile_name, "a+");
	if(fp_wifi==NULL){
		perror("*******LOG FILE OPEN ERROR********\n");
		exit(0);
	}
	//RF
	memset(logfile_name,0,200);
	memset(tmp,0,100);
	strcat(logfile_name, LOGFILE_BASE);
	sprintf(tmp, "%d%d%d-%d-%d-", m8_Gps_->datetime.year,
			m8_Gps_->datetime.month, m8_Gps_->datetime.day,
			m8_Gps_->datetime.hours, m8_Gps_->datetime.minutes);
	strcat(logfile_name, tmp);

	sprintf(tmp, RF_LOGFILE);
	strcat(logfile_name, tmp);

	printf("LOG FILE: %s\n", logfile_name);
	fp_rf = fopen(logfile_name, "a+");
	if(fp_rf==NULL){
		perror("*******LOG FILE OPEN ERROR********\n");
		exit(0);
	}
	/**
	 * RSSI file of rfsub1G
	 */
	FILE* fp_rf_rssi;
	fp_rf_rssi = fopen(RF_RSSI_LOC, "r");
	if(fp_rf_rssi==NULL){
		perror("*******RSSI FILE OPEN ERROR********\n");
		exit(0);
	}

	/**
	 * SOCKETS
	 */
	struct sockaddr_in rf_recv_addr;
	struct sockaddr_in wifi_recv_addr;
	int sock_rf;
	int sock_wifi;


	memset(&rf_recv_addr, 0, sizeof(rf_recv_addr));
	rf_recv_addr.sin_family = AF_INET;
	rf_recv_addr.sin_addr.s_addr = inet_addr(myrf_ip); //htonl(INADDR_ANY); //
	rf_recv_addr.sin_port = htons(RFRECVPORT);

	memset(&wifi_recv_addr, 0, sizeof(wifi_recv_addr));
	wifi_recv_addr.sin_family = AF_INET;
	wifi_recv_addr.sin_addr.s_addr = inet_addr(mywifi_ip);//htonl(INADDR_ANY);// //
	wifi_recv_addr.sin_port = htons(WIFIRECVPORT);

	if ((sock_rf = socket(PF_INET, SOCK_DGRAM, 0)) < 0) {
		perror("socket");
		return NULL;
	}

	if (bind(sock_rf, (struct sockaddr *) &rf_recv_addr,
			sizeof(struct sockaddr)) < 0) {
		perror("bind");
		return NULL;
	}

	if ((sock_wifi = socket(PF_INET, SOCK_DGRAM, 0)) < 0) {
		perror("socket");
		return NULL;
	}

	if (bind(sock_wifi, (struct sockaddr *) &wifi_recv_addr,
			sizeof(struct sockaddr)) < 0) {
		perror("bind");
		return NULL;
	}

	int on=1;
  	if(setsockopt(sock_wifi,SOL_SOCKET,SO_REUSEADDR | SO_BROADCAST,&on,sizeof(on)) <0) {
		printf("socket option  SO_REUSEADDR not support\n");
		return NULL;
	}

	uint8_t hours, minutes, seconds;
	uint16_t mills;
	float longitude, latitude;
	uint16_t speed;
	long long sn;


	/**
	 * select LOOP
	 */
	char recvbuf[BUFSIZ];
	int pos;
	int len;
	int rf_rssi;
	fd_set rfds;
	struct timeval time_out;
	time_out.tv_sec=1;
	time_out.tv_usec=0;
	int maxfd = sock_rf > sock_wifi ? sock_rf:sock_wifi;
	int ret;
	while(1)
	{
		FD_ZERO(&rfds);
		FD_SET(sock_rf, &rfds);
		FD_SET(sock_wifi, &rfds);
		ret = select(maxfd+1, &rfds, NULL, NULL, &time_out);
		if(ret < 0){
			perror("*********select return SOCKET_ERROR**********\n");
			exit(0);
		} else if(ret == 0){
			pthread_testcancel();
		} else {
			if (FD_ISSET(sock_rf, &rfds)){
				len = recvfrom(sock_rf, recvbuf, sizeof(recvbuf), 0, NULL,NULL);
				if(len > 0){
					pos = 0;
					memcpy(&sn, recvbuf+pos, sizeof(long long));
					pos += sizeof(long long);
					memcpy(&hours, recvbuf+pos, 1);
					pos += 1;
					memcpy(&minutes, recvbuf+pos, 1);
					pos += 1;
					memcpy(&seconds, recvbuf+pos, 1);
					pos += 1;
					memcpy(&mills, recvbuf+pos, 2);
					pos += 2;
					memcpy(&longitude, recvbuf+pos, sizeof(float));
					pos += sizeof(float);
					memcpy(&latitude, recvbuf+pos, sizeof(float));
					pos += sizeof(float);
					memcpy(&speed, recvbuf+pos, 2);
					pos += 2;
					if(pos != len) {
						perror("sock_rf: pos != len\n");
						exit(0);
					}
				}

				fseek(fp_rf_rssi, 0, SEEK_SET);
				fscanf(fp_rf_rssi, "%d", &rf_rssi);

				fprintf(fp_rf, "SN@%lld ", sn);
				fprintf(fp_rf, "TIME@%d:%d:%d %u ", hours, minutes, seconds, mills);
				fprintf(fp_rf, "%f,%f ", longitude, latitude);
				fprintf(fp_rf, "SPEED@%d ", speed);
				fprintf(fp_rf, "RSSI@%d\n", rf_rssi);
				fflush(fp_rf);

				pthread_mutex_lock(&dist_->lock);
				dist_->rf_latitude=latitude;
				dist_->rf_longitude=longitude;
				dist_->rf_valid=1;
				pthread_mutex_unlock(&dist_->lock);
			}
			if (FD_ISSET(sock_wifi, &rfds)){
				len = recvfrom(sock_wifi, recvbuf, sizeof(recvbuf), 0, NULL,NULL);
				if(len > 0){
					pos = 0;
					memcpy(&sn, recvbuf+pos, sizeof(long long));
					pos += sizeof(long long);
					memcpy(&hours, recvbuf+pos, 1);
					pos += 1;
					memcpy(&minutes, recvbuf+pos, 1);
					pos += 1;
					memcpy(&seconds, recvbuf+pos, 1);
					pos += 1;
					memcpy(&mills, recvbuf+pos, 2);
					pos += 2;
					memcpy(&longitude, recvbuf+pos, sizeof(float));
					pos += sizeof(float);
					memcpy(&latitude, recvbuf+pos, sizeof(float));
					pos += sizeof(float);
					memcpy(&speed, recvbuf+pos, 2);
					pos += 2;

					if(pos != len) {
						perror("sock_wifi: pos != len\n");
						exit(0);
					}
				}
				fprintf(fp_wifi, "SN@%lld ", sn);
				fprintf(fp_wifi, "TIME@%d:%d:%d %u ", hours, minutes, seconds, mills);
				fprintf(fp_wifi, "%f,%f ", longitude, latitude);
				fprintf(fp_wifi, "SPEED@%u\n", speed);
				fflush(fp_wifi);

				pthread_mutex_lock(&dist_->lock);
				dist_->wifi_latitude=latitude;
				dist_->wifi_longitude=longitude;
				dist_->wifi_valid=1;
				pthread_mutex_unlock(&dist_->lock);
			}
		}
	}

}


void* gpsdata_decode_loop(void * parm) {
	Ublox *M8_Gps_ = (Ublox*)parm;
	i2cgps gps;

	printf("%d\n",gps.write_gps_config(gps_config_change, 40));

	int totalBytes, bytes;
	while(1) {
		totalBytes = gps.get_byte_available();
		while (totalBytes > 0) {
		    bytes = gps.get_gps_data2buf(totalBytes);
		    if(bytes < 0){
		    	printf("gpsdata_decode_loop: bytes<0!\n");
		    	exit(0);
		    }
		    for (int i = 0; i < bytes; i++) {
		      if((gps.gpsdata_buf())[i]!=0xff)
		        M8_Gps_->encode((char)(gps.gpsdata_buf())[i]);
		    }
		    totalBytes -= bytes;
		}
		pthread_testcancel();
	}
}

int main(){

	int byte2read;
	pthread_t gpstid;
	pthread_t sendlooptid;
	void * tret;
	Ublox * m8_Gps = NULL;
	int gpsloopflag = 0;
	int sendloopflag = 0;
	int recvloopflag = 0;
	int err, ret;
	char cmd;
	int tmpnum;
	char *tmpbuf;
	tmpbuf = (char*)malloc(CMDSIZE);

	do {
		printf("Input CMD (h for help):\n");
		scanf("%c", &cmd);
		getchar();
		switch(cmd){
		case 'h':
			printf("i: Init interfaces.\n");
			//printf("g: Start gps decoding loop.\n");
			printf("s: Start packet sending loop.\n");
			printf("r: Start Receiving loop.\n");
			printf("t: Terminate loops.\n");
			printf("p: ping test.\n");
			break;
		case 'i':

			printf("Input device number (1,2):\n");
			scanf("%d", &tmpnum);
			getchar();
			snprintf(myrf_ip, sizeof(myrf_ip), "192.168.3.%d", tmpnum);
			snprintf(mywifi_ip, sizeof(mywifi_ip), "192.168.4.%d", tmpnum);
			snprintf(remoterf_ip, sizeof(remoterf_ip), "192.168.3.%d", tmpnum==1?2:1);
			snprintf(remotewifi_ip, sizeof(remotewifi_ip), "192.168.4.%d", tmpnum==1?2:1);

			system("ip link set wlp1s0 down");
			system("./iw-802.11p dev wlp1s0 set type ocb");
			system("ip link set wlp1s0 up");
			system("./iw-802.11p dev wlp1s0 ocb join 5805 10MHZ");
			strcpy(tmpbuf , "ifconfig wlp1s0 ");
			strcat(tmpbuf, mywifi_ip);
			printf("%s\n", tmpbuf);
			system(tmpbuf);

			system("rmmod spidev");
//			snprintf(tmpbuf, CMDSIZE, "insmod /home/root/si4463_tdma.ko global_slots_perframe=2 global_slot_size_ms=195 global_device_num=2 global_device_id=%d", tmpnum);
			printf("%s\n", tmpbuf);
			//sleep(1);
//			system(tmpbuf);
			system("insmod /home/root/si4463_fpga.ko");
			system("iptables -I OUTPUT -d 8.8.0.0/16 -j DROP");
			system("iptables -A OUTPUT -p udp --dport 1534 -j DROP");
			system("mount -t debugfs none /home/root/d");
			system("echo 400 > /home/root/d/si4463/speed_kbps");
			//sleep(1);
			strcpy(tmpbuf , "ifconfig sif0 ");
			strcat(tmpbuf, myrf_ip);
			printf("%s\n", tmpbuf);
			system(tmpbuf);

			/**
			 * open GPS deamon
			 */
			if(gpsloopflag)
				break;
			m8_Gps = new Ublox();
			ret = pthread_create(&gpstid, NULL, gpsdata_decode_loop, (void*)m8_Gps);
			gpsloopflag = 1;

			break;

		case 's':
			if(sendloopflag)
				break;
			ret = pthread_create(&sendlooptid, NULL, send_tester_loop, (void*)m8_Gps);

			sendloopflag = 1;
			break;
		case 'r':
//			printf("Input my rf IP:\n ");
//			scanf("%s", myrf_ip);
//			getchar();
//			printf("Input remote rf IP:\n ");
//			scanf("%s", remoterf_ip);
//			getchar();
//			printf("Input my wifi IP:\n ");
//			scanf("%s", mywifi_ip);
//			getchar();
//			printf("Input remote wifi IP:\n ");
//			scanf("%s", remotewifi_ip);
//			getchar();
			printf("%s\n", myrf_ip);
			printf("%s\n", remoterf_ip);
			printf("%s\n", mywifi_ip);
			printf("%s\n", remotewifi_ip);
			recv_tester_loop((void*)m8_Gps);

			break;
		case 't':
			pthread_cancel(gpstid);
			pthread_cancel(sendlooptid);
			err=pthread_join(gpstid,&tret);
			if(err!=0)
					printf("can't join thread : %s\n",strerror(err));
			printf("GPS thread exit code %d\n",(int)tret);
			gpsloopflag = 0;
			err=pthread_join(sendlooptid,&tret);
			if(err!=0)
					printf("can't join thread : %s\n",strerror(err));
			printf("sendlooptid thread exit code %d\n",(int)tret);
			sendloopflag = 0;
			break;
		case 'p':
			strcpy(tmpbuf , "ping -c 5 ");
			strcat(tmpbuf, remotewifi_ip);
			system(tmpbuf);
			strcpy(tmpbuf , "ping -c 5 ");
			strcat(tmpbuf, remoterf_ip);
			system(tmpbuf);
			break;
		default:
			printf("Staus:\n");
			printf("gpsloopflag:%d\n", gpsloopflag);
			printf("sendloopflag:%d\n", sendloopflag);
			break;
		}
	} while (1);

	return 0;
}
