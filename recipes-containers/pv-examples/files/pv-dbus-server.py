#!/usr/bin/env python3
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

if __name__ == '__main__':
    bus = SystemBus()
    bus.publish("org.pantavisor.Example", ExampleService())
    
    loop = GLib.MainLoop()
    print("Starting D-Bus example service on org.pantavisor.Example...")
    loop.run()
