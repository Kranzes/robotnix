#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

from typing import Any
import json
import urllib.request
import os
import pathlib

from robotnix_common import save

def fetch_metadata(
        devices_json_url: str = "https://github.com/ArrowOS/arrow_ota/raw/master/arrow_ota.json"
        ) -> Any:
    metadata = {}

    devices = json.load(urllib.request.urlopen(devices_json_url))
    for device in devices:
        data = devices[device][0]

        # Check device version
        if 'v12.1' in data:
            branch = 'arrow-12.1'
            version = 'v12.1'
        elif 'v11.0' in data:
            branch = 'arrow-11.0'
            version = 'v11.0'
        else:
            continue

        if 'OFFICIAL' not in data[version][0]:
            continue

        vendor = data['oem']
        vendor = vendor.lower()

        blacklisted_devices = ['alioth', 'armani', 'monet', 'vangogh', 'x3', 'avicii', 'apollo', 'daisy'];
        
        if device in blacklisted_devices:
            continue

        if device == 'RMX1801':
            vendor = 'realme'

        # Poco/Redmi devices use the Xiaomi vendor files
        if vendor in ['poco', 'redmi']:
            vendor = 'xiaomi'

        metadata[device] = {
            'branch': branch,
            'name': data['model'],
            'variant': 'userdebug',
            'vendor': vendor
        }

    return metadata

if __name__ == '__main__':
    metadata = fetch_metadata()
    os.chdir(pathlib.Path(__file__).parent.resolve())
    save('device-metadata.json', metadata)
