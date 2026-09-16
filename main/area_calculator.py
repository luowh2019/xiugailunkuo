from PySide6.QtCore import QObject, QTimer, QUrl, Signal, Slot, Qt, QThread,Property
import numpy as np
import cv2
import random as rng
import io
from PIL import Image

# ============================================================
# 轮廓提取方法库：每种方法含一组可调参数
#   key   参数唯一标识（QML 通过 key 传值）
#   label 界面显示名
#   value/min/max/step 滑杆默认值 / 范围 / 步长
#   min_area 所有方法共有的最小面积过滤（0 = 不过滤，用于去噪）
# ============================================================
CONTOUR_METHODS = {
    "canny": {
        "label": "Canny 边缘",
        "params": [
            {"key": "low",      "label": "低阈值",   "value": 50,   "min": 1,    "max": 255,   "step": 1},
            {"key": "high",     "label": "高阈值",   "value": 150,  "min": 1,    "max": 255,   "step": 1},
            {"key": "min_area", "label": "最小面积", "value": 0,    "min": 0,    "max": 10000, "step": 50},
        ],
    },
    "binary": {
        "label": "固定阈值",
        "params": [
            {"key": "thresh",   "label": "阈值",     "value": 127,  "min": 1,    "max": 255,   "step": 1},
            {"key": "min_area", "label": "最小面积", "value": 0,    "min": 0,    "max": 10000, "step": 50},
        ],
    },
    "adaptive": {
        "label": "自适应阈值",
        "params": [
            {"key": "block",    "label": "邻域",     "value": 11,   "min": 3,    "max": 51,    "step": 2},
            {"key": "c",        "label": "常数C",    "value": 5,    "min": 0,    "max": 30,    "step": 1},
            {"key": "min_area", "label": "最小面积", "value": 0,    "min": 0,    "max": 10000, "step": 50},
        ],
    },
    "sobel": {
        "label": "Sobel 梯度",
        "params": [
            {"key": "ksize",    "label": "核大小",   "value": 3,    "min": 1,    "max": 7,     "step": 2},
            {"key": "thresh",   "label": "梯度阈值", "value": 100,  "min": 1,    "max": 255,   "step": 1},
            {"key": "min_area", "label": "最小面积", "value": 0,    "min": 0,    "max": 10000, "step": 50},
        ],
    },
    "laplacian": {
        "label": "Laplacian",
        "params": [
            {"key": "ksize",    "label": "核大小",   "value": 3,    "min": 1,    "max": 7,     "step": 2},
            {"key": "thresh",   "label": "响应阈值", "value": 50,   "min": 1,    "max": 255,   "step": 1},
            {"key": "min_area", "label": "最小面积", "value": 0,    "min": 0,    "max": 10000, "step": 50},
        ],
    },
}

