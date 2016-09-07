/*
 * node.cpp
 *
 *  Created on: Aug 24, 2016
 *      Author: wu
 */

#include "node.h"
#include <math.h>
#include <stdlib.h>
#include <algorithm>
#include <string>
#include <string.h>

int timestr2second(char * str)
{
	int h,m,s;
	char* token = strtok(str, ":");
	h = atoi(token);
	token = strtok( NULL, ":");
	m = atoi(token);
	token = strtok( NULL, ":");
	s = atoi(token);
	return h*3600 + m*60 + s;
}

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

void node::sendlog2buf(FILE *fp)
{
	char StrLine[1024];
	char* tmp[20];
	map<int, struct elements_sendlog> * sendlog_data_p;
	for (int i=0; i<20; i++){
		tmp[i] = (char*)malloc(200);
	}

	sendlog_data_p = &(this->sendlog_data);
	//去掉第一行的header
	fgets(StrLine, 1024, fp);
	fgets(StrLine, 1024, fp);

	while (!feof(fp))
	{
		int i = 0;
		struct elements_sendlog ele_;
		char timeStr[20];
		int time;
		fgets(StrLine,1024,fp);  //读取一行

		if(strstr(StrLine, "/* Sub1G"))
			continue;

		char* token = strtok( StrLine, " ");
		while( token != NULL )
		{
			strcpy(tmp[i++], token);
			token = strtok( NULL, " ");
		}
		if(i<5)
			continue;
		ele_.sn = atoi(strchr(tmp[0], '@')+1);
		strcpy(timeStr, strchr(tmp[1], '@')+1);
		time = timestr2second(timeStr);

		token = strtok(strchr(tmp[4], '@')+1, ",");
		ele_.longi_curr = atof(token);
		token = strtok( NULL, " ");
		ele_.lati_curr = atof(token);

		ele_.speed = atoi(strchr(tmp[5], '@')+1);

		(*sendlog_data_p)[time] = ele_;
	}
}

void node::recvlog2buf(FILE *fp, char* loc)
{
	char StrLine[1024];
	char* tmp[20];
	double last_distance = -1;
	int timeSecCount = 0;
	map<int, struct elements_persec> * recvlog_data_p;
	map<int, struct time_section> * time_section_p;

	for (int i=0; i<20; i++){
		tmp[i] = (char*)malloc(200);
	}

	if (!strcmp(loc, "rf")){
		recvlog_data_p = &(this->recvlog_rf_data);
		time_section_p = &(this->time_section_rf);
	} else {
		recvlog_data_p = &(this->recvlog_wifi_data);
		time_section_p = &(this->time_section_wifi);
	}

	//去掉第一行的header
	fgets(StrLine, 1024, fp);
	fgets(StrLine, 1024, fp);
	fgets(StrLine, 1024, fp);

	int last_time;
	bool newfile = true;
	while (!feof(fp))
	{
		int i = 0;
		struct elements_persec ele_;
		char timeStr[20];
		int time;

		fgets(StrLine,1024,fp);  //读取一行

		if(strstr(StrLine, "/* Sub1G")) {
			last_distance = -1;
			(*time_section_p)[timeSecCount].end = last_time;
			newfile = true;
			continue;
		}

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
			continue;
		long long sn = atoi(strchr(tmp[0], '@')+1);
		strcpy(timeStr, strchr(tmp[1], '@')+1);
		time = timestr2second(timeStr);
		last_time = time;
		if(newfile) {
			timeSecCount++;
			(*time_section_p)[timeSecCount].start = time;
			newfile = false;
		}

		token = strtok(strchr(tmp[3], '@')+1, ",");
		float longi_pkt = atof(token);
		token = strtok( NULL, " ");
		float lati_pkt = atof(token);

		token = strtok(strchr(tmp[4], '@')+1, ",");
		float longi_curr = atof(token);
		token = strtok( NULL, " ");
		float lati_curr = atof(token);

		int speed = atoi(strchr(tmp[5], '@')+1);
		int rssi = atoi(strchr(tmp[6], '@')+1);

		long ltime = atol(strchr(tmp[7], '@')+1);

		double distance = get_distance(lati_pkt, longi_pkt, lati_curr, longi_curr);
		double round_distance = round(distance);
		if(last_distance != -1) {
			if(fabs(last_distance - round_distance) > 2000) {
				continue;
			}
			last_distance = round_distance;
		} else {
			last_distance = round_distance;
		}

		map<int, struct elements_persec>::iterator t = (*recvlog_data_p).find(time);
		if(t != (*recvlog_data_p).end()) {
			(*recvlog_data_p)[time].count++;
			(*recvlog_data_p)[time].distance = ((*recvlog_data_p)[time].distance + round_distance) / 2;
			(*recvlog_data_p)[time].rssi = ((*recvlog_data_p)[time].rssi + rssi) / 2;
			(*recvlog_data_p)[time].speed = ((*recvlog_data_p)[time].speed + speed) / 2;
		}else {
			(*recvlog_data_p)[time].count = 1;
			(*recvlog_data_p)[time].distance = round_distance;
			(*recvlog_data_p)[time].rssi = rssi;
			(*recvlog_data_p)[time].speed = speed;
		}
	}
	(*time_section_p)[timeSecCount].end = last_time;
}

