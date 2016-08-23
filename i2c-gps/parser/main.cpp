#include <iostream>
#include <string.h>
#include <stdio.h>
#include <string>
#include <math.h>
#include <stdlib.h>
#include <map>
#include <vector>
#include <algorithm>
using namespace std;

#define AVER_PKT_NUM 100.0
#define AVER_DISTANCE	1

struct elements_perline{
	long long sn;
	double longi_pkt;
	double lati_pkt;
	double longi_curr;
	double lati_curr;
	int speed;
	int rssi;
	double distance;
	long ltime;
};

struct elements_time{
	int rssi;
	float pdr;
	double distance;
};

#define PI                      3.1415926
#define EARTH_RADIUS            6378.137        //地球近似半径
// 求弧度
double radian(double d)
{
    return d * PI / 180.0;   //角度1˚ = π / 180
}
double round(double r)
{
    return (r > 0.0) ? floor(r + 0.5) : ceil(r - 0.5);
}
//计算距离
double get_distance(double lat1, double lng1, double lat2, double lng2)
{
	double radLat1 = radian(lat1);
	double radLat2 = radian(lat2);
	double a = radLat1 - radLat2;
	double b = radian(lng1) - radian(lng2);

	double dst = 2 * asin((sqrt(pow(sin(a / 2), 2) + cos(radLat1) * cos(radLat2) * pow(sin(b / 2), 2) )));

    dst = dst * EARTH_RADIUS;
    dst= round(dst * 100000) / 100000;

    return dst*1000;
}

