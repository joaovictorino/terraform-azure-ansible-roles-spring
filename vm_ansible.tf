resource "azurerm_linux_virtual_machine" "vm_aula_ansible" {
  name                  = "myVMAnsible"
  location              = var.location
  resource_group_name   = azurerm_resource_group.rg_aula.name
  network_interface_ids = [azurerm_network_interface.nic_aula_ansible.id]
  size                  = "Standard_DS1_v2"

  os_disk {
    name                 = "myOsAnsibleDisk"
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }

  computer_name                   = "myvmansible"
  admin_username                  = var.user
  admin_password                  = var.password
  disable_password_authentication = false

  tags = {
    environment = "aula infra",
    tool        = "ansible"
  }

  depends_on = [azurerm_resource_group.rg_aula,
    azurerm_network_interface.nic_aula_ansible,
    azurerm_network_interface.nic_aula,
    azurerm_network_interface.nic_aula_db,
    azurerm_public_ip.publicip_aula_ansible,
    azurerm_public_ip.publicip_aula,
    azurerm_linux_virtual_machine.vm_aula,
  azurerm_linux_virtual_machine.vm_aula_db]
}

resource "time_sleep" "wait_30_seconds" {
  depends_on      = [azurerm_linux_virtual_machine.vm_aula_ansible]
  create_duration = "30s"
}

resource "local_file" "inventory" {
  filename   = "./ansible/hosts"
  content    = <<EOF
[mysqlserver]
${azurerm_network_interface.nic_aula_db.private_ip_address}

[springapp]
${azurerm_network_interface.nic_aula.private_ip_address}

[app:children]
mysqlserver
springapp

[app:vars]
ansible_user=azureuser
ansible_ssh_pass=godofw@r35
ansible_python_interpreter=/usr/bin/python3
ansible_ssh_common_args='-o StrictHostKeyChecking=no'
EOF
  depends_on = [time_sleep.wait_30_seconds]
}

resource "null_resource" "upload" {
  provisioner "file" {
    connection {
      type     = "ssh"
      user     = var.user
      password = var.password
      host     = azurerm_public_ip.publicip_aula_ansible.ip_address
    }
    source      = "ansible"
    destination = "/home/azureuser"
  }

  depends_on = [time_sleep.wait_30_seconds]
}

resource "null_resource" "deploy" {
  triggers = {
    order = null_resource.upload.id
  }
  provisioner "remote-exec" {
    connection {
      type     = "ssh"
      user     = var.user
      password = var.password
      host     = azurerm_public_ip.publicip_aula_ansible.ip_address
    }
    inline = [
      "sudo apt-get update",
      "sudo apt-get install -y software-properties-common",
      "sudo apt-add-repository --yes --update ppa:ansible/ansible",
      "sudo apt-get -y install python3 ansible",
      "ansible-playbook -i /home/azureuser/ansible/hosts /home/azureuser/ansible/main.yml"
    ]
  }
}
