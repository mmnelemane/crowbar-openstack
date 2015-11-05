#
# Copyright 2015 SUSE Linux GmbH
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
# Cookbook Name:: ceilometer
# Recipe:: ceph
#
ceph_env_filter = " AND ceph_config_environment:ceph-config-default"
ceph_servers = search(:node, "roles:ceph-osd#{ceph_env_filter}") || []

unless ceph_servers.length > 0
  Chef::Log.warn("Ceph servers not available.")
  return
end

keystone_settings = KeystoneHelper.keystone_settings(node, @cookbook_name)


Chef::Log.info("MMNELEMANE: Inside ceph.rb recipe")

if node.roles.include?("ceph-radosgw")
  ceph_conf = "/etc/ceph/ceph.conf"
  admin_keyring = "/etc/ceph/ceph.client.admin.keyring"
  
  cmd = ["ceph", "-k", admin_keyring, "-c", ceph_conf, "-s"]
  check_ceph = Mixlib::ShellOut.new(cmd)

  unless check_ceph.run_command.stdout.match("(HEALTH_OK|HEALTH_WARN)")
    Chef::Log.info("Ceph cluster is not healthy, skipping radosgw setup for ceilometer")
    return
  end
  Chef::Log.info("Ceph cluster is fine. Continuing with buckets")

  # Create admin user and add caps to access buckets and users
  # if rgw_access_key != "<None>" && rgw_secret_key != "<None>"
  #   execute "create_rgw_admin_user_with_keys" do
  #     command "radosgw-admin user create --display-name=Radosgw_Admin --uid=#{rgw_userid} --access-key=#{rgw_access_key} --secret=#{rgw_secret_key}"
  #     not_if "out=$(radosgw-admin user info --uid=#{rgw_userid}); [$? != 0] || echo ${out} | grep -q '#{rgw_userid}'"
  #     action :run
  #     notifies :run, "execute[add_radosgw_buckets_caps]", :immediately
  #   end
  # else
  #   execute "create_radosgw_admin_user" do
  #     command "radosgw-admin user create --display-name=RadosGW_Admin --uid=#{rgw_userid}"
  #     not_if "out=$(radosgw-admin user info #{rgw_userid}) ; [$? != 0] || echo ${out} | grep -q '#{rgw_userid}'"
  #     action :run
  #     notifies :run, "execute[add_radosgw_buckets_caps]", :immediately
  #   end
  #   # cmd = "radosgw-admin user info --uid=#{rgw_userid}"
  #   # shell_cmd = Mixlib::ShellOut.new(cmd)
  #   # out = shell_cmd.run_command.stdout
  #   # unless out.empty?
  #   #   rgw_keys = JSON.parse(out)
  #   #   @rgw_access_key = rgw_keys["keys"][0]["access_key"]
  #   #   @rgw_secret_key = rgw_keys["keys"][0]["secret_key"]
  #   # end
  # end

  # Update caps for Radosgw admin user
  execute "add_radosgw_buckets_caps" do
    command "radosgw-admin caps add --uid=#{@cookbook_name} --caps='buckets=*'"
    only_if "out=$(radosgw-admin user info #{@cookbook_name}) ; [$? != 0] || echo ${out} | grep -q '#{@cookbook_name}'"
    action :run
    notifies :run, "execute[add_radosgw_users_caps]", :immediately
  end

  execute "add_radosgw_users_caps" do
    command "radosgw-admin caps add --uid=#{@cookbook_name} --caps='users=read'"
    only_if "out=$(radosgw-admin user info #{@cookbook_name}) ; [$? != 0] || echo ${out} | grep -q '#{@cookbook_name}'"
    action :run
  end

  env = "--os-username #{keystone_settings["admin_user"]} "+
        "--os-password #{keystone_settings["admin_password"]} "+
        "--os-auth-url #{keystone_settings["admin_auth_url"]} "+
        "--os-tenant-name #{keystone_settings["admin_tenant"]}"

  cmd = "openstack #{env} ec2 credentials list --user #{@cookbook_name} -c Access -f value"
  get_ec2_access = Mixlib::ShellOut.new(cmd)
  #@rgw_access_key = get_ec2_access.run_command.stdout
  rgw_access_key = get_ec2_access.run_command.stdout

  cmd = "openstack #{env} ec2 credentials list --user #{@cookbook_name} -c Secret -f value"
  get_ec2_secret = Mixlib::ShellOut.new(cmd)
  #@rgw_secret_key = get_ec2_secret.run_command.stdout
  rgw_secret_key = get_ec2_secret.run_command.stdout
  Chef::Log.info("MMNELEMANE: Access: #{rgw_access_key}, Secret: #{rgw_secret_key}")

  node.set[:ceilometer][:rbd][:rgw_access_key] = rgw_access_key
  node.set[:ceilometer][:rbd][:rgw_secret_key] = rgw_secret_key
  node.save

end


