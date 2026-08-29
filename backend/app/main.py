import io
import signal
from contextlib import asynccontextmanager
from threading import Condition, Event, Lock, current_thread, main_thread

from fastapi import FastAPI, HTTPException
from fastapi.responses import HTMLResponse, Response, StreamingResponse
from picamera2 import Picamera2
from picamera2.encoders import MJPEGEncoder
from picamera2.outputs import FileOutput
from pydantic import BaseModel


class StreamingOutput(io.BufferedIOBase):
    def __init__(self):
        self.frame = None
        self.sequence = 0
        self.condition = Condition()

    def write(self, buf):
        with self.condition:
            self.frame = buf
            self.sequence += 1
            self.condition.notify_all()


picam2: Picamera2 | None = None
camera_error: str | None = None
output = StreamingOutput()
stream_stop = Event()
camera_lock = Lock()
exposure_auto = True
frame_rate = 15

ALLOWED_FRAME_RATES = {1, 5, 15}


class ExposureSettings(BaseModel):
    auto: bool
    exposure_time_us: int | None = None


class ExposureStep(BaseModel):
    factor: float


class FrameRateSettings(BaseModel):
    fps: int


def start_stream_encoder():
    if picam2 is None:
        return

    picam2.start_encoder(
        MJPEGEncoder(),
        FileOutput(output),
    )


def stop_streams():
    stream_stop.set()
    with output.condition:
        output.condition.notify_all()


def install_shutdown_signal_handlers():
    if current_thread() is not main_thread():
        return {}

    previous_handlers = {}

    for sig in (signal.SIGINT, signal.SIGTERM):
        previous_handler = signal.getsignal(sig)
        previous_handlers[sig] = previous_handler

        def handler(signum, frame, previous_handler=previous_handler):
            stop_streams()

            if callable(previous_handler):
                previous_handler(signum, frame)

        signal.signal(sig, handler)

    return previous_handlers


def restore_shutdown_signal_handlers(previous_handlers):
    if current_thread() is not main_thread():
        return

    for sig, previous_handler in previous_handlers.items():
        signal.signal(sig, previous_handler)


@asynccontextmanager
async def lifespan(app: FastAPI):
    global picam2, camera_error

    stream_stop.clear()
    previous_signal_handlers = install_shutdown_signal_handlers()

    try:
        picam2 = Picamera2()

        config = picam2.create_video_configuration(
            main={"size": (640, 480)},
            controls={"FrameRate": 15},
        )
        picam2.configure(config)

        picam2.set_controls({
            "AeEnable": True,
        })
        picam2.start()
        start_stream_encoder()

        camera_error = None

    except Exception as exc:
        picam2 = None
        camera_error = str(exc)

    yield

    stop_streams()

    if picam2 is not None:
        try:
            picam2.stop_encoder()
        except Exception:
            pass

        picam2.stop()
        picam2.close()

    restore_shutdown_signal_handlers(previous_signal_handlers)


app = FastAPI(
    title="Microscope Picam2",
    lifespan=lifespan,
)


@app.get("/", response_class=HTMLResponse)
def index():
    return """
    <!doctype html>
    <html lang="nl">
    <head>
        <meta charset="utf-8">
        <title>Microscope Picam2</title>
    </head>
    <body>
        <h1>Microscope Picam2</h1>

        <img
            src="/api/stream"
            alt="Live camerabeeld"
        >
    </body>
    </html>
    """


@app.get("/api/status")
def status():
    if picam2 is None:
        return {
            "status": "error",
            "camera": {
                "connected": False,
                "error": camera_error,
            },
        }

    return {
        "status": "ok",
        "camera": {
            "connected": True,
            "model": picam2.camera_properties.get("Model", "unknown"),
        },
    }


def generate_mjpeg():
    last_sequence = 0

    while not stream_stop.is_set():
        with output.condition:
            output.condition.wait_for(
                lambda: stream_stop.is_set()
                or (
                    output.frame is not None
                    and output.sequence != last_sequence
                )
            )

            if stream_stop.is_set():
                return

            frame = output.frame
            last_sequence = output.sequence

        yield (
            b"--FRAME\r\n"
            b"Content-Type: image/jpeg\r\n"
            b"Content-Length: " + str(len(frame)).encode() + b"\r\n"
            b"\r\n"
            + frame
            + b"\r\n"
        )


@app.get("/api/stream")
def stream():
    return StreamingResponse(
        generate_mjpeg(),
        media_type="multipart/x-mixed-replace; boundary=FRAME",
        headers={
            "Cache-Control": "no-cache, private",
            "Pragma": "no-cache",
        },
    )


