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

if ceph_servers.length > 0 && node.roles.include?("ceph-radosgw")
  ceph_conf = "/etc/ceph/ceph.conf"
  admin_keyring = "/etc/ceph/ceph.client.admin.keyring"
  ruid = "rgw_admin"
  
  cmd = ["ceph", "-k", admin_keyring, "-c", ceph_conf, "-s"]
  check_ceph = Mixlib::ShellOut.new(cmd)

  unless check_ceph.run_command.stdout.match("(HEALTH_OK|HEALTH_WARN)")
    Chef::Log.info("Ceph cluster is not healthy, skipping radosgw setup for ceilometer")
    return
  end

  # Create admin user and add caps to access buckets and users
  if rgw_access_key != "<None>" && rgw_secret_key != "<None>"
    execute "create_rgw_admin_user_with_keys" do
      command "radosgw-admin user create --display-name=Radosgw_Admin --uid=#{ruid} --access-key=#{@rgw_access_key} --secret=#{@rgw_secret_key}"
      not_if "out=$(radosgw-admin user info --uid=#{ruid}); [$? != 0] || echo ${out} | grep -q '#{ruid}'"
      action :run
      notifies :run, "execute[add_radosgw_buckets_caps]", :immediately
    end
  else
    execute "create_radosgw_admin_user" do
      command "radosgw-admin user create --display-name=RadosGW_Admin --uid=#{ruid}"
      not_if "out=$(radosgw-admin user info #{ruid}) ; [$? != 0] || echo ${out} | grep -q '#{ruid}'"
      action :run
      notifies :run, "execute[add_radosgw_buckets_caps]", :immediately
    end

    cmd = "radosgw-admin user info --uid=#{ruid}"
    shell_cmd = Mixlib::ShellOut.new(cmd)
    out = shell_cmd.run_command.stdout
    unless out.empty?
      rgw_keys = JSON.parse(out)
      @rgw_access_key = rgw_keys["keys"][0]["access_key"]
      @rgw_secret_key = rgw_keys["keys"][0]["secret_key"]
    end

    # Update caps for Radosgw admin user
    execute "add_radosgw_buckets_caps" do
      command "radosgw-admin caps add --uid=#{ruid} --caps='buckets=read'"
      only_if "out=$(radosgw-admin user info #{ruid}) ; [$? != 0] || echo ${out} | grep -q '#{ruid}'"
      action :run
      notifies :run, "execute[add_radosgw_users_caps]", :immediately
    end

    execute "add_radosgw_users_caps" do
      command "radosgw-admin caps add --uid=#{ruid} --caps='users=read'"
      only_if "out=$(radosgw-admin user info #{ruid}) ; [$? != 0] || echo ${out} | grep -q '#{ruid}'"
      action :run
    end
  end
end


