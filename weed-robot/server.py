import asyncio
import json
import time
from contextlib import asynccontextmanager

from fastapi import (
    FastAPI,
    WebSocket,
    WebSocketDisconnect,
)
from fastapi.middleware.cors import (
    CORSMiddleware,
)
from fastapi.responses import (
    StreamingResponse,
)

import navigation.routes_api as routes_api

from detect import detector
from esp_link import esp_link
from lidar_reader import lidar_reader
from spray_system import spray_system

from robot_config import (
    DETECTION_STALE_TIME,
    ESP_PEER_ALIVE_TIMEOUT,
    LIDAR_UI_INTERVAL,
    LIDAR_VISUALIZATION_ENABLED,
    SPRAY_CONFIDENCE,
    SPRAY_SUPERVISOR_INTERVAL,
    TARGET_LABELS,
    TELEMETRY_INTERVAL,
)


POSE_RECORDING_INTERVAL = 0.50
ESP_EVENT_INTERVAL = 0.05


robot_state = {
    "mode": "manual",
    "autonomy_state": "manual",

    "mission_active": False,
    "manual_override": False,

    "spraying_enabled": False,

    "auto_inhibited": False,

    "target_detected": False,
    "target_confidence": 0.0,

    "teaching_started": False,
    "recording_point_count": 0,
    "recording_pause_reason":"",
}


_recording_accept_after = 0.0
_last_recorded_pose_time = None
_last_recorded_distance_m = None


def get_esp_state():
    state = esp_link.get_state()

    uart_open = bool(
        state.get(
            "esp_uart_connected",
            False,
        )
    )

    hb_ack_age = state.get(
        "esp_hb_ack_age_s"
    )

    peer_alive = (
        uart_open
        and isinstance(
            hb_ack_age,
            (int, float),
        )
        and hb_ack_age
        <= ESP_PEER_ALIVE_TIMEOUT
    )

    state["esp_uart_open"] = (
        uart_open
    )

    state["esp_peer_alive"] = (
        peer_alive
    )

    # Temporary Flutter compatibility.
    state[
        "esp_uart_connected"
    ] = peer_alive

    return state


def esp_peer_alive():
    return bool(
        get_esp_state().get(
            "esp_peer_alive",
            False,
        )
    )


def manual_motion_allowed():
    return (
        robot_state["mode"]
        == "manual"
        or robot_state[
            "manual_override"
        ]
    )


def selected_target_confidence():
    state = (
        detector
        .get_detection_state()
    )

    timestamp = float(
        state.get(
            "timestamp",
            0.0,
        )
        or 0.0
    )

    if timestamp <= 0:
        return 0.0

    if (
        time.monotonic()
        - timestamp
        > DETECTION_STALE_TIME
    ):
        return 0.0

    detections = state.get(
        "detections",
        {},
    )

    target = (
        spray_system
        .get_state()[
            "spray_target"
        ]
    )

    aliases = TARGET_LABELS.get(
        target,
        {target},
    )

    best = 0.0

    for (
        label,
        confidence,
    ) in detections.items():

        normalized = (
            str(label)
            .strip()
            .lower()
        )

        if normalized not in aliases:
            continue

        try:
            best = max(
                best,
                float(confidence),
            )

        except (
            TypeError,
            ValueError,
        ):
            pass

    return best


