# PlatformIO post-build step: firmware.hex -> firmware.uf2 (nRF52840 family 0xADA52840).
# Uses uf2conv.py shipped with the Adafruit nRF52 core.
import os

Import("env")

UF2_FAMILY = "0xADA52840"


def make_uf2(source, target, env):
    hex_path = str(target[0])
    uf2_path = os.path.splitext(hex_path)[0] + ".uf2"
    framework = env.PioPlatform().get_package_dir("framework-arduinoadafruitnrf52")
    uf2conv = os.path.join(framework, "tools", "uf2conv", "uf2conv.py")
    env.Execute(f'"$PYTHONEXE" -W ignore::SyntaxWarning "{uf2conv}" -f {UF2_FAMILY} -c -o "{uf2_path}" "{hex_path}"')


env.AddPostAction("$BUILD_DIR/${PROGNAME}.hex", make_uf2)
