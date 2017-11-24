#
# Copyright 2016 SUSE Linux GmBH
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

node[:neutron][:platform][:cisco_apic_pkgs].each { |p| package p }

neutron = nil
if node.attribute?(:cookbook) and node[:cookbook] == "nova"
  neutrons = node_search_with_cache("roles:neutron-server", node[:nova][:neutron_instance])
  neutron = neutrons.first || raise("Neutron instance '#{node[:nova][:neutron_instance]}' for nova not found")
else
  neutron = node
end

keystone_settings = KeystoneHelper.keystone_settings(neutron, @cookbook_name)

aciswitches = node[:neutron][:apic][:apic_switches].to_hash
template "/etc/neutron/neutron-server.conf.d/100-ml2_conf_cisco_apic.ini.conf" do
  cookbook "neutron"
  source "ml2_conf_cisco_apic.ini.erb"
  mode "0640"
  owner "root"
  group node[:neutron][:platform][:group]
  variables(
    keystone_settings: keystone_settings,
    ml2_mechanism_drivers: node[:neutron][:ml2_mechanism_drivers],
    policy_drivers: "aim_mapping",
    extension_drivers: "aim_extension,proxy_group",
    default_ip_pool: "192.168.0.0/16",
    optimized_dhcp: node[:neutron][:apic][:optimized_dhcp],
    optimized_metadata: node[:neutron][:apic][:optimized_metadata]
  )
  notifies :restart, "service[#{node[:neutron][:platform][:service_name]}]"
end

template "/etc/aim/aim.conf" do
  cookbook "neutron"
  source "aim.conf.erb"
  mode "0640"
  owner "root"
  group node[:neutron][:platform][:group]
  variables(
    sql_connection: neutron[:neutron][:db][:sql_connection],
    rabbit_settings: CrowbarOpenStackHelper.rabbitmq_settings(node, "neutron")
  )
  notifies :restart, "service[#{node[:neutron][:platform][:service_name]}]"
end

template "/etc/aim/aimctl.conf" do
  cookbook "neutron"
  source "aimctl.conf.erb"
  mode "0640"
  owner "root"
  group node[:neutron][:platform][:group]
  variables(
    apic_switches: aciswitches,
    vpc_pairs: node[:neutron][:apic][:vpc_pairs]
  )
  notifies :restart, "service[#{node[:neutron][:platform][:service_name]}]"
end
