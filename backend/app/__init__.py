from picamera2 import Picamera2


# Recent Picamera2/libcamera versions keep ExposureTime and AnalogueGain in
# Picamera2's control cache. Once either has been set manually (for example
# during an AEB capture), subsequent requests can keep the corresponding
# ExposureTimeMode/AnalogueGainMode in manual mode even when AeEnable is set
# back to True. In that state ExposureValue is accepted but no longer affects
# the image.
#
# Picamera2 uses a zero ExposureTime/AnalogueGain value as the signal to return
# those controls to automatic mode. Newer libcamera versions also expose the
# explicit *Mode controls, so set those to Auto as well when available.
if not getattr(Picamera2, "_microrasp_auto_exposure_patch", False):
    _picamera2_set_controls = Picamera2.set_controls

    def _microrasp_set_controls(self, controls):
        if isinstance(controls, dict) and controls.get("AeEnable") is True:
            controls = dict(controls)
            advertised = self.camera_controls

            if "ExposureTime" not in controls:
                controls["ExposureTime"] = 0

                if "ExposureTimeMode" in advertised:
                    controls["ExposureTimeMode"] = 0

            if "AnalogueGain" not in controls:
                controls["AnalogueGain"] = 0

                if "AnalogueGainMode" in advertised:
                    controls["AnalogueGainMode"] = 0

        return _picamera2_set_controls(self, controls)

    Picamera2.set_controls = _microrasp_set_controls
    Picamera2._microrasp_auto_exposure_patch = True
