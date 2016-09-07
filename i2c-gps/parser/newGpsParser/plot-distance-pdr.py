import numpy as np
import pylab as pl
import sys

def drawLine(file_path, output):
    Distance=[]
    Pdr=[]
    Count=[]
    fileObj=open(file_path)
    for line in fileObj.readlines(): 
         (distance,pdr)=line.split(" ")
         Distance.append(distance)
         Pdr.append(pdr[:-1])
         #Y.append(Y1[:-1])
    pl.plot(Distance,Pdr, label="PDR")
    pl.legend();
    pl.savefig(output)
    

if __name__=="__main__":
    drawLine(sys.argv[1],sys.argv[2]) 
