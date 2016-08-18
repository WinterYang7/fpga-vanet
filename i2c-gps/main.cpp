#include <stdio.h>
#include <pthread.h>
#include <unistd.h>
//#include <iostream>
#include<cstring>
#include <sys/types.h>
#include <sys/socket.h>
#include <net/if.h>
#include <sys/ioctl.h>
#include <sys/time.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <errno.h>

#include "i2c-gps.h"
#include "serial-gps.h"
#include "Ublox.h"

#define CMDSIZE	150

#define RFSENDPORT 8000
#define RFRECVPORT 8001
#define WIFISENDPORT 9000
#define WIFIRECVPORT 9001

#define RF_RSSI_LOC		"/home/root/d/si4463/rssi_last_pkt"
#define WIFI_RSSI_LOC_BASE	"/home/root/d/ieee80211/phy0/netdev:wlp1s0/stations/"
#define WIFI_RSSI_LOC_TAIL	"/last_signal"
#define LOGFILE_BASE	"/media/realroot/"
#define RF_LOGFILE		"rflog.txt"
#define WIFI_LOGFILE	"wifilog.txt"
#define SEND_LOGFILE	"sendlog.txt"

char send_logfile_str[200];

char mywifi_ip[30];
char myrf_ip[30];
char remotewifi_ip[30];
char remoterf_ip[30];

int pwr_lvl = 127;
int speed = 400;
/**
 * The platform model serials in the M8 document are 0-Portable 2-Stationary 3-Pedestrian 4-Automotive ..
 * default is 2-stationary.
 *
 * I adjust this serials by mobility.
 * 		0-Stationary
 * 		1-Pedestrian
 * 		2-Automotive
 * 		3-Portable
 */
#define MAX_PLATFORM_MODEL_SN	3
int gps_platform_model_sn = 0;//

bool changeSpeedFlag = 0;
bool changePwrFlag = 0;
bool changeGpsplatformFlag = 0;

unsigned char gps_config_change[] = {

		/* CFG_GNSS: GPS & GLONASS with SBAS */
		0xB5, 0x62, 0x06, 0x3E, 0x34, 0x00, 0x00, 0x00, 0x20,
		0x06, 0x00, 0x08, 0x10, 0x00, 0x01, 0x00, 0x01, 0x01,
		0x01, 0x01, 0x03, 0x00, 0x01, 0x00, 0x01, 0x01, 0x03,
		0x08, 0x10, 0x00, 0x00, 0x00, 0x01, 0x01, 0x04, 0x00,
		0x08, 0x00, 0x00, 0x00, 0x01, 0x01, 0x05, 0x00, 0x03,
		0x00, 0x00, 0x00, 0x01, 0x01, 0x06, 0x08, 0x0E, 0x00,
		0x01, 0x00, 0x01, 0x01, 0x15, 0xED,

		/* CFG_SBAS: MSAS */
		0xB5, 0x62, 0x06, 0x16, 0x08, 0x00, 0x01, 0x03, 0x03,
		0x00, 0x00, 0x02, 0x02, 0x00, 0x2F, 0xC3,

		/*timepulse*/
		/* 5Hz, 50% */
		0xB5, 0x62, 0x06, 0x31, 0x20,0x00,0x00,0x01,0x00,0x00,
		0x00,0x00,0x00,0x00,0x05,0x00,0x00,0x00,0x01,0x00,
		0x00,0x00,0x00,0x00,0x00,0x80,0x00,0x00,0x00,0x00,
		0x00,0x00,0x00,0x00,0xAB,0x00,0x00,0x00,0x89,0xA2

};

