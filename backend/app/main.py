import io
import json
import re
import signal
import subprocess
import unicodedata
from contextlib import asynccontextmanager
from datetime import datetime
from pathlib import Path
from threading import Condition, Event, Lock, current_thread, main_thread
from time import monotonic

import piexif
import piexif.helper
from fastapi import BackgroundTasks, FastAPI, HTTPException
from fastapi.responses import FileResponse, HTMLResponse, StreamingResponse
from fastapi.staticfiles import StaticFiles
from picamera2 import Picamera2
from picamera2.encoders import MJPEGEncoder
from picamera2.outputs import FileOutput
from pydantic import BaseModel


PROJECT_DIR = Path(__file__).resolve().parents[2]
LIVE_SIZE = (640, 480)
LIVE_SENSOR_SIZE = (2028, 1520)
PHOTO_DIR = PROJECT_DIR / "photos"
FRONTEND_DIST = PROJECT_DIR / "frontend" / "dist"
POWEROFF_HELPER = Path("/usr/local/sbin/microscope-picam2-poweroff")

AEB_TIMEOUT_SECONDS = 5.0
AEB_STEPS = (
    (-2, 0.25, "m2"),
    (0, 1.0, "0"),
    (2, 4.0, "p2"),
)


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
metadata_lock = Lock()
capture_status_lock = Lock()
latest_metadata: dict = {}
capture_status: dict = {
    "active": False,
    "aeb": False,
    "step": 0,
    "total": 0,
    "ev": None,
    "state": "idle",
    "error": None,
}
exposure_auto = True
exposure_value = 0.0
manual_exposure_time_us: int | None = None
frame_rate = 15
white_balance_auto = True
white_balance_gains: tuple[float, float] | None = None

ALLOWED_FRAME_RATES = {1, 5, 15}
ALLOWED_EXPOSURE_VALUES = {-1.0, -0.5, -0.25, 0.0, 0.25, 0.5, 1.0}


class ExposureSettings(BaseModel):
    auto: bool
    exposure_time_us: int | None = None


class ExposureStep(BaseModel):
    factor: float


class ExposureValueSettings(BaseModel):
    value: float


class FrameRateSettings(BaseModel):
    fps: int


class PhotoSettings(BaseModel):
    name: str
    aeb: bool = False


class WhiteBalanceSettings(BaseModel):
    auto: bool


class ShutdownSettings(BaseModel):
    confirm: str


def start_stream_encoder():
    if picam2 is None:
        return

    picam2.start_encoder(
        MJPEGEncoder(),
        FileOutput(output),
    )


def cache_camera_metadata(request):
    global latest_metadata

    metadata = request.get_metadata()

    with metadata_lock:
        latest_metadata = metadata


def get_latest_metadata():
    with metadata_lock:
        return latest_metadata.copy()


def set_capture_status(**changes):
    with capture_status_lock:
        capture_status.update(changes)


def get_capture_status():
    with capture_status_lock:
        return capture_status.copy()


def sanitize_photo_name(name: str):
    normalized = unicodedata.normalize("NFKD", name)
    normalized = normalized.encode("ascii", "ignore").decode("ascii")
    normalized = re.sub(r"\s+", "-", normalized.strip())
    normalized = re.sub(r"[^A-Za-z0-9_-]+", "-", normalized)
    normalized = re.sub(r"-+", "-", normalized).strip("-_")

    return normalized[:80]


def get_unique_photo_path(filename: str):
    photo_path = PHOTO_DIR / filename
    counter = 2

    while photo_path.exists():
        photo_path = PHOTO_DIR / f"{Path(filename).stem}-{counter}.jpg"
        counter += 1

    return photo_path


def get_photo_path(filename: str):
    if filename != Path(filename).name or Path(filename).suffix.lower() != ".jpg":
        raise HTTPException(status_code=400, detail="Invalid photo filename")

    photo_path = PHOTO_DIR / filename

    if not photo_path.is_file():
        raise HTTPException(status_code=404, detail="Photo not found")

    return photo_path


