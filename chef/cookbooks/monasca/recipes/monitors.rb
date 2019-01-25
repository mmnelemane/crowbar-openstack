include_recipe "keystone::monitor_monasca" if node["roles"].include?("keystone-server")
include_recipe "swift::monitor_monasca" if node["roles"].include?("swift-proxy")
include_recipe "glance::monitor_monasca" if node["roles"].include?("glance-server")
include_recipe "cinder::monitor_monasca" if node["roles"].include?("cinder-controller")
include_recipe "neutron::monitor_monasca" if node["roles"].include?("neutron-server")
include_recipe "nova::monitor_monasca" if node["roles"].include?("nova-compute-kvm")
include_recipe "nova::monitor_monasca" if node["roles"].include?("nova-compute-qemu")
include_recipe "nova::monitor_monasca" if node["roles"].include?("nova-controller")
include_recipe "barbican::monitor_monasca" if node["roles"].include?("barbican-controller")
include_recipe "manila::monitor_monasca" if node["roles"].include?("manila-server")
include_recipe "sahara::monitor_monasca" if node["roles"].include?("sahara-server")
include_recipe "heat::monitor_monasca" if node["roles"].include?("heat-server")