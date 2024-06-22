#!/bin/bash

APP_BUNDLE_ID="com.aisport.coach.SportsCoach" # 替换为你的应用程序的 Bundle Identifier
EXPORT_PATH="$HOME/Download/" # 设置导出路径

# 获取设备的 UDID
DEVICE_ID=$(idevice_id -l | head -n 1)

if [ -z "$DEVICE_ID" ]; then
  echo "No device found"
  exit 1
fi

# 创建导出路径
mkdir -p "$EXPORT_PATH"

# 检查应用程序是否安装在设备上
ideviceinstaller -u "$DEVICE_ID" -l | grep "$APP_BUNDLE_ID" > /dev/null
if [ $? -ne 0 ]; then
  echo "App with bundle ID $APP_BUNDLE_ID not found on device $DEVICE_ID"
  exit 1
fi

# 获取应用程序的 UUID
APP_UUID=$(ideviceprovision list -u "$DEVICE_ID" | grep "$APP_BUNDLE_ID" | awk '{print $1}')

if [ -z "$APP_UUID" ]; then
  echo "Failed to find app UUID for bundle ID $APP_BUNDLE_ID"
  exit 1
fi

# 导出应用的数据容器
ideviceprovision copy "$APP_UUID" "$EXPORT_PATH"

if [ $? -ne 0 ]; then
  echo "Failed to export app container to: $EXPORT_PATH"
  exit 1
fi

echo "App container exported successfully to: $EXPORT_PATH"
