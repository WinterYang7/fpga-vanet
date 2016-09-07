import numpy as np
import pylab as pl
import sys

def drawLine(file_path, output):
    Time=[]
    Distance=[]
    Rssi=[]
    Pdr=[]
    fileObj=open(file_path)
    for line in fileObj.readlines(): 
         (time,distance,pdr)=line.split(" ")
         Time.append(time)
         Distance.append(distance)
         #Rssi.append(rssi)
         Pdr.append(pdr[:-1])
         #Y.append(Y1[:-1])
    pl.plot(Time,Distance, label="Distance")
    #pl.plot(Time,Rssi, label="RSSI")
    pl.plot(Time,Pdr, label="PDR")
    pl.legend();
    pl.savefig(output)
 
    ##QQ-plot
    
if __name__=="__main__":
    drawLine(sys.argv[1],sys.argv[2]) 
    
