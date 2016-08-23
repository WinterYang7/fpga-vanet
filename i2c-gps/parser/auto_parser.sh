#!/bin/bash
if [ x$1 == x ];then
	echo "No input!"
else
	./parser $1
	python plot-distance-pdr.py
	python plot-time-drp.py
fi

