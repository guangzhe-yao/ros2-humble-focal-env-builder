#!/usr/bin/env python3
import argparse
import os
import socket
import sys
import threading
import time

import rclpy
from rclpy.action import ActionClient, ActionServer, CancelResponse, GoalResponse
from rclpy.executors import MultiThreadedExecutor
from rclpy.node import Node
from rclpy.qos import DurabilityPolicy, HistoryPolicy, QoSProfile, ReliabilityPolicy

from control_msgs.action import SingleJointPosition
from std_msgs.msg import String
from std_srvs.srv import Trigger


TEST_NS = "/link_test"


def link_qos() -> QoSProfile:
    return QoSProfile(
        history=HistoryPolicy.KEEP_LAST,
        depth=10,
        reliability=ReliabilityPolicy.RELIABLE,
        durability=DurabilityPolicy.VOLATILE,
    )


class LinkTestServer(Node):
    def __init__(self, label: str, publish_period: float) -> None:
        super().__init__(f"ros2_link_test_server_{label}")
        self.label = label
        self.hostname = socket.gethostname()
        self.client_messages = 0
        self.server_messages = 0

        self.publisher = self.create_publisher(String, f"{TEST_NS}/from_server", link_qos())
        self.subscription = self.create_subscription(
            String,
            f"{TEST_NS}/from_client",
            self._client_message_cb,
            link_qos(),
        )
        self.ping_service = self.create_service(Trigger, f"{TEST_NS}/ping", self._ping_cb)
        self.status_service = self.create_service(Trigger, f"{TEST_NS}/status", self._status_cb)
        self.action_server = ActionServer(
            self,
            SingleJointPosition,
            f"{TEST_NS}/single_joint_position",
            execute_callback=self._execute_action,
            goal_callback=self._goal_cb,
            cancel_callback=self._cancel_cb,
        )
        self.timer = self.create_timer(publish_period, self._publish_server_message)

        self.get_logger().info(
            "server ready: label=%s host=%s rmw=%s domain=%s cyclone=%s"
            % (
                self.label,
                self.hostname,
                os.environ.get("RMW_IMPLEMENTATION", ""),
                os.environ.get("ROS_DOMAIN_ID", ""),
                os.environ.get("CYCLONEDDS_URI", ""),
            )
        )

    def _publish_server_message(self) -> None:
        self.server_messages += 1
        msg = String()
        msg.data = f"{self.label}@{self.hostname} server_messages={self.server_messages}"
        self.publisher.publish(msg)

    def _client_message_cb(self, msg: String) -> None:
        self.client_messages += 1
        if self.client_messages <= 3 or self.client_messages % 20 == 0:
            self.get_logger().info(
                f"received client topic message #{self.client_messages}: {msg.data}"
            )

    def _ping_cb(self, request: Trigger.Request, response: Trigger.Response) -> Trigger.Response:
        del request
        response.success = True
        response.message = f"pong from {self.label}@{self.hostname}"
        return response

    def _status_cb(self, request: Trigger.Request, response: Trigger.Response) -> Trigger.Response:
        del request
        response.success = self.client_messages > 0
        response.message = (
            f"client_messages={self.client_messages};"
            f"server_messages={self.server_messages};"
            f"host={self.hostname};"
            f"label={self.label}"
        )
        return response

    def _goal_cb(self, goal_request: SingleJointPosition.Goal) -> GoalResponse:
        self.get_logger().info(
            "accepted action goal: position=%.3f max_velocity=%.3f"
            % (goal_request.position, goal_request.max_velocity)
        )
        return GoalResponse.ACCEPT

    def _cancel_cb(self, goal_handle) -> CancelResponse:
        del goal_handle
        return CancelResponse.ACCEPT

    def _execute_action(self, goal_handle):
        target = goal_handle.request.position
        max_velocity = goal_handle.request.max_velocity
        feedback = SingleJointPosition.Feedback()

        steps = 5
        for index in range(steps):
            if goal_handle.is_cancel_requested:
                goal_handle.canceled()
                return SingleJointPosition.Result()
            ratio = float(index + 1) / float(steps)
            feedback.position = target * ratio
            feedback.velocity = max_velocity
            feedback.error = target - feedback.position
            goal_handle.publish_feedback(feedback)
            time.sleep(0.1)

        goal_handle.succeed()
        return SingleJointPosition.Result()


class LinkTestClient(Node):
    def __init__(self, label: str, publish_period: float) -> None:
        super().__init__(f"ros2_link_test_client_{label}")
        self.label = label
        self.hostname = socket.gethostname()
        self.server_messages = 0
        self.feedback_messages = 0

        self.publisher = self.create_publisher(String, f"{TEST_NS}/from_client", link_qos())
        self.subscription = self.create_subscription(
            String,
            f"{TEST_NS}/from_server",
            self._server_message_cb,
            link_qos(),
        )
        self.ping_client = self.create_client(Trigger, f"{TEST_NS}/ping")
        self.status_client = self.create_client(Trigger, f"{TEST_NS}/status")
        self.action_client = ActionClient(
            self,
            SingleJointPosition,
            f"{TEST_NS}/single_joint_position",
        )
        self.client_messages = 0
        self.timer = self.create_timer(publish_period, self._publish_client_message)

        self.get_logger().info(
            "client ready: label=%s host=%s rmw=%s domain=%s cyclone=%s"
            % (
                self.label,
                self.hostname,
                os.environ.get("RMW_IMPLEMENTATION", ""),
                os.environ.get("ROS_DOMAIN_ID", ""),
                os.environ.get("CYCLONEDDS_URI", ""),
            )
        )

    def _publish_client_message(self) -> None:
        self.client_messages += 1
        msg = String()
        msg.data = f"{self.label}@{self.hostname} client_messages={self.client_messages}"
        self.publisher.publish(msg)

    def _server_message_cb(self, msg: String) -> None:
        self.server_messages += 1
        if self.server_messages <= 3 or self.server_messages % 20 == 0:
            self.get_logger().info(
                f"received server topic message #{self.server_messages}: {msg.data}"
            )

    def _feedback_cb(self, feedback_msg) -> None:
        self.feedback_messages += 1
        feedback = feedback_msg.feedback
        self.get_logger().info(
            "action feedback #%d: position=%.3f velocity=%.3f error=%.3f"
            % (
                self.feedback_messages,
                feedback.position,
                feedback.velocity,
                feedback.error,
            )
        )


def remaining(deadline: float) -> float:
    return max(0.1, deadline - time.monotonic())


def wait_for(predicate, node: Node, deadline: float, description: str) -> bool:
    while time.monotonic() < deadline:
        rclpy.spin_once(node, timeout_sec=0.1)
        if predicate():
            return True
    node.get_logger().error(f"timeout waiting for {description}")
    return False


def call_trigger(node: LinkTestClient, client, deadline: float, name: str):
    while not client.wait_for_service(timeout_sec=0.5):
        if time.monotonic() >= deadline:
            node.get_logger().error(f"timeout waiting for service {name}")
            return None
    future = client.call_async(Trigger.Request())
    rclpy.spin_until_future_complete(node, future, timeout_sec=remaining(deadline))
    if not future.done():
        node.get_logger().error(f"timeout calling service {name}")
        return None
    result = future.result()
    node.get_logger().info(f"service {name}: success={result.success} message={result.message}")
    return result


def run_server(args: argparse.Namespace) -> int:
    rclpy.init()
    node = LinkTestServer(args.label, args.publish_period)
    executor = MultiThreadedExecutor(num_threads=4)
    executor.add_node(node)
    try:
        executor.spin()
    except KeyboardInterrupt:
        pass
    finally:
        executor.shutdown()
        node.destroy_node()
        if rclpy.ok():
            rclpy.shutdown()
    return 0


def run_client(args: argparse.Namespace) -> int:
    rclpy.init()
    node = LinkTestClient(args.label, args.publish_period)
    deadline = time.monotonic() + args.timeout
    ok = True

    if not wait_for(lambda: node.server_messages > 0, node, deadline, "server topic"):
        ok = False

    ping = call_trigger(node, node.ping_client, deadline, f"{TEST_NS}/ping")
    if ping is None or not ping.success:
        ok = False

    if not node.action_client.wait_for_server(timeout_sec=remaining(deadline)):
        node.get_logger().error(f"timeout waiting for action {TEST_NS}/single_joint_position")
        ok = False
    else:
        goal = SingleJointPosition.Goal()
        goal.position = 1.25
        goal.max_velocity = 0.5
        goal.min_duration.sec = 0
        goal.min_duration.nanosec = 500000000
        send_future = node.action_client.send_goal_async(goal, feedback_callback=node._feedback_cb)
        rclpy.spin_until_future_complete(node, send_future, timeout_sec=remaining(deadline))
        if not send_future.done() or send_future.result() is None:
            node.get_logger().error("timeout sending action goal")
            ok = False
        else:
            goal_handle = send_future.result()
            if not goal_handle.accepted:
                node.get_logger().error("action goal rejected")
                ok = False
            else:
                result_future = goal_handle.get_result_async()
                rclpy.spin_until_future_complete(node, result_future, timeout_sec=remaining(deadline))
                if not result_future.done():
                    node.get_logger().error("timeout waiting for action result")
                    ok = False
                else:
                    node.get_logger().info("action result received")

    time.sleep(args.settle_time)
    rclpy.spin_once(node, timeout_sec=0.1)
    status = call_trigger(node, node.status_client, deadline, f"{TEST_NS}/status")
    if status is None or not status.success:
        ok = False

    node.get_logger().info(
        "summary: server_topic_messages=%d client_topic_messages=%d action_feedback=%d"
        % (node.server_messages, node.client_messages, node.feedback_messages)
    )
    node.destroy_node()
    rclpy.shutdown()
    return 0 if ok else 2


def main() -> int:
    parser = argparse.ArgumentParser(description="ROS 2 Orin/Pico CycloneDDS link test")
    parser.add_argument("role", choices=("server", "client"))
    parser.add_argument("--label", default="node")
    parser.add_argument("--timeout", type=float, default=20.0)
    parser.add_argument("--publish-period", type=float, default=0.2)
    parser.add_argument("--settle-time", type=float, default=1.0)
    args = parser.parse_args()

    if args.role == "server":
        return run_server(args)
    return run_client(args)


if __name__ == "__main__":
    sys.exit(main())
