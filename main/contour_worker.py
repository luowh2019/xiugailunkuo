from PySide6.QtCore import QObject, Signal, Slot
import cv2
import numpy as np

class ContourWorker(QObject):
    finished = Signal(object)

    @Slot(object,int)
    def process(self, img, threshold):
        gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
        gray = cv2.blur(gray,(3,3))
        edge = cv2.Canny(gray, threshold, threshold*2)
        kernel=np.ones((3,3),np.uint8)
        edge=cv2.dilate(edge,kernel,iterations=2)
        edge=cv2.erode(edge,kernel,iterations=2)
        contours,_=cv2.findContours(edge,cv2.RETR_EXTERNAL,cv2.CHAIN_APPROX_SIMPLE)
        result=img.copy()
        cv2.drawContours(result,contours,-1,(0,0,255),2)
        self.finished.emit((result,contours))
