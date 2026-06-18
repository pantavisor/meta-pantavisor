#!/usr/bin/env python3
import os
import time

# The hosted system bus socket is injected by pv-xconnect at this path. Point
# Gio/pydbus at it explicitly instead of relying on the compiled-in default
# (/var/run/dbus/system_bus_socket), which need not exist in this container.
os.environ.setdefault(
    "DBUS_SYSTEM_BUS_ADDRESS", "unix:path=/run/dbus/system_bus_socket"
)

from pydbus import SystemBus
from gi.repository import GLib
import json

class ExampleService(object):
    """
        <node>
            <interface name="org.pantavisor.Example">
                <method name="GetInfo">
                    <arg type="s" name="response" direction="out"/>
                </method>
            </interface>
        </node>
    """
    def GetInfo(self):
        # In a real mediated scenario, the bus or pv-xconnect might have
        # enriched the message metadata or we check peer credentials.
        return json.dumps({
            "service": "dbus-example",
            "status": "active"
        })

def connect_bus():
    # The bus socket is injected shortly after the container starts, so the
    # first attempts may race the injection. Retry until it is reachable.
    while True:
        try:
            return SystemBus()
        except GLib.GError as e:
            print("Waiting for hosted system bus: %s" % e)
            time.sleep(1)

if __name__ == '__main__':
    bus = connect_bus()
    bus.publish("org.pantavisor.Example", ExampleService())

    loop = GLib.MainLoop()
    print("Starting D-Bus example service on org.pantavisor.Example...")
    loop.run()
