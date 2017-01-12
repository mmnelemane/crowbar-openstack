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

node[:neutron][:platform][:odl_pkgs].each { |p| package p }

odl_controller_ip = node[:neutron][:odl][:controller_ip]
odl_controller_port = node[:neutron][:odl][:controller_port]
odl_manager_port = node[:neutron][:odl][:manager_port]
odl_protocol = node[:neutron][:odl][:protocol]
ovs_manager = "tcp:#{odl_controller_ip}:#{odl_manager_port}"
ovs_controller = "tcp:#{odl_controller_ip}:#{odl_controller_port}"

# Switch and Flow setup for opendaylight
Chef::Log.error("MMNELEMANE: Applying ODL switch configuration")
bash "update_ovs_switches" do
  user "root"
  action :run
  code <<-EOF
    ovs_id=$(ovs-vsctl show | head -1)

    echo "Configuring switch with ID: $ovs_id" >> /tmp/log.txt
    
    service openstack-neutron-openvswitch-agent stop
    service openvswitch stop
    ovs-vsctl set-manager #{ovs_manager}
    service openvswitch start

    if [ -nz $(ovs-vsctl br-exists br-fixed) ]; then
        local_ip=$(ifconfig br-fixed | grep "inet addr" | awk '{print $2}' | awk -F':' '{print $2}')
        ovs-vsctl set Open_vSwitch $ovs_id other_config={local_ip=$local_ip}
    fi
   
    for bridge in "br-fixed" "br-public"
    do
        br_exists=
        eval $(ovs-vsctl br-exists $bridge)
        if [ -nz $br_exists ]; then
            ovs-vsctl add-br $bridge
        fi
        ovs-vsctl set Open_vSwitch $ovs_id other_config:provider_mappings=physnet1:$bridge
        ovs-ofctl add-flow $bridge action=NORMAL
        ovs-vsctl add-port br-int int-$bridge
        ovs-vsctl set interface int-$bridge type=patch
        ovs-vsctl set interface int-$bridge options:peer=phy-br-public
    done
    for bridge in "br-int" "br-public" "br-tunnel" "br-fixed"
    do
      ovs-vsctl set-controller $bridge #{ovs_controller}
    done

  EOF
end

odl_url = "#{odl_protocol}://#{odl_controller_ip}:#{odl_controller_port}/controller/nb/v2/neutron"
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

