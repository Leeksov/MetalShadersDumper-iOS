TARGET := iphone:clang:latest:7.0
INSTALL_TARGET_PROCESSES = minecraftpe
ARCHS = arm64
THEOS_PACKAGE_SCHEME = rootless
THEOS_DEVICE_IP = 192.168.1.148

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = MetalShadersDumper-iOS

$(TWEAK_NAME)_FILES = Tweak.mm
$(TWEAK_NAME)_CFLAGS = \
  -fobjc-arc
$(TWEAK_NAME)_LOGOS_DEFAULT_GENERATOR = internal
include $(THEOS_MAKE_PATH)/tweak.mk
