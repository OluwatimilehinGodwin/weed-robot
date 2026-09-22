from typing import Optional
import threading

from fastapi import (
    APIRouter,
    HTTPException,
)

from pydantic import BaseModel

from .route_store import RouteStore


router = APIRouter(
    prefix="/routes",
    tags=["routes"],
)

store = RouteStore()


# Recorded fields are never loaded
# for autonomous replay.
active_route_id = None

recording_route_id = None

_recording_lock = (
    threading.RLock()
)


class StartRouteRequest(
    BaseModel
):
    name: str


class RoutePointRequest(
    BaseModel
):
    x_cm: float
    y_cm: float

    heading_deg: float = 0.0
    velocity_cm_s: float = 0.0

    mode: str = "AUTO"

    timestamp_ms: Optional[int] = None

    distance_cm: float = 0.0


class RoutePointsBatchRequest(
    BaseModel
):
    points: list[
        RoutePointRequest
    ]


class RouteEventRequest(
    BaseModel
):
    event_type: str


def restore_recording_state():
    global recording_route_id
    global active_route_id

    with _recording_lock:
        if (
            recording_route_id
            is not None
        ):
            status = (
                store.get_route_status(
                    recording_route_id
                )
            )

            if status == "recording":
                return (
                    recording_route_id
                )

        route = (
            store
            .get_latest_recording_route()
        )

        if route is None:
            recording_route_id = None
            active_route_id = None

            return None

        recording_route_id = int(
            route["id"]
        )

        active_route_id = None

        return recording_route_id


def _decorate(
    route,
):
    if route is None:
        return None

    route["loaded"] = False

    route["recording"] = (
        route["id"]
        == recording_route_id
        and route.get(
            "status"
        )
        == "recording"
    )

    return route


def _require_route(
    route_id,
):
    if not store.route_exists(
        route_id
    ):
        raise HTTPException(
            status_code=404,
            detail=(
                "Recorded field "
                "not found"
            ),
        )


def _require_recording(
    route_id,
):
    restore_recording_state()

    _require_route(
        route_id
    )

    status = (
        store.get_route_status(
            route_id
        )
    )

    if status != "recording":
        raise HTTPException(
            status_code=409,
            detail=(
                "Field recording "
                "is already closed"
            ),
        )

    if (
        recording_route_id
        != route_id
    ):
        raise HTTPException(
            status_code=409,
            detail=(
                "This field is not "
                "the active recording"
            ),
        )


@router.get("")
def list_routes():
    restore_recording_state()

    return [
        _decorate(route)
        for route
        in store.list_routes()
    ]


@router.get("/recording")
def get_active_recording():
    restore_recording_state()

    if recording_route_id is None:
        return {
            "active": False,
            "route": None,
        }

    route = store.get_route(
        recording_route_id
    )

    if route is None:
        return {
            "active": False,
            "route": None,
        }

    return {
        "active": True,
        "route": _decorate(
            route
        ),
    }


@router.post("/start")
def start_route(
    request: StartRouteRequest,
):
    global recording_route_id
    global active_route_id

    name = request.name.strip()

    if not name:
        raise HTTPException(
            status_code=400,
            detail=(
                "Field name is required"
            ),
        )

    with _recording_lock:
        restore_recording_state()

        if recording_route_id is not None:
            existing = store.get_route(
                recording_route_id
            )

            raise HTTPException(
                status_code=409,
                detail={
                    "code":
                        "recording_already_active",

                    "message":
                        (
                            "An unfinished field "
                            "recording already exists"
                        ),

                    "route_id":
                        recording_route_id,

                    "name":
                        (
                            existing.get(
                                "name",
                                "",
                            )
                            if existing
                            else ""
                        ),
                },
            )

        route = store.create_route(
            name=name,
            field_width_cm=0.0,
            field_height_cm=0.0,
            row_count=0,
        )

        recording_route_id = int(
            route["id"]
        )

        active_route_id = None

        return _decorate(
            route
        )


