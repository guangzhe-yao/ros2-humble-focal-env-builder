#include <algorithm>
#include <iostream>
#include <memory>
#include <string>
#include <vector>

#include "controller_interface/controller_interface.hpp"
#include "pluginlib/class_loader.hpp"
#include "rclcpp/rclcpp.hpp"

int main(int argc, char ** argv)
{
  rclcpp::init(argc, argv);

  try
  {
    pluginlib::ClassLoader<controller_interface::ControllerInterface> loader(
      "controller_interface", "controller_interface::ControllerInterface");

    const std::string plugin_name = "controller_interface_smoke/SmokeController";
    const std::vector<std::string> classes = loader.getDeclaredClasses();
    if (std::find(classes.begin(), classes.end(), plugin_name) == classes.end())
    {
      std::cerr << "Plugin was not registered: " << plugin_name << '\n';
      rclcpp::shutdown();
      return 1;
    }

    auto controller = loader.createSharedInstance(plugin_name);
    if (controller->init("smoke_controller") != controller_interface::return_type::OK)
    {
      std::cerr << "Controller initialization failed\n";
      rclcpp::shutdown();
      return 2;
    }

    const auto command_config = controller->command_interface_configuration();
    const auto state_config = controller->state_interface_configuration();
    if (command_config.type != controller_interface::interface_configuration_type::NONE ||
        state_config.type != controller_interface::interface_configuration_type::NONE)
    {
      std::cerr << "Unexpected interface configuration\n";
      rclcpp::shutdown();
      return 3;
    }

    const auto update_result = controller->update(
      rclcpp::Time(1, 0), rclcpp::Duration::from_seconds(0.01));
    if (update_result != controller_interface::return_type::OK)
    {
      std::cerr << "Controller update failed\n";
      rclcpp::shutdown();
      return 4;
    }

    const double gain = controller->get_node()->get_parameter("gain").as_double();
    std::cout << "Loaded plugin: " << plugin_name << '\n';
    std::cout << "Controller node: " << controller->get_node()->get_name() << '\n';
    std::cout << "auto_declare gain: " << gain << '\n';
    std::cout << "Interface configuration: NONE/NONE\n";
    std::cout << "update() result: OK\n";
  }
  catch (const pluginlib::PluginlibException & error)
  {
    std::cerr << "Pluginlib error: " << error.what() << '\n';
    rclcpp::shutdown();
    return 5;
  }

  rclcpp::shutdown();
  return 0;
}