def embed_photo_metadata(jpeg_data: bytes, photo_metadata: dict, safe_name: str):
    exif_dict = piexif.load(jpeg_data)

    exif_dict["0th"][piexif.ImageIFD.ImageDescription] = safe_name
    exif_dict["Exif"][piexif.ExifIFD.UserComment] = piexif.helper.UserComment.dump(
        json.dumps(
            photo_metadata,
            ensure_ascii=False,
            default=str,
            separators=(",", ":"),
        ),
        encoding="unicode",
    )

    exif_bytes = piexif.dump(exif_dict)
    output_file = io.BytesIO()
    piexif.insert(exif_bytes, jpeg_data, output_file)

    return output_file.getvalue()


def wait_for_exposure(target_exposure_us: int):
    if picam2 is None:
        raise RuntimeError("Camera not available")

    deadline = monotonic() + AEB_TIMEOUT_SECONDS
    tolerance = max(100, round(target_exposure_us * 0.02))
    last_exposure = None

    while monotonic() < deadline:
        metadata = picam2.capture_metadata()
        last_exposure = metadata.get("ExposureTime")

        if (
            last_exposure is not None
            and abs(int(last_exposure) - target_exposure_us) <= tolerance
        ):
            return metadata

    raise TimeoutError(
        f"Exposure did not stabilise at {target_exposure_us} us "
        f"within {AEB_TIMEOUT_SECONDS:.0f} seconds; last value was {last_exposure} us"
    )


def stop_streams():
    stream_stop.set()
    with output.condition:
        output.condition.notify_all()


def poweroff_pi():
    subprocess.run(
        ["sudo", "-n", str(POWEROFF_HELPER)],
        check=False,
    )


