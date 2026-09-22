import time
from threading import Lock

from gpiozero import (
    AngularServo,
    DigitalInputDevice,
    DigitalOutputDevice,
)
from gpiozero.pins.lgpio import LGPIOFactory

from robot_config import (
    EMPTY_CONFIRM_TIME,
    HORIZONTAL_ANGLE,
    LEVEL_SENSOR_GPIO,
    LEVEL_SENSOR_WATER_ACTIVE_LOW,
    PUMP_RELAY_ACTIVE_LOW,
    PUMP_RELAY_GPIO,
    SERVO_GPIO,
    SERVO_MAX_PULSE_WIDTH,
    SERVO_MIN_PULSE_WIDTH,
    SERVO_SETTLE_TIME,
    USE_LEVEL_SENSOR_FOR_AUTONOMY,
    VERTICAL_ANGLE,
    WATER_RECOVERY_TIME,
)


class SpraySystem:
    def __init__(self):
        self._lock = Lock()

        self._factory = None
        self._servo = None
        self._pump = None
        self._level_sensor = None

        self._initialized = False

        self.target = "weed"
        self.orientation = "horizontal"

        self.servo_ready = False
        self.servo_error = None
        self._servo_ready_at = 0.0

        self.pump_on = False

        self.tank_state = "checking"
        self.raw_water_present = False

        self._state_started_at = time.monotonic()
        self._recovering_from_empty = False

    def initialize(self):
        with self._lock:
            if self._initialized:
                return

            self._factory = LGPIOFactory()

            self._level_sensor = DigitalInputDevice(
                LEVEL_SENSOR_GPIO,
                pull_up=True,
                pin_factory=self._factory,
            )

            self._pump = DigitalOutputDevice(
                PUMP_RELAY_GPIO,
                active_high=not PUMP_RELAY_ACTIVE_LOW,
                initial_value=False,
                pin_factory=self._factory,
            )

            try:
                self._servo = AngularServo(
                    SERVO_GPIO,
                    min_angle=0,
                    max_angle=180,
                    initial_angle=None,
                    min_pulse_width=SERVO_MIN_PULSE_WIDTH,
                    max_pulse_width=SERVO_MAX_PULSE_WIDTH,
                    pin_factory=self._factory,
                )

                self._servo.angle = HORIZONTAL_ANGLE

                self._servo_ready_at = (
                    time.monotonic()
                    + SERVO_SETTLE_TIME
                )

                self.servo_ready = True
                self.servo_error = None

            except Exception as error:
                self.servo_ready = False
                self.servo_error = str(error)

            self.target = "weed"
            self.orientation = "horizontal"

            self.pump_on = False

            self.raw_water_present = (
                self._read_water_locked()
            )

            self.tank_state = (
                "bypassed"
                if not USE_LEVEL_SENSOR_FOR_AUTONOMY
                else "checking"
            )

            self._state_started_at = time.monotonic()
            self._recovering_from_empty = False

            self._initialized = True

            state = (
                "ENABLED"
                if USE_LEVEL_SENSOR_FOR_AUTONOMY
                else "BYPASSED"
            )

            print(
                f"Spray system ready. "
                f"Tank interlock: {state}"
            )

    def _read_water_locked(self):
        if self._level_sensor is None:
            return False

        raw_high = bool(
            self._level_sensor.value
        )

        if LEVEL_SENSOR_WATER_ACTIVE_LOW:
            return not raw_high

        return raw_high

    def _set_pump_raw_locked(
        self,
        enabled,
    ):
        enabled = bool(enabled)

        if self._pump is None:
            self.pump_on = False
            return

        if enabled:
            self._pump.on()
        else:
            self._pump.off()

        self.pump_on = enabled

    def update_level(self):
        with self._lock:
            now = time.monotonic()

            self.raw_water_present = (
                self._read_water_locked()
            )

            if not USE_LEVEL_SENSOR_FOR_AUTONOMY:
                self.tank_state = "bypassed"
                return None

            wet = self.raw_water_present

            if self.tank_state == "checking":
                self._set_pump_raw_locked(False)

                self.tank_state = (
                    "recovery_pending"
                    if wet
                    else "empty_pending"
                )

                self._recovering_from_empty = False
                self._state_started_at = now

                return None

            if self.tank_state == "water_available":
                if not wet:
                    self._set_pump_raw_locked(False)

                    self.tank_state = "empty_pending"
                    self._state_started_at = now

                return None

            if self.tank_state == "empty_pending":
                self._set_pump_raw_locked(False)

                if wet:
                    self.tank_state = "water_available"
                    self._recovering_from_empty = False
                    self._state_started_at = now

                    return None

                if (
                    now - self._state_started_at
                    >= EMPTY_CONFIRM_TIME
                ):
                    self.tank_state = "empty_confirmed"
                    self._recovering_from_empty = True
                    self._state_started_at = now

                    return "empty_confirmed"

                return None

            if self.tank_state == "empty_confirmed":
                self._set_pump_raw_locked(False)

                if wet:
                    self.tank_state = "recovery_pending"
                    self._recovering_from_empty = True
                    self._state_started_at = now

                return None

            if self.tank_state == "recovery_pending":
                self._set_pump_raw_locked(False)

                if not wet:
                    self.tank_state = (
                        "empty_confirmed"
                        if self._recovering_from_empty
                        else "empty_pending"
                    )

                    self._state_started_at = now
                    return None

                if (
                    now - self._state_started_at
                    >= WATER_RECOVERY_TIME
                ):
                    self.tank_state = "water_available"

                    recovered = (
                        self._recovering_from_empty
                    )

                    self._recovering_from_empty = False
                    self._state_started_at = now

                    if recovered:
                        return "water_recovered"

                    return None

                return None

            self._set_pump_raw_locked(False)

            self.tank_state = "checking"
            self._state_started_at = now

            return None

    def set_target(
        self,
        target,
    ):
        target = target.strip().lower()

        if target not in {
            "weed",
            "maize",
        }:
            raise ValueError(
                "Target must be weed or maize"
            )

        with self._lock:
            self._set_pump_raw_locked(False)

            if self._servo is None:
                raise RuntimeError(
                    "Spray rail servo is unavailable"
                )

            if target == "weed":
                angle = HORIZONTAL_ANGLE
                orientation = "horizontal"
            else:
                angle = VERTICAL_ANGLE
                orientation = "vertical"

            self._servo.angle = angle

            self.target = target
            self.orientation = orientation

            self._servo_ready_at = (
                time.monotonic()
                + SERVO_SETTLE_TIME
            )

            self.servo_ready = True
            self.servo_error = None

    def _servo_settled_locked(self):
        return (
            self.servo_ready
            and
            time.monotonic()
            >= self._servo_ready_at
        )

    def set_pump(
        self,
        enabled,
    ):
        with self._lock:
            if not enabled:
                self._set_pump_raw_locked(False)
                return

            if USE_LEVEL_SENSOR_FOR_AUTONOMY:
                water_ok = (
                    self.tank_state
                    == "water_available"
                )
            else:
                water_ok = True

            if (
                not water_ok
                or
                not self._servo_settled_locked()
            ):
                self._set_pump_raw_locked(False)
                return

            self._set_pump_raw_locked(True)

    def get_state(self):
        with self._lock:
            if USE_LEVEL_SENSOR_FOR_AUTONOMY:
                effective_water = (
                    self.tank_state
                    == "water_available"
                )
            else:
                effective_water = True

            return {
                "spray_target":
                    self.target,

                "rail_orientation":
                    self.orientation,

                "servo_ready":
                    self.servo_ready,

                "servo_error":
                    self.servo_error,

                "rail_settled":
                    self._servo_settled_locked(),

                "tank_state":
                    self.tank_state,

                "tank_interlock_enabled":
                    USE_LEVEL_SENSOR_FOR_AUTONOMY,

                "sensor_water_present":
                    self.raw_water_present,

                "water_available":
                    effective_water,

                "tank_empty_confirmed": (
                    USE_LEVEL_SENSOR_FOR_AUTONOMY
                    and
                    self.tank_state
                    == "empty_confirmed"
                ),

                "pump_on":
                    self.pump_on,
            }

    def close(self):
        with self._lock:
            self._set_pump_raw_locked(False)

            for name in (
                "_servo",
                "_level_sensor",
                "_pump",
            ):
                device = getattr(
                    self,
                    name,
                )

                if device is not None:
                    try:
                        device.close()
                    finally:
                        setattr(
                            self,
                            name,
                            None,
                        )

            if self._factory is not None:
                self._factory.close()
                self._factory = None

            self._initialized = False
            self.servo_ready = False


spray_system = SpraySystem()
