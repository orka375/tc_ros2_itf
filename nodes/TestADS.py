import pyads

PLC_IP = "192.168.250.100"
PLC_AMS_NET_ID = "192.168.250.100.1.1"

plc = pyads.Connection(
    PLC_AMS_NET_ID,
    pyads.PORT_TC3PLC1,
    PLC_IP
)

try:
    print("Opening ADS connection...")
    plc.open()
    print("ADS connection opened")

    print("Reading PLC state...")
    state = plc.read_state()
    print("PLC state:", state)

except Exception as e:
    print("ADS ERROR:", repr(e))

finally:
    plc.close()
    print("Connection closed")