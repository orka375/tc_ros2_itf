import sqlite3
import rclpy
from rclpy.node import Node


class RobotDatabase(Node):

    def __init__(self):
        super().__init__('robot_database')

        self.db = sqlite3.connect(
            '/mnt/c/RobotDB/robotdata.db'
        )

        self.cursor = self.db.cursor()

        self.read_robots()


    def read_robots(self):

        self.cursor.execute(
            """
            SELECT id,name,manufacturer,model
            FROM Robot
            """
        )

        robots = self.cursor.fetchall()

        for robot in robots:
            self.get_logger().info(
                str(robot)
            )


def main():

    rclpy.init()

    node = RobotDatabase()

    rclpy.spin(node)

    node.destroy_node()
    rclpy.shutdown()


if __name__ == '__main__':
    main()