# Microscope-Picam2

Microscope camera based on Raspberry Pi, HQ Camera and Picamera2.

## Production / new Raspberry Pi

A production installation does **not** use a virtual environment. MicroRasp always
uses the Raspberry Pi OS system interpreter at `/usr/bin/python3`.

Picamera2 and libcamera are installed through `apt`. The remaining Python
dependencies are installed locally in the MicroRasp directory under `python/`.

### Build a release

On the development machine:

```bash
./build-dist.sh
```

This creates:

```text
dist/
├── MicroRasp/
│   ├── backend/
│   ├── frontend/
│   │   └── dist/
│   ├── python/
│   ├── photos/
│   │   └── mertens.sh
│   ├── resources/
│   │   └── mertens.sh
│   ├── .env.local.example
│   ├── LICENSE
│   ├── install.sh
│   ├── uninstall.sh
│   ├── check-installation.sh
│   ├── requirements.txt
│   ├── run.sh
│   ├── start.sh
│   ├── stop.sh
│   ├── enable-autostart.sh
│   └── disable-autostart.sh
└── MicroRasp.zip
```

The distribution directory and ZIP are generated locally and ignored by Git.
Upload `dist/MicroRasp.zip` as the binary asset for a GitHub Release.

The canonical Mertens helper is stored in `resources/mertens.sh`. At every
MicroRasp service start, `run.sh` recreates `photos/mertens.sh` from that
copy and sets it to read-only mode `0555`. This means the photos directory can
be emptied through SFTP or a file manager without permanently losing the helper;
a service restart restores it automatically.

When `mertens.sh YYMMDD-HHMMSS` detects focus-stack filenames
(`YYMMDD-HHMMSS-<number>-<name>`), it also creates
`YYMMDD-HHMMSS-focusstack/` in the current directory. HDR/AEB stacks are
placed there as fused TIFF files; non-HDR stacks are copied there as JPEG files.
Stack numbers are zero-padded in that directory so file-name sorting preserves
the stacking order.


### Install on a new Pi

Copy `MicroRasp.zip` to the final location on the Pi, then:

```bash
unzip MicroRasp.zip
cd MicroRasp
./install.sh
```

The installer:

- installs `python3-picamera2` and `python3-pip` through apt;
- verifies Picamera2/libcamera using the system Python;
- installs FastAPI, Uvicorn, Pydantic dependencies and piexif into `./python`;
- records the Python ABI tag used for those packages;
- installs and starts the `microscope-picam2` systemd service;
- runs `check-installation.sh` as a final end-to-end installation check;
- installs the restricted poweroff helper used by the web interface.

The application is then available on port 8000.

Autostart is enabled by default during installation. To disable or re-enable
autostart without uninstalling MicroRasp:

```bash
./disable-autostart.sh
./enable-autostart.sh
```

These scripts only change whether MicroRasp starts automatically at boot.
Use `./start.sh` and `./stop.sh` to control the currently running service.

### Uninstall

To remove the MicroRasp systemd service, poweroff helper and sudoers rule:

```bash
./uninstall.sh
```

The uninstall script deliberately leaves the MicroRasp directory, local Python
packages and captured photos untouched. Remove the MicroRasp directory manually
afterwards if it is no longer needed. System packages installed through `apt`
are not removed because they may be used by other software.

You can rerun the check at any time with:

```bash
./check-installation.sh
```

A missing or uninitialised camera is reported as a warning; missing software, an ABI mismatch, a stopped service or an unreachable API is an error.

If Raspberry Pi OS later upgrades to another Python minor version, `run.sh`
will refuse to use the old local packages. Run `./install.sh` again to rebuild
`python/` for the new system Python. The `photos/` directory is not touched.

### Production configuration

No `.env.local` is required. Defaults are:

```text
AEB_STOPS=1.5
SATURATION_FACTOR=2.0
```

Hostname and IP address are read from the Pi itself.

To override one of the defaults, create `.env.local` in the MicroRasp
directory, for example:

```bash
AEB_STOPS=1.5
SATURATION_FACTOR=2
```

## Development

The existing development workflow remains separate from the production release.

The development Pi can continue to use `deploy.sh`, `runback.sh` and the
existing `.venv`. This is intentionally independent of the release package.

### Development machine

Node.js 22 or newer is required.

Install frontend dependencies:

```bash
cd frontend
npm install
```

Create `frontend/.env.local` from `frontend/.env.local.example` when needed.
Development-only settings such as `PICAM_API_TARGET` and `PI_HOST` belong
there.

Start the frontend development server with:

```bash
npm run dev
```

For backend development, the existing virtual environment may still be used.
It should inherit system packages when Picamera2 is used locally:

```bash
python3 -m venv --system-site-packages .venv
source .venv/bin/activate
python -m pip install fastapi==0.141.1 uvicorn==0.52.1 piexif==1.1.3
```

For the normal development deployment to an existing Pi:

```bash
./deploy.sh <pi-host>
```

This will put the files on the PI in the directory ~:/Deploy/Microscope-Picam2. You can run the backend
with startcam.sh en stopcam.sh, or alternatively runback.sh, you will see the loglines flying by. Be aware,
using runback.sh demands that the camera is stopped with stopcam.sh first.

Debugging frontend: running the frontend on the development PC and the backend on the PI: Go to frontend subdir on the
dev machine and execute runfront.sh. You can test on http://localhost:5173 on the dev. You will have some Vue tools
on screen (small arrow centre under), because you use the VITE server now.