#include <cstdint>

#include "controller_interface/controller_interface.hpp"
#include "pluginlib/class_list_macros.hpp"

namespace controller_interface_smoke
{

class SmokeController : public controller_interface::ControllerInterface
{
public:
  controller_interface::CallbackReturn on_init() override
  {
    gain_ = auto_declare<double>("gain", 2.0);
    return controller_interface::CallbackReturn::SUCCESS;
  }

  controller_interface::InterfaceConfiguration command_interface_configuration() const override
  {
    return {controller_interface::interface_configuration_type::NONE};
  }

  controller_interface::InterfaceConfiguration state_interface_configuration() const override
  {
    return {controller_interface::interface_configuration_type::NONE};
  }

  controller_interface::return_type update(
    const rclcpp::Time & time, const rclcpp::Duration & period) override
  {
    last_time_seconds_ = time.seconds();
    last_period_seconds_ = period.seconds();
    ++update_count_;
    return controller_interface::return_type::OK;
  }

private:
  double gain_{0.0};
  double last_time_seconds_{0.0};
  double last_period_seconds_{0.0};
  std::uint64_t update_count_{0};
};

}  // namespace controller_interface_smoke

PLUGINLIB_EXPORT_CLASS(
  controller_interface_smoke::SmokeController,
  controller_interface::ControllerInterface)