@router.get("/{route_id}")
def get_route(
    route_id: int,
):
    restore_recording_state()

    route = store.get_route(
        route_id
    )

    if route is None:
        raise HTTPException(
            status_code=404,
            detail=(
                "Recorded field "
                "not found"
            ),
        )

    return _decorate(
        route
    )


@router.post(
    "/{route_id}/points"
)
def add_route_point(
    route_id: int,
    request: RoutePointRequest,
):
    _require_recording(
        route_id
    )

    seq = store.append_point(
        route_id=route_id,

        x_cm=request.x_cm,
        y_cm=request.y_cm,

        heading_deg=(
            request.heading_deg
        ),

        velocity_cm_s=(
            request.velocity_cm_s
        ),

        mode=request.mode,

        timestamp_ms=(
            request.timestamp_ms
        ),

        distance_cm=(
            request.distance_cm
        ),
    )

    return {
        "status": "saved",
        "route_id": route_id,
        "seq": seq,
    }


@router.post(
    "/{route_id}/points/batch"
)
def add_route_points_batch(
    route_id: int,
    request: RoutePointsBatchRequest,
):
    _require_recording(
        route_id
    )

    points = [
        {
            "x_cm":
                point.x_cm,

            "y_cm":
                point.y_cm,

            "heading_deg":
                point.heading_deg,

            "velocity_cm_s":
                point.velocity_cm_s,

            "mode":
                point.mode,

            "timestamp_ms":
                point.timestamp_ms,

            "distance_cm":
                point.distance_cm,
        }
        for point
        in request.points
    ]

    result = store.append_points(
        route_id,
        points,
    )

    return {
        "status": "saved",
        "route_id": route_id,
        **result,
    }


@router.post(
    "/{route_id}/events"
)
def add_route_event(
    route_id: int,
    request: RouteEventRequest,
):
    _require_recording(
        route_id
    )

    event_type = (
        request.event_type
        .strip()
        .upper()
    )

    if not event_type:
        raise HTTPException(
            status_code=400,
            detail=(
                "Event type is required"
            ),
        )

    store.add_event(
        route_id,
        event_type,
    )

    return {
        "status": "saved",
        "event": event_type,
    }


@router.post(
    "/{route_id}/finish"
)
def finish_route(
    route_id: int,
):
    global recording_route_id
    global active_route_id

    with _recording_lock:
        _require_recording(
            route_id
        )

        route = store.finish_route(
            route_id
        )

        if route is None:
            raise HTTPException(
                status_code=404,
                detail=(
                    "Recorded field "
                    "not found"
                ),
            )

        recording_route_id = None
        active_route_id = None

        return _decorate(
            route
        )


@router.post(
    "/{route_id}/discard"
)
def discard_route(
    route_id: int,
):
    global recording_route_id
    global active_route_id

    with _recording_lock:
        _require_recording(
            route_id
        )

        deleted = store.delete_route(
            route_id
        )

        if not deleted:
            raise HTTPException(
                status_code=404,
                detail=(
                    "Recorded field "
                    "not found"
                ),
            )

        if (
            recording_route_id
            == route_id
        ):
            recording_route_id = None

        active_route_id = None

        return {
            "status":
                "discarded",

            "route_id":
                route_id,
        }


@router.delete(
    "/{route_id}"
)
def delete_route(
    route_id: int,
):
    status = store.get_route_status(
        route_id
    )

    if status is None:
        raise HTTPException(
            status_code=404,
            detail=(
                "Recorded field "
                "not found"
            ),
        )

    if status == "recording":
        raise HTTPException(
            status_code=409,
            detail=(
                "Use Discard Recording "
                "for an unfinished field"
            ),
        )

    if not store.delete_route(
        route_id
    ):
        raise HTTPException(
            status_code=404,
            detail=(
                "Recorded field "
                "not found"
            ),
        )

    return {
        "status":
            "deleted",

        "route_id":
            route_id,
    }