def get_system_identity():
    hostname = subprocess.run(
        ["hostname"],
        capture_output=True,
        text=True,
        check=False,
    ).stdout.strip()

    addresses = subprocess.run(
        ["hostname", "-I"],
        capture_output=True,
        text=True,
        check=False,
    ).stdout.split()

    ip_address = next(
        (
            address
            for address in addresses
            if "." in address and not address.startswith("127.")
        ),
        None,
    )

    return hostname or None, ip_address


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
    global picam2, camera_error, latest_metadata

    PHOTO_DIR.mkdir(parents=True, exist_ok=True)
    stream_stop.clear()

    with metadata_lock:
        latest_metadata = {}

    previous_signal_handlers = install_shutdown_signal_handlers()

    try:
        picam2 = Picamera2()
        picam2.post_callback = cache_camera_metadata

        config = picam2.create_video_configuration(
            main={"size": LIVE_SIZE},
            sensor={
                "output_size": LIVE_SENSOR_SIZE,
                "bit_depth": 12,
            },
            controls={"FrameRate": 15},
        )
        picam2.configure(config)

        picam2.set_controls({
            "AeEnable": True,
            "ExposureValue": exposure_value,
            "AwbEnable": True,
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

    hostname, ip_address = get_system_identity()

    return {
        "status": "ok",
        "camera": {
            "connected": True,
            "hostname": hostname,
            "ip_address": ip_address,
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


@app.get("/api/photo/status")
def photo_status():
    return get_capture_status()


def build_photo_metadata(
    requested_name: str,
    filename: str,
    capture_time: datetime,
    still_config: dict,
    captured_metadata: dict,
    *,
    aeb: bool,
    aeb_ev: int | None = None,
    base_exposure_us: int | None = None,
):
    active_colour_gains = captured_metadata.get("ColourGains")

    return {
        "microscope_picam2": {
            "name": requested_name,
            "filename": filename,
            "capture_time": capture_time.isoformat(timespec="seconds"),
            "camera_model": picam2.camera_properties.get("Model", "unknown") if picam2 else "unknown",
            "stream_resolution": list(LIVE_SIZE),
            "still_resolution": list(still_config["main"]["size"]),
            "jpeg_quality": picam2.options.get("quality", 90) if picam2 else 90,
            "frame_rate_fps": frame_rate,
            "exposure_auto": exposure_auto,
            "exposure_value_ev": exposure_value if exposure_auto else None,
            "white_balance_mode": "auto" if white_balance_auto else "single_shot",
            "white_balance_red_gain": (
                active_colour_gains[0]
                if active_colour_gains is not None
                else None
            ),
            "white_balance_blue_gain": (
                active_colour_gains[1]
                if active_colour_gains is not None
                else None
            ),
            "aeb": aeb,
            "aeb_ev": aeb_ev,
            "aeb_base_exposure_us": base_exposure_us,
        },
        "camera_metadata": captured_metadata,
    }


def restore_live_view(preview_config: dict, current_exposure):
    if picam2 is None:
        return

    picam2.switch_mode(preview_config)

    frame_duration_us = round(1_000_000 / frame_rate)
    restore_controls = {
        "AeEnable": exposure_auto,
        "FrameDurationLimits": (
            frame_duration_us,
            frame_duration_us,
        ),
    }

    if exposure_auto:
        restore_controls["ExposureValue"] = exposure_value
    elif manual_exposure_time_us is not None:
        restore_controls["ExposureTime"] = manual_exposure_time_us
    elif current_exposure is not None:
        restore_controls["ExposureTime"] = current_exposure

    if white_balance_auto:
        restore_controls["AwbEnable"] = True
    elif white_balance_gains is not None:
        restore_controls["AwbEnable"] = False
        restore_controls["ColourGains"] = white_balance_gains

    picam2.set_controls(restore_controls)
    start_stream_encoder()


@app.post("/api/photo")
def take_photo(settings: PhotoSettings):
    if picam2 is None:
        raise HTTPException(status_code=503, detail="Camera not available")

    requested_name = settings.name.strip()
    safe_name = sanitize_photo_name(requested_name)

    if not safe_name:
        raise HTTPException(
            status_code=400,
            detail="Photo name is required",
        )

    set_capture_status(
        active=True,
        aeb=settings.aeb,
        step=0,
        total=3 if settings.aeb else 1,
        ev=None,
        state="starting",
        error=None,
    )

    try:
        with camera_lock:
            capture_time = datetime.now()
            timestamp = capture_time.strftime("%y%m%d-%H%M%S")
            metadata = get_latest_metadata()

            if not metadata:
                metadata = picam2.capture_metadata()

            current_exposure = metadata.get("ExposureTime")
            current_gain = metadata.get("AnalogueGain")
            current_colour_gains = metadata.get("ColourGains")

            if current_exposure is None:
                raise HTTPException(
                    status_code=500,
                    detail="Current exposure time unavailable",
                )

            preview_config = picam2.camera_configuration()

            if settings.aeb:
                if current_gain is None:
                    raise HTTPException(
                        status_code=500,
                        detail="Current analogue gain unavailable",
                    )

                still_controls = {
                    "AeEnable": False,
                    "ExposureTime": int(current_exposure),
                    "AnalogueGain": float(current_gain),
                }
            else:
                still_controls = {
                    "AeEnable": exposure_auto,
                }

                if exposure_auto:
                    still_controls["ExposureValue"] = exposure_value
                elif manual_exposure_time_us is not None:
                    still_controls["ExposureTime"] = manual_exposure_time_us
                else:
                    still_controls["ExposureTime"] = current_exposure

            # Freeze the current live-view white balance for the still image(s).
            if white_balance_auto and current_colour_gains is not None:
                still_controls["AwbEnable"] = False
                still_controls["ColourGains"] = tuple(current_colour_gains)
            elif not white_balance_auto and white_balance_gains is not None:
                still_controls["AwbEnable"] = False
                still_controls["ColourGains"] = white_balance_gains
            else:
                still_controls["AwbEnable"] = True

            still_config = picam2.create_still_configuration(
                controls=still_controls,
            )

            picam2.stop_encoder()

            try:
                if settings.aeb:
                    picam2.switch_mode(still_config)
                    exposure_min, exposure_max, _ = picam2.camera_controls["ExposureTime"]
                    files = []

                    for index, (ev, factor, label) in enumerate(AEB_STEPS, start=1):
                        target_exposure = round(int(current_exposure) * factor)
                        target_exposure = max(
                            exposure_min,
                            min(target_exposure, exposure_max),
                        )

                        set_capture_status(
                            active=True,
                            aeb=True,
                            step=index,
                            total=3,
                            ev=ev,
                            state="stabilising",
                            error=None,
                        )

                        picam2.set_controls({
                            "AeEnable": False,
                            "ExposureTime": target_exposure,
                            "AnalogueGain": float(current_gain),
                        })

                        try:
                            wait_for_exposure(target_exposure)
                        except TimeoutError as exc:
                            raise HTTPException(status_code=504, detail=str(exc)) from exc

                        set_capture_status(state="capturing")

                        photo = io.BytesIO()
                        captured_metadata = picam2.capture_file(
                            photo,
                            format="jpeg",
                        )
                        actual_exposure = int(
                            captured_metadata.get("ExposureTime", target_exposure)
                        )

                        base_filename = (
                            f"{timestamp}-{safe_name}-AEB-{label}-{actual_exposure}us.jpg"
                        )
                        photo_path = get_unique_photo_path(base_filename)
                        filename = photo_path.name

                        photo_metadata = build_photo_metadata(
                            requested_name,
                            filename,
                            capture_time,
                            still_config,
                            captured_metadata,
                            aeb=True,
                            aeb_ev=ev,
                            base_exposure_us=int(current_exposure),
                        )
                        photo_data = embed_photo_metadata(
                            photo.getvalue(),
                            photo_metadata,
                            safe_name,
                        )
                        photo_path.write_bytes(photo_data)
                        files.append({
                            "filename": filename,
                            "size_bytes": len(photo_data),
                            "ev": ev,
                            "exposure_time_us": actual_exposure,
                        })

                    result = {
                        "aeb": True,
                        "filenames": [item["filename"] for item in files],
                        "files": files,
                    }
                else:
                    set_capture_status(
                        active=True,
                        aeb=False,
                        step=1,
                        total=1,
                        ev=None,
                        state="capturing",
                        error=None,
                    )

                    photo = io.BytesIO()
                    captured_metadata = picam2.switch_mode_and_capture_file(
                        still_config,
                        photo,
                        format="jpeg",
                    )

                    base_filename = f"{timestamp}-{safe_name}.jpg"
                    photo_path = get_unique_photo_path(base_filename)
                    filename = photo_path.name
                    photo_metadata = build_photo_metadata(
                        requested_name,
                        filename,
                        capture_time,
                        still_config,
                        captured_metadata,
                        aeb=False,
                    )
                    photo_data = embed_photo_metadata(
                        photo.getvalue(),
                        photo_metadata,
                        safe_name,
                    )
                    photo_path.write_bytes(photo_data)
                    result = {
                        "aeb": False,
                        "filename": filename,
                        "size_bytes": len(photo_data),
                    }
            finally:
                if settings.aeb:
                    restore_live_view(preview_config, current_exposure)
                else:
                    frame_duration_us = round(1_000_000 / frame_rate)
                    restore_controls = {
                        "AeEnable": exposure_auto,
                        "FrameDurationLimits": (
                            frame_duration_us,
                            frame_duration_us,
                        ),
                    }

                    if exposure_auto:
                        restore_controls["ExposureValue"] = exposure_value
                    elif manual_exposure_time_us is not None:
                        restore_controls["ExposureTime"] = manual_exposure_time_us
                    else:
                        restore_controls["ExposureTime"] = current_exposure

                    if white_balance_auto:
                        restore_controls["AwbEnable"] = True
                    elif white_balance_gains is not None:
                        restore_controls["AwbEnable"] = False
                        restore_controls["ColourGains"] = white_balance_gains

                    picam2.set_controls(restore_controls)
                    start_stream_encoder()

        set_capture_status(
            active=False,
            state="complete",
            error=None,
        )
        return result
    except HTTPException as exc:
        set_capture_status(
            active=False,
            state="error",
            error=exc.detail,
        )
        raise
    except Exception as exc:
        set_capture_status(
            active=False,
            state="error",
            error=str(exc),
        )
        raise


@app.get("/api/files")
def list_files():
    PHOTO_DIR.mkdir(parents=True, exist_ok=True)

    files = []
    for photo_path in sorted(PHOTO_DIR.glob("*.jpg"), reverse=True):
        stat = photo_path.stat()
        files.append({
            "name": photo_path.name,
            "size_bytes": stat.st_size,
            "modified": datetime.fromtimestamp(stat.st_mtime).isoformat(timespec="seconds"),
        })

    return {
        "directory": str(PHOTO_DIR),
        "files": files,
    }


@app.get("/api/files/{filename}")
def download_file(filename: str):
    photo_path = get_photo_path(filename)

    return FileResponse(
        path=photo_path,
        media_type="image/jpeg",
        filename=photo_path.name,
    )


@app.get("/api/framerate")
def get_framerate():
    if picam2 is None:
        raise HTTPException(status_code=503, detail="Camera not available")

    return {
        "fps": frame_rate,
        "frame_duration_us": round(1_000_000 / frame_rate),
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

    metadata = get_latest_metadata()

    exposure_time_us = metadata.get("ExposureTime")
    if not exposure_auto and manual_exposure_time_us is not None:
        exposure_time_us = manual_exposure_time_us

    return {
        "auto": exposure_auto,
        "exposure_value": exposure_value,
        "exposure_time_us": exposure_time_us,
        "analogue_gain": metadata.get("AnalogueGain"),
        "digital_gain": metadata.get("DigitalGain"),
    }


@app.put("/api/exposure")
def set_exposure(settings: ExposureSettings):
    global exposure_auto, manual_exposure_time_us

    if picam2 is None:
        raise HTTPException(status_code=503, detail="Camera not available")

    controls = {
        "AeEnable": settings.auto,
    }

    if settings.auto:
        controls["ExposureValue"] = exposure_value
    elif settings.exposure_time_us is not None:
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

        if not settings.auto and settings.exposure_time_us is not None:
            manual_exposure_time_us = settings.exposure_time_us

    return {
        "auto": exposure_auto,
        "exposure_value": exposure_value,
        "exposure_time_us": (
            manual_exposure_time_us
            if not exposure_auto
            else settings.exposure_time_us
        ),
    }


@app.put("/api/exposure/value")
def set_exposure_value(settings: ExposureValueSettings):
    global exposure_value

    if picam2 is None:
        raise HTTPException(status_code=503, detail="Camera not available")

    if not exposure_auto:
        raise HTTPException(
            status_code=400,
            detail="Exposure compensation is only available in auto mode",
        )

    if settings.value not in ALLOWED_EXPOSURE_VALUES:
        raise HTTPException(
            status_code=400,
            detail="Exposure value must be -1, -0.5, -0.25, 0, 0.25, 0.5 or 1",
        )

    with camera_lock:
        picam2.set_controls({
            "ExposureValue": settings.value,
        })
        exposure_value = settings.value

    return {
        "auto": True,
        "exposure_value": exposure_value,
    }


@app.put("/api/exposure/step")
def step_exposure(step: ExposureStep):
    global manual_exposure_time_us

    if picam2 is None:
        raise HTTPException(status_code=503, detail="Camera not available")

    if exposure_auto:
        raise HTTPException(
            status_code=400,
            detail="Exposure stepping is only available in manual mode",
        )

    current_exposure = manual_exposure_time_us

    if current_exposure is None:
        current_exposure = get_latest_metadata().get("ExposureTime")

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

    with camera_lock:
        picam2.set_controls({
            "ExposureTime": new_exposure,
        })
        manual_exposure_time_us = new_exposure

    return {
        "auto": False,
        "exposure_time_us": new_exposure,
        "factor": step.factor,
    }


@app.get("/api/whitebalance")
def get_white_balance():
    if picam2 is None:
        raise HTTPException(status_code=503, detail="Camera not available")

    metadata = get_latest_metadata()
    colour_gains = metadata.get("ColourGains")

    return {
        "auto": white_balance_auto,
        "mode": "auto" if white_balance_auto else "single_shot",
        "red_gain": colour_gains[0] if colour_gains is not None else None,
        "blue_gain": colour_gains[1] if colour_gains is not None else None,
        "colour_temperature": metadata.get("ColourTemperature"),
        "locked": metadata.get("AwbLocked"),
    }


@app.put("/api/whitebalance")
def set_white_balance(settings: WhiteBalanceSettings):
    global white_balance_auto, white_balance_gains

    if picam2 is None:
        raise HTTPException(status_code=503, detail="Camera not available")

    if not settings.auto:
        raise HTTPException(
            status_code=400,
            detail="Use single-shot white balance to set a fixed white balance",
        )

    with camera_lock:
        picam2.set_controls({
            "AwbEnable": True,
        })
        white_balance_auto = True
        white_balance_gains = None

    return {
        "auto": True,
        "mode": "auto",
    }


@app.post("/api/whitebalance/single")
def set_single_shot_white_balance():
    global white_balance_auto, white_balance_gains

    if picam2 is None:
        raise HTTPException(status_code=503, detail="Camera not available")

    with camera_lock:
        picam2.set_controls({
            "AwbEnable": True,
        })

        previous_gains = None
        stable_frames = 0
        selected_gains = None
        selected_metadata = None

        # Prefer AwbLocked when the platform reports it. The stability fallback
        # also makes this usable on pipelines that do not expose AwbLocked.
        for _ in range(8):
            metadata = picam2.capture_metadata()
            colour_gains = metadata.get("ColourGains")

            if colour_gains is None:
                continue

            gains = (float(colour_gains[0]), float(colour_gains[1]))
            selected_gains = gains
            selected_metadata = metadata

            if metadata.get("AwbLocked") is True:
                break

            if previous_gains is not None:
                red_delta = abs(gains[0] - previous_gains[0])
                blue_delta = abs(gains[1] - previous_gains[1])
                red_limit = max(0.01, abs(gains[0]) * 0.01)
                blue_limit = max(0.01, abs(gains[1]) * 0.01)

                if red_delta <= red_limit and blue_delta <= blue_limit:
                    stable_frames += 1
                else:
                    stable_frames = 0

                if stable_frames >= 2:
                    break

            previous_gains = gains

        if selected_gains is None:
            raise HTTPException(
                status_code=500,
                detail="White balance gains unavailable",
            )

        picam2.set_controls({
            "AwbEnable": False,
            "ColourGains": selected_gains,
        })

        white_balance_auto = False
        white_balance_gains = selected_gains

    return {
        "auto": False,
        "mode": "single_shot",
        "red_gain": selected_gains[0],
        "blue_gain": selected_gains[1],
        "colour_temperature": (
            selected_metadata.get("ColourTemperature")
            if selected_metadata is not None
            else None
        ),
    }


@app.post("/api/system/shutdown")
def shutdown_pi(settings: ShutdownSettings, background_tasks: BackgroundTasks):
    if settings.confirm != "shutdown":
        raise HTTPException(
            status_code=400,
            detail="Shutdown confirmation missing",
        )

    if not POWEROFF_HELPER.is_file():
        raise HTTPException(
            status_code=503,
            detail="Poweroff helper is not installed",
        )

    background_tasks.add_task(poweroff_pi)

    return {
        "status": "shutting_down",
    }


if FRONTEND_DIST.is_dir():
    app.mount(
        "/",
        StaticFiles(directory=FRONTEND_DIST, html=True),
        name="frontend",
    )
else:
    @app.get("/", response_class=HTMLResponse)
    def frontend_not_built():
        return """
        <!doctype html>
        <html lang="nl">
        <head>
            <meta charset="utf-8">
            <title>Microscope Picam2</title>
        </head>
        <body>
            <h1>Microscope Picam2</h1>
            <p>Frontend is nog niet gebouwd. Start de server via runback.sh.</p>
        </body>
        </html>
        """