#define SIZE_PER_PLATFORM 44
unsigned char gps_platform_model_data[] = {
		/* CFG_NAV5: Platform model: 2-Stationary */
		0xB5, 0x62, 0x06, 0x24, 0x24, 0x00, 0xFF, 0xFF, 0x02,
		0x03, 0x00, 0x00, 0x00, 0x00, 0x10, 0x27, 0x00, 0x00,
		0x05, 0x00, 0xFA, 0x00, 0xFA, 0x00, 0x64, 0x00, 0x5E,
		0x01, 0x00, 0x3C, 0x00, 0x00, 0x00, 0x00, 0xC8, 0x00,
		0x03, 0x00, 0x00, 0x00, 0x00, 0x00, 0x4B, 0xD2,

		/* CFG_NAV5: Platform model: 3-Pedestrian */
		0xB5, 0x62, 0x06, 0x24, 0x24, 0x00, 0xFF, 0xFF, 0x03,
		0x03, 0x00, 0x00, 0x00, 0x00, 0x10, 0x27, 0x00, 0x00,
		0x05, 0x00, 0xFA, 0x00, 0xFA, 0x00, 0x64, 0x00, 0x5E,
		0x01, 0x00, 0x3C, 0x00, 0x00, 0x00, 0x00, 0xC8, 0x00,
		0x03, 0x00, 0x00, 0x00, 0x00, 0x00, 0x4C, 0xF4,

		/* CFG_NAV5: Platform model: 4-Automotive */
		0xB5, 0x62, 0x06, 0x24, 0x24, 0x00, 0xFF, 0xFF, 0x04,
		0x03, 0x00, 0x00, 0x00, 0x00, 0x10, 0x27, 0x00, 0x00,
		0x05, 0x00, 0xFA, 0x00, 0xFA, 0x00, 0x64, 0x00, 0x5E,
		0x01, 0x00, 0x3C, 0x00, 0x00, 0x00, 0x00, 0xC8, 0x00,
		0x03, 0x00, 0x00, 0x00, 0x00, 0x00, 0x4D, 0x16,

		/* CFG_NAV5: Platform model: 0-Portable */
		0xB5, 0x62, 0x06, 0x24, 0x24, 0x00, 0xFF, 0xFF, 0x00,
		0x03, 0x00, 0x00, 0x00, 0x00, 0x10, 0x27, 0x00, 0x00,
		0x05, 0x00, 0xFA, 0x00, 0xFA, 0x00, 0x64, 0x00, 0x5E,
		0x01, 0x00, 0x3C, 0x00, 0x00, 0x00, 0x00, 0xC8, 0x00,
		0x03, 0x00, 0x00, 0x00, 0x00, 0x00, 0x49, 0x8E,

};