def sync_route_state():
    recording_id = (
        routes_api
        .recording_route_id
    )

    if (
        recording_id is None
        and robot_state[
            "mission_active"
        ]
    ):
        spray_system.set_pump(
            False
        )

        esp_link.move_stop()
        esp_link.mode_stop()

        robot_state[
            "mission_active"
        ] = False

        robot_state[
            "manual_override"
        ] = False

        robot_state[
            "spraying_enabled"
        ] = False

    if recording_id is None:
        robot_state[
            "teaching_started"
        ] = False

        robot_state[
            "recording_point_count"
        ] = 0

        robot_state[
            "recording_pause_reason"
        ] = ""

    elif (
        not robot_state[
            "mission_active"
        ]
        and
        not robot_state[
            "manual_override"
        ]
        and
        not robot_state[
            "recording_pause_reason"
        ]
    ):
        robot_state[
            "recording_pause_reason"
        ] = "paused"

    if (
        robot_state["mode"]
        != "auto"
    ):
        autonomy_state = "manual"

    elif robot_state[
        "auto_inhibited"
    ]:
        autonomy_state = "inhibited"

    elif robot_state[
        "manual_override"
    ]:
        autonomy_state = (
            "manual_override"
        )

    elif robot_state[
        "mission_active"
    ]:
        autonomy_state = (
            "teaching"
        )

    elif recording_id is not None:
        autonomy_state = (
            "teach_ready"
        )

    else:
        autonomy_state = "setup"

    robot_state[
        "autonomy_state"
    ] = autonomy_state

    mapping_active = (
        robot_state["mode"]
        == "auto"
        and robot_state[
            "mission_active"
        ]
        and recording_id
        is not None
    )

    return {
        "route_ready":
            recording_id
            is not None,

        "active_route_id":
            recording_id,

        "recording_route_id":
            recording_id,

        "recording_pause_reason":
            robot_state[
                "recording_pause_reason"
            ],

        "mapping_active":
            mapping_active,
    }
    

def build_telemetry(
    include_lidar_points=False,
):
    detector_state = (
        detector.get_stats()
    )

    spray_state = (
        spray_system.get_state()
    )

    esp_state = (
        get_esp_state()
    )

    route_state = (
        sync_route_state()
    )

    lidar_state = (
        lidar_reader.get_state(
            include_points=(
                include_lidar_points
            )
        )
    )

    robot_state[
        "perception_active"
    ] = bool(
        detector_state[
            "running"
        ]
    )

    return {
        **robot_state,
        **route_state,
        **detector_state,
        **spray_state,
        **esp_state,
        **lidar_state,
    }

def set_recording_pause_reason(
    reason,
):
    if (
        routes_api
        .recording_route_id
        is None
    ):
        robot_state[
            "recording_pause_reason"
        ] = ""

        return

    robot_state[
        "recording_pause_reason"
    ] = str(
        reason or ""
    )

async def flush_pose_samples():
    global _last_recorded_pose_time
    global _last_recorded_distance_m

    samples = (
        esp_link
        .get_pose_samples(
            max_items=256
        )
    )

    if not samples:
        return 0

    route_id = (
        routes_api
        .recording_route_id
    )

    if (
        route_id is None
        or not robot_state[
            "teaching_started"
        ]
        or not robot_state[
            "mission_active"
        ]
    ):
        return 0

    points = []

    for sample in samples:
        received = float(
            sample.get(
                "received_monotonic",
                0.0,
            )
            or 0.0
        )

        if (
            received
            < _recording_accept_after
        ):
            continue

        distance_m = float(
            sample.get(
                "distance_m",
                0.0,
            )
            or 0.0
        )

        velocity_cm_s = 0.0

        if (
            _last_recorded_pose_time
            is not None
            and
            _last_recorded_distance_m
            is not None
        ):
            dt = (
                received
                - _last_recorded_pose_time
            )

            if dt > 0.001:
                velocity_cm_s = max(
                    0.0,
                    (
                        distance_m
                        - _last_recorded_distance_m
                    )
                    * 100.0
                    / dt,
                )

        _last_recorded_pose_time = (
            received
        )

        _last_recorded_distance_m = (
            distance_m
        )

        timestamp_ms = int(
            (
                time.time()
                - (
                    time.monotonic()
                    - received
                )
            )
            * 1000
        )

        points.append({
            "x_cm":
                float(
                    sample.get(
                        "x_m",
                        0.0,
                    )
                )
                * 100.0,

            "y_cm":
                float(
                    sample.get(
                        "y_m",
                        0.0,
                    )
                )
                * 100.0,

            "heading_deg":
                float(
                    sample.get(
                        "heading_deg",
                        0.0,
                    )
                ),

            "velocity_cm_s":
                velocity_cm_s,

            "mode":
                (
                    "MANUAL"
                    if robot_state[
                        "manual_override"
                    ]
                    else "AUTO"
                ),

            "timestamp_ms":
                timestamp_ms,

            "distance_cm":
                distance_m
                * 100.0,
        })

    if not points:
        return 0

    try:
        result = (
            await asyncio.to_thread(
                routes_api
                .store
                .append_points,

                route_id,
                points,
            )
        )

    except Exception as error:
        print(
            "Pose recording error:",
            error,
        )

        return 0

    count = int(
        result.get(
            "count",
            0,
        )
    )

    robot_state[
        "recording_point_count"
    ] += count

    return count


