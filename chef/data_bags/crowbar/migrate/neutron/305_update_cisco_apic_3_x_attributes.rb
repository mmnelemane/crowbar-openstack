def upgrade(ta, td, a, d)
  a["apic"]["opflex"].delete("peer_ip")
  a["apic"]["opflex"].delete("peer_port")
  a["apic"]["opflex"]["integration_bridge"] = ta["apic"]["opflex"]["integration_bridge"]
  a["apic"]["opflex"]["access_bridge"] = ta["apic"]["opflex"]["access_bridge"]
  return a, d
end

def downgrade(ta, td, a, d)
  a["apic"]["opflex"]["peer_ip"] = ta["apic"]["opflex"]["peer_ip"]
  a["apic"]["opflex"]["peer_port"] = ta["apic"]["opflex"]["peer_porT"]
  a["apic"]["opflex"].delete("integration_bridge")
  a["apic"]["opflex"].delete("access_bridge")
 return a, d
end
