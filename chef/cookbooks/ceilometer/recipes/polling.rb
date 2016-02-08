# Copyright 2011 Dell, Inc.
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

package "ceilometer-polling" do
  if %w(rhel suse).include?(node[:platform_family])
    package_name "openstack-ceilometer-polling"
  end
  action :install
end

include_recipe "#{@cookbook_name}::common"

ha_enabled = node[:ceilometer][:ha][:polling][:enabled]

service "ceilometer-polling" do
  service_name node[:ceilometer][:polling][:service_name]
  supports status: true, restart: true, start: true, stop: true
  action [:enable, :start]
  subscribes :restart, resources("template[/etc/ceilometer/ceilometer.conf]")
  subscribes :restart, resources("template[/etc/ceilometer/pipeline.yaml]")
  provider Chef::Provider::CrowbarPacemakerService if ha_enabled
end

# Prepare controller with the rgw_admin role
if node.roles.include?("ceilometer-polling")
  rgw_userid = "rgw_admin"
  keystone_register "create radosgw admin role" do
    protocol keystone_settings["protocol"]
    insecure keystone_settings["insecure"]
    host keystone_settings["internal_url_host"]
    port keystone_settings["admin_port"]
    token keystone_settings["admin_token"]
    role_name rgw_userid
    action :add_role
  end

  keystone_register "create radosgw admin user" do
    protocol keystone_settings["protocol"]
    insecure keystone_settings["insecure"]
    host keystone_settings["internal_url_host"]
    port keystone_settings["admin_port"]
    token keystone_settings["admin_token"]
    user_name rgw_userid
    action :add_user
  end

  keystone_register "give radosgw admin user access" do
    protocol keystone_settings["protocol"]
    insecure keystone_settings["insecure"]
    host keystone_settings["internal_url_host"]
    port keystone_settings["admin_port"]
    token keystone_settings["admin_token"]
    user_name rgw_userid
    role_name rgw_userid
    tenant_name keystone_settings["service_tenant"]
    action :add_access
  end

  keystone_register "give ec2 credentials to radosgw admin" do
    protocol keystone_settings["protocol"]
    insecure keystone_settings["insecure"]
    host keystone_settings["internal_url_host"]
    port keystone_settings["admin_port"]
    token keystone_settings["admin_token"]
    user_name rgw_userid
    tenant_name keystone_settings["service_tenant"]
    action :add_ec2
  end

end

if ha_enabled
  log "HA support for ceilometer-polling is enabled"
  include_recipe "ceilometer::polling_ha"
else
  log "HA support for ceilometer-polling is disabled"
end