async def pose_recording_supervisor():
    while True:
        try:
            await flush_pose_samples()

        except Exception as error:
            print(
                "Pose recorder error:",
                error,
            )

        await asyncio.sleep(
            POSE_RECORDING_INTERVAL
        )


async def stop_teaching_for_safety(
    message=None,
    reason="safety_stop",
):
    if robot_state[
        "mission_active"
    ]:
        try:
            await flush_pose_samples()

        except Exception:
            pass

    spray_system.set_pump(
        False
    )

    esp_link.move_stop()
    esp_link.mode_stop()

    robot_state[
        "mission_active"
    ] = False

    robot_state[
        "manual_override"
    ] = False

    robot_state[
        "spraying_enabled"
    ] = False

    robot_state[
        "target_detected"
    ] = False

    robot_state[
        "target_confidence"
    ] = 0.0

    set_recording_pause_reason(
        reason
    )

    sync_route_state()

    if message:
        print(
            message
        )

async def esp_event_supervisor():
    while True:
        try:
            events = (
                esp_link
                .get_events(
                    max_items=20
                )
            )

            for event in events:
                event_name = (
                    str(
                        event.get(
                            "event",
                            "",
                        )
                    )
                    .strip()
                    .upper()
                )

                if not event_name:
                    continue

                route_id = (
                    routes_api
                    .recording_route_id
                )

                if (
                    route_id is not None
                    and robot_state[
                        "teaching_started"
                    ]
                ):
                    try:
                        await asyncio.to_thread(
                            routes_api
                            .store
                            .add_event,

                            route_id,
                            event_name,
                        )

                    except Exception as error:
                        print(
                            "ESP event save error:",
                            error,
                        )

                if (
                    event_name
                    == "DEAD_END"
                    and robot_state[
                        "mission_active"
                    ]
                ):
                    await stop_teaching_for_safety(
                        (
                            "Dead end detected - "
                            "recording paused"
                        ),
                        reason="dead_end",
                    )

            if (
                robot_state[
                    "mission_active"
                ]
                and not esp_peer_alive()
            ):
                await stop_teaching_for_safety(
                    (
                        "ESP32 communication lost - "
                        "recording paused"
                    ),
                    reason="esp_offline",
                )

        except Exception as error:
            print(
                "ESP event supervisor error:",
                error,
            )

        await asyncio.sleep(
            ESP_EVENT_INTERVAL
        )


async def enter_global_manual(
):
    spray_system.set_pump(
        False
    )

    # Keep AUTO inhibit state,
    # then explicitly enter MANUAL.
    esp_link.set_auto_inhibit(
        robot_state[
            "auto_inhibited"
        ]
    )

    esp_link.mode_manual()

    if detector.get_stats()[
        "running"
    ]:
        await asyncio.to_thread(
            detector.stop
        )

    robot_state.update({
        "mode":
            "manual",

        "autonomy_state":
            "manual",

        "mission_active":
            False,

        "manual_override":
            False,

        "spraying_enabled":
            False,

        "target_detected":
            False,

        "target_confidence":
            0.0,
    })
    
    sync_route_state


def enter_auto_setup():
    spray_state = (
        spray_system.get_state()
    )

    if not spray_state[
        "water_available"
    ]:
        return False

    if robot_state[
        "auto_inhibited"
    ]:
        return False

    spray_system.set_pump(
        False
    )

    esp_link.mode_stop()

    robot_state.update({
        "mode":
            "auto",

        "autonomy_state":
            "setup",

        "mission_active":
            False,

        "manual_override":
            False,

        "spraying_enabled":
            False,

        "target_detected":
            False,

        "target_confidence":
            0.0,
    })

    detector.start()

    sync_route_state()

    return True


