TARGET := iphone:clang:latest:7.0
INSTALL_TARGET_PROCESSES = minecraftpe
ARCHS = arm64
THEOS_PACKAGE_SCHEME = rootless
THEOS_DEVICE_IP = 192.168.1.148

HEADER_DIRS = $(shell find . -type f -name "*.h" -exec dirname {} \; | sort -u)
ADDITIONAL_CCFLAGS += $(foreach dir, $(HEADER_DIRS), -I$(dir))

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = MetalShadersDumper-iOS

$(TWEAK_NAME)_FILES = $(shell find . -type f \( -iname "*.cpp" -o -iname "*.c" -o -iname "*.m" -o -iname "*.mm" -o -iname "*.x" -o -iname "*.xm" \))
$(TWEAK_NAME)_CFLAGS = -fobjc-arc
$(TWEAK_NAME)_LOGOS_DEFAULT_GENERATOR = internal
include $(THEOS_MAKE_PATH)/tweak.mk
