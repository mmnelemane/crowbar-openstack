def upgrade(ta, td, a, d)
  a["apic"]["phys_domain"] = ta["apic"]["phys_domain"] unless a["apic"].key?("phys_domain")
  a["apic"]["vm_domains"] = ta["apic"]["vm_domains"] unless a["apic"].key?("vm_domains")

  return a, d
end

def downgrade(ta, td, a, d)
  a["apic"].delete("phys_domain") unless ta["apic"].key?("phys_domain")
  a["apic"].delete("vm_domains") unless ta["apic"].key?("vm_domains")

  return a, d
end
