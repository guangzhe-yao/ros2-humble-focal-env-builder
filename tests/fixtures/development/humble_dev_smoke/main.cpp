#include <rclcpp/rclcpp.hpp>
#include <humble_dev_interfaces/msg/value.hpp>

int main(int argc, char **argv) {
  rclcpp::init(argc, argv);
  auto node = std::make_shared<rclcpp::Node>("humble_development_smoke");
  auto publisher = node->create_publisher<humble_dev_interfaces::msg::Value>("smoke", 1);
  humble_dev_interfaces::msg::Value message;
  message.value = "offline development works";
  publisher->publish(message);
  rclcpp::shutdown();
  return 0;
}