double node::get_distance_at_time(node * nodex, int time_sec)
{
	float latix, longix, laticurr, longicurr;
	latix = nodex->sendlog_data.find(time_sec)->second.lati_curr;
	longix = nodex->sendlog_data.find(time_sec)->second.longi_curr;
	laticurr = this->sendlog_data.find(time_sec)->second.lati_curr;
	longicurr = this->sendlog_data.find(time_sec)->second.longi_curr;

	double distance = get_distance(latix, longix, laticurr, longicurr);
	return round(distance);
}

/**
 * 利用k-order Bursty Degree计算时间相关性(2010-mobicom-toward)
 */
#define DISTANCE_BARRI 100
double node::get_korder_Bursty_Degree_at_x(int x, char* loc){
	double r0 = 0.0;
	double t0, t1;
	map<int, struct elements_persec> * recvlog_data_p;
	map<int, struct elements_persec>::iterator i0,i1;

	if (!strcmp(loc, "rf")){
		recvlog_data_p = &(this->recvlog_rf_data);
	} else {
		recvlog_data_p = &(this->recvlog_wifi_data);
	}

	x += (*recvlog_data_p).begin()->first;
	int n = (*recvlog_data_p).rbegin()->first;
	for(int t=x; t<=n; t++){
		i0 = (*recvlog_data_p).find(t);
		i1 = (*recvlog_data_p).find(t-x);
		if(i0 == (*recvlog_data_p).end())
			t0 = 0.0;
		else if(i0->second.distance < DISTANCE_BARRI || i0->second.distance > 600) {
			continue;
		} else
			t0 = i0->second.count /10.0;
		if(i1 == (*recvlog_data_p).end())
			t1 = 0.0;
		else if(i0->second.distance < DISTANCE_BARRI || i0->second.distance > 600) {
			continue;
		} else
			t1 = i0->second.count /10.0;

		r0 += pow(t0 - t1, 2);
		if(r0>0){
			double xxx=1;
		}
	}
	r0 = (1/(2*((double)n-(double)x))) * r0;
	r0 = sqrt(r0);
	return r0;
}

bool node::search_time_section(int time, char* loc)
{
	map<int, struct time_section> * time_section_p;
	map<int, struct time_section>::iterator iter;

	if (!strcmp(loc, "rf")){
		time_section_p = &(this->time_section_rf);
	} else {
		time_section_p = &(this->time_section_wifi);
	}

	for(iter = time_section_p->begin(); iter != time_section_p->end(); iter++){
		if(time > iter->second.start && time < iter->second.end)
			return true;
	}
	return false;
}
