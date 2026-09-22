import itertools
import os
import queue
import threading
import time

import serial

from robot_config import (
    ESP_BAUD_RATE,
    ESP_HEARTBEAT_INTERVAL,
    ESP_RECONNECT_INTERVAL,
    ESP_SERIAL_PORT,
    ESP_WORKER_POLL_INTERVAL,
)


class EspLink:
    def __init__(self):
        self._port = os.environ.get(
            "TIMIREX_ESP_PORT",
            ESP_SERIAL_PORT,
        )

        self._serial = None
        self._thread = None

        self._stop_event = threading.Event()

        self._tx_queue = queue.PriorityQueue()
        self._sequence = itertools.count()

        self._state_lock = threading.Lock()

        self._connected = False
        self._last_error = None

        self._last_rx_line = ""
        self._last_rx_time = 0.0

        self._last_tx_line = ""
        self._last_tx_time = 0.0

        self._last_hb_ack_time = 0.0

        self._last_ack = ""
        self._last_nack = ""

        self._nav_mode = "STOP"
        self._nav_steer_deg = 0.0
        self._nav_left_percent = 0.0
        self._nav_right_percent = 0.0
        self._nav_dead_end = False
        self._nav_lidar_healthy = False
        self._nav_update_time = 0.0

        self._pose_x_m = 0.0
        self._pose_y_m = 0.0
        self._pose_heading_deg = 0.0
        self._pose_distance_m = 0.0
        self._pose_update_time = 0.0

        self._last_event = ""
        self._last_event_time = 0.0

        self._rx_buffer = bytearray()

        self._pose_queue = queue.Queue(
            maxsize=512,
        )

        self._event_queue = queue.Queue(
            maxsize=32,
        )

    @property
    def connected(self):
        with self._state_lock:
            return self._connected

    def start(self):
        if (
            self._thread is not None
            and self._thread.is_alive()
        ):
            return

        self._stop_event.clear()

        self._thread = threading.Thread(
            target=self._worker,
            name="esp-uart",
            daemon=True,
        )

        self._thread.start()

    def stop(self):
        if (
            self._thread is not None
            and self._thread.is_alive()
        ):
            self._enqueue(
                "MOVE,STOP",
                priority=0,
                allow_disconnected=True,
            )

            time.sleep(0.03)

        self._stop_event.set()

        if self._thread is not None:
            self._thread.join(
                timeout=1.0,
            )

            self._thread = None

        self._close_serial()

    def send(
        self,
        command,
        priority=5,
    ):
        if not self.connected:
            return False

        self._enqueue(
            command,
            priority=priority,
            allow_disconnected=True,
        )

        return True

    def _enqueue(
        self,
        command,
        priority,
        allow_disconnected=False,
    ):
        command = command.strip()

        if not command:
            return

        if (
            not allow_disconnected
            and not self.connected
        ):
            return

        self._tx_queue.put(
            (
                priority,
                next(self._sequence),
                command,
            )
        )

    def _clear_queue(self, target_queue):
        while True:
            try:
                target_queue.get_nowait()
            except queue.Empty:
                break

    def _clear_tx_queue(self):
        self._clear_queue(
            self._tx_queue
        )

    def _clear_pose_queue(self):
        self._clear_queue(
            self._pose_queue
        )

    def _clear_event_queue(self):
        self._clear_queue(
            self._event_queue
        )

    def _put_bounded(
        self,
        target_queue,
        item,
    ):
        try:
            target_queue.put_nowait(
                item
            )

        except queue.Full:
            try:
                target_queue.get_nowait()
            except queue.Empty:
                pass

            try:
                target_queue.put_nowait(
                    item
                )
            except queue.Full:
                pass

    def _set_connection_state(
        self,
        connected,
        error=None,
    ):
        with self._state_lock:
            self._connected = connected
            self._last_error = error

    def _reset_received_state(self):
        self._rx_buffer.clear()

        self._clear_pose_queue()
        self._clear_event_queue()

        with self._state_lock:
            self._last_rx_line = ""
            self._last_rx_time = 0.0

            self._last_hb_ack_time = 0.0

            self._last_ack = ""
            self._last_nack = ""

            self._nav_mode = "STOP"
            self._nav_steer_deg = 0.0
            self._nav_left_percent = 0.0
            self._nav_right_percent = 0.0
            self._nav_dead_end = False
            self._nav_lidar_healthy = False
            self._nav_update_time = 0.0

            self._pose_x_m = 0.0
            self._pose_y_m = 0.0
            self._pose_heading_deg = 0.0
            self._pose_distance_m = 0.0
            self._pose_update_time = 0.0

            self._last_event = ""
            self._last_event_time = 0.0

    def _open_serial(self):
        try:
            self._serial = serial.Serial(
                self._port,
                ESP_BAUD_RATE,
                timeout=0,
                write_timeout=0.05,
            )

            self._clear_tx_queue()
            self._reset_received_state()

            safe_commands = (
                "MOVE,STOP",
                "AUTO_INHIBIT,1",
                "MODE,MANUAL",
            )

            if not all(
                self._write_line(command)
                for command in safe_commands
            ):
                return False

            self._set_connection_state(
                True,
                None,
            )

            print(
                f"ESP UART connected: "
                f"{self._port}"
            )

            return True

        except Exception as error:
            self._serial = None

            self._set_connection_state(
                False,
                str(error),
            )

            return False

    def _close_serial(self):
        serial_port = self._serial
        self._serial = None

        if serial_port is not None:
            try:
                serial_port.close()
            except Exception:
                pass

        self._rx_buffer.clear()

        with self._state_lock:
            error = self._last_error

        self._set_connection_state(
            False,
            error,
        )

    def _write_line(
        self,
        command,
    ):
        if self._serial is None:
            return False

        try:
            payload = (
                f"{command}\n"
                .encode("ascii")
            )

            self._serial.write(
                payload
            )

            with self._state_lock:
                self._last_tx_line = command
                self._last_tx_time = (
                    time.monotonic()
                )

            return True

        except Exception as error:
            self._set_connection_state(
                False,
                str(error),
            )

            self._close_serial()

            return False

    def _handle_rx_line(
        self,
        line,
    ):
        now = time.monotonic()

        with self._state_lock:
            self._last_rx_line = line
            self._last_rx_time = now

        if line == "HB_ACK":
            with self._state_lock:
                self._last_hb_ack_time = now

            return

        if line.startswith("ACK,"):
            with self._state_lock:
                self._last_ack = line

            return

        if line.startswith("NACK,"):
            with self._state_lock:
                self._last_nack = line

            return

        parts = line.split(",")

        if (
            len(parts) == 7
            and parts[0] == "NAV"
        ):
            try:
                mode = parts[1].strip().upper()

                steer_deg = float(
                    parts[2]
                )

                left_percent = float(
                    parts[3]
                )

                right_percent = float(
                    parts[4]
                )

                dead_end = (
                    parts[5].strip()
                    == "1"
                )

                lidar_healthy = (
                    parts[6].strip()
                    == "1"
                )

            except ValueError:
                return

            with self._state_lock:
                self._nav_mode = mode
                self._nav_steer_deg = steer_deg
                self._nav_left_percent = left_percent
                self._nav_right_percent = right_percent
                self._nav_dead_end = dead_end
                self._nav_lidar_healthy = lidar_healthy
                self._nav_update_time = now

            return

        if (
            len(parts) == 5
            and parts[0] == "POSE"
        ):
            try:
                x_m = float(
                    parts[1]
                )

                y_m = float(
                    parts[2]
                )

                heading_deg = float(
                    parts[3]
                )

                distance_m = float(
                    parts[4]
                )

            except ValueError:
                return

            sample = {
                "x_m": x_m,
                "y_m": y_m,
                "heading_deg": heading_deg,
                "distance_m": distance_m,
                "received_monotonic": now,
            }

            with self._state_lock:
                self._pose_x_m = x_m
                self._pose_y_m = y_m
                self._pose_heading_deg = (
                    heading_deg
                )
                self._pose_distance_m = (
                    distance_m
                )
                self._pose_update_time = now

            self._put_bounded(
                self._pose_queue,
                sample,
            )

            return

        if (
            len(parts) >= 2
            and parts[0] == "EVENT"
        ):
            event_name = ",".join(
                parts[1:]
            ).strip()

            event = {
                "event": event_name,
                "received_monotonic": now,
            }

            with self._state_lock:
                self._last_event = (
                    event_name
                )

                self._last_event_time = (
                    now
                )

            self._put_bounded(
                self._event_queue,
                event,
            )

    def _read_available(self):
        if self._serial is None:
            return

        try:
            waiting = (
                self._serial.in_waiting
            )

            if waiting <= 0:
                return

            chunk = self._serial.read(
                min(
                    waiting,
                    512,
                )
            )

            if not chunk:
                return

            self._rx_buffer.extend(
                chunk
            )

            if len(self._rx_buffer) > 4096:
                self._rx_buffer.clear()
                return

            while True:
                newline_index = (
                    self._rx_buffer.find(
                        b"\n"
                    )
                )

                if newline_index < 0:
                    break

                raw = bytes(
                    self._rx_buffer[
                        :newline_index
                    ]
                )

                del self._rx_buffer[
                    :newline_index + 1
                ]

                line = raw.decode(
                    "ascii",
                    errors="ignore",
                ).strip()

                if not line:
                    continue

                self._handle_rx_line(
                    line
                )

        except Exception as error:
            self._set_connection_state(
                False,
                str(error),
            )

            self._close_serial()

    def _worker(self):
        next_reconnect = 0.0
        next_heartbeat = 0.0

        while not self._stop_event.is_set():
            now = time.monotonic()

            if self._serial is None:
                if now >= next_reconnect:
                    if self._open_serial():
                        next_heartbeat = (
                            now
                            + ESP_HEARTBEAT_INTERVAL
                        )
                    else:
                        next_reconnect = (
                            now
                            + ESP_RECONNECT_INTERVAL
                        )

                time.sleep(
                    ESP_WORKER_POLL_INTERVAL
                )

                continue

            try:
                _, _, command = (
                    self._tx_queue
                    .get_nowait()
                )

                if not self._write_line(
                    command
                ):
                    next_reconnect = (
                        time.monotonic()
                        + ESP_RECONNECT_INTERVAL
                    )

                    continue

            except queue.Empty:
                pass

            now = time.monotonic()

            if now >= next_heartbeat:
                if not self._write_line(
                    "HB"
                ):
                    next_reconnect = (
                        time.monotonic()
                        + ESP_RECONNECT_INTERVAL
                    )

                    continue

                next_heartbeat = (
                    now
                    + ESP_HEARTBEAT_INTERVAL
                )

            self._read_available()

            time.sleep(
                ESP_WORKER_POLL_INTERVAL
            )

        self._close_serial()

    def mode_manual(self):
        self._enqueue(
            "MOVE,STOP",
            priority=0,
        )

        self._enqueue(
            "MODE,MANUAL",
            priority=1,
        )

    def mode_auto(self):
        self._enqueue(
            "MOVE,STOP",
            priority=0,
        )

        self._enqueue(
            "MODE,AUTO",
            priority=1,
        )

    def mode_stop(self):
        self._enqueue(
            "MOVE,STOP",
            priority=0,
        )

        self._enqueue(
            "MODE,STOP",
            priority=1,
        )

    def move_forward(self):
        return self.send(
            "MOVE,FWD",
            priority=5,
        )

    def move_reverse(self):
        return self.send(
            "MOVE,REV",
            priority=5,
        )

    def move_left(self):
        return self.send(
            "MOVE,LEFT",
            priority=5,
        )

    def move_right(self):
        return self.send(
            "MOVE,RIGHT",
            priority=5,
        )

    def move_stop(self):
        if not self.connected:
            return False

        self._enqueue(
            "MOVE,STOP",
            priority=0,
            allow_disconnected=True,
        )

        return True

    def set_auto_inhibit(
        self,
        inhibited,
    ):
        command = (
            "AUTO_INHIBIT,1"
            if inhibited
            else "AUTO_INHIBIT,0"
        )

        return self.send(
            command,
            priority=1,
        )

    def reset_pose(self):
        return self.send(
            "POSE,RESET",
            priority=1,
        )

    def get_pose_samples(
        self,
        max_items=100,
    ):
        samples = []

        for _ in range(max_items):
            try:
                samples.append(
                    self._pose_queue
                    .get_nowait()
                )

            except queue.Empty:
                break

        return samples

    def get_events(
        self,
        max_items=20,
    ):
        events = []

        for _ in range(max_items):
            try:
                events.append(
                    self._event_queue
                    .get_nowait()
                )

            except queue.Empty:
                break

        return events

    def get_state(self):
        now = time.monotonic()

        with self._state_lock:
            if self._last_rx_time > 0:
                rx_age = (
                    now
                    - self._last_rx_time
                )
            else:
                rx_age = None

            if self._last_hb_ack_time > 0:
                hb_ack_age = (
                    now
                    - self._last_hb_ack_time
                )
            else:
                hb_ack_age = None

            if self._nav_update_time > 0:
                nav_age = (
                    now
                    - self._nav_update_time
                )
            else:
                nav_age = None

            if self._pose_update_time > 0:
                pose_age = (
                    now
                    - self._pose_update_time
                )
            else:
                pose_age = None

            if self._last_event_time > 0:
                event_age = (
                    now
                    - self._last_event_time
                )
            else:
                event_age = None

            return {
                "esp_uart_connected":
                    self._connected,

                "esp_uart_error":
                    self._last_error,

                "esp_last_rx":
                    self._last_rx_line,

                "esp_last_tx":
                    self._last_tx_line,

                "esp_rx_age_s": (
                    round(rx_age, 3)
                    if rx_age is not None
                    else None
                ),

                "esp_hb_ack_age_s": (
                    round(hb_ack_age, 3)
                    if hb_ack_age is not None
                    else None
                ),

                "esp_last_ack":
                    self._last_ack,

                "esp_last_nack":
                    self._last_nack,

                "esp_nav_mode":
                    self._nav_mode,

                "esp_nav_steer_deg":
                    round(
                        self._nav_steer_deg,
                        2,
                    ),

                "esp_left_percent":
                    round(
                        self._nav_left_percent,
                        1,
                    ),

                "esp_right_percent":
                    round(
                        self._nav_right_percent,
                        1,
                    ),

                "esp_dead_end":
                    self._nav_dead_end,

                "esp_lidar_healthy":
                    self._nav_lidar_healthy,

                "esp_nav_age_s": (
                    round(nav_age, 3)
                    if nav_age is not None
                    else None
                ),

                "esp_pose_x_m":
                    round(
                        self._pose_x_m,
                        3,
                    ),

                "esp_pose_y_m":
                    round(
                        self._pose_y_m,
                        3,
                    ),

                "esp_pose_heading_deg":
                    round(
                        self._pose_heading_deg,
                        2,
                    ),

                "esp_pose_distance_m":
                    round(
                        self._pose_distance_m,
                        3,
                    ),

                "esp_pose_age_s": (
                    round(pose_age, 3)
                    if pose_age is not None
                    else None
                ),

                "esp_last_event":
                    self._last_event,

                "esp_event_age_s": (
                    round(event_age, 3)
                    if event_age is not None
                    else None
                ),
            }


esp_link = EspLink()