@app.post("/api/photo")
def take_photo():
    global frame_rate

    if picam2 is None:
        raise HTTPException(status_code=503, detail="Camera not available")

    with camera_lock:
        metadata = picam2.capture_metadata()
        current_exposure = metadata.get("ExposureTime")

        still_controls = {
            "AeEnable": exposure_auto,
        }

        if not exposure_auto and current_exposure is not None:
            still_controls["ExposureTime"] = current_exposure

        still_config = picam2.create_still_configuration(
            controls=still_controls,
        )

        photo = io.BytesIO()

        picam2.stop_encoder()

        try:
            picam2.switch_mode_and_capture_file(
                still_config,
                photo,
                format="jpeg",
            )
        finally:
            frame_duration_us = round(1_000_000 / frame_rate)

            restore_controls = {
                "AeEnable": exposure_auto,
                "FrameDurationLimits": (
                    frame_duration_us,
                    frame_duration_us,
                ),
            }

            if not exposure_auto and current_exposure is not None:
                restore_controls["ExposureTime"] = current_exposure

            picam2.set_controls(restore_controls)
            start_stream_encoder()

        return Response(
            content=photo.getvalue(),
            media_type="image/jpeg",
            headers={
                "Content-Disposition": 'attachment; filename="microscope.jpg"',
                "Cache-Control": "no-store",
            },
        )


@app.get("/api/framerate")
def get_framerate():
    if picam2 is None:
        raise HTTPException(status_code=503, detail="Camera not available")

    with camera_lock:
        metadata = picam2.capture_metadata()
        frame_duration_us = metadata.get("FrameDuration")

    fps = None
    if frame_duration_us:
        fps = round(1_000_000 / frame_duration_us)

    return {
        "fps": fps,
        "frame_duration_us": frame_duration_us,
        "options": sorted(ALLOWED_FRAME_RATES, reverse=True),
    }


@app.put("/api/framerate")
def set_framerate(settings: FrameRateSettings):
    global frame_rate

    if picam2 is None:
        raise HTTPException(status_code=503, detail="Camera not available")

    if settings.fps not in ALLOWED_FRAME_RATES:
        raise HTTPException(
            status_code=400,
            detail="Frame rate must be 15, 5 or 1 fps",
        )

    frame_duration_us = round(1_000_000 / settings.fps)

    with camera_lock:
        picam2.set_controls({
            "FrameDurationLimits": (frame_duration_us, frame_duration_us),
        })
        frame_rate = settings.fps

    return {
        "fps": settings.fps,
        "frame_duration_us": frame_duration_us,
        "options": sorted(ALLOWED_FRAME_RATES, reverse=True),
    }


@app.get("/api/exposure")
def get_exposure():
    if picam2 is None:
        raise HTTPException(status_code=503, detail="Camera not available")

    with camera_lock:
        metadata = picam2.capture_metadata()

    return {
        "auto": exposure_auto,
        "exposure_time_us": metadata.get("ExposureTime"),
        "analogue_gain": metadata.get("AnalogueGain"),
        "digital_gain": metadata.get("DigitalGain"),
    }


@app.put("/api/exposure")
def set_exposure(settings: ExposureSettings):
    global exposure_auto

    if picam2 is None:
        raise HTTPException(status_code=503, detail="Camera not available")

    controls = {
        "AeEnable": settings.auto,
    }

    if not settings.auto and settings.exposure_time_us is not None:
        exposure_min, exposure_max, _ = picam2.camera_controls["ExposureTime"]

        if not exposure_min <= settings.exposure_time_us <= exposure_max:
            raise HTTPException(
                status_code=400,
                detail=f"Exposure time must be between {exposure_min} and {exposure_max} us",
            )

        controls["ExposureTime"] = settings.exposure_time_us

    with camera_lock:
        picam2.set_controls(controls)
        exposure_auto = settings.auto

    return {
        "auto": exposure_auto,
        "exposure_time_us": settings.exposure_time_us,
    }


@app.put("/api/exposure/step")
def step_exposure(step: ExposureStep):
    global exposure_auto

    if picam2 is None:
        raise HTTPException(status_code=503, detail="Camera not available")

    if exposure_auto:
        raise HTTPException(
            status_code=400,
            detail="Exposure stepping is only available in manual mode",
        )

    with camera_lock:
        metadata = picam2.capture_metadata()
        current_exposure = metadata.get("ExposureTime")

        if current_exposure is None:
            raise HTTPException(
                status_code=500,
                detail="Current exposure time unavailable",
            )

        exposure_min, exposure_max, _ = picam2.camera_controls["ExposureTime"]

        new_exposure = round(current_exposure * step.factor)

        new_exposure = max(
            exposure_min,
            min(new_exposure, exposure_max),
        )

        picam2.set_controls({
            "ExposureTime": new_exposure,
        })

    return {
        "auto": False,
        "exposure_time_us": new_exposure,
        "factor": step.factor,
    }