class AreaCalculator(QObject):
    """面积计算逻辑类，暴露给QML调用"""
    # 信号：更新面积显示
    areaUpdated = Signal(float)
    # 信号：更新点坐标显示
    pointsUpdated = Signal(list)

    #信号：更新参数
    canshuUpdated = Signal()

    # 双向绑定的信号
    # 信号 轮廓索引


    # 信号 轮廓数量
    
    def __init__(self, provider=None):
        super().__init__()
        self.provider = provider
        self._points = None  # 存储点坐标 [(x1,y1), (x2,y2), ...]
        self.updated_contour = []
        # [img_0],[]
        self.img_cache = {}
        self.max_cache = 20
        self.i = -1

        # 用于存图片
        self.current_image_key = ""

        # 轮廓编辑撤销栈
        self.undo_stack = []
        self.max_undo = 30

        # 图片 URI 递增序号：每次生成全新 URI，强制 QML Image 重新加载
        self.img_seq = 0

        # ---- 轮廓提取：方法 + 参数（点击「显示轮廓」后才执行） ----
        self.contour_method = "canny"   # 当前提取方法
        self.contour_params = {p["key"]: p["value"]
                               for p in CONTOUR_METHODS["canny"]["params"]}
        self.contour_extracted = False  # 是否已提取过轮廓（决定参数改动是否自动重算）
        self.contours = []              # 最新提取的轮廓列表
        self.len_contour = 0

        # 编辑模式兜底默认值
        self._points = None
        self.pix_scale = 1.0
        self.sw = 1.0
        self.sh = 1.0

    def _reset_contour_state(self, clear_cache=True):
        """清空轮廓提取结果，使「显示轮廓」需要重新执行"""
        self.i = -1
        self.contours = []
        self.updated_contour = []
        self.len_contour = 0
        self.contour_extracted = False
        self.undo_stack.clear()
        if clear_cache:
            self.img_cache.clear()

    def img_clear(self):
        self.i = -1
        self.img_cache.clear()
        self.updated_contour = []
        self.current_image_key = ""
        self._reset_contour_state(clear_cache=False)
    def process_image_fast(self,img_name,img):
        # 生成唯一key
        key = img_name

        if key in self.img_cache:
            return self.img_cache[key]

        # 图片通过 image://opencv 提供器直接传原始 OpenCV 数组，
        # 不再走 base64/JPEG 编码链路
        # 带序号前缀的 URI：image://opencv/v{序号}/{key}
        # QML 侧 Image.source 每次变化，强制重新请求图片，避免换图后仍显示旧图
        self.img_seq += 1
        uri = f"image://opencv/v{self.img_seq}/{key}"
        if self.provider:
            self.provider.update(key, img)

        # 6. 存入缓存
        self.img_cache[key] = uri
        if len(self.img_cache) > self.max_cache:
            oldest = next(iter(self.img_cache))
            del self.img_cache[oldest]
        # return uri
    @Slot(list)
    def get_crop(self,crop):
        self.crop = crop
        self.img_cv = self.img_cv[self.crop[1]:self.crop[3],self.crop[0]:self.crop[2]]
        # 裁剪后只保留原图，轮廓需重新点击「显示轮廓」提取
        self._reset_contour_state(clear_cache=True)
        self.process_image_fast("img", self.img_cv)
    @Slot(str)
    def get_i(self,i):
        self.i = int(i)
    @Slot(str)
    def get_pix(self,pix):
        try:
            self.pix_scale = float(pix)
        except (TypeError, ValueError):
            self.pix_scale = 1.0
    @Slot(float)
    def get_scalew(self,w):
        self.sw = w
    @Slot(float)
    def get_scaleh(self,h):
        self.sh = h
    @Slot()
    def get_jx(self):
        self.img_cv = cv2.flip(self.img_cv,1)
        # 变换后只保留原图，轮廓需重新提取
        self._reset_contour_state(clear_cache=True)
        self.process_image_fast("img", self.img_cv)
    @Slot()
    def get_90(self):
        self.img_cv = cv2.rotate(self.img_cv,cv2.ROTATE_90_CLOCKWISE)
        self._reset_contour_state(clear_cache=True)
        self.process_image_fast("img", self.img_cv)

    @Slot(int,bool,result=list)
    def index_cal(self,index,increase):
        """按方向切换轮廓索引，返回 [新索引, 该方向是否还能继续]"""
        n = getattr(self, "len_contour", 0)
        if n <= 0:
            return [-1, True]
        if index < 0 or index >= n:
            # 尚未定位：下一个→第0个；上一个→最后一个
            self.i = 0 if increase else n - 1
        elif increase:
            self.i = index + 1
        else:
            self.i = index - 1
        self.i = max(0, min(self.i, n - 1))
        can_continue = (self.i < n - 1) if increase else (self.i > 0)
        return [self.i, can_continue]

    @Slot(str,result=str)
    def get_img(self,key):
        # 按需重建可能被缓存淘汰的关键图
        if key == "img" and hasattr(self, "img_cv") and self.img_cv is not None:
            self.process_image_fast("img", self.img_cv)
        elif key == "all" and getattr(self, "contour_extracted", False) and hasattr(self, "contours"):
            img_all = self.img_cv.copy()
            cv2.drawContours(img_all, self.contours, -1, (0, 0, 255), 2)
            self.process_image_fast("all", img_all)
        elif key.startswith("contour") and key[7:].isdigit():
            idx = int(key[7:])
            if key not in self.img_cache and 0 <= idx < self.len_contour:
                img = self.img_cv.copy()
                color = (rng.randint(0,256), rng.randint(0,256), rng.randint(0,256))
                cv2.drawContours(img, self.updated_contour, idx, color, 2)
                self.process_image_fast(key, img)

        if key in self.img_cache:
            self.current_image_key = key
            return self.img_cache[key]
        return ""

    # 点击“修改轮廓时”激活
    # get_canshu(croped,crop_array,scale_w,scale_h,pixinput.text)
    @Slot(bool,list,float,float,str)
    def get_canshu(self,croped,crop,sw,sh,pix):
        self.cropped = croped
        self.crop = crop

        try:
            self.pix_scale = float(pix)
        except (TypeError, ValueError):
            self.pix_scale = 1.0
        # 缩放比例兜底：图片尺寸未就绪时 sw/sh 为 0，避免除零
        self.sw = sw if (sw and sw > 0) else 1.0
        self.sh = sh if (sh and sh > 0) else 1.0

        # 尚未提取轮廓时直接返回（导入/裁剪后仅显示图像）
        if (not getattr(self, "updated_contour", None) or
                getattr(self, "len_contour", 0) == 0):
            return

        # 索引越界保护
        if self.i < 0 or self.i >= self.len_contour:
            self.i = 0

        # 每一次的退出都需要重新计算
        self._points = self.updated_contour[self.i]*[1/self.sw,1/self.sh]

        # 进入编辑模式时清空撤销栈
        self.undo_stack.clear()

        # 将点集发送给QML
        self.canshuUpdated.emit()
        self.pointsUpdated.emit(self._points.tolist())
    @Slot(result=str)
    def draw_contour(self):
        if self.i == -1:
            self.i = 0
        color = (rng.randint(0,256), rng.randint(0,256), rng.randint(0,256))
        self.img_show = self.img_cv.copy()
            # --------------------------
        # 安全判断：轮廓存在 + 索引有效
        # --------------------------
        if (not hasattr(self, 'updated_contour') or 
            self.updated_contour is None or 
            len(self.updated_contour) == 0 or
            self.i < 0 or self.i >= len(self.updated_contour)):
            return

        # --------------------------
        # 取出【你指定的那一个轮廓】
        # --------------------------
        single_contour = self.updated_contour[self.i]

        # # --------------------------
        # # 1. 计算面积（浮点，精准）
        # # --------------------------
        # area = cv2.contourArea(single_contour)
        # print(f"第 {self.i} 个轮廓面积 =", area)

        # --------------------------
        # 2. 标准化轮廓格式 + 转整数（画图必备）
        # --------------------------
        
        contour = np.array(single_contour, dtype=np.float32).reshape(-1, 1, 2)
        contour_int = np.int32(contour)

        # --------------------------
        # 3. 只画这一个轮廓（不报错）
        # --------------------------
        cv2.drawContours(self.img_show, [contour_int], 0, color, 1)
        # except Exception as e:
        #     print("绘制异常:", e)

        k = "xg"+str(self.i)
        # print(k)
        if k in self.img_cache:
            del self.img_cache[k]
        self.process_image_fast(k,self.img_show)

        self.current_image_key = k
        return self.img_cache[k]
    @Slot(str)
    def save_img(self, save_path):
        try:
            # 1. 从图片提供器中取出当前显示的 OpenCV 图像
            img = None
            key = self.current_image_key
            if key.startswith("image://opencv/"):
                key = key.split("image://opencv/", 1)[-1]
            if self.provider is not None:
                with self.provider.lock:
                    img = self.provider.images.get(key)
            if img is None and hasattr(self, "img_cv"):
                img = self.img_cv
            if img is None:
                return

            # 2. 编码为 PNG 写入文件（兼容中文路径）
            ok, buf = cv2.imencode('.png', img)
            if ok:
                with open(save_path, "wb") as f:
                    f.write(buf.tobytes())
        except Exception:
            pass
    @Slot(str)
    def get_file(self,f):
        # 兼容两种传入：file:/// 前缀（文件对话框）或纯路径（拖拽打开）
        if f.startswith("file:///"):
            self.file_path = f[8:]
        else:
            self.file_path = f
        if not self.file_path.strip():
            return
        # 只加载图像，不做任何轮廓处理（点击「显示轮廓」后才提取）
        self.img_clear()
        img_gt = cv2.imdecode(np.fromfile(self.file_path,dtype=np.uint8),-1)
        self.img_cv = img_gt if img_gt is not None else None
        if self.img_cv is None:
            return
        self.process_image_fast("img", self.img_cv)
        
    @Slot(result=list)
    def get_img_size(self):
        """返回当前图像的像素尺寸 [宽, 高]；未加载时为 [0, 0]"""
        if hasattr(self, "img_cv") and self.img_cv is not None:
            h, w = self.img_cv.shape[:2]
            return [int(w), int(h)]
        return [0, 0]

    # 按当前方法 + 参数提取轮廓
    def get_contours(self):
        edge = self._compute_edges()
        self.contours, self.hierarchy = cv2.findContours(edge,
            cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)

        # 最小面积过滤（去噪）
        min_area = float(self.contour_params.get("min_area", 0))
        if min_area > 0:
            self.contours = [c for c in self.contours if cv2.contourArea(c) >= min_area]

        self.len_contour = len(self.contours)
        self.contour_extracted = True

        self.area_xiugai = [None]*self.len_contour
        self.updated_contour = [None]*self.len_contour

        # 绘制所有轮廓
        self.process_image_fast("img", self.img_cv)          # 原图
        img_all = self.img_cv.copy()
        cv2.drawContours(img_all, self.contours, -1, (0, 0, 255), 2)
        self.process_image_fast("all", img_all)              # 所有轮廓图
        for i in range(self.len_contour):
            self.area_xiugai[i] = cv2.contourArea(self.contours[i])
            self.updated_contour[i] = self.contours[i]
            if i < 10:
                img = self.img_cv.copy()
                color = (rng.randint(0,256), rng.randint(0,256), rng.randint(0,256))
                cv2.drawContours(img, self.updated_contour, i, color, 2)
                self.process_image_fast("contour"+str(i), img)

    # 根据当前方法 + 参数生成二值边缘图
    def _compute_edges(self):
        img = self.img_cv
        gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
        gray = cv2.blur(gray, (3, 3))
        p = self.contour_params
        method = self.contour_method

        if method == "canny":
            low = int(p["low"]); high = int(p["high"])
            if high < low:
                high = low
            edge = cv2.Canny(gray, low, high)
            kernel = np.ones((3, 3), np.uint8)
            edge = cv2.dilate(edge, kernel, iterations=1)
            edge = cv2.erode(edge, kernel, iterations=1)
            return edge
        if method == "binary":
            _, edge = cv2.threshold(gray, int(p["thresh"]), 255, cv2.THRESH_BINARY)
            return edge
        if method == "adaptive":
            block = int(p["block"])
            if block < 3:
                block = 3
            if block % 2 == 0:
                block += 1
            edge = cv2.adaptiveThreshold(gray, 255, cv2.ADAPTIVE_THRESH_GAUSSIAN_C,
                                         cv2.THRESH_BINARY, block, int(p["c"]))
            return edge
        if method == "sobel":
            k = int(p["ksize"])
            gx = cv2.Sobel(gray, cv2.CV_32F, 1, 0, ksize=k)
            gy = cv2.Sobel(gray, cv2.CV_32F, 0, 1, ksize=k)
            mag = cv2.magnitude(gx, gy)
            mag = cv2.convertScaleAbs(mag)
            _, edge = cv2.threshold(mag, int(p["thresh"]), 255, cv2.THRESH_BINARY)
            return edge
        if method == "laplacian":
            k = int(p["ksize"])
            lap = cv2.Laplacian(gray, cv2.CV_32F, ksize=k)
            lap = cv2.convertScaleAbs(lap)
            _, edge = cv2.threshold(lap, int(p["thresh"]), 255, cv2.THRESH_BINARY)
            return edge
        # 兜底：Canny 默认参数
        return cv2.Canny(gray, 50, 150)

    # 用户点击「显示轮廓」：提取并返回"所有轮廓"图的 URI
    @Slot(result=str)
    def run_contours(self):
        if not hasattr(self, "img_cv") or self.img_cv is None:
            return ""
        self.img_cache.clear()   # 强制重算，避免命中旧图缓存
        self.get_contours()
        return self.get_img("all")

    # 切换轮廓提取方法；若已提取过轮廓则自动重算
    @Slot(str,result=str)
    def set_contour_method(self, method):
        if method in CONTOUR_METHODS:
            self.contour_method = method
            self.contour_params = {p["key"]: p["value"]
                                   for p in CONTOUR_METHODS[method]["params"]}
        if self.contour_extracted:
            return self.run_contours()
        return ""

    # 修改某个参数；若已提取过轮廓则自动重算
    @Slot(str,float,result=str)
    def set_contour_param(self, key, value):
        if key in self.contour_params:
            self.contour_params[key] = float(value)
        if self.contour_extracted:
            return self.run_contours()
        return ""

    # 返回方法列表 ["key|显示名", ...]
    @Slot(result=list)
    def get_contour_methods(self):
        return [f"{k}|{v['label']}" for k, v in CONTOUR_METHODS.items()]

    # 返回当前方法的参数列表 [{key,label,value,min,max,step}, ...]
    @Slot(result=list)
    def get_contour_params(self):
        result = []
        for p in CONTOUR_METHODS[self.contour_method]["params"]:
            d = dict(p)
            d["value"] = self.contour_params.get(p["key"], p["value"])
            result.append(d)
        return result

    @Slot(result=int)
    def get_contour_count(self):
        return int(getattr(self, "len_contour", 0))

    @Slot(result=bool)
    def has_contours(self):
        return bool(getattr(self, "contour_extracted", False))
    
    @Slot(float, float,float, float)
    def delete_batch_by_rect(self, x1, y1, x2, y2):
        """
        框选矩形批量删除轮廓顶点
        :param x1,y1: 选区左上角
        :param x2,y2: 选区右下角
        """
        if self._points is None or len(self._points) <= 5:
            if self._points is not None:
                self.pointsUpdated.emit(self._points.tolist())
            return

        # 记录撤销
        self._push_undo()

        # 统一选区范围
        min_x = min(x1, x2)
        max_x = max(x1, x2)
        min_y = min(y1, y2)
        max_y = max(y1, y2)

        pts = self._points[:, 0, :]
        # 判断点是否在矩形内
        in_rect_mask = ~((pts[:,0] >= min_x) & (pts[:,0] <= max_x) &
                        (pts[:,1] >= min_y) & (pts[:,1] <= max_y))

        # 保留不在选区内的点，最少保留5个
        new_contour = self._points[in_rect_mask]
        if len(new_contour) < 5:
            self.pointsUpdated.emit(self._points.tolist())
            return

        self._points = new_contour
        self.pointsUpdated.emit(self._points.tolist())
        # 计算面积并发送至qml
        self.get_contour_area()
    @Slot(float, float)
    def addPoint(self, x, y):
        """QML调用：添加一个点"""
        if self._points is None:
            return

        # 记录撤销
        self._push_undo()

        # 添加点的向量运算
        self.b = np.array([[[x,y],],])
        # 用于显示的向量
        self._points = self.fast_insert_point(self._points,self.b[0][0])

        # 更新点坐标
        self.pointsUpdated.emit(self._points.tolist())
        # 计算面积并发送至qml
        self.get_contour_area()

    # 删除离鼠标最近的轮廓顶点
    @Slot(float, float)
    def delete_nearest_point(self, x, y):
        if self._points is None or len(self._points) <= 3:
            if self._points is not None:
                self.pointsUpdated.emit(self._points.tolist())
            return

        # 记录撤销
        self._push_undo()

        pts = self._points[:, 0, :]
        click_pt = np.array([x, y])
        dists = np.linalg.norm(pts - click_pt, axis=1)
        del_idx = np.argmin(dists)

        # 删除对应行
        self._points = np.delete(self._points, del_idx, axis=0)
        self.pointsUpdated.emit(self._points.tolist())
        # 计算面积并发送至qml
        self.get_contour_area()

    # 撤销上一次轮廓编辑操作
    @Slot()
    def undo_edit(self):
        """撤销一次添加/删除顶点的操作"""
        if not self.undo_stack:
            return
        self._points = self.undo_stack.pop()
        self.pointsUpdated.emit(self._points.tolist())
        self.get_contour_area()

    def _push_undo(self):
        """把当前点集压入撤销栈"""
        if self._points is None:
            return
        self.undo_stack.append(self._points.copy())
        if len(self.undo_stack) > self.max_undo:
            self.undo_stack.pop(0)

    # 点到线段距离
    def _seg_dist(self, p, a, b):
        ap = p - a
        ab = b - a
        t = np.dot(ap, ab) / (np.dot(ab, ab) + 1e-8)
        t = np.clip(t, 0, 1)
        proj = a + t * ab
        return np.linalg.norm(p - proj)

    # 对外获取轮廓
    def get_contour(self):
        return self._points.tolist()
    
    # ----------------------
    # 🔥 核心优化：快速插入
    # ----------------------
    def fast_insert_point(self, contour, new_point, k=5):
        n = len(contour) if contour is not None else 0
        if n == 0:
            return np.array([[[new_point[0], new_point[1]]]], dtype=np.float32)
        if n < 6:
            return np.insert(contour, 0, self.b, axis=0)

        # 1. 把轮廓展平 (N,2) —— 超快
        pts = contour[:, 0, :]

        # 2. 🔥 向量计算所有距离（numpy 底层C加速，10万点也不卡）
        dists = np.linalg.norm(pts - new_point, axis=1)

        # 3. 🔥 只取最近的 k 个点（默认3个，足够准）
        topk_idx = np.argpartition(dists, k)[:k]
        topk_idx = np.sort(topk_idx)  # 排序保证顺序

        # 4. 🔥 只检查这几个点的前后边（遍历 3~5 次，结束！）
        min_dist = float('inf')
        insert_idx = 0
        for i in topk_idx:
            # 检查 i 这条边
            a = pts[i]
            b = pts[(i+1)%n]
            d = self._seg_dist(new_point, a, b)
            if d < min_dist:
                min_dist = d
                insert_idx = i+1

        # 安全插入
        insert_idx = min(insert_idx, n)
        new_contour = np.insert(contour, insert_idx, self.b, axis=0)
        return new_contour

        # --------------------------
    # 🔥 新增：OPENCV 计算轮廓面积
    # --------------------------
    @Slot()
    def get_contour_area(self):
        if len(self._points) < 3:
            area = 0.0
            return self.areaUpdated.emit(area)
        try:
            # 1. 先将点转化至原图上
            points_0 = self._points*[self.sw,self.sh]

            # 2. 强制转换成 opencv 要求的格式：np.float32 + (N,1,2)
            contour_clean = points_0.astype(np.float32).reshape(-1, 1, 2)
            self.updated_contour[self.i] = contour_clean

            # 3. 用 OpenCV 计算面积
            area = cv2.contourArea(contour_clean)

            # 4. 乘以比例系数
            area = round(area*self.pix_scale, 2)
            self.area_xiugai[self.i] = area
            return self.areaUpdated.emit(area)

        except:
            area = 0.0
            return self.areaUpdated.emit(area)
        
        
        
    @Slot()
    def clearPoints(self):
        """QML调用：清空所有点"""
        self._points.clear()
        self.areaUpdated.emit(0.0)
        self._update_points_display()
        
    
    def _update_points_display(self):
        """更新点坐标显示文本"""
        if not self._points.any():
            display_text = "已绘制点：无"
        else:
            display_text = "已绘制点："
            # 只显示前10个点避免文本过长
            for i, [[x, y]] in enumerate(self._points[:10]):
                display_text += f"({x:.1f},{y:.1f}) "
            if len(self._points) > 10:
                display_text += f"... 共{len(self._points)}个点"
        
        self.pointsUpdated.emit(display_text)