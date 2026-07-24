import sys
if sys.prefix == '/usr':
    sys.real_prefix = sys.prefix
    sys.prefix = sys.exec_prefix = '/home/administrator/Masterproject2/20_ROS/src/Interface/install/tc_ros2_itf'
