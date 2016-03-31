
CFLAGS += 

default: i2c-gps.o main.o Ublox.o
	${CXX} ${CFLAGS} i2c-gps.o Ublox.o main.o -o gpstester  -lpthread
i2c-gps.o:
	${CXX} ${CFLAGS} -c i2c-gps.cpp
Ublox.o:
	${CXX} ${CFLAGS} -c Ublox.cpp
main.o:
	${CXX} ${CFLAGS} -c main.cpp
clean:
	rm -rf *.o
	rm -rf gpstester
