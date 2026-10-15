#include <gtest/gtest.h>
#include <humble_dev_interfaces/msg/value.hpp>

TEST(GeneratedMessage, StoresValue) {
  humble_dev_interfaces::msg::Value message;
  message.value = "offline";
  EXPECT_EQ(message.value, "offline");
}
