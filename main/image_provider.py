from PySide6.QtQuick import QQuickImageProvider
from PySide6.QtGui import QImage
import threading

class OpenCVImageProvider(QQuickImageProvider):
    def __init__(self):
        super().__init__(QQuickImageProvider.Image)
        self.images = {}
        self.lock = threading.Lock()

    def update(self, key, img):
        with self.lock:
            self.images[key] = img.copy()

    def requestImage(self, key, size, requestedSize):
        with self.lock:
            # 兼容带序号前缀的 URI：image://opencv/v{seq}/{real_key}，
            # 去掉 v{seq}/ 后按真实 key 取图；旧格式无前缀时直接使用
            real_key = key
            if "/" in key:
                head, _, rest = key.partition("/")
                if head.startswith("v") and head[1:].isdigit():
                    real_key = rest
            img = self.images.get(real_key)
            if img is None:
                return QImage()
            h, w = img.shape[:2]
            qimg = QImage(img.data, w, h, img.strides[0], QImage.Format_BGR888).copy()
            if size is not None:
                size.setWidth(w)
                size.setHeight(h)
            return qimg
