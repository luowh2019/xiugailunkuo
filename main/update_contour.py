import cv2
import numpy as np

# 轮廓修改类

class Update_contour():
    def __init__(self,img,contour):
        '''img == opencv格式的底片，contour == 需要修改的轮廓'''
        

        self.drawing = False # true if mouse is pressed
        self.mode = False # if True, draw rectangle. Press 'm' to toggle to curve
        self.ix,self.iy = -1,-1
        self.jx,self.jy = -1,-1
        self.contour =  contour
        self.wx = 600

        self.contours_poly = [None]
        # contour = contour.reshape(3)
        self.img = img

        self.img_for_show = self.img.copy()


        self.ini_array = self.contour
        self.updated_array = self.contour

        # 相对于原图像的轮廓向量
        self.transform_array = self.contour

        self.area = 0.0
        self.f = 1.0

        self.activate_function()
    def activate_function(self):
        cv2.namedWindow('Change_contour')
        self.img_zoom = self.img.copy()
        self.zoom_region = self.img.copy()

        # 在轮廓点处画红色实心圆圈
        #cv2.drawContours(self.img_for_show, self.updated_array, -1, (0,0,255),2,cv2.LINE_8)

        self.updated_draw()
        
        cv2.imshow('Change_contour',self.img_for_show)
        cv2.setMouseCallback('Change_contour',self.draw_circle)
        cv2.waitKey(0)

    def array_cal(self):
        '''删减向量的计算'''
        mask = np.ones(len(self.transform_array), dtype=bool)
        mask[self.index]=False
        self.updated_array = self.updated_array[mask,...]

        # 删减self.transform_array相同序号的点
        self.transform_array = self.transform_array[mask,...]

        # 更新self.contour,改进不能反复缩放问题
        self.contour = self.transform_array

    def updated_draw(self):
        self.img_for_show = self.zoom_region.copy()
        if (self.updated_array.any()==False):
            return
        else:
            

            # 在轮廓点处画红色实心圆圈
            cv2.drawContours(self.img_for_show, self.updated_array, -1, (0,0,255),2,cv2.LINE_8)

            # 画多边形
            self.contours_poly[0] = cv2.approxPolyDP(self.updated_array, 3, True)
            cv2.drawContours(self.img_for_show, self.contours_poly, 0, (0,255,0))

            self.area =  cv2.contourArea(self.contours_poly[0])
        cv2.imshow('Change_contour',self.img_for_show)
    # mouse callback function
    def draw_circle(self,event,x,y,flags,param):
        #global ix,iy,drawing,mode,img,contour
        self.index=[]
        if event == cv2.EVENT_LBUTTONDOWN:
            self.drawing = True
            self.ix,self.iy = x,y
            # self.img_for_show = self.zoom_region.copy()

        elif event == cv2.EVENT_MOUSEMOVE:
            if self.drawing == True:
                # 鼠标移动时画红色矩形
                self.updated_draw()
                cv2.rectangle(self.img_for_show,(self.ix,self.iy),(x,y),(0,0,255),-1)
                
                # 同时绘制红色圆圈及多边形
                
                cv2.imshow('Change_contour',self.img_for_show)
                # 显示图像，self.img_for_show 已被更改
                #cv2.imshow('Change_contour',self.img_for_show)
        elif event == cv2.EVENT_LBUTTONUP:
            self.drawing = False
            self.jx,self.jy = x,y
            cv2.imshow('Change_contour',self.img_for_show)              

            for k in range(len(self.transform_array)):
                # 三重循环，计算卡慢
                # for i in range(self.ix,x+1):
                #     for j in range(self.iy,y+1):
                #         # self.new_array = np.vstack((self.new_array,[[[i,j],],]))
                #         a = np.any(self.updated_array[k]-np.array([[i,j],]),axis=0)
                #         if ((np.any(a))==False):
                #             self.index.append(k)      
                
                # 逐个元素判断，相对较快
                if(self.updated_array[k][0][0]<=x and self.updated_array[k][0][0]>=self.ix):
                    if(self.updated_array[k][0][1]<=y and self.updated_array[k][0][1]>=self.iy):
                        self.index.append(k)
            # 删除矩形框内的点
            self.array_cal()

            # 更新图像,还原self.img_for_show，展示新轮廓，点
            self.updated_draw()

        elif event == cv2.EVENT_RBUTTONDOWN:
            # # 先更新显示
            # self.updated_draw()

            # 再画圆
            cv2.circle(self.img_for_show,(x,y),5,(0,0,255),-1)

            # 绘制完成后展示
            cv2.imshow('Change_contour',self.img_for_show)  

            # 添加点的向量运算
            b = np.array([[[x,y],],])

            distances = np.linalg.norm(self.updated_array-b,axis=1)
            distances2 = np.linalg.norm(distances,axis=1)

            closest_index = np.argmin(distances2)
            # 复制closest_index后的向量
            temp_array_u = self.updated_array[closest_index+1:-1]

            #删除closest_index后的向量   
            self.updated_array = np.delete(self.updated_array,
                range(closest_index+1,len(self.updated_array)),axis=0)

            # 假定新增的向量在index之后
            self.updated_array = np.vstack((self.updated_array,b))
            self.updated_array = np.vstack((self.updated_array,temp_array_u))

            # 对self.transform_array作相同的处理，注意b2的值
            b2 = np.array([[[x+self.img_zoom.shape[1]-self.zoom_region.shape[1],
                y+self.img_zoom.shape[0]-self.zoom_region.shape[0]],],])
            temp_array_t = self.transform_array[closest_index+1:-1]
            
            self.transform_array = np.delete(self.transform_array,
                range(closest_index+1,len(self.transform_array)),axis=0)
            self.transform_array = np.vstack((self.transform_array,b2))
            self.transform_array = np.vstack((self.transform_array,temp_array_t))

            # 更新self.contour,改进不能反复缩放问题
            self.contour = (self.transform_array/self.f).astype(int)


            # 更新显示
            self.updated_draw()
            
        elif event == cv2.EVENT_MOUSEWHEEL:  # 如果是滑动鼠标滚轮
            self.mode = True
            if flags > 0:  # 如果鼠标滚轮向上滑动
                self.f += 0.1  # 缩放比例增加
                if self.f>5:
                    self.f = 5 # 缩放比例不能大于5
            elif flags < 0:  # 如果鼠标滚轮向下滑动
                self.f -= 0.1  # 缩放比例减少
                if self.f <= 0.2:  # 缩放比例不能小于0.2
                    self.f = 0.2

            #self.zoom_region = self.img_for_show.copy()                
            self.img_zoom = cv2.resize(self.img, None, fx=self.f, fy=self.f)  # 对原图进行缩放
            

            self.zoom_region = self.img_zoom[int(self.f*y-y):, int(self.f*x-x):]
            self.updated_array =(self.contour*self.f-np.array([self.img_zoom.shape[1]-self.zoom_region.shape[1],
                self.img_zoom.shape[0]-self.zoom_region.shape[0]])).astype(int)


            # 对self.transform_array作放大的处理
            self.transform_array = (self.contour*self.f).astype(int)
            self.updated_draw()