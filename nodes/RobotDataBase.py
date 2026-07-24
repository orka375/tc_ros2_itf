import json
from typing import Any, Dict, List, Tuple

import psycopg2
from psycopg2.extras import RealDictCursor
import rclpy
from rcl_interfaces.msg import ParameterType, SetParametersResult
from rcl_interfaces.srv import SetParameters
from rclpy.node import Node
from std_msgs.msg import String
from std_srvs.srv import Trigger


ENTITY_CONFIG: Dict[str, Dict[str, Any]] = {
    "robots": {
        "table": "Robot",
        "id": "id",
        "allowed_filters": {
            "id",
            "name",
            "manufacturer",
            "model",
            "robot_type",
            "axes",
            "payload",
            "reach",
            "controller",
            "ip_address",
        },
        "editable_fields": {
            "name",
            "manufacturer",
            "model",
            "robot_type",
            "axes",
            "payload",
            "reach",
            "controller",
            "ip_address",
        },
    },
    "tools": {
        "table": "RobotTool",
        "id": "id",
        "allowed_filters": {
            "id",
            "robot_id",
            "name",
        },
        "editable_fields": {
            "robot_id",
            "name",
            "tcp_x",
            "tcp_y",
            "tcp_z",
            "tcp_rx",
            "tcp_ry",
            "tcp_rz",
            "weight",
            "cog_x",
            "cog_y",
            "cog_z",
        },
    },
    "frames": {
        "table": "CoordSys",
        "id": "id",
        "allowed_filters": {
            "id",
            "plant_id",
            "name",
        },
        "editable_fields": {
            "plant_id",
            "name",
            "x",
            "y",
            "z",
            "rx",
            "ry",
            "rz",
        },
    },
    "plants": {
        "table": "Plant",
        "id": "id",
        "allowed_filters": {
            "id",
            "name",
        },
        "editable_fields": {
            "name",
            "description",
            "robots",
        },
    },
}