async def handle_empty_confirmed():
    if robot_state[
        "mission_active"
    ]:
        try:
            await flush_pose_samples()

        except Exception:
            pass

    spray_system.set_pump(
        False
    )

    esp_link.move_stop()

    esp_link.set_auto_inhibit(
        True
    )

    if (
        robot_state["mode"]
        == "manual"
    ):
        esp_link.mode_manual()

    else:
        esp_link.mode_stop()

    if detector.get_stats()[
        "running"
    ]:
        await asyncio.to_thread(
            detector.stop
        )

    robot_state.update({
        "auto_inhibited":
            True,

        "mission_active":
            False,

        "manual_override":
            False,

        "spraying_enabled":
            False,

        "target_detected":
            False,

        "target_confidence":
            0.0,
    })

    set_recording_pause_reason(
        "water_empty"
    )

    sync_route_state()

def handle_water_recovered():
    robot_state[
        "auto_inhibited"
    ] = False

    robot_state[
        "mission_active"
    ] = False

    robot_state[
        "manual_override"
    ] = False

    robot_state[
        "spraying_enabled"
    ] = False

    esp_link.set_auto_inhibit(
        False
    )

    if (
        robot_state["mode"]
        == "manual"
    ):
        esp_link.mode_manual()

    else:
        esp_link.mode_stop()

    set_recording_pause_reason(
        "paused"
    )

    sync_route_state()

async def spray_supervisor():
    while True:
        try:
            event = (
                spray_system
                .update_level()
            )

            if (
                event
                == "empty_confirmed"
            ):
                await (
                    handle_empty_confirmed()
                )

            elif (
                event
                == "water_recovered"
            ):
                handle_water_recovered()

            confidence = (
                selected_target_confidence()
            )

            target_detected = (
                confidence
                >= SPRAY_CONFIDENCE
            )

            spray_state = (
                spray_system.get_state()
            )

            esp_state = (
                get_esp_state()
            )

            detector_running = bool(
                detector
                .get_stats()[
                    "running"
                ]
            )

            spraying_enabled = (
                robot_state["mode"]
                == "auto"

                and robot_state[
                    "mission_active"
                ]

                and not robot_state[
                    "manual_override"
                ]

                and not robot_state[
                    "auto_inhibited"
                ]

                and esp_state[
                    "esp_peer_alive"
                ]

                and not bool(
                    esp_state.get(
                        "esp_dead_end",
                        False,
                    )
                )

                and detector_running

                and spray_state[
                    "servo_ready"
                ]

                and spray_state[
                    "rail_settled"
                ]

                and spray_state[
                    "water_available"
                ]
            )

            robot_state[
                "target_confidence"
            ] = round(
                confidence,
                4,
            )

            robot_state[
                "target_detected"
            ] = target_detected

            robot_state[
                "spraying_enabled"
            ] = spraying_enabled

            # Continuous spray while the
            # selected target remains detected.
            spray_system.set_pump(
                spraying_enabled
                and target_detected
            )

        except Exception as error:
            try:
                spray_system.set_pump(
                    False
                )

            except Exception:
                pass

            print(
                "Spray supervisor error:",
                error,
            )

        await asyncio.sleep(
            SPRAY_SUPERVISOR_INTERVAL
        )