void* send_tester_loop(void * parm) {
	Ublox *m8_Gps_ = (Ublox*)parm;
	struct sockaddr_in wifi_send_addr;
	int sock_wifi;
	struct ifreq ifr;
	struct sockaddr_in rf_send_addr;
	int sock_rf;

	struct sockaddr_in remote_rf_addr;
	struct sockaddr_in remote_wifi_addr;

	int ret,len ;
	char sendbuf[BUFSIZ];

	/**
	 * Send log file
	 */
#ifndef DEBUG
	//wait for GPS validation
	while(!m8_Gps_->datetime.valid){
		printf("send_tester_loop: waiting for GPS validation\n");
		usleep(500 * 1000);
	}
#endif
	FILE* fp_send;
	char tmp[100];
	char logfile_name[200];
	strcpy(logfile_name, LOGFILE_BASE);

	sprintf(tmp, "%d%d%d-%d-%d-", m8_Gps_->datetime.year,
			m8_Gps_->datetime.month, m8_Gps_->datetime.day,
			m8_Gps_->datetime.hours, m8_Gps_->datetime.minutes);
	strcat(logfile_name, tmp);
	sprintf(tmp, SEND_LOGFILE);
	strcat(logfile_name, tmp);
	strcpy(send_logfile_str, logfile_name);
	fp_send = fopen(logfile_name, "a+");
	if(fp_send==NULL){
		perror("*******LOG FILE OPEN ERROR********\n");
		exit(0);
	}
	fprintf(fp_send, "/* Sub1G: Speed = %d, pwr_lvl = %d */\n", speed, pwr_lvl);

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

	strcpy(ifr.ifr_name, "wlp1s0");
	ioctl(sock_wifi, SIOCGIFHWADDR, &ifr);
	char wifi_mac[32];
	sprintf(wifi_mac, "%02x:%02x:%02x:%02x:%02x:%02x",
	            (unsigned   char)ifr.ifr_hwaddr.sa_data[0],
	            (unsigned   char)ifr.ifr_hwaddr.sa_data[1],
	            (unsigned   char)ifr.ifr_hwaddr.sa_data[2],
	            (unsigned   char)ifr.ifr_hwaddr.sa_data[3],
	            (unsigned   char)ifr.ifr_hwaddr.sa_data[4],
	            (unsigned   char)ifr.ifr_hwaddr.sa_data[5]);

	printf("wifi MAC: %s, size: %d\n",wifi_mac, strlen(wifi_mac));

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

#ifndef DEBUG
	//wait for GPS validation
	while(!m8_Gps_->datetime.valid){
		printf("waiting for GPS validation\n");
		sleep(1);
	}
#endif

	long long sn = 1;
	long long wifi_sn = 1;
	long long rf_sn = 1;
	bool rest=0;
	int pos = 0;
	uint8_t hours, minutes, seconds;
	uint16_t millis;
	float latitude, longitude;
	uint16_t speed;
	struct  timeval localtime;

  	while(1){
#ifndef DEBUG
		if(m8_Gps_->fixtype > 0) {
#endif
			hours = m8_Gps_->datetime.hours;
			minutes = m8_Gps_->datetime.minutes;
			seconds = m8_Gps_->datetime.seconds;
			millis = m8_Gps_->datetime.millis;
			longitude = m8_Gps_->longitude;
			latitude = m8_Gps_->latitude;
			speed = m8_Gps_->speed;
			pos = 0;
			memcpy(sendbuf+pos, &sn, sizeof(long long));
			pos += sizeof(long long);
			memcpy(sendbuf+pos, &hours, 1);
			pos += 1;
			memcpy(sendbuf+pos, &minutes, 1);
			pos += 1;
			memcpy(sendbuf+pos, &seconds, 1);
			pos += 1;
			memcpy(sendbuf+pos, &millis, 2);
			pos += 2;
			memcpy(sendbuf+pos, &longitude, sizeof(float));
			pos += sizeof(float);
			memcpy(sendbuf+pos, &latitude, sizeof(float));
			pos += sizeof(float);
			memcpy(sendbuf+pos, &speed, 2);
			pos += 2;

			/**
			 * sub1G sending
			 */
//			if(!rest) {
				memcpy(sendbuf, &rf_sn, sizeof(long long));
				rf_sn++;
				if ((len = sendto(sock_rf, sendbuf, pos, 0,
						(struct sockaddr *) &remote_rf_addr, sizeof(struct sockaddr))) < 0) {
					perror("sendto");
					return NULL;
				}
//				rest = 1;
//			} else {
//				rest = 0;
//			}

			/**
			 * 802.11p sending
			 */
			memcpy(sendbuf, &wifi_sn, sizeof(long long));
			wifi_sn++;
			memcpy(sendbuf+pos, wifi_mac, strlen(wifi_mac));
			pos += strlen(wifi_mac);

			if ((len = sendto(sock_wifi, sendbuf, pos, 0,
					(struct sockaddr *) &remote_wifi_addr, sizeof(struct sockaddr))) < 0) {
				perror("sendto");
				return NULL;
			}
			sn++;

			gettimeofday(&localtime, NULL);
			fprintf(fp_send, "SN@%lld ", sn);
			fprintf(fp_send, "TIME@%d:%d:%d %u ", hours, minutes, seconds, millis);
			fprintf(fp_send, "LTIME@%ld ", localtime.tv_sec);
			fprintf(fp_send, "GPSCURR@%f,%f ", longitude, latitude);
			fprintf(fp_send, "SPEED@%u\n", speed);
			fflush(fp_send);

			usleep(1000 * 100);
#ifndef DEBUG
		} else {
			printf("Sendloop: GPS invalid!\n");
		}
#endif
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
	int rssi_rf_lastpkt;
	int rssi_wifi_lastpkt;
	float pkt_loss_rate_rf_last20;
	float pkt_loss_rate_wifi_last20;

	char rflogStr[200];
	char wifilogStr[200];
	pthread_mutex_t lock;
};
void* print_distance_loop(void *parm) {
	struct dist * dist_ = (struct dist *)parm;
	while(1){
		pthread_testcancel();

		system("clear");
		printf("RF-sub1G LogFile: %s\n", dist_->rflogStr);
		printf("802.11p  LogFile: %s\n", dist_->wifilogStr);
		printf("Send LogFile: %s\n", send_logfile_str);
		if(dist_->rf_valid){

			printf("RF-sub1G distance: %f, rssi: %d, pkt_loss_rate_last20: %f\n",
					get_distance(dist_->rf_latitude, dist_->rf_longitude,
							dist_->m8_Gps->latitude, dist_->m8_Gps->longitude),
					dist_->rssi_rf_lastpkt,
					dist_->pkt_loss_rate_rf_last20);
		}else{
			printf("RF-sub1G distance: ---- pkt_loss_rate_last20: %f\n", dist_->pkt_loss_rate_rf_last20);
		}
		if(dist_->wifi_valid){

			printf("802.11p distance: %f, SNR: %d, pkt_loss_rate_last20: %f\n",
					get_distance(dist_->wifi_latitude, dist_->wifi_longitude,
							dist_->m8_Gps->latitude, dist_->m8_Gps->longitude),
					dist_->rssi_wifi_lastpkt,
					dist_->pkt_loss_rate_wifi_last20);
		}else{
			printf("802.11p distance: ---- pkt_loss_rate_last20: %f\n", dist_->pkt_loss_rate_wifi_last20);
		}
		pthread_mutex_lock(&dist_->lock);
		dist_->rf_valid=0;
		dist_->wifi_valid=0;
		pthread_mutex_unlock(&dist_->lock);


		//sleep(1);
		usleep(600 * 1000);
	}

}

float cal_pktlossrate_lastn(long long * pktsn_set, int n){
	int i;
	long long start = pktsn_set[0];
	float pkt_loss = 0;

	for(i=0; i<n && pktsn_set[i] > 0; i++, start++){
		if(pktsn_set[i] > start){
			pkt_loss += pktsn_set[i] - start;

			start = pktsn_set[i];
		}
	}

	if(pkt_loss > n)
		return 1;
	else
		return (pkt_loss/n);
}

void* recv_tester_loop(void * parm) {
	Ublox *m8_Gps_ = (Ublox*)parm;

	pthread_t disttid;
	struct dist* dist_;
	dist_ = (struct dist*)malloc(sizeof(struct dist));

#ifndef DEBUG
	//wait for GPS validation
	while(!m8_Gps_->datetime.valid){
		printf("recv_tester_loop: waiting for GPS validation\n");
		usleep(500 * 1000);
	}
#endif

	/**
	 * open log files
	 */
	FILE* fp_wifi, * fp_rf;
	char logfile_name[200];
	char tmp[100];
	memset(logfile_name,0,200);
	memset(tmp,0,100);
	strcpy(logfile_name, LOGFILE_BASE);
#ifndef DEBUG
	//wait for GPS validation 2
	while(!m8_Gps_->datetime.valid){
		printf("recv_tester_loop: waiting for GPS validation\n");
		usleep(500 * 1000);
	}
#endif
	sprintf(tmp, "%d%d%d-%d-%d-", m8_Gps_->datetime.year,
			m8_Gps_->datetime.month, m8_Gps_->datetime.day,
			m8_Gps_->datetime.hours, m8_Gps_->datetime.minutes);
	strcat(logfile_name, tmp);

	sprintf(tmp, WIFI_LOGFILE);
	strcat(logfile_name, tmp);

	strcpy(dist_->wifilogStr, logfile_name);
	printf("LOG FILE: %s\n", logfile_name);
	fp_wifi = fopen(logfile_name, "a+");
	if(fp_wifi==NULL){
		perror("*******LOG FILE OPEN ERROR********\n");
		exit(0);
	}
	fprintf(fp_wifi, "/* Sub1G: Speed = %d, pwr_lvl = %d */\n", speed, pwr_lvl);
	//RF
	memset(logfile_name,0,200);
	memset(tmp,0,100);
	strcpy(logfile_name, LOGFILE_BASE);
#ifndef DEBUG
	//wait for GPS validation 2
	while(!m8_Gps_->datetime.valid){
		printf("recv_tester_loop: waiting for GPS validation\n");
		usleep(500 * 1000);
	}
#endif
	sprintf(tmp, "%d%d%d-%d-%d-", m8_Gps_->datetime.year,
			m8_Gps_->datetime.month, m8_Gps_->datetime.day,
			m8_Gps_->datetime.hours, m8_Gps_->datetime.minutes);
	strcat(logfile_name, tmp);

	sprintf(tmp, RF_LOGFILE);
	strcat(logfile_name, tmp);

	strcpy(dist_->rflogStr, logfile_name);
	printf("LOG FILE: %s\n", logfile_name);
	fp_rf = fopen(logfile_name, "a+");
	if(fp_rf==NULL){
		perror("*******LOG FILE OPEN ERROR********\n");
		exit(0);
	}
	fprintf(fp_rf, "/* Sub1G: Speed = %d, pwr_lvl = %d */\n", speed, pwr_lvl);

	/**
	 * Print LOOP
	 */
	pthread_mutex_init(&dist_->lock, NULL);
	dist_->m8_Gps = m8_Gps_;
	dist_->rf_valid=0;
	dist_->wifi_valid=0;

	pthread_create(&disttid, NULL, print_distance_loop, (void*)dist_);

	/**
	 * RSSI file of rfsub1G
	 */
	FILE* fp_rf_rssi;

	/**
	 * RSSI file of 802.11p
	 */
	FILE* fp_wifi_rssi;
	char rssi_wifi_file_name[200];
	memset(rssi_wifi_file_name, 0, 200);

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
	char wifi_mac[20];

	long long pktsn_rf_last20[20];
	long long pktsn_wifi_last20[20];
	int pkt_rf_p = 0;
	int pkt_wifi_p = 0;
	memset(pktsn_rf_last20, -1, 20*sizeof(long long));
	memset(pktsn_wifi_last20, -1, 20*sizeof(long long));

	struct  timeval localtime;
	/**
	 * select LOOP
	 */
	char recvbuf[BUFSIZ];
	int pos;
	int len;
	int rf_rssi;
	int wifi_rssi;
	fd_set rfds;
	struct timeval time_out;
	time_out.tv_sec=1;
	time_out.tv_usec=0;
	int maxfd = sock_rf > sock_wifi ? sock_rf:sock_wifi;
	int ret;
	float distance;
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

				fp_rf_rssi = fopen(RF_RSSI_LOC, "r");
				if(fp_rf_rssi==NULL){
					perror("*******RSSI FILE OPEN ERROR********\n");
					exit(0);
				}
				fscanf(fp_rf_rssi, "%d", &rf_rssi);
				fclose(fp_rf_rssi);

				gettimeofday(&localtime, NULL);

				fprintf(fp_rf, "SN@%lld ", sn);
				fprintf(fp_rf, "TIME@%d:%d:%d %u ", hours, minutes, seconds, mills);
				fprintf(fp_rf, "GPSPKT@%f,%f ", longitude, latitude);
				fprintf(fp_rf, "GPSCURR@%f,%f ", m8_Gps_->longitude, m8_Gps_->latitude);
				fprintf(fp_rf, "SPEED@%d ", speed);
				fprintf(fp_rf, "RSSI@%d ", rf_rssi);
				fprintf(fp_rf, "LTIME@%ld\n", localtime.tv_sec);
				fflush(fp_rf);

				pktsn_rf_last20[pkt_rf_p] = sn;
				pkt_rf_p = (pkt_rf_p+1) % 20;
				dist_->pkt_loss_rate_rf_last20 = cal_pktlossrate_lastn(pktsn_rf_last20, 20);
				dist_->rssi_rf_lastpkt = rf_rssi;

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
					memcpy(wifi_mac, recvbuf+pos, 17);
					pos += 17;
					wifi_mac[17] = '\0';
					if(pos != len) {
						perror("sock_wifi: pos != len\n");
						exit(0);
					}
				}

				memset(rssi_wifi_file_name, 0, 200);
				strcat(rssi_wifi_file_name, WIFI_RSSI_LOC_BASE);
				strcat(rssi_wifi_file_name, wifi_mac);
				strcat(rssi_wifi_file_name, WIFI_RSSI_LOC_TAIL);

				fp_wifi_rssi = fopen(rssi_wifi_file_name, "r");
				if(fp_wifi_rssi==NULL){
					perror("*******802.11p RSSI FILE OPEN ERROR********\n");
					exit(0);
				}
				fscanf(fp_wifi_rssi, "%d", &wifi_rssi);
				fclose(fp_wifi_rssi);

				fprintf(fp_wifi, "SN@%lld ", sn);
				fprintf(fp_wifi, "TIME@%d:%d:%d %u ", hours, minutes, seconds, mills);
				fprintf(fp_wifi, "GPSPKT@%f,%f ", longitude, latitude);
				fprintf(fp_wifi, "GPSCURR@%f,%f ", m8_Gps_->longitude, m8_Gps_->latitude);
				fprintf(fp_wifi, "SPEED@%u ", speed);
				fprintf(fp_wifi, "SNR@%d ", wifi_rssi);
				fprintf(fp_wifi, "LTIME@%ld\n", localtime.tv_sec);
				fflush(fp_wifi);

				pktsn_wifi_last20[pkt_wifi_p] = sn;
				pkt_wifi_p = (pkt_wifi_p+1) % 20;
				dist_->pkt_loss_rate_wifi_last20 = cal_pktlossrate_lastn(pktsn_wifi_last20, 20);
				dist_->rssi_wifi_lastpkt = wifi_rssi;

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
	serialGps gps_serial;
	bool ret;

	if(changeGpsplatformFlag) {
		gps.write_gps_config(gps_platform_model_data + (gps_platform_model_sn * SIZE_PER_PLATFORM), SIZE_PER_PLATFORM);
	} else {
		printf("changeGpsplatformFlag error!\n");
	}

	printf("%d\n",gps.write_gps_config(gps_config_change, sizeof(gps_config_change)));

	int bytesread;
	while(1) {
		bytesread = gps_serial.get_gps_data2buf();
	    if(bytesread < 0){
	    	printf("gpsdata_decode_loop: bytes<0!\n");
	    	exit(0);
	    }

		for (int i = 0; i < bytesread; i++) {
			M8_Gps_->encode((char)(gps_serial.gpsdata_buf())[i]);

		}

		pthread_testcancel();
	}
}

