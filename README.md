# Atmotube PRO 2 iOS Sample App

This sample application demonstrates how to interact with Atmotube PRO 2 devices using iOS BLE. It provides a reference implementation for scanning, connecting, reading real-time data, and downloading historical data.

The app is using [Atmotube PRO 2 API](https://support.atmotube.com/en/articles/12714501-atmotube-pro-2-api-documentation) 

## Requirements

- Xcode 15.0+
- iOS 15.0+
- A physical iOS device (Bluetooth is not supported on the Simulator)

## Setup

1. Open `Atmotube PRO2 example.xcodeproj` in Xcode.
2. Select your physical device as the run destination.
3. Build and Run.

## Features

- **Scan**: Discovers nearby Atmotube PRO 2 devices.
- **Connect**: Connects to the device and reads real-time data.
- **History**: Downloads historical data and exports it to CSV.

## Dependencies

- [iOS-nRF-Connect-Device-Manager](https://github.com/NordicSemiconductor/IOS-nRF-Connect-Device-Manager) for McuMgr operations (History download).
