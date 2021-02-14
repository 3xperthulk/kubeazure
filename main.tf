provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "KubernetesRG" {
  name     = "Kubernetes-RG"
  location = "West US"
}

resource "azurerm_network_security_group" "KubernetesNSG" {
  name                = "kubernetes-SG"
  location            = azurerm_resource_group.KubernetesRG.location
  resource_group_name = azurerm_resource_group.KubernetesRG.name
}

resource "azurerm_network_security_rule" "KuberneteAllowSsh" {
  name                        = "kubernetes-allow-ssh"
  priority                    = 1000
  direction                   = "inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "22"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.KubernetesRG.name
  network_security_group_name = azurerm_network_security_group.KubernetesNSG.name
}

resource "azurerm_network_security_rule" "KuberneteAllowApi" {
  name                        = "kubernetes-allow-api-server"
  priority                    = 1001
  direction                   = "inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "6443"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.KubernetesRG.name
  network_security_group_name = azurerm_network_security_group.KubernetesNSG.name
}

resource "azurerm_virtual_network" "KubernetesVNet" {
  name                = "Kubernetes-VNet"
  location            = azurerm_resource_group.KubernetesRG.location
  resource_group_name = azurerm_resource_group.KubernetesRG.name
  address_space       = ["10.0.0.0/16"]
 #dns_servers         = ["10.0.0.4", "10.0.0.5"]

  tags = {
    environment = "Kubernetes"
  }
}

resource "azurerm_subnet" "KubetneteSubnet" {
  name                 = "kubetnete-subnet"
  resource_group_name  = azurerm_resource_group.KubernetesRG.name
  virtual_network_name = azurerm_virtual_network.KubernetesVNet.name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_public_ip" "KubernetesIP" {
  name                = "Kubernetes-Ip"
  resource_group_name = azurerm_resource_group.KubernetesRG.name
  location            = azurerm_resource_group.KubernetesRG.location
  allocation_method   = "Static"

  tags = {
    environment = "Production"
  }
}

resource "azurerm_lb" "KubernetesLB" {
  name                = "Kubernetes-lb"
  location            = azurerm_resource_group.KubernetesRG.location
  resource_group_name = azurerm_resource_group.KubernetesRG.name

  frontend_ip_configuration {
    name                 = "PublicIPAddress"
    public_ip_address_id = azurerm_public_ip.KubernetesIP.id
  }
}

resource "azurerm_lb_backend_address_pool" "KubernetesLbBackend" {
  loadbalancer_id     = azurerm_lb.KubernetesLB.id
  resource_group_name = azurerm_resource_group.KubernetesRG.name
  name                = "kubernetes-lb-pool"
}

resource "azurerm_network_interface" "ControllerNIC" {
  count               = 3
  name                = "controller-nic${count.index}"
  location            = azurerm_resource_group.KubernetesRG.location
  resource_group_name = azurerm_resource_group.KubernetesRG.name
  ip_configuration {
    name                          = "controller-configuration"
    subnet_id                     = azurerm_subnet.KubetneteSubnet.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_network_interface_backend_address_pool_association" "NicLbAssoc" {
  count                   = 3
  network_interface_id    = azurerm_network_interface.ControllerNIC[count.index].id
  ip_configuration_name   = "controller-configuration"
  backend_address_pool_id = azurerm_lb_backend_address_pool.KubernetesLbBackend.id
}

resource "azurerm_availability_set" "KubernetesAvset" {
 name                         = "kubernetes-avset"
 location            = azurerm_resource_group.KubernetesRG.location
 resource_group_name = azurerm_resource_group.KubernetesRG.name
 platform_fault_domain_count  = 2
 platform_update_domain_count = 2
 managed                      = true
}

resource "azurerm_linux_virtual_machine" "ControllerVM" {
  count                 = 3
  name                  = "controller-vm${count.index}"
  location              = azurerm_resource_group.KubernetesRG.location
  resource_group_name   = azurerm_resource_group.KubernetesRG.name
  network_interface_ids = [element(azurerm_network_interface.ControllerNIC.*.id, count.index)] #azurerm_network_interface.ControllerNIC[count.index].id
  availability_set_id   = azurerm_availability_set.KubernetesAvset.id
  size                  = "Standard_DS1_v2"
  admin_username        = "azureuser"

  source_image_reference {
    publisher = "OpenLogic"
    offer     = "CentOS"
    sku       = "7.5"
    version   = "latest"
  }
  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }
  admin_ssh_key {
    username   = "azureuser"
    public_key = file(var.sshFilePath)
  }

  tags = {
    environment = "Kubernetes"
  }
}

resource "azurerm_network_interface" "WorkerNIC" {
  count               = 3
  name                = "worker-nic${count.index}"
  location            = azurerm_resource_group.KubernetesRG.location
  resource_group_name = azurerm_resource_group.KubernetesRG.name

  ip_configuration {
    name                          = "worker-configuration"
    subnet_id                     = azurerm_subnet.KubetneteSubnet.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_linux_virtual_machine" "WorkerVM" {
  count                 = 3
  name                  = "worker-vm${count.index}"
  location              = azurerm_resource_group.KubernetesRG.location
  resource_group_name   = azurerm_resource_group.KubernetesRG.name
  network_interface_ids = [element(azurerm_network_interface.WorkerNIC.*.id, count.index)] #azurerm_network_interface.ControllerNIC[count.index].id
  size                  = "Standard_DS1_v2"
  admin_username        = "azureuser"

  source_image_reference {
    publisher = "OpenLogic"
    offer     = "CentOS"
    sku       = "7.5"
    version   = "latest"
}
  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }
  admin_ssh_key {
    username   = "azureuser"
    public_key = file(var.sshFilePath)
  }

  tags = {
    environment = "Kubernetes"
  }
}
