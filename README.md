# Microscope-Picam2
Microscope camera based on HQ, Pi 3B+ and Picamera2

# Setup
## Environments
Developmachine and Pi on same subnet. IP of Pi fixed and tied to MAC Address. Best if Pi has 16GB+, and
full installation including Pi Connect and ssh access with keys.  
Pi has specific name e.g.: Raspi3B-<number> and Raspi3B-<number>.local or whatever. Put this IP-Mac coupling 
in the hosts file on your dev machine.  
The PI is defined as a remote host in Pycharm, with base directory: ~/Deploy/Microscope-Picam2.
The PI is defined as a remote host in Pycharm, with base directory: ~/Deploy/Microscope-Picam2.
Make sure .venv and .idea directories are not synchronizing!  
GIT repository on devmachine. On the PI the Deploy/Microscope-Picam2 directory.  
## Installing the Pi
A virtual environment and packages are necessary to run the software. On the PI:  
### Install the .venv  
cd ~/Deploy/microscope-picam2  
python3 -m venv --system-site-packages .venv  
source .venv/bin/activate  
### Check:
python --version  
python -c "from picamera2 import Picamera2; print('Picamera2 OK')"  
### Install packages:
cd ~/Deploy/microscope-picam2  
source .venv/bin/activate  
python -m pip install fastapi==0.141.1 uvicorn==0.52.1
### Check:
python -c "import fastapi, uvicorn; print(fastapi.&#95;&#95;version&#95;&#95;, uvicorn.&#95;&#95;version&#95;&#95;)"  
## Running on the Pi
### Copy backend directory from dev to Pi
### Start server
cd ~/Deploy/microscope-picam2  
source .venv/bin/activate  
uvicorn backend.app.main:app --host 0.0.0.0 --port 8000  
### Check from Devmachine:
http://<ip-van-de-pi>:8000/api/status  
Result:  
{
  "status": "ok",
  "camera": "not_initialized"
}  
## Installing .venv on dev machine
### Check software:
Check node and npm:  
node --version  
npm --version  
Minimum versions must be 22+   
If not, upgrade node:   
nvm install 22  
nvm use 22   
nvm alias default 22   
and check versions again
Maybe nvm is not installed, install with:  
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.6/install.sh | bash  
source ~/.bashrc   
command -v nvm  
should return nvm. Note: close all command shells including pycharm and reopen before checking!
### Create now the .venv form the root of the repository:  
python3 -m venv --system-site-packages .venv  
source .venv/bin/activate  
### Install new vue project (ONLY WHEN FRONTEND DOES NOT EXIST)
From base directory of repository:  
npm create vue@latest  
and answer:  
Project name: frontend  
Add TypeScript? No  
Add JSX Support? No  
Add Vue Router? No  
Add Pinia? No  
Add Vitest? No  
Add End-to-End Testing? No  
Add ESLint? Yes  
Add Prettier? Yes  
Add Vue DevTools? No  
### When frontend exists, install dependencies:  
cd frontend   
npm install   
Sometimes there is a version conflict. Use AI to solve this (put error message in and change the
versionnumbers in package.json). Sometimes they will tell you to use the --force or --legacy-peer-deps. Don't,
just change the package.json file.  
Configure the piname in file ...   
## Start frontend:
npm run dev   
and goto: http://localhost:5173  










