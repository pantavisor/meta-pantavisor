#!/usr/bin/env python3
from pydbus import SystemBus
from gi.repository import GLib
import sys

class AttackerService(object):
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
        return "Attacker response"

if __name__ == '__main__':
    try:
        bus = SystemBus()
        print("Attempting to steal org.pantavisor.Example as non-root user...")
        bus.publish("org.pantavisor.Example", AttackerService())
        print("ERROR: Successfully stole the name! Policy enforcement failed.")
        sys.exit(1)
    except Exception as e:
        print(f"SUCCESS: Name ownership rejected as expected: {e}")
        sys.exit(0)