async def start_or_resume_teaching():
    global _recording_accept_after
    global _last_recorded_pose_time
    global _last_recorded_distance_m

    spray_state = (
        spray_system.get_state()
    )

    if (
        robot_state["mode"]
        != "auto"
    ):
        return "Select AUTO first"

    if (
        robot_state[
            "auto_inhibited"
        ]
        or not spray_state[
            "water_available"
        ]
    ):
        return (
            "Teaching blocked "
            "by tank safety"
        )

    if not esp_peer_alive():
        return (
            "Teaching blocked: "
            "ESP32 unavailable"
        )

    route_id = (
        routes_api
        .recording_route_id
    )

    if route_id is None:
        return (
            "Start a new field "
            "recording first"
        )

    detector.start()

    spray_system.set_pump(
        False
    )

    initial_start = (
        not robot_state[
            "teaching_started"
        ]
    )

    # Discard stale pose packets.
    esp_link.get_pose_samples(
        max_items=1000
    )

    if initial_start:
        esp_link.reset_pose()

        # ESP remains stopped while
        # the pose origin is reset.
        await asyncio.sleep(
            0.25
        )

        esp_link.get_pose_samples(
            max_items=1000
        )

        # Explicit origin guarantees
        # every map begins at 0, 0.
        await asyncio.to_thread(
            routes_api
            .store
            .append_point,

            route_id,
            0.0,
            0.0,
            0.0,
            0.0,
            "AUTO",
            int(
                time.time()
                * 1000
            ),
            0.0,
        )

        robot_state[
            "recording_point_count"
        ] = 1

    _recording_accept_after = (
        time.monotonic()
    )

    _last_recorded_pose_time = None
    _last_recorded_distance_m = None

    esp_link.set_auto_inhibit(
        False
    )

    esp_link.mode_auto()

    robot_state[
        "teaching_started"
    ] = True

    robot_state[
        "mission_active"
    ] = True

    robot_state[
        "manual_override"
    ] = False

    robot_state[
        "spraying_enabled"
    ] = False

    set_recording_pause_reason("")
    sync_route_state()

    if initial_start:
        return (
            "Teaching mission started"
        )

    return (
        "Teaching mission resumed"
    )


async def handle_command(
    command,
):
    if command == "start":
        if (
            robot_state["mode"]
            != "auto"
        ):
            return (
                "Detection requires "
                "AUTO mode"
            )

        if robot_state[
            "auto_inhibited"
        ]:
            return (
                "Detection blocked "
                "by tank safety"
            )

        detector.start()

        return (
            "Detection started"
        )

    if command == "stop":
        spray_system.set_pump(
            False
        )

        esp_link.mode_stop()

        await flush_pose_samples()

        robot_state[
            "mission_active"
        ] = False

        robot_state[
            "manual_override"
        ] = False

        robot_state[
            "spraying_enabled"
        ] = False

        if detector.get_stats()[
            "running"
        ]:
            await asyncio.to_thread(
                detector.stop
            )

        set_recording_pause_reason(
            "operator_stopped"
        )

        sync_route_state()

        return (
            "Detection and "
            "teaching stopped"
        )

    if command == "mode_auto":
        if enter_auto_setup():
            return (
                "AUTO setup ready"
            )

        return (
            "AUTO blocked "
            "by tank safety"
        )

    if command == "mode_manual":
        await flush_pose_samples()

        await enter_global_manual()

        return (
            "MANUAL mode ready"
        )

    if command in {
        "manual",
        "manual_override",
    }:
        sync_route_state()

        if (
            robot_state["mode"]
            == "auto"

            and routes_api
            .recording_route_id
            is not None

            and robot_state[
                "mission_active"
            ]

            and not robot_state[
                "auto_inhibited"
            ]

            and esp_peer_alive()
        ):
            spray_system.set_pump(
                False
            )

            esp_link.mode_manual()

            robot_state[
                "manual_override"
            ] = True
            
            set_recording_pause_reason(
                "manual_reposition"
            )

            robot_state[
                "spraying_enabled"
            ] = False

            sync_route_state()

            return (
                "Manual override ready"
            )

        return (
            "Manual override unavailable"
        )

    if command in {
        "auto",
        "resume_auto",
    }:
        if (
            robot_state["mode"]
            == "auto"

            and robot_state[
                "mission_active"
            ]

            and robot_state[
                "manual_override"
            ]

            and not robot_state[
                "auto_inhibited"
            ]

            and esp_peer_alive()
        ):
            esp_link.set_auto_inhibit(
                False
            )

            esp_link.mode_auto()

            robot_state[
                "manual_override"
            ] = False

            set_recording_pause_reason(
                ""
            )

            sync_route_state()

            return (
                "Autonomous "
                "navigation resumed"
            )

        return (
            "AUTO resume unavailable"
        )

    if command in {
        "start_mission",
        "start_teach",
    }:
        return await (
            start_or_resume_teaching()
        )

    if command == "stop_mission":
        spray_system.set_pump(
            False
        )

        esp_link.move_stop()
        esp_link.mode_stop()

        await flush_pose_samples()

        robot_state[
            "mission_active"
        ] = False

        robot_state[
            "manual_override"
        ] = False

        robot_state[
            "spraying_enabled"
        ] = False

        robot_state[
            "target_detected"
        ] = False

        robot_state[
            "target_confidence"
        ] = 0.0

        set_recording_pause_reason(
            "operator_stopped"
        )
        sync_route_state()

        return (
            "Teaching mission stopped"
        )

    if command == "forward":
        if (
            manual_motion_allowed()
            and esp_peer_alive()
            and esp_link.move_forward()
        ):
            return "Forward"

        return (
            "Manual control unavailable"
        )

    if command == "reverse":
        if (
            manual_motion_allowed()
            and esp_peer_alive()
            and esp_link.move_reverse()
        ):
            return "Reverse"

        return (
            "Manual control unavailable"
        )

    if command == "left":
        if (
            manual_motion_allowed()
            and esp_peer_alive()
            and esp_link.move_left()
        ):
            return "Left"

        return (
            "Manual control unavailable"
        )

    if command == "right":
        if (
            manual_motion_allowed()
            and esp_peer_alive()
            and esp_link.move_right()
        ):
            return "Right"

        return (
            "Manual control unavailable"
        )

    if command == "motion_stop":
        esp_link.move_stop()

        return "Stopped"

    if command == "target_weed":
        spray_system.set_pump(
            False
        )

        spray_system.set_target(
            "weed"
        )

        return "Target: weed"

    if command == "target_maize":
        spray_system.set_pump(
            False
        )

        spray_system.set_target(
            "maize"
        )

        return "Target: maize"

    if command == "start_replay":
        return (
            "Route replay "
            "is not supported"
        )

    return (
        f"Unknown command: "
        f"{command}"
    )


