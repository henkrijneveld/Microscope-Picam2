import io
from contextlib import asynccontextmanager
from threading import Condition

from fastapi import FastAPI
from fastapi.responses import HTMLResponse, StreamingResponse
from picamera2 import Picamera2
from picamera2.encoders import MJPEGEncoder
from picamera2.outputs import FileOutput


class StreamingOutput(io.BufferedIOBase):
    def __init__(self):
        self.frame = None
        self.condition = Condition()

    def write(self, buf):
        with self.condition:
            self.frame = buf
            self.condition.notify_all()


picam2: Picamera2 | None = None
camera_error: str | None = None
output = StreamingOutput()


@asynccontextmanager
async def lifespan(app: FastAPI):
    global picam2, camera_error

    try:
        picam2 = Picamera2()

        config = picam2.create_video_configuration(
            main={"size": (640, 480)}
        )
        picam2.configure(config)

        picam2.start_recording(
            MJPEGEncoder(),
            FileOutput(output),
        )

        camera_error = None

    except Exception as exc:
        picam2 = None
        camera_error = str(exc)

    yield

    if picam2 is not None:
        picam2.stop_recording()
        picam2.close()


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
    while True:
        with output.condition:
            output.condition.wait()
            frame = output.frame

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