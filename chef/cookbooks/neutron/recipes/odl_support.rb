#
# Copyright 2016 SUSE LINUX GmbH
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

neutron = nil
if node.attribute?(:cookbook) && node[:cookbook] == "nova"
  neutrons = node_search_with_cache("roles:neutron-server", node[:nova][:neutron_instance])
  neutron = neutrons.first || raise("Neutron instance '#{node[:nova][:neutron_instance]}' \
                                    for nova not found")
else
  neutron = node
end

if node.roles.include?("neutron-server")
  node[:neutron][:platform][:odl_pkgs].each { |p| package p }
end


# Stop Neutron Services to ensure no APIs are run during ODL configuration
service node[:neutron][:platform][:service_name] do
  action :stop
end

# Stop Neutron OVS and L3 agents on all nodes
[node[:neutron][:platform][:ovs_agent_name], node[:neutron][:platform][:l3_agent_name]].each do |agent|
  service "#{agent}" do
    action [:disable, :stop]
  end
end

# Clean up OVSDB. No need to explicitly delete the bridges and ports
bash "cleanup_ovsdb" do
  user "root"
  action :run
  code <<-EOF
    systemctl stop openvswitch
    rm -rf /var/log/openvswitch/*
    rm -rf /etc/openvswitch/conf.db
    systemctl start openvswitch
  EOF
end

# Create br-fixed and br-public for ODL to patch
["br-fixed", "br-public"].each do |bridge|
  execute "create_fixed_public_bridges" do
    command "ovs-vsctl --may-exist add-br #{bridge}"
    action :run
  end
end

# Prepare variables for switch setup for opendaylight controller
odl_controller_ip = neutron[:neutron][:odl][:controller_ip]
odl_manager_port = neutron[:neutron][:odl][:manager_port]
odl_protocol = neutron[:neutron][:odl][:protocol]
odl_controller_port = neutron[:neutron][:odl][:controller_port]

# Find a way to get the NIC ip address on the node
# Currently assuming it to be eth0
bash "set_ovs_local_ip" do
  user "root"
  action :run
  code <<-EOF
    sleep 2
    ovs_id=$(ovs-vsctl show | head -n 1)
    local_ip=$(ifconfig br-fixed | grep "inet addr" | awk '{print $2}' | awk -F':' '{print $2}')
    if [ -z $local_ip ]; then 
      local_ip=$(ifconfig eth0 | grep "inet addr" | awk '{print $2}' | awk -F':' '{print $2}')
    fi
    ovs-vsctl set Open_vSwitch $ovs_id other_config:local_ip=$local_ip
    mappings="physnet1:br-fixed,physnet2:br-public"
    ovs_id=$(ovs-vsctl show | head -n 1)
    ovs-vsctl set Open_vSwitch $ovs_id other_config:provider_mappings=$mappings
    sleep 2
  EOF
end
Chef::Log.warn("MMNELEMANE: Applied OVS local_ip configurations")    


# Recreate OVS bridge setup
ovs_manager = "tcp:#{odl_controller_ip}:#{odl_manager_port}"
ovs_controller = "tcp:#{odl_controller_ip}:#{odl_controller_port}"
bash "recreate_ovs_setup" do
  user "root"
  action :run
  code <<-EOF
    ovs-vsctl add-port br-int
    ovs-vsctl add-port br-int int-br-fixed
    ovs-vsctl add-port br-fixed phy-br-fixed
    ovs-vsctl add-port br-fixed eth0
    ovs-vsctl set Interface phy-br-fixed type=patch
    ovs-vsctl set Interface int-br-fixed type=patch
    ovs-vsctl set Interface phy-br-fixed options:peer=int-br-fixed
    ovs-vsctl set Interface int-br-fixed options:peer=phy-br-fixed
    ovs-vsctl set-manager #{ovs_manager}
    sleep 2
    ovs-vsctl set-controller br-fixed #{ovs_controller}
    ovs-vsctl set-controller br-public #{ovs_controller}
  EOF
end

# (mmnelemane): May revisit include the below configs when working with l3-router
# Need to add the new parameters in dhcp_agent.ini.erb if this is enabled.
# neutron_options = "--config-file /etc/neutron/neutron.conf --config-file /etc/neutron/plugins/ml2/ml2_conf.ini"
# execute "neutron_db_sync" do
#   command "neutron-db-manage #{neutron_options} upgrade head"
#   action :run
#   notifies :restart, "service[#{node[:neutron][:platform][:service_name]}]"
# end

if node.roles.include?("neutron-server")
  # Required as workaround for OpenStack Newton
  odl_api_port = node[:opendaylight][:port]
  template "/etc/neutron/dhcp_agent.ini" do
    cookbook "neutron"
    source "dhcp_agent.ini.erb"
    mode "0640"
    owner "root"
    group node[:neutron][:platform][:group]
    variables(
      force_metadata: true,
      ovsdb_interface: "vsctl"
    )
    notifies :restart, "service[#{node[:neutron][:platform][:service_name]}]" 
  end

  odl_url = "#{odl_protocol}://#{odl_controller_ip}:#{odl_api_port}/controller/nb/v2/neutron"
  template "/etc/neutron/plugins/ml2/ml2_conf_odl.ini" do
    cookbook "neutron"
    source "ml2_conf_odl.ini.erb"
    mode "0640"
    owner "root"
    group node[:neutron][:platform][:group]
    variables(
      ml2_odl_url: odl_url,
      ml2_odl_username: node[:neutron][:odl][:username],
      ml2_odl_password: node[:neutron][:odl][:password]
    )
    notifies :restart, "service[#{node[:neutron][:platform][:service_name]}]"
  end

  # Need an additional config parameter from admin user to enable odl-l3.
  # The below configuration can be applied if odl_l3 is enabled.
  # l3_router = ["odl-router"]
  # template "/etc/neutron/neutron.conf" do
  #   source "neutron.conf.erb"
  #   variables(
  #     service_plugins: l3_router
  #   )
  #   notifies :restart, "service[#{node[:neutron][:platform][:service_name]}]"
  # end
end

# Start Neutron Services with ODL configuration
service node[:neutron][:platform][:service_name] do
  action :start
end