@asynccontextmanager
async def lifespan(app):
    spray_system.initialize()
    spray_system.update_level()

    esp_link.start()

    if LIDAR_VISUALIZATION_ENABLED:
        lidar_reader.start()

    recovered_route_id = (
        routes_api
        .restore_recording_state()
    )

    if recovered_route_id is not None:
        recovered_route = (
            routes_api
            .store
            .get_route(
                recovered_route_id
            )
        )

        recovered_points = (
            recovered_route.get(
                "points",
                [],
            )
            if recovered_route
            else []
        )

        point_count = len(
            recovered_points
        )

        robot_state[
            "recording_point_count"
        ] = point_count

        # Zero points means a route
        # was created but actual
        # teaching never began.
        robot_state[
            "teaching_started"
        ] = (
            point_count > 0
        )

        robot_state[
            "recording_pause_reason"
        ] = "interrupted"

        print(
            "Recovered unfinished "
            f"field recording "
            f"{recovered_route_id}"
        )

    else:
        robot_state[
            "recording_point_count"
        ] = 0

        robot_state[
            "teaching_started"
        ] = False

        robot_state[
            "recording_pause_reason"
        ] = ""
        

    tasks = [
        asyncio.create_task(
            spray_supervisor()
        ),

        asyncio.create_task(
            pose_recording_supervisor()
        ),

        asyncio.create_task(
            esp_event_supervisor()
        ),
    ]

    try:
        yield

    finally:
        for task in tasks:
            task.cancel()

        for task in tasks:
            try:
                await task

            except asyncio.CancelledError:
                pass

            except Exception:
                pass

        spray_system.set_pump(
            False
        )

        esp_link.move_stop()
        esp_link.mode_stop()

        if detector.get_stats()[
            "running"
        ]:
            await asyncio.to_thread(
                detector.stop
            )

        lidar_reader.stop()
        esp_link.stop()
        spray_system.close()


