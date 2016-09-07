/**
 * 不变量：时间和距离
 * 变量：序号包有可能收的到有可能收不到
 * 对每一个节点，先把所有的数据读到节点中，(采用读参数文件的方式指定每个节点的文件地址)
 * 再根据接收log中的节点编号找到对应的节点发送记录。
 * 每AVER秒计算一次平均PDR与平均距离、平均速度、平均RSSI
 * (可以直接按照每秒有10个包来进行计算，这样就不需要查询发送方的数据了。对于中间缺的秒，按照时间查询发送记录，计算出距离，PDR算为0)
 */

#include "node.h"
#include <math.h>
#include <stdlib.h>
#include <algorithm>
#include <string>
#include <string.h>
#include <iostream>



int usage()
{
	printf("-c <parameter file location>\n");
	return -1;
}


int main(int argc,char **argv)
{
	char paraFileName[200];
	FILE *fp_para, *fp_out, *fp[10];
	map<double, float> distance_pdr_map;
	map<double, float> wifi_distance_pdr_map;

	map<int, float> rssi_pdr_rf_map;
	map<int, float> rssi_pdr_wifi_map;

	map<double, vector<float> >  distance_pdrvec_rf_map;
	map<double, vector<float> >  distance_pdrvec_wifi_map;


/*	argc--;
	argv++;
	while(argc > 0) {
		if(argv[0][0]=='-' && argv[0][1]=='c') {
			if(argc < 2 || argv[0][2] != '\0') return usage();
			strcpy(paraFileName, argv[1]);
			argc--;
			argv++;
		}
		argc--;
		argv++;
	}

	if((fp = fopen(paraFileName,"r")) == NULL)
	{
		cout<<"open error!"<<endl;
		return usage();
	}
*/

	node node1, node2;
	fp[1] = fopen(NODE1_SEND,"r");
	fp[2] = fopen(NODE1_RECV_RF, "r");
	fp[3] = fopen(NODE1_RECV_WIFI, "r");
	fp[4] = fopen(NODE2_SEND,"r");
	fp[5] = fopen(NODE2_RECV_RF, "r");
	fp[6] = fopen(NODE2_RECV_WIFI, "r");

	node1.sendlog2buf(fp[1]);
	node1.recvlog2buf(fp[2], "rf");
	node1.recvlog2buf(fp[3], "wifi");

	node2.sendlog2buf(fp[4]);
	node2.recvlog2buf(fp[5], "rf");
	node2.recvlog2buf(fp[6], "wifi");

	/**
	 * RF
	 */
	//TIME-Distance-pdr
	if((fp_out = fopen("RF-time-distance-PDR.txt","w+")) == NULL)
	{
		cout<<"error!"<<endl;
		return -1;
	}
	for(int time = node1.recvlog_rf_data.begin()->first;
			time < node1.recvlog_rf_data.rbegin()->first;
			time ++)
	{
		if(!(node1.search_time_section(time, "rf") && node2.search_time_section(time, "rf")))
			continue;

		double distance;
		int rssi;
		float pdr;
		bool flag1,flag2;

		map<int, struct elements_persec >::iterator iter_tmp = node1.recvlog_rf_data.find(time);
		if(iter_tmp != node1.recvlog_rf_data.end()) {
			flag1 = true;
			distance = iter_tmp->second.distance;
			pdr = ((float)iter_tmp->second.count)/10.0;
			rssi = iter_tmp->second.rssi;
		} else {
			flag1 = false;
		}

		iter_tmp = node2.recvlog_rf_data.find(time);
		if(iter_tmp != node2.recvlog_rf_data.end()) {
			flag2 = true;
			if(flag1) {
				distance = (distance + iter_tmp->second.distance) / 2.0;
				pdr = (pdr + ((float)iter_tmp->second.count)/10.0) / 2.0;
				rssi = (rssi + iter_tmp->second.rssi) / 2;

			} else {
				distance = iter_tmp->second.distance;
				pdr = (((float)iter_tmp->second.count)/10.0 + 0.0 ) / 2.0;
				rssi = iter_tmp->second.rssi;
			}
		} else {
			flag2 = false;
		}

		if(!flag1 && !flag2) {
			double tmp_distance = node1.get_distance_at_time(&node2, time);
			fprintf(fp_out, "%d %f 0\n", time, tmp_distance);
			map<double, float>::iterator t = distance_pdr_map.find(tmp_distance);
			if(t != distance_pdr_map.end()){
				distance_pdr_map[tmp_distance] = (distance_pdr_map[tmp_distance] + 0)/2.0;
			}
			else{
				distance_pdr_map[tmp_distance] = 0;
			}

			distance_pdrvec_rf_map[tmp_distance].push_back(0.0);
		}
		else {
			fprintf(fp_out, "%d %f %f\n", time, round(distance), pdr * 100);
			map<double, float>::iterator t = distance_pdr_map.find(round(distance));
			if(t != distance_pdr_map.end()){
				distance_pdr_map[round(distance)] = (distance_pdr_map[round(distance)] + pdr)/2.0;
			}
			else{
				distance_pdr_map[round(distance)] = pdr;
			}

			distance_pdrvec_rf_map[round(distance)].push_back(pdr);
		}
	}

	//distance-pdr
	fclose(fp_out);
	if((fp_out = fopen("RF-distance-PDR.txt","w+")) == NULL)
	{
		cout<<"error!"<<endl;
		return -1;
	}
	float sum=0, distance_sum=0, count=0;
	long distance_count=0;
	for(map<double, float>::iterator iter_map_pdr = distance_pdr_map.begin(); iter_map_pdr != distance_pdr_map.end(); iter_map_pdr++)
	{
		sum += iter_map_pdr->second;
		distance_sum += iter_map_pdr->first;
		count++;
		if(count == AVER_DISTANCE) {
			fprintf(fp_out, "%f %f\n", distance_sum/AVER_DISTANCE, sum/AVER_DISTANCE);
			sum = 0;
			distance_sum = 0;
			distance_count = 0;
			count = 0;
		}
	}

	fclose(fp_out);
	if((fp_out = fopen("RF-k-order.txt","w+")) == NULL)
	{
		cout<<"error!"<<endl;
		return -1;
	}
	for(int k=1; k<200; k++){
		double r0 = node1.get_korder_Bursty_Degree_at_x(k, "rf");
		fprintf(fp_out, "%d, %f\n", k, r0);
	}
	//distance_pdrvec_map
	fclose(fp_out);
	if((fp_out = fopen("RF-distance-PDR_Vector.txt","w+")) == NULL)
	{
		cout<<"error!"<<endl;
		return -1;
	}

	distance_count = 0;
	int distance_gear = 50;
	int print_gear = 0;
	bool print_line = false;
	for(map<double, vector<float> >::iterator iter_tmp = distance_pdrvec_rf_map.begin(); iter_tmp != distance_pdrvec_rf_map.end(); iter_tmp++)
	{
		while(iter_tmp->first > distance_gear) {
			distance_gear += 50;
			print_line = true;
		}
		if(print_gear < distance_gear) {
			fprintf(fp_out, "\n");
			fprintf(fp_out, "%d ", distance_gear);//iter_tmp->first);
			print_gear = distance_gear;
		}
		vector<float>::iterator iter_vec;
		for(iter_vec = (iter_tmp->second).begin(); iter_vec != (iter_tmp->second).end(); iter_vec++)
		{
			fprintf(fp_out, "%.3f ", *iter_vec);
		}
	}


	/**
	 * WIFI
	 */
	//distance_pdr_map.clear();
	fclose(fp_out);
	if((fp_out = fopen("wifi-time-distance-PDR.txt","w+")) == NULL)
	{
		cout<<"error!"<<endl;
		return -1;
	}
	for(int time = node1.recvlog_wifi_data.begin()->first;
			time < node1.recvlog_wifi_data.rbegin()->first;
			time ++)
	{
		if(!(node1.search_time_section(time, "wifi") && node2.search_time_section(time, "wifi")))
			continue;

		double distance;
		float pdr;
		bool flag1,flag2;

		map<int, struct elements_persec >::iterator iter_tmp = node1.recvlog_wifi_data.find(time);
		if(iter_tmp != node1.recvlog_wifi_data.end()) {
			flag1 = true;
			distance = iter_tmp->second.distance;
			pdr = ((float)iter_tmp->second.count)/10.0;
		} else {
			flag1 = false;
		}

		iter_tmp = node2.recvlog_wifi_data.find(time);
		if(iter_tmp != node2.recvlog_wifi_data.end()) {
			flag2 = true;
			if(flag1) {
				distance = (distance + iter_tmp->second.distance) / 2.0;
				pdr = (pdr + ((float)iter_tmp->second.count)/10.0) / 2.0;

			} else {
				distance = iter_tmp->second.distance;
				pdr = (((float)iter_tmp->second.count)/10.0 + 0.0 ) / 2.0;

			}
		} else {
			flag2 = false;
		}

		if(!flag1 && !flag2) {
			double tmp_distance = node1.get_distance_at_time(&node2, time);
			fprintf(fp_out, "%d %f 0\n", time, tmp_distance);
			map<double, float>::iterator t = wifi_distance_pdr_map.find(tmp_distance);
			if(t != wifi_distance_pdr_map.end()){
				wifi_distance_pdr_map[tmp_distance] = (wifi_distance_pdr_map[tmp_distance] + 0)/2.0;
			}
			else{
				wifi_distance_pdr_map[tmp_distance] = 0;
			}

			distance_pdrvec_wifi_map[tmp_distance].push_back(0.0);
		}
		else {
			fprintf(fp_out, "%d %f %f\n", time, round(distance), pdr * 100);
			map<double, float>::iterator t = wifi_distance_pdr_map.find(round(distance));
			if(t != wifi_distance_pdr_map.end()){
				wifi_distance_pdr_map[round(distance)] = (wifi_distance_pdr_map[round(distance)] + pdr)/2.0;
			}
			else{
				wifi_distance_pdr_map[round(distance)] = pdr;
			}

			distance_pdrvec_wifi_map[round(distance)].push_back(pdr);
		}
	}
	//distance-pdr
	fclose(fp_out);
	if((fp_out = fopen("wifi-distance-PDR.txt","w+")) == NULL)
	{
		cout<<"error!"<<endl;
		return -1;
	}

	sum=0, distance_sum=0, count=0;

	for(map<double, float>::iterator iter_map_pdr = wifi_distance_pdr_map.begin(); iter_map_pdr != wifi_distance_pdr_map.end(); iter_map_pdr++)
	{
		sum += iter_map_pdr->second;
		distance_sum += iter_map_pdr->first;
		count++;
		if(count == AVER_DISTANCE) {
			fprintf(fp_out, "%f %f\n", distance_sum/AVER_DISTANCE, sum/AVER_DISTANCE);
			sum = 0;
			distance_sum = 0;
			distance_count = 0;
			count = 0;
		}
	}

	fclose(fp_out);
	if((fp_out = fopen("wifi-k-order.txt","w+")) == NULL)
	{
		cout<<"error!"<<endl;
		return -1;
	}
	for(int k=1; k<200; k++){
		double r0 = node1.get_korder_Bursty_Degree_at_x(k, "wifi");
		fprintf(fp_out, "%d, %f\n", k, r0);
	}

	//distance_pdrvec_map
	fclose(fp_out);
	if((fp_out = fopen("WIFI-distance-PDR_Vector.txt","w+")) == NULL)
	{
		cout<<"error!"<<endl;
		return -1;
	}
	distance_count = 0;
	distance_gear = 50;
	print_gear = 0;
	print_line = false;
	for(map<double, vector<float> >::iterator iter_tmp = distance_pdrvec_wifi_map.begin(); iter_tmp != distance_pdrvec_wifi_map.end(); iter_tmp++)
	{
		while(iter_tmp->first > distance_gear) {
			distance_gear += 50;
			print_line = true;
		}
		if(print_gear < distance_gear) {
			fprintf(fp_out, "\n");
			fprintf(fp_out, "%d ", distance_gear);//iter_tmp->first);
			print_gear = distance_gear;
		}
		vector<float>::iterator iter_vec;
		for(iter_vec = (iter_tmp->second).begin(); iter_vec != (iter_tmp->second).end(); iter_vec++)
		{
			fprintf(fp_out, "%.3f ", *iter_vec);
		}
	}

}
