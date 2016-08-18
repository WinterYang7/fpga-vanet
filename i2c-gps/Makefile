
CFLAGS += 
#CFLAGS += -DDEBUG

default: i2c-gps.o serial-gps.o main.o Ublox.o
	${CXX} ${CFLAGS} i2c-gps.o serial-gps.o Ublox.o main.o -o gpstester  -lpthread
main.o:
	${CXX} ${CFLAGS} -c main.cpp

gps_test: i2c-gps.o serial-gps.o gps_valid_tester.o Ublox.o
	${CXX} ${CFLAGS} i2c-gps.o serial-gps.o Ublox.o gps_valid_tester.o -o gps_valid_tester  -lpthread
i2c-gps.o:
	${CXX} ${CFLAGS} -c i2c-gps.cpp
serial-gps.o:
	${CXX} ${CFLAGS} -c serial-gps.cpp
Ublox.o:
	${CXX} ${CFLAGS} -c Ublox.cpp
gps_valid_tester.o:
	${CXX} ${CFLAGS} -c gps_valid_tester.cpp
	
clean:
	rm -rf *.o
	rm -rf gpstester
	rm -rf gps_valid_tester