class RobotDatabase(Node):
    def __init__(self) -> None:
        super().__init__("robot_database")

        self.declare_parameter("db_host", "localhost")
        self.declare_parameter("db_port", 5432)
        self.declare_parameter("db_name", "robotdata")
        self.declare_parameter("db_user", "admin")
        self.declare_parameter("db_password", "1")

        db_host = self.get_parameter("db_host").value
        db_port = int(self.get_parameter("db_port").value)
        db_name = self.get_parameter("db_name").value
        db_user = self.get_parameter("db_user").value
        db_password = self.get_parameter("db_password").value

        self.connection = psycopg2.connect(
            dbname=db_name,
            user=db_user,
            password=db_password,
            host=db_host,
            port=db_port,
        )
        self.connection.autocommit = False

        self.read_response_pub = self.create_publisher(String, "robot_database/read_response", 10)
        self.edit_response_pub = self.create_publisher(String, "robot_database/edit_response", 10)

        self.read_request_sub = self.create_subscription(
            String,
            "robot_database/read_request",
            self.on_read_request,
            10,
        )
        self.edit_request_sub = self.create_subscription(
            String,
            "robot_database/edit_request",
            self.on_edit_request,
            10,
        )

        self.get_robots_srv = self.create_service(Trigger, "robot_database/get_robots", self.on_get_robots)
        self.get_tools_srv = self.create_service(Trigger, "robot_database/get_tools", self.on_get_tools)
        self.get_frames_srv = self.create_service(Trigger, "robot_database/get_frames", self.on_get_frames)
        self.get_plants_srv = self.create_service(Trigger, "robot_database/get_plants", self.on_get_plants)

        self.db_command_srv = self.create_service(
            SetParameters,
            "robot_database/db_command",
            self.on_db_command,
        )

        self.get_logger().info(
            f"Connected to PostgreSQL database {db_name} at {db_host}:{db_port} as {db_user}."
        )
        self.get_logger().info("Ready: topics read/edit request+response and services get_* + db_command")
        self.print_usage_examples()

    def destroy_node(self) -> bool:
        try:
            self.connection.close()
        except Exception:
            pass
        return super().destroy_node()

    def _publish(self, publisher, payload: Dict[str, Any]) -> None:
        msg = String()
        msg.data = json.dumps(payload)
        publisher.publish(msg)

    def _parse_json(self, raw: str) -> Dict[str, Any]:
        data = json.loads(raw)
        if not isinstance(data, dict):
            raise ValueError("payload must be a JSON object")
        return data

    def _validate_entity(self, entity: str) -> Dict[str, Any]:
        entity_key = entity.lower().strip()
        if entity_key not in ENTITY_CONFIG:
            raise ValueError("entity must be one of: robots, tools, frames, plants")
        return ENTITY_CONFIG[entity_key]

    def _build_where_clause(
        self,
        filters: Dict[str, Any],
        allowed_filters: set,
    ) -> Tuple[str, List[Any]]:
        if not filters:
            return "", []

        parts: List[str] = []
        values: List[Any] = []
        for key, value in filters.items():
            if key not in allowed_filters:
                raise ValueError(f"unsupported filter key: {key}")
            parts.append(f"{key} = %s")
            values.append(value)

        return " WHERE " + " AND ".join(parts), values

    def _read_entity(self, entity: str, filters: Dict[str, Any]) -> List[Dict[str, Any]]:
        config = self._validate_entity(entity)
        table = config["table"]
        where_sql, where_values = self._build_where_clause(filters, config["allowed_filters"])
        query = f"SELECT * FROM {table}{where_sql} ORDER BY id"

        with self.connection.cursor(cursor_factory=RealDictCursor) as cursor:
            cursor.execute(query, where_values)
            rows = cursor.fetchall()
        return list(rows)

    def _insert_entity(self, entity: str, data: Dict[str, Any]) -> Dict[str, Any]:
        config = self._validate_entity(entity)
        editable_fields = config["editable_fields"]
        table = config["table"]

        payload = {k: v for k, v in data.items() if k in editable_fields}
        if not payload:
            raise ValueError("insert data is empty or contains no editable columns")

        columns = list(payload.keys())
        values = [payload[c] for c in columns]
        placeholders = ", ".join(["%s"] * len(values))
        columns_sql = ", ".join(columns)

        query = f"INSERT INTO {table} ({columns_sql}) VALUES ({placeholders}) RETURNING *"
        with self.connection.cursor(cursor_factory=RealDictCursor) as cursor:
            cursor.execute(query, values)
            row = cursor.fetchone()
        self.connection.commit()
        return dict(row)

    def _update_entity(self, entity: str, row_id: int, data: Dict[str, Any]) -> Dict[str, Any]:
        config = self._validate_entity(entity)
        editable_fields = config["editable_fields"]
        table = config["table"]

        payload = {k: v for k, v in data.items() if k in editable_fields}
        if not payload:
            raise ValueError("update data is empty or contains no editable columns")

        set_parts = []
        values = []
        for key, value in payload.items():
            set_parts.append(f"{key} = %s")
            values.append(value)
        values.append(row_id)

        query = f"UPDATE {table} SET {', '.join(set_parts)} WHERE id = %s RETURNING *"
        with self.connection.cursor(cursor_factory=RealDictCursor) as cursor:
            cursor.execute(query, values)
            row = cursor.fetchone()
        self.connection.commit()

        if row is None:
            raise ValueError(f"no {entity} row found with id={row_id}")

        return dict(row)

    def _delete_entity(self, entity: str, row_id: int) -> Dict[str, Any]:
        config = self._validate_entity(entity)
        table = config["table"]

        query = f"DELETE FROM {table} WHERE id = %s RETURNING id"
        with self.connection.cursor(cursor_factory=RealDictCursor) as cursor:
            cursor.execute(query, [row_id])
            row = cursor.fetchone()
        self.connection.commit()

        if row is None:
            raise ValueError(f"no {entity} row found with id={row_id}")

        return {"deleted_id": row_id}

    def _run_edit(self, entity: str, action: str, row_id: Any, data: Dict[str, Any]) -> Dict[str, Any]:
        normalized_action = action.lower().strip()
        if normalized_action == "insert":
            inserted = self._insert_entity(entity, data)
            return {"action": "insert", "entity": entity, "row": inserted}
        if normalized_action == "update":
            if row_id is None:
                raise ValueError("update requires id")
            updated = self._update_entity(entity, int(row_id), data)
            return {"action": "update", "entity": entity, "row": updated}
        if normalized_action == "delete":
            if row_id is None:
                raise ValueError("delete requires id")
            deleted = self._delete_entity(entity, int(row_id))
            return {"action": "delete", "entity": entity, **deleted}
        raise ValueError("action must be insert, update or delete")

    def on_read_request(self, msg: String) -> None:
        try:
            payload = self._parse_json(msg.data)
            entity = payload["entity"]
            filters = payload.get("filters", {})

            if "id" in payload:
                filters["id"] = payload["id"]

            rows = self._read_entity(entity, filters)
            self._publish(
                self.read_response_pub,
                {"ok": True, "entity": entity, "count": len(rows), "rows": rows},
            )
        except Exception as exc:
            self.connection.rollback()
            self._publish(self.read_response_pub, {"ok": False, "error": str(exc)})

    def on_edit_request(self, msg: String) -> None:
        try:
            payload = self._parse_json(msg.data)
            entity = payload["entity"]
            action = payload["action"]
            row_id = payload.get("id")
            data = payload.get("data", {})

            result = self._run_edit(entity, action, row_id, data)
            self._publish(self.edit_response_pub, {"ok": True, **result})
        except Exception as exc:
            self.connection.rollback()
            self._publish(self.edit_response_pub, {"ok": False, "error": str(exc)})

    def _trigger_read(self, entity: str, response: Trigger.Response) -> Trigger.Response:
        try:
            rows = self._read_entity(entity, {})
            response.success = True
            response.message = json.dumps({"entity": entity, "count": len(rows), "rows": rows})
        except Exception as exc:
            self.connection.rollback()
            response.success = False
            response.message = str(exc)
        return response

    def on_get_robots(self, _request: Trigger.Request, response: Trigger.Response) -> Trigger.Response:
        return self._trigger_read("robots", response)

    def on_get_tools(self, _request: Trigger.Request, response: Trigger.Response) -> Trigger.Response:
        return self._trigger_read("tools", response)

    def on_get_frames(self, _request: Trigger.Request, response: Trigger.Response) -> Trigger.Response:
        return self._trigger_read("frames", response)

    def on_get_plants(self, _request: Trigger.Request, response: Trigger.Response) -> Trigger.Response:
        return self._trigger_read("plants", response)

    def _set_parameter_value_to_python(self, parameter_value: Any) -> Any:
        ptype = parameter_value.type
        if ptype == ParameterType.PARAMETER_BOOL:
            return parameter_value.bool_value
        if ptype == ParameterType.PARAMETER_INTEGER:
            return parameter_value.integer_value
        if ptype == ParameterType.PARAMETER_DOUBLE:
            return parameter_value.double_value
        if ptype == ParameterType.PARAMETER_STRING:
            return parameter_value.string_value
        if ptype == ParameterType.PARAMETER_BYTE_ARRAY:
            return list(parameter_value.byte_array_value)
        if ptype == ParameterType.PARAMETER_BOOL_ARRAY:
            return list(parameter_value.bool_array_value)
        if ptype == ParameterType.PARAMETER_INTEGER_ARRAY:
            return list(parameter_value.integer_array_value)
        if ptype == ParameterType.PARAMETER_DOUBLE_ARRAY:
            return list(parameter_value.double_array_value)
        if ptype == ParameterType.PARAMETER_STRING_ARRAY:
            return list(parameter_value.string_array_value)
        return None

    def on_db_command(self, request: SetParameters.Request, response: SetParameters.Response) -> SetParameters.Response:
        params: Dict[str, Any] = {}
        for parameter in request.parameters:
            params[parameter.name] = self._set_parameter_value_to_python(parameter.value)

        result = SetParametersResult()
        try:
            mode = str(params.get("mode", "read")).lower().strip()
            entity = str(params["entity"]).lower().strip()

            if mode == "read":
                filters: Dict[str, Any] = {}
                if "id" in params and params["id"] is not None:
                    filters["id"] = int(params["id"])
                if "filters" in params and params["filters"]:
                    parsed_filters = json.loads(str(params["filters"]))
                    if not isinstance(parsed_filters, dict):
                        raise ValueError("filters must be a JSON object")
                    filters.update(parsed_filters)

                rows = self._read_entity(entity, filters)
                result.successful = True
                result.reason = json.dumps({"ok": True, "entity": entity, "count": len(rows), "rows": rows})
            elif mode == "edit":
                action = str(params["action"]).lower().strip()
                row_id = params.get("id")
                data_raw = str(params.get("data", "{}"))
                data_obj = json.loads(data_raw)
                if not isinstance(data_obj, dict):
                    raise ValueError("data must be a JSON object")

                edit_result = self._run_edit(entity, action, row_id, data_obj)
                result.successful = True
                result.reason = json.dumps({"ok": True, **edit_result})
            else:
                raise ValueError("mode must be read or edit")
        except Exception as exc:
            self.connection.rollback()
            result.successful = False
            result.reason = str(exc)

        response.results = [result]
        return response

    def print_usage_examples(self) -> None:
        examples = """
    ================ Robot Database Interface ================

    ----------------------------------------------------------
    READ ROBOTS
    ----------------------------------------------------------

    ros2 topic pub --once /robot_database/read_request std_msgs/msg/String \\
    '{data: "{\"entity\":\"robots\"}'

    Read robot by id:

    ros2 topic pub --once /robot_database/read_request std_msgs/msg/String \\
    '{data: "{\"entity\":\"robots\",\"id\":1}'

    Read robot by name:

    ros2 topic pub --once /robot_database/read_request std_msgs/msg/String \\
    '{data: "{\"entity\":\"robots\",\"filters\":{\"name\":\"robot1\"}}'


    ----------------------------------------------------------
    READ TOOLS
    ----------------------------------------------------------

    ros2 topic pub --once /robot_database/read_request std_msgs/msg/String \\
    '{data: "{\"entity\":\"tools\"}'


    Read tools belonging to robot:

    ros2 topic pub --once /robot_database/read_request std_msgs/msg/String \\
    '{data: "{\"entity\":\"tools\",\"filters\":{\"robot_id\":1}}'


    ----------------------------------------------------------
    INSERT ROBOT
    ----------------------------------------------------------

    ros2 topic pub --once /robot_database/edit_request std_msgs/msg/String \\
    '{data: "{\"entity\":\"robots\",\"action\":\"insert\",\"data\":{\"name\":\"robot1\",\"manufacturer\":\"KUKA\",\"model\":\"KR10\"}}'


    ----------------------------------------------------------
    UPDATE ROBOT
    ----------------------------------------------------------

    ros2 topic pub --once /robot_database/edit_request std_msgs/msg/String \\
    '{data: "{\"entity\":\"robots\",\"action\":\"update\",\"id\":1,\"data\":{\"name\":\"new_robot_name\"}}'


    ----------------------------------------------------------
    DELETE ROBOT
    ----------------------------------------------------------

    ros2 topic pub --once /robot_database/edit_request std_msgs/msg/String \\
    '{data: "{\"entity\":\"robots\",\"action\":\"delete\",\"id\":1}'


    ----------------------------------------------------------
    SERVICE EXAMPLES
    ----------------------------------------------------------

    Get all robots:

    ros2 service call /robot_database/get_robots std_srvs/srv/Trigger


    Get all tools:

    ros2 service call /robot_database/get_tools std_srvs/srv/Trigger


    Get all frames:

    ros2 service call /robot_database/get_frames std_srvs/srv/Trigger


    Get all plants:

    ros2 service call /robot_database/get_plants std_srvs/srv/Trigger


    ==========================================================

    """
        self.get_logger().info(examples)

def main() -> None:
    rclpy.init()
    node = RobotDatabase()
    rclpy.spin(node)
    node.destroy_node()
    rclpy.shutdown()


if __name__ == "__main__":
    main()