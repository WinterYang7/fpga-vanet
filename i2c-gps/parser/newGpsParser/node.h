/*
 * node.h
 *
 *  Created on: Aug 24, 2016
 *      Author: wu
 */

#ifndef NODE_H_
#define NODE_H_

#include <map>
#include <vector>
#include <stdio.h>

using namespace std;

#define AVER 2
#define AVER_DISTANCE 1

//#define NODE1_SEND "/home/wu/Desktop/workspace/i2cpgsParser/0819/wjbang-city-send-adjusted.txt"
//#define NODE1_RECV_RF "/home/wu/Desktop/workspace/i2cpgsParser/0819/wjbang-city-rf-adjusted.txt"
//#define NODE1_RECV_WIFI "/home/wu/Desktop/workspace/i2cpgsParser/0819/wjbang-city-wifi-adjusted.txt"
//
//#define NODE2_SEND "/home/wu/Desktop/workspace/i2cpgsParser/0819/xyong-city-send-adjusted.txt"
//#define NODE2_RECV_RF "/home/wu/Desktop/workspace/i2cpgsParser/0819/xyong-city-rf-adjusted.txt"
//#define NODE2_RECV_WIFI "/home/wu/Desktop/workspace/i2cpgsParser/0819/xyong-city-wifi-adjusted.txt"

#define NODE1_SEND "/home/wu/Desktop/workspace/i2cpgsParser/0819/wjb-send-adjusted.txt"
#define NODE1_RECV_RF "/home/wu/Desktop/workspace/i2cpgsParser/0819/wjb-rf-all-adjusted.txt"
#define NODE1_RECV_WIFI "/home/wu/Desktop/workspace/i2cpgsParser/0819/wjb-wifi-all-adjusted.txt"

#define NODE2_SEND "/home/wu/Desktop/workspace/i2cpgsParser/0819/xy-send-adjusted.txt"
#define NODE2_RECV_RF "/home/wu/Desktop/workspace/i2cpgsParser/0819/xy-rf-all-adjusted.txt"
#define NODE2_RECV_WIFI "/home/wu/Desktop/workspace/i2cpgsParser/0819/xy-wifi-all-adjusted.txt"

struct elements_sendlog{
	long sn;
	double longi_curr;
	double lati_curr;
	int speed;
	int rssi;
	long ltime;
};

struct elements_recvlog{
	long sn;
	double longi_pkt;
	double lati_pkt;
	double longi_curr;
	double lati_curr;
	int speed;
	int rssi;
	double distance;
	long ltime;
};

struct elements_persec{
	double distance;
	int rssi;
	int speed;
	int count;
};

struct time_section{
	int start;
	int end;
};
/**
 * 节点储存的数据应该是由发送数据和接收数据组成
 * 数据由时间作为key，对应内容为一个以包序号为key的map，包含每个包的时间与经纬度以及速度；
 *
 * sendlog 也只需要记一条数据就行了
 */
class node {
public:

	map<int, struct elements_sendlog> sendlog_data;
//	map<int, map<int, struct elements_recvlog> > recvlog_rf_data;
//	map<int, map<int, struct elements_recvlog> > recvlog_wifi_data;
	map<int, struct elements_persec > recvlog_rf_data;
	map<int, struct elements_persec > recvlog_wifi_data;

	map<int, struct time_section> time_section_rf;
	map<int, struct time_section> time_section_wifi;

	void sendlog2buf(FILE *fp);
	void recvlog2buf(FILE *fp, char* loc);
	double get_distance_at_time(node * nodex, int time_sec);
	double get_korder_Bursty_Degree_at_x(int x, char* loc);

	bool search_time_section(int time, char* loc);
};

#endif /* NODE_H_ */
