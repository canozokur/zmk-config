# SPDX-License-Identifier: MIT

# Suppress "unique_unit_address_if_enabled" to handle the following overlaps,
# which are real in silicon (no devicetree fix exists):
# - power@40000000 & clock@40000000
# - acl@4001e000 & flash-controller@4001e000
list(APPEND EXTRA_DTC_FLAGS "-Wno-unique_unit_address_if_enabled")