int main(int argc,char **argv)
{
	vector<struct elements_perline> data_vec;
	vector<int> gps_loss_vec;
	map<double, int> distance_rssi_map;
	map<double, float> distance_pdr_map;
	map<double, int> distance_count_map;

	map<long, struct elements_time> time_rpd_map;

	char filename[200];
	char StrLine[1024];
	char* tmp[20];
	//int sn;
	//double lati_pkt, longi_pkt, lati_curr, longi_curr, distance;
	//int speed;
	//int rssi;

	for (int i=0; i<20; i++){
		tmp[i] = (char*)malloc(200);
	}

	strcpy(filename, argv[1]);//"/home/wu/Desktop/workspace/i2cpgsParser/0819/16819-1-59-rflog.txt");//
	FILE *fp;
	if((fp = fopen(filename,"r")) == NULL)
	{
		cout<<"error!"<<endl;
		return -1;
	}
	//去掉第一行的header
	fgets(StrLine, 1024, fp);
	fgets(StrLine, 1024, fp);
	fgets(StrLine, 1024, fp);

	while (!feof(fp))
	{
		int i = 0;
		struct elements_perline ele_;
		struct elements_time ele_time_;
		fgets(StrLine,1024,fp);  //读取一行
		char* token = strtok( StrLine, " ");
		while( token != NULL )
		{
			strcpy(tmp[i++], token);
			/* While there are tokens in "string" */
			//printf( "%s ", token );
			/* Get next token: */
			token = strtok( NULL, " ");
		}
		if(i<6)
			break;
		ele_.sn = atoi(strchr(tmp[0], '@')+1);
		token = strtok(strchr(tmp[3], '@')+1, ",");
		ele_.longi_pkt = atof(token);
		token = strtok( NULL, " ");
		ele_.lati_pkt = atof(token);

		token = strtok(strchr(tmp[4], '@')+1, ",");
		ele_.longi_curr = atof(token);
		token = strtok( NULL, " ");
		ele_.lati_curr = atof(token);

		ele_.speed = atoi(strchr(tmp[5], '@')+1);
		ele_.rssi = atoi(strchr(tmp[6], '@')+1);

		ele_.ltime = atol(strchr(tmp[7], '@')+1);

		ele_.distance = get_distance(ele_.lati_pkt, ele_.longi_pkt, ele_.lati_curr, ele_.longi_curr);

		data_vec.push_back(ele_);

	}
	int debug_size = data_vec.size();
	double last_distance = -1;
	long beginTime = -1;
	for (vector<struct elements_perline>::iterator iter = data_vec.begin(); iter != data_vec.end(); ++iter)
	{
		double round_distance = round((*iter).distance);
		if(last_distance != -1) {
			if(fabs(last_distance - round_distance) > 2000) {
				gps_loss_vec.push_back((*iter).ltime);
				continue;
			}
			last_distance = round_distance;
		} else {
			last_distance = round_distance;
		}

		//距离与RSSI的关系
		map<double, int>::iterator t1 = distance_rssi_map.find(round_distance);
		if(t1 != distance_rssi_map.end()) {
			distance_rssi_map[round_distance] = (distance_rssi_map[round_distance] + (*iter).rssi)/2;
			distance_count_map[round_distance]++;
		}
		else {
			distance_rssi_map[round_distance] = (*iter).rssi;
			distance_count_map[round_distance] = 1;
		}
		//距离与pdr的关系，每项的pdr由该项前N个包算出
		//先计算前20个包的pdr
		float pdr;

		vector<struct elements_perline>::iterator iter_pdr = iter;

		if(iter_pdr == data_vec.begin())
			pdr = 1.0;
		else
		{
			int start = (*iter_pdr).sn;
			int end = start - AVER_PKT_NUM;
			float pkt_count = 0.0;
			int i=0;
			do
			{
				if((*iter_pdr).sn > end)
					pkt_count++;
				iter_pdr--;
				i++;
			} while(iter_pdr!=data_vec.begin() && i < AVER_PKT_NUM);
			if(i < AVER_PKT_NUM)
				continue;//前20个包不计入pdr
			pdr = pkt_count/AVER_PKT_NUM;
		}

		map<double, float>::iterator t2 = distance_pdr_map.find(round_distance);
		if(t2 != distance_pdr_map.end()){
			distance_pdr_map[round_distance] = (distance_pdr_map[round_distance] + pdr)/2.0;
			distance_count_map[round_distance]++;
		}
		else{
			distance_pdr_map[round_distance] = pdr;
			distance_count_map[round_distance] = 1;
		}

		/**
		 * 时间和pdr，场强，距离的关系
		 * map<long, int> time_rssi_map;
		 * map<long, float> time_pdr_map;
		 * map<long, double> time_distance_map;
		 */
		long ltime = (*iter).ltime;

		if(beginTime == -1){
			beginTime = ltime;
		}
		ltime -= beginTime;

		map<long, struct elements_time>::iterator t = time_rpd_map.find(ltime);

		if(ltime == 669) {
			debug_size = time_rpd_map.size();
		}
		if(t != time_rpd_map.end()) {
			time_rpd_map[ltime].rssi = (time_rpd_map[ltime].rssi + (*iter).rssi)/2;
			time_rpd_map[ltime].pdr = (time_rpd_map[ltime].pdr + pdr)/2.0;
			time_rpd_map[ltime].distance = (time_rpd_map[ltime].distance + round_distance)/2.0;
		}
		else {
			time_rpd_map[ltime].rssi = (*iter).rssi;
			time_rpd_map[ltime].pdr = pdr;
			time_rpd_map[ltime].distance = round_distance;
		}

	}

	debug_size = gps_loss_vec.size();

	map<double, int>::iterator iter_map_rssi;
	map<double, float>::iterator iter_map_pdr;
	map<long, struct elements_time>::iterator t;

	fclose(fp);
	if((fp = fopen("distance-rssi.txt","w+")) == NULL)
	{
		cout<<"error!"<<endl;
		return -1;
	}

	cout<<"距离-rssi\n"<<endl;
	for(iter_map_rssi = distance_rssi_map.begin(); iter_map_rssi != distance_rssi_map.end(); iter_map_rssi++)
	{
		printf("%f, %d\n", iter_map_rssi->first, iter_map_rssi->second);
		fprintf(fp, "%f %d\n", iter_map_rssi->first, iter_map_rssi->second);
	}

	fclose(fp);
	if((fp = fopen("distance-PDR.txt","w+")) == NULL)
	{
		cout<<"error!"<<endl;
		return -1;
	}
	cout<<"距离-PDR\n"<<endl;
	float sum=0, distance_sum=0, count=0;
	for(iter_map_pdr = distance_pdr_map.begin(); iter_map_pdr != distance_pdr_map.end(); iter_map_pdr++)
	{
		sum += iter_map_pdr->second;
		distance_sum += iter_map_pdr->first;
		count++;
		if(count == AVER_DISTANCE) {
			printf("%f, %f\n", distance_sum/AVER_DISTANCE, sum/AVER_DISTANCE);
			fprintf(fp, "%f %f\n", distance_sum/AVER_DISTANCE, sum/AVER_DISTANCE);
			sum = 0;
			distance_sum = 0;
			count = 0;
		}

	}

	cout<<"Time-distance-rssi-PDR\n"<<endl;
	fclose(fp);
	if((fp = fopen("time-distance-rssi-pdr.txt","w+")) == NULL)
	{
		cout<<"error!"<<endl;
		return -1;
	}

	for(int i=time_rpd_map.begin()->first; i<= time_rpd_map.rbegin()->first; i++){
		if((t = time_rpd_map.find(i)) != time_rpd_map.end()){
			printf("%ld %f %d %f\n", i, (t->second).distance, (t->second).rssi, (t->second).pdr);
			fprintf(fp, "%ld %f %d %f\n", i, (t->second).distance/5, abs((t->second).rssi/2), (t->second).pdr*100);
		} else {
			vector<int>::iterator result = find(gps_loss_vec.begin(), gps_loss_vec.end(), i+beginTime);
			if(result == gps_loss_vec.end()) {
				printf("%ld %f %d %f\n", i, 0, 0, 0);
				fprintf(fp, "%ld %f %d %f\n", i, 0, 0, 0);
			}else{
//				printf("xxxxxx");
			}
		}
	}
/*	for(t = time_rpd_map.begin(); t != time_rpd_map.end(); t++){
		printf("%ld %f %d %f\n", t->first, (t->second).distance, (t->second).rssi, (t->second).pdr);
		fprintf(fp, "%ld %f %d %f\n", t->first, (t->second).distance/5, abs((t->second).rssi/2), (t->second).pdr*100);
	}*/
	fclose(fp);
//	cout<<"Time-Rssi\n"<<endl;
//	fclose(fp);
//	if((fp = fopen("time-rssi.txt","a+")) == NULL)
//	{
//		cout<<"error!"<<endl;
//		return -1;
//	}
//	for(t_trm = time_rssi_map.begin(); t_trm != time_rssi_map.end(); t_trm++){
//		printf("%ld %d\n", t_trm->first, t_trm->second);
//		fprintf(fp, "%ld %d\n", t_trm->first, t_trm->second);
//	}
//
//	cout<<"Time-PDR\n"<<endl;
//	fclose(fp);
//	if((fp = fopen("time-pdr.txt","a+")) == NULL)
//	{
//		cout<<"error!"<<endl;
//		return -1;
//	}
//	for(t_tpm = time_pdr_map.begin(); t_tpm != time_pdr_map.end(); t_tpm++){
//		printf("%ld %f\n", t_tpm->first, t_tpm->second);
//		fprintf(fp, "%ld %f\n", t_tpm->first, t_tpm->second);
//	}
//
//	cout<<"Time-distance\n"<<endl;
//	fclose(fp);
//	if((fp = fopen("time-distance.txt","a+")) == NULL)
//	{
//		cout<<"error!"<<endl;
//		return -1;
//	}
//	for(t_tdm = time_distance_map.begin(); t_tdm != time_distance_map.end(); t_tdm++){
//		printf("%ld %f\n", t_tdm->first, t_tdm->second);
//		fprintf(fp, "%ld %f\n", t_tdm->first, t_tdm->second);
//	}

	return 0;
}
