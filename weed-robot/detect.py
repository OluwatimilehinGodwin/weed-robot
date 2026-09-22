import threading
import time

import cv2
import torch

from picamera2 import Picamera2
from ultralytics import YOLO

from robot_config import (
    CAMERA_SIZE,
    CAMERA_WARMUP_TIME,
    DETECTION_CONFIDENCE,
    DETECTION_IMAGE_SIZE,
    DETECTOR_STOP_TIMEOUT,
    JPEG_QUALITY,
    MODEL_PATH,
    YOLO_CPU_THREADS,
)


class WeedDetector:
    def __init__(self):
        cv2.setNumThreads(1)
        torch.set_num_threads(
            YOLO_CPU_THREADS
        )

        print(
            f"Loading YOLO model: "
            f"{MODEL_PATH}"
        )

        self.model = YOLO(
            str(MODEL_PATH)
        )

        self.latest_jpeg = None
        self.frame_id = 0

        self.weed_count = 0
        self.fps = 0.0

        self.running = False
        self.streaming = False

        self.latest_detections = {}
        self.last_inference_time = 0.0

        self._lock = (
            threading.Lock()
        )

        self._stop_event = (
            threading.Event()
        )

        self._thread = None

    def start(self):
        with self._lock:
            if self.running:
                return False

            self.running = True
            self.streaming = False

            self.latest_jpeg = None
            self.weed_count = 0
            self.fps = 0.0

            self.latest_detections = {}
            self.last_inference_time = 0.0

        self._stop_event.clear()

        self._thread = threading.Thread(
            target=self._run,
            name="yolo-detector",
            daemon=True,
        )

        self._thread.start()

        return True

    def stop(self):
        with self._lock:
            was_running = self.running

            self.latest_detections = {}
            self.last_inference_time = 0.0

        if not was_running:
            return False

        self._stop_event.set()

        thread = self._thread

        if thread is not None:
            thread.join(
                timeout=DETECTOR_STOP_TIMEOUT
            )

            if thread.is_alive():
                print(
                    "Detector stop is "
                    "still pending"
                )

                return False

        self._thread = None

        return True

    def _class_name(
        self,
        class_id,
    ):
        class_id = int(
            class_id
        )

        names = self.model.names

        if isinstance(
            names,
            dict,
        ):
            label = names.get(
                class_id,
                str(class_id),
            )
        else:
            try:
                label = names[class_id]
            except (
                IndexError,
                TypeError,
            ):
                label = str(
                    class_id
                )

        return (
            str(label)
            .strip()
            .lower()
        )

    def _extract_detection_state(
        self,
        result,
    ):
        detected = {}

        boxes = result.boxes

        if (
            boxes is None
            or boxes.cls is None
            or boxes.conf is None
        ):
            return detected

        class_ids = (
            boxes.cls
            .detach()
            .cpu()
            .tolist()
        )

        confidences = (
            boxes.conf
            .detach()
            .cpu()
            .tolist()
        )

        for (
            class_id,
            confidence,
        ) in zip(
            class_ids,
            confidences,
        ):
            label = self._class_name(
                class_id
            )

            confidence = float(
                confidence
            )

            detected[label] = max(
                detected.get(
                    label,
                    0.0,
                ),
                confidence,
            )

        return detected

    def _run(self):
        picam2 = None

        try:
            picam2 = Picamera2()

            camera_config = (
                picam2
                .create_video_configuration(
                    main={
                        "size":
                            CAMERA_SIZE,

                        "format":
                            "RGB888",
                    }
                )
            )

            picam2.configure(
                camera_config
            )

            picam2.start()

            time.sleep(
                CAMERA_WARMUP_TIME
            )

            previous_time = (
                time.perf_counter()
            )

            displayed_fps = 0.0

            while (
                not self._stop_event
                .is_set()
            ):
                frame = (
                    picam2.capture_array(
                        "main"
                    )
                )

                result = (
                    self.model.predict(
                        source=frame,
                        imgsz=(
                            DETECTION_IMAGE_SIZE
                        ),
                        conf=(
                            DETECTION_CONFIDENCE
                        ),
                        device="cpu",
                        verbose=False,
                    )[0]
                )

                current_detections = (
                    self
                    ._extract_detection_state(
                        result
                    )
                )

                inference_time = (
                    time.monotonic()
                )

                with self._lock:
                    self.latest_detections = (
                        current_detections
                    )

                    self.last_inference_time = (
                        inference_time
                    )

                annotated_frame = (
                    result.plot()
                )

                current_time = (
                    time.perf_counter()
                )

                elapsed = (
                    current_time
                    - previous_time
                )

                previous_time = (
                    current_time
                )

                current_fps = (
                    1 / elapsed
                    if elapsed > 0
                    else 0.0
                )

                if displayed_fps == 0:
                    displayed_fps = (
                        current_fps
                    )
                else:
                    displayed_fps = (
                        0.9 * displayed_fps
                        + 0.1 * current_fps
                    )

                detection_count = (
                    0
                    if result.boxes is None
                    else len(result.boxes)
                )

                cv2.putText(
                    annotated_frame,
                    (
                        f"FPS: "
                        f"{displayed_fps:.1f}"
                    ),
                    (15, 30),
                    cv2.FONT_HERSHEY_SIMPLEX,
                    0.7,
                    (255, 255, 255),
                    2,
                )

                cv2.putText(
                    annotated_frame,
                    (
                        f"Detections: "
                        f"{detection_count}"
                    ),
                    (15, 60),
                    cv2.FONT_HERSHEY_SIMPLEX,
                    0.7,
                    (255, 255, 255),
                    2,
                )

                (
                    success,
                    encoded_frame,
                ) = cv2.imencode(
                    ".jpg",
                    annotated_frame,
                    [
                        cv2.IMWRITE_JPEG_QUALITY,
                        JPEG_QUALITY,
                    ],
                )

                if not success:
                    continue

                with self._lock:
                    self.latest_jpeg = (
                        encoded_frame
                        .tobytes()
                    )

                    self.frame_id += 1

                    self.weed_count = (
                        detection_count
                    )

                    self.fps = (
                        displayed_fps
                    )

                    self.streaming = True

        except Exception as error:
            print(
                f"Detector error: "
                f"{error}"
            )

        finally:
            if picam2 is not None:
                try:
                    picam2.stop()
                except Exception:
                    pass

                try:
                    picam2.close()
                except Exception:
                    pass

            with self._lock:
                self.running = False
                self.streaming = False

                self.latest_jpeg = None

                self.weed_count = 0
                self.fps = 0.0

                self.latest_detections = {}
                self.last_inference_time = 0.0

            print(
                "Pi camera closed"
            )

    def get_frame(self):
        with self._lock:
            return (
                self.frame_id,
                self.latest_jpeg,
            )

    def get_stats(self):
        with self._lock:
            return {
                "running":
                    self.running,

                "streaming":
                    self.streaming,

                "weed_count":
                    self.weed_count,

                "fps":
                    self.fps,
            }

    def get_detection_state(self):
        with self._lock:
            return {
                "detections":
                    dict(
                        self.latest_detections
                    ),

                "timestamp":
                    self.last_inference_time,
            }


detector = WeedDetector()
