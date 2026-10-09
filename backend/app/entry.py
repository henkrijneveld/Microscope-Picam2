import re
from contextvars import ContextVar
from datetime import datetime as real_datetime
from threading import Lock

from fastapi import HTTPException
from starlette.middleware.base import BaseHTTPMiddleware

from . import main as core


STACK_TIMESTAMP_HEADER = "x-microrasp-stack-timestamp"
STACK_NUMBER_HEADER = "x-microrasp-stack-number"
STACK_TIMESTAMP_PATTERN = re.compile(r"^\d{6}-\d{6}$")

stack_timestamp_context = ContextVar("stack_timestamp", default=None)
stack_number_context = ContextVar("stack_number", default=None)
stack_capture_lock = Lock()


class FocusStackContextMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request, call_next):
        timestamp_token = stack_timestamp_context.set(
            request.headers.get(STACK_TIMESTAMP_HEADER)
            if request.url.path == "/api/photo"
            else None
        )
        number_token = stack_number_context.set(
            request.headers.get(STACK_NUMBER_HEADER)
            if request.url.path == "/api/photo"
            else None
        )

        try:
            return await call_next(request)
        finally:
            stack_timestamp_context.reset(timestamp_token)
            stack_number_context.reset(number_token)


def parse_focus_stack():
    raw_timestamp = stack_timestamp_context.get()
    raw_number = stack_number_context.get()

    if raw_timestamp is None and raw_number is None:
        return None

    if raw_timestamp is None or raw_number is None:
        raise HTTPException(
            status_code=400,
            detail="Focus stack timestamp and number must both be supplied",
        )

    if not STACK_TIMESTAMP_PATTERN.fullmatch(raw_timestamp):
        raise HTTPException(
            status_code=400,
            detail="Invalid focus stack timestamp",
        )

    try:
        stack_timestamp = real_datetime.strptime(raw_timestamp, "%y%m%d-%H%M%S")
        stack_number = int(raw_number)
    except ValueError as exc:
        raise HTTPException(
            status_code=400,
            detail="Invalid focus stack timestamp or number",
        ) from exc

    if stack_number < 1:
        raise HTTPException(
            status_code=400,
            detail="Focus stack number must be at least 1",
        )

    return stack_timestamp, stack_number


def take_photo_with_focus_stack(settings):
    focus_stack = parse_focus_stack()

    if focus_stack is None:
        return core.take_photo(settings)

    stack_timestamp, stack_number = focus_stack

    class StackDateTime(real_datetime):
        @classmethod
        def now(cls, tz=None):
            if tz is None:
                return stack_timestamp

            return stack_timestamp.replace(tzinfo=tz)

    with stack_capture_lock:
        original_datetime = core.datetime
        original_sanitize = core.sanitize_photo_name

        def sanitize_stack_photo_name(name):
            safe_name = original_sanitize(name)

            if not safe_name:
                return safe_name

            prefix = f"{stack_number}-"
            return f"{prefix}{safe_name[:max(1, 80 - len(prefix))]}"

        core.datetime = StackDateTime
        core.sanitize_photo_name = sanitize_stack_photo_name

        try:
            return core.take_photo(settings)
        finally:
            core.datetime = original_datetime
            core.sanitize_photo_name = original_sanitize


app = core.app
app.add_middleware(FocusStackContextMiddleware)

for route in app.routes:
    if (
        getattr(route, "path", None) == "/api/photo"
        and "POST" in getattr(route, "methods", set())
        and hasattr(route, "dependant")
    ):
        route.endpoint = take_photo_with_focus_stack
        route.dependant.call = take_photo_with_focus_stack
        break