app = FastAPI(
    lifespan=lifespan
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(
    routes_api.router
)


@app.get("/health")
def health():
    return {
        "status": "ok",

        "robot":
            build_telemetry(
                False
            ),
    }


async def video_generator():
    last_frame_id = -1

    while True:
        (
            frame_id,
            frame,
        ) = detector.get_frame()

        if (
            frame is None
            or frame_id
            == last_frame_id
        ):
            await asyncio.sleep(
                0.01
            )

            continue

        last_frame_id = frame_id

        yield (
            b"--frame\r\n"
            b"Content-Type: image/jpeg\r\n"
            b"Cache-Control: no-cache\r\n\r\n"
            + frame
            + b"\r\n"
        )


@app.get("/video_feed")
def video_feed():
    return StreamingResponse(
        video_generator(),

        media_type=(
            "multipart/"
            "x-mixed-replace; "
            "boundary=frame"
        ),

        headers={
            "Cache-Control":
                (
                    "no-store, no-cache, "
                    "must-revalidate, "
                    "max-age=0"
                ),

            "Pragma":
                "no-cache",

            "X-Accel-Buffering":
                "no",
        },
    )


async def send_periodic_telemetry(
    websocket,
    send_lock,
):
    while True:
        payload = {
            "type":
                "telemetry",

            **build_telemetry(
                False
            ),
        }

        async with send_lock:
            await websocket.send_json(
                payload
            )

        await asyncio.sleep(
            TELEMETRY_INTERVAL
        )


async def send_periodic_lidar(
    websocket,
    send_lock,
):
    if not LIDAR_VISUALIZATION_ENABLED:
        return

    while True:
        state = (
            lidar_reader.get_state(
                include_points=True
            )
        )

        payload = {
            "type":
                "lidar",

            "lidar_connected":
                state[
                    "lidar_connected"
                ],

            "lidar_point_count":
                state[
                    "lidar_point_count"
                ],

            "lidar_points":
                state.get(
                    "lidar_points",
                    [],
                ),
        }

        async with send_lock:
            await websocket.send_json(
                payload
            )

        await asyncio.sleep(
            LIDAR_UI_INTERVAL
        )


@app.websocket("/ws")
async def websocket_endpoint(
    websocket: WebSocket,
):
    await websocket.accept()

    await enter_global_manual()

    send_lock = asyncio.Lock()

    initial = {
        "type":
            "status",

        **build_telemetry(
            False
        ),

        "message":
            "Connected",
    }

    await websocket.send_json(
        initial
    )

    telemetry_task = (
        asyncio.create_task(
            send_periodic_telemetry(
                websocket,
                send_lock,
            )
        )
    )

    lidar_task = (
        asyncio.create_task(
            send_periodic_lidar(
                websocket,
                send_lock,
            )
        )
    )

    try:
        while True:
            raw = (
                await websocket
                .receive_text()
            )

            try:
                data = json.loads(
                    raw
                )

            except json.JSONDecodeError:
                async with send_lock:
                    await (
                        websocket
                        .send_json({
                            "type":
                                "error",

                            "message":
                                "Invalid JSON",
                        })
                    )

                continue

            if (
                data.get("type")
                != "command"
            ):
                continue

            command = str(
                data.get(
                    "command",
                    "",
                )
            ).strip()

            try:
                message = (
                    await handle_command(
                        command
                    )
                )

                response_type = "ack"

            except Exception as error:
                message = str(error)
                response_type = "error"

            # Movement commands do not
            # produce WebSocket ACKs.
            if command not in {
                "forward",
                "reverse",
                "left",
                "right",
                "motion_stop",
            }:
                async with send_lock:
                    await (
                        websocket
                        .send_json({
                            "type":
                                response_type,

                            "message":
                                message,
                        })
                    )

    except WebSocketDisconnect:
        pass

    finally:
        try:
            await flush_pose_samples()

        except Exception:
            pass

        telemetry_task.cancel()
        lidar_task.cancel()

        for task in (
            telemetry_task,
            lidar_task,
        ):
            try:
                await task

            except asyncio.CancelledError:
                pass

            except Exception:
                pass

        await enter_global_manual()
