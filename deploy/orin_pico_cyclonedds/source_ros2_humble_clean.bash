# Source this file before starting ROS 2 Humble processes on Pico machines that
# still have ROS 1 Noetic loaded from the legacy robot profile.

_zj_filter_colon_var() {
  local var_name="$1"
  local current_value="${!var_name:-}"
  local filtered=""
  local item

  [ -z "$current_value" ] && return 0

  IFS=':' read -r -a _zj_path_items <<< "$current_value"
  for item in "${_zj_path_items[@]}"; do
    case "$item" in
      /opt/ros/noetic*|/opt/ros/foxy*)
        continue
        ;;
    esac
    if [ -z "$filtered" ]; then
      filtered="$item"
    else
      filtered="$filtered:$item"
    fi
  done

  if [ -n "$filtered" ]; then
    export "$var_name=$filtered"
  else
    unset "$var_name"
  fi
}

unset ROS_DISTRO
unset ROS_VERSION
unset ROS_PYTHON_VERSION
unset ROS_PACKAGE_PATH
unset ROS_ROOT
unset ROS_ETC_DIR
unset ROS_MASTER_URI
unset ROS_HOSTNAME
unset ROS_IP
unset ROSLISP_PACKAGE_DIRECTORIES

_zj_filter_colon_var PATH
_zj_filter_colon_var PYTHONPATH
_zj_filter_colon_var LD_LIBRARY_PATH
_zj_filter_colon_var CMAKE_PREFIX_PATH
_zj_filter_colon_var AMENT_PREFIX_PATH
_zj_filter_colon_var COLCON_PREFIX_PATH
_zj_filter_colon_var PKG_CONFIG_PATH

case "$-" in
  *u*)
    _zj_had_nounset=1
    set +u
    ;;
  *)
    _zj_had_nounset=0
    ;;
esac

unset _zj_path_items
unset -f _zj_filter_colon_var

set +u
# shellcheck disable=SC1091
source /opt/ros/humble/setup.bash
if [ -f /etc/profile.d/ros2_humble_cyclone.sh ]; then
  # shellcheck disable=SC1091
  source /etc/profile.d/ros2_humble_cyclone.sh
fi
if [ "$_zj_had_nounset" = "1" ]; then
  set -u
fi
unset _zj_had_nounset