int usage(){
	printf("Parameter Error!\n");
	printf("-i [device sn (0,1)]\n");
	printf("-s :Open sending thread\n");
	printf("-r :Open receiving thread\n");
	printf("-g [spped (0<s<500)]:\n");
	printf("-l [power_level (0<=p<=127)]\n");
	printf("-P [gps platform model (0~3)] : 0-Stationary, 1-Pedestrian, 2-Automotive, 3-Portabl, \n");
	return -1;
}

int main(int argc, char **argv){

	int byte2read;
	pthread_t gpstid;
	pthread_t sendlooptid;
	void * tret;
	Ublox * m8_Gps = NULL;
	bool gpsloopflag = 0;
	bool sendloopflag = 0;
	bool recvloopflag = 0;

	int err, ret;
	char cmd;
	int tmpnum;
	char *tmpbuf;

	tmpbuf = (char*)malloc(CMDSIZE);

	argc--;
	argv++;

	while(argc > 0) {
		if(argv[0][0]=='-' && argv[0][1]=='i') {
			if (isdigit(argv[0][2])) {
				tmpnum = atoi(argv[0] + 2);
			} else {
				if(argc < 2 || argv[0][2] != '\0') return usage();
				tmpnum = atoi(argv[1]);
				argc--;
				argv++;
			}
		} else if(!strcmp(argv[0],"-s")) {
			sendloopflag = 1;
		} else if(!strcmp(argv[0],"-r")) {
			recvloopflag = 1;
		} else if(argv[0][0]=='-' && argv[0][1]=='g') {
			if (isdigit(argv[0][2])) {
				return usage();
			} else {
				if(argc < 2 || argv[0][2] != '\0') return usage();
				speed = atoi(argv[1]);
				changeSpeedFlag = 1;
				argc--;
				argv++;
			}
		} else if(argv[0][0]=='-' && argv[0][1]=='l') {
			if (isdigit(argv[0][2])) {
				return usage();
			} else {
				if(argc < 2 || argv[0][2] != '\0') return usage();
				pwr_lvl = atoi(argv[1]);
				changePwrFlag = 1;
				argc--;
				argv++;
			}
		} else if(argv[0][0]=='-' && argv[0][1]=='P') {
			if (isdigit(argv[0][2])) {
				return usage();
			} else {
				if(argc < 2 || argv[0][2] != '\0') return usage();
				if(gps_platform_model_sn < 0 || gps_platform_model_sn > MAX_PLATFORM_MODEL_SN) {
					printf("Unsupported GPS platform model!\n");
					return usage();
				}
				gps_platform_model_sn = atoi(argv[1]);
				changeGpsplatformFlag = 1;
				argc--;
				argv++;
			}
		}
		argc--;
		argv++;
	}

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
	system("insmod /home/root/si4463_fpga.ko");
	system("iptables -I OUTPUT -d 8.8.0.0/16 -j DROP");
	system("iptables -A OUTPUT -p udp --dport 1534 -j DROP");
	system("mount -t debugfs none /home/root/d");
	//sleep(1);
	if(changeSpeedFlag) {
		sprintf(tmpbuf,"echo %d > /home/root/d/si4463/speed_kbps", speed);
		printf("%s\n", tmpbuf);
		system(tmpbuf);
	}
	if(changePwrFlag) {
		sprintf(tmpbuf, "echo %d > /home/root/d/si4463/power_lvl", pwr_lvl);
		printf("%s\n", tmpbuf);
		system(tmpbuf);
	}

	strcpy(tmpbuf , "ifconfig sif0 ");
	strcat(tmpbuf, myrf_ip);
	printf("%s\n", tmpbuf);
	system(tmpbuf);


	/**
	 * open GPS deamon
	 */

	m8_Gps = new Ublox();
	ret = pthread_create(&gpstid, NULL, gpsdata_decode_loop, (void*)m8_Gps);
	gpsloopflag = 1;

	if(sendloopflag){
		ret = pthread_create(&sendlooptid, NULL, send_tester_loop, (void*)m8_Gps);
	}
	if(recvloopflag){
		printf("%s\n", myrf_ip);
		printf("%s\n", remoterf_ip);
		printf("%s\n", mywifi_ip);
		printf("%s\n", remotewifi_ip);
		recv_tester_loop((void*)m8_Gps);
	}

#ifdef DEBUG
	printf("Debug mode, Gps validation is not concerned.\n");
#endif
	do {
		printf("Input CMD (h for help):\n");
		scanf("%c", &cmd);
		getchar();
		switch(cmd){
		case 'h':
			//printf("g: Start gps decoding loop.\n");
			printf("s: Start packet sending loop.\n");
			printf("r: Start Receiving loop.\n");
			printf("t: Terminate loops.\n");
			printf("p: ping test.\n");
			printf("l: Change RF power level.\n");
			printf("g: Change RF speed.\n");
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
		case 'l':
			do {
				printf("Input power level 0~127: ");
				scanf("%d", &pwr_lvl);
			}
			while(pwr_lvl < 0 || pwr_lvl > 127);
			sprintf(tmpbuf, "echo %d > /home/root/d/si4463/power_lvl", pwr_lvl);
			printf("%s\n", tmpbuf);
			system(tmpbuf);
			break;
		case 'g':
			do {
				printf("Input speed 0~400: ");
				scanf("%d", &speed);
				getchar();
			}
			while(speed < 0);
			sprintf(tmpbuf, "echo %d > /home/root/d/si4463/speed_kbps", speed);
			printf("%s\n", tmpbuf);
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
