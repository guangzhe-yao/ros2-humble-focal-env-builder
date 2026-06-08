cmake_minimum_required(VERSION 3.16)
project(controller_interface_smoke)

find_package(ament_cmake REQUIRED)
find_package(controller_interface REQUIRED)
find_package(pluginlib REQUIRED)
find_package(rclcpp REQUIRED)

add_library(smoke_controller SHARED
  src/smoke_controller.cpp
)
target_compile_features(smoke_controller PUBLIC cxx_std_17)
ament_target_dependencies(smoke_controller
  controller_interface
  pluginlib
  rclcpp
)

pluginlib_export_plugin_description_file(
  controller_interface
  smoke_controller_plugin.xml
)

add_executable(controller_interface_smoke_test
  src/smoke_loader.cpp
)
target_compile_features(controller_interface_smoke_test PUBLIC cxx_std_17)
ament_target_dependencies(controller_interface_smoke_test
  controller_interface
  pluginlib
  rclcpp
)

install(
  TARGETS smoke_controller controller_interface_smoke_test
  ARCHIVE DESTINATION lib
  LIBRARY DESTINATION lib
  RUNTIME DESTINATION lib/${PROJECT_NAME}
)

ament_package()

