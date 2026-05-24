TARGET := iphone:clang:latest:14.0
ARCHS = arm64
DEBUG = 0
FINALPACKAGE = 1

include $(THEOS)/makefiles/common.mk

LIBRARY_NAME = DunenBLELogger
DunenBLELogger_FILES = DunenBLELogger/DunenBLELogger.m
DunenBLELogger_FRAMEWORKS = Foundation CoreBluetooth
DunenBLELogger_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/library.mk
