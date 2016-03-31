#include "Ublox.h"

#define I2CGPS_I2C_ADDR 		0x42
#define I2C_DEVICE_FD 		0
#define BUFFER_SIZE			255
typedef unsigned char		u8;


class i2cgps{
public:
	i2cgps();
	~i2cgps();
	int init(void);
	int write_gps_config(u8 *data, int size);
	//

	u8* gpsdata_buf();
	int gpsdata_buf_size();

//	int get_coordinate(float *buf);
//	float get_altitude(void);
//	int get_UTCtime_hms(int *buf);
	int get_byte_available(void);
	int get_gps_data2buf(int size);

private:
//	Ublox M8_Gps_;
	int i2cfd_;
	u8 *gpsdata_;
	int size_;
	int i2c_wrtie(u8 subaddress, u8 *data, int size);
	int i2c_read(u8 subaddress, u8 *buf, int size);


};
