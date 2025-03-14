provider "azurerm" {
features {}
subscription_id = var.F-SubscriptionID
}


#variables
variable "A-location" {
    description = "Location of the resources, example: eastus2"
    #default     = "eastus"
}

variable "B-resource_group_name" {
    description = "Name of the resource group to create"
}

variable "C-home_public_ip" {
    description = "Your home public ip address"
}

variable "D-username" {
    description = "Username for Virtual Machines"
    #default     = "azureuser"
}

variable "E-password" {
    description = "Password for Virtual Machines"
    sensitive = true
}

variable "F-SubscriptionID" {
  description = "Subscription ID to use"  
}

resource "azurerm_resource_group" "RG" {
  location = var.A-location
  name     = var.B-resource_group_name
}

#logic app to self destruct resourcegroup after 24hrs
data "azurerm_subscription" "sub" {
}

resource "azurerm_logic_app_workflow" "workflow1" {
  location = azurerm_resource_group.RG.location
  name     = "labdelete"
  resource_group_name = azurerm_resource_group.RG.name
  identity {
    type = "SystemAssigned"
  }
  depends_on = [
    azurerm_resource_group.RG,
  ]
}
resource "azurerm_role_assignment" "contrib1" {
  scope = azurerm_resource_group.RG.id
  role_definition_name = "Contributor"
  principal_id  = azurerm_logic_app_workflow.workflow1.identity[0].principal_id
  depends_on = [azurerm_logic_app_workflow.workflow1]
}


resource "azurerm_resource_group_template_deployment" "apiconnections" {
  name                = "group-deploy"
  resource_group_name = azurerm_resource_group.RG.name
  deployment_mode     = "Incremental"
  template_content = <<TEMPLATE
{
    "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#",
    "contentVersion": "1.0.0.0",
    "parameters": {},
    "variables": {},
    "resources": [
        {
            "type": "Microsoft.Web/connections",
            "apiVersion": "2016-06-01",
            "name": "arm-1",
            "location": "${azurerm_resource_group.RG.location}",
            "kind": "V1",
            "properties": {
                "displayName": "labdeleteconn1",
                "authenticatedUser": {},
                "statuses": [
                    {
                        "status": "Ready"
                    }
                ],
                "connectionState": "Enabled",
                "customParameterValues": {},
                "alternativeParameterValues": {},
                "parameterValueType": "Alternative",
                "createdTime": "2023-05-21T23:07:20.1346918Z",
                "changedTime": "2023-05-21T23:07:20.1346918Z",
                "api": {
                    "name": "arm",
                    "displayName": "Azure Resource Manager",
                    "description": "Azure Resource Manager exposes the APIs to manage all of your Azure resources.",
                    "iconUri": "https://connectoricons-prod.azureedge.net/laborbol/fixes/path-traversal/1.0.1552.2695/arm/icon.png",
                    "brandColor": "#003056",
                    "id": "/subscriptions/${data.azurerm_subscription.sub.subscription_id}/providers/Microsoft.Web/locations/${azurerm_resource_group.RG.location}/managedApis/arm",
                    "type": "Microsoft.Web/locations/managedApis"
                },
                "testLinks": []
            }
        },
        {
            "type": "Microsoft.Logic/workflows",
            "apiVersion": "2017-07-01",
            "name": "labdelete",
            "location": "${azurerm_resource_group.RG.location}",
            "dependsOn": [
                "[resourceId('Microsoft.Web/connections', 'arm-1')]"
            ],
            "identity": {
                "type": "SystemAssigned"
            },
            "properties": {
                "state": "Enabled",
                "definition": {
                    "$schema": "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#",
                    "contentVersion": "1.0.0.0",
                    "parameters": {
                        "$connections": {
                            "defaultValue": {},
                            "type": "Object"
                        }
                    },
                    "triggers": {
                        "Recurrence": {
                            "recurrence": {
                                "frequency": "Minute",
                                "interval": 3,
                                "startTime": "${timeadd(timestamp(),"24h")}"
                            },
                            "evaluatedRecurrence": {
                                "frequency": "Minute",
                                "interval": 3,
                                "startTime": "${timeadd(timestamp(),"24h")}"
                            },
                            "type": "Recurrence"
                        }
                    },
                    "actions": {
                        "Delete_a_resource_group": {
                            "runAfter": {},
                            "type": "ApiConnection",
                            "inputs": {
                                "host": {
                                    "connection": {
                                        "name": "@parameters('$connections')['arm']['connectionId']"
                                    }
                                },
                                "method": "delete",
                                "path": "/subscriptions/@{encodeURIComponent('${data.azurerm_subscription.sub.subscription_id}')}/resourcegroups/@{encodeURIComponent('${azurerm_resource_group.RG.name}')}",
                                "queries": {
                                    "x-ms-api-version": "2016-06-01"
                                }
                            }
                        }
                    },
                    "outputs": {}
                },
                "parameters": {
                    "$connections": {
                        "value": {
                            "arm": {
                                "connectionId": "[resourceId('Microsoft.Web/connections', 'arm-1')]",
                                "connectionName": "arm-1",
                                "connectionProperties": {
                                    "authentication": {
                                        "type": "ManagedServiceIdentity"
                                    }
                                },
                                "id": "/subscriptions/${data.azurerm_subscription.sub.subscription_id}/providers/Microsoft.Web/locations/${azurerm_resource_group.RG.location}/managedApis/arm"
                            }
                        }
                    }
                }
            }
        }
    ]
}
TEMPLATE
}

resource "random_pet" "name" {
  length = 1
}

#log analytics workspace
resource "azurerm_log_analytics_workspace" "LAW" {
  name                = "LAW-${random_pet.name.id}"
  location            = azurerm_resource_group.RG.location
  resource_group_name = azurerm_resource_group.RG.name
  
}


#vnets and subnets
resource "azurerm_virtual_network" "hub-vnet" {
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.RG.location
  name                = "AZ-hub-vnet"
  resource_group_name = azurerm_resource_group.RG.name
  subnet {
    address_prefixes     = ["10.0.0.0/24"]
    name                 = "default"
    security_group = azurerm_network_security_group.hubvnetNSG.id
  }
  subnet {
    address_prefixes     = ["10.0.1.0/24"]
    name                 = "GatewaySubnet" 
  }
  subnet {
    address_prefixes     = ["10.0.2.0/24"]
    name                 = "AzureFirewallSubnet" 
  }
  timeouts {
    create = "2h"
    read = "2h"
    update = "2h"
    delete = "2h"
  }
  
}


resource "azurerm_virtual_network" "spoke-vnet" {
  address_space       = ["10.250.0.0/16"]
  location            = azurerm_resource_group.RG.location
  name                = "AZ-spoke-vnet"
  resource_group_name = azurerm_resource_group.RG.name
  subnet {
    address_prefixes     = ["10.250.0.0/24"]
    name                 = "default"
    security_group = azurerm_network_security_group.spokevnetNSG.id
  }
  subnet {
    address_prefixes     = ["10.250.1.0/24"]
    name                 = "GatewaySubnet" 
  }
  timeouts {
    create = "2h"
    read = "2h"
    update = "2h"
    delete = "2h"
  }
  
}

resource "azurerm_virtual_network_peering" "hubtospokepeering" {
  name                      = "hub-to-spoke-peering"
  remote_virtual_network_id = azurerm_virtual_network.spoke-vnet.id
  resource_group_name       = azurerm_resource_group.RG.name
  virtual_network_name      = "AZ-hub-vnet"
  allow_forwarded_traffic = true
  allow_gateway_transit = true
  timeouts {
    create = "2h"
    read = "2h"
    update = "2h"
    delete = "2h"
  }
  depends_on = [
    azurerm_virtual_network.hub-vnet,
    azurerm_virtual_network.spoke-vnet,
    
  ]
}
resource "azurerm_virtual_network_peering" "spoketohubpeering" {
  name                      = "spoke-to-hub-peering"
  remote_virtual_network_id = azurerm_virtual_network.hub-vnet.id
  resource_group_name       = azurerm_resource_group.RG.name
  virtual_network_name      = "AZ-spoke-vnet"
  allow_forwarded_traffic = true
  #use_remote_gateways = true
  timeouts {
    create = "2h"
    read = "2h"
    update = "2h"
    delete = "2h"
  }
  depends_on = [
    azurerm_virtual_network.spoke-vnet,
    azurerm_virtual_network.hub-vnet,
    
  ]
}

#route table
resource "azurerm_route_table" "RT" {
  name                          = "all-to-fw"
  location                      = azurerm_resource_group.RG.location
  resource_group_name           = azurerm_resource_group.RG.name
  

  route {
    name           = "inet"
    address_prefix = "0.0.0.0/0"
    next_hop_type  = "VirtualAppliance"
    next_hop_in_ip_address = "10.0.2.4"
  }
  route {
    name           = "tospoke"
    address_prefix = "10.250.0.0/16"
    next_hop_type  = "VirtualAppliance"
    next_hop_in_ip_address = "10.0.2.4"
  }
  route {
    name           = "tohub"
    address_prefix = "10.0.0.0/24"
    next_hop_type  = "VirtualAppliance"
    next_hop_in_ip_address = "10.0.2.4"
  }
  route {
    name           = "tohome"
    address_prefix = "${var.C-home_public_ip}/32"
    next_hop_type  = "Internet"
    
  }
  
  timeouts {
    create = "2h"
    read = "2h"
    update = "2h"
    delete = "2h"
  }
}

resource "azurerm_subnet_route_table_association" "onhubdefaultsubnet" {
  subnet_id      = azurerm_virtual_network.hub-vnet.subnet.*.id[0]
  route_table_id = azurerm_route_table.RT.id
  timeouts {
    create = "2h"
    read = "2h"
    #update = "2h"
    delete = "2h"
  }
}
resource "azurerm_subnet_route_table_association" "onspokedefaultsubnet" {
  subnet_id      = azurerm_virtual_network.spoke-vnet.subnet.*.id[0]
  route_table_id = azurerm_route_table.RT.id
  timeouts {
    create = "2h"
    read = "2h"
    #update = "2h"
    delete = "2h"
  }
}

#NSG's
resource "azurerm_network_security_group" "hubvnetNSG" {
  location            = azurerm_resource_group.RG.location
  name                = "AZ-hub-vnet-default-nsg"
  resource_group_name = azurerm_resource_group.RG.name
  timeouts {
    create = "2h"
    read = "2h"
    update = "2h"
    delete = "2h"
  }
  
}
resource "azurerm_network_security_rule" "hubvnetnsgrule1" {
  access                      = "Allow"
  destination_address_prefix  = "*"
  destination_port_range      = "3389"
  direction                   = "Inbound"
  name                        = "AllowCidrBlockRDPInbound"
  network_security_group_name = "AZ-hub-vnet-default-nsg"
  priority                    = 2711
  protocol                    = "Tcp"
  resource_group_name         = azurerm_network_security_group.hubvnetNSG.resource_group_name
  source_address_prefix       = var.C-home_public_ip
  source_port_range           = "*"
  timeouts {
    create = "2h"
    read = "2h"
    update = "2h"
    delete = "2h"
  }
  
}


resource "azurerm_network_security_group" "spokevnetNSG" {
  location            = azurerm_resource_group.RG.location
  name                = "AZ-spoke-vnet-default-nsg"
  resource_group_name = azurerm_resource_group.RG.name
  timeouts {
    create = "2h"
    read = "2h"
    update = "2h"
    delete = "2h"
  }
  
}
resource "azurerm_network_security_rule" "spokevnetnsgrule1" {
  access                      = "Allow"
  destination_address_prefix  = "*"
  destination_port_range      = "3389"
  direction                   = "Inbound"
  name                        = "AllowCidrBlockRDPInbound"
  network_security_group_name = "AZ-spoke-vnet-default-nsg"
  priority                    = 2711
  protocol                    = "Tcp"
  resource_group_name         = azurerm_network_security_group.spokevnetNSG.resource_group_name
  source_address_prefix       = var.C-home_public_ip
  source_port_range           = "*"
  timeouts {
    create = "2h"
    read = "2h"
    update = "2h"
    delete = "2h"
  }
  
}





#Public IP's
resource "azurerm_public_ip" "azurevpngw-pip" {
  name                = "azurevpngw-pip"
  location            = azurerm_resource_group.RG.location
  resource_group_name = azurerm_resource_group.RG.name
  allocation_method = "Static"
  sku = "Standard"
  timeouts {
    create = "2h"
    read = "2h"
    update = "2h"
    delete = "2h"
  }
  
}

resource "azurerm_public_ip" "azfw-pip" {
  name                = "azfw-pip"
  location            = azurerm_resource_group.RG.location
  resource_group_name = azurerm_resource_group.RG.name
  allocation_method = "Static"
  sku = "Standard"
  timeouts {
    create = "2h"
    read = "2h"
    update = "2h"
    delete = "2h"
  }
  
}
resource "azurerm_public_ip" "hubvm-pip" {
  name                = "hubvm-pip"
  location            = azurerm_resource_group.RG.location
  resource_group_name = azurerm_resource_group.RG.name
  allocation_method = "Static"
  timeouts {
    create = "2h"
    read = "2h"
    update = "2h"
    delete = "2h"
  }
  
}
resource "azurerm_public_ip" "spokevm-pip" {
  name                = "spokevm-pip"
  location            = azurerm_resource_group.RG.location
  resource_group_name = azurerm_resource_group.RG.name
  allocation_method = "Static"
  timeouts {
    create = "2h"
    read = "2h"
    update = "2h"
    delete = "2h"
  }
  
}



#Azfirewall and policy
resource "azurerm_firewall_policy" "azfwpolicy" {
  name                = "azfw-policy"
  resource_group_name = azurerm_resource_group.RG.name
  location            = azurerm_resource_group.RG.location
  sku = "Premium"
  
  timeouts {
    create = "2h"
    read = "2h"
    update = "2h"
    delete = "2h"
  }
}
resource "azurerm_firewall_policy_rule_collection_group" "azfwpolicyrcg" {
  name               = "azfwpolicy-rcg"
  firewall_policy_id = azurerm_firewall_policy.azfwpolicy.id
  priority           = 500
  network_rule_collection {
    name     = "network_rule_collection1"
    priority = 400
    action   = "Allow"
    rule {
      name                  = "network_rule_collection1_rule1"
      protocols             = ["Any"]
      source_addresses      = ["*"]
      destination_addresses = ["*"]
      destination_ports     = ["*"]
    }
  }
  timeouts {
    create = "2h"
    read = "2h"
    update = "2h"
    delete = "2h"
    }
  
}
resource "azurerm_firewall" "azfw" {
  name                = "AzureFirewall"
  location            = azurerm_resource_group.RG.location
  resource_group_name = azurerm_resource_group.RG.name
  sku_name            = "AZFW_VNet"
  sku_tier            = "Premium"
  firewall_policy_id = azurerm_firewall_policy.azfwpolicy.id

  ip_configuration {
    name                 = "configuration"
    subnet_id            = azurerm_virtual_network.hub-vnet.subnet.*.id[2]
    public_ip_address_id = azurerm_public_ip.azfw-pip.id
  }
  timeouts {
    create = "2h"
    read = "2h"
    update = "2h"
    delete = "2h"
  }
  
}
#firewall logging
resource "azurerm_monitor_diagnostic_setting" "fwlogs"{
  name = "fwlogs-${random_pet.name.id}"
  target_resource_id = azurerm_firewall.azfw.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.LAW.id
  log_analytics_destination_type = "Dedicated"

  enabled_log {
    category = "AZFWNetworkRule"
  }
  enabled_log {
    category = "AZFWApplicationRule"
  }
  enabled_log {
    category = "AZFWNatRule"
  }
  enabled_log {
    category = "AZFWThreatIntel"
  }
  enabled_log {
    category = "AZFWIdpsSignature"
  }
  enabled_log {
    category = "AZFWDnsQuery"
  }
  enabled_log {
    category = "AZFWFqdnResolveFailure"
  }
  enabled_log {
    category = "AZFWFatFlow"
  }
  enabled_log {
    category = "AZFWFlowTrace"
  }
}


#vNIC's
resource "azurerm_network_interface" "hubvm-nic" {
  location            = azurerm_resource_group.RG.location
  name                = "hubvm-nic"
  resource_group_name = azurerm_resource_group.RG.name
  ip_configuration {
    name                          = "ipconfig1"
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.hubvm-pip.id
    subnet_id                     = azurerm_virtual_network.hub-vnet.subnet.*.id[0]
  }
  timeouts {
    create = "2h"
    read = "2h"
    update = "2h"
    delete = "2h"
  }
  
}
resource "azurerm_network_interface" "spokevm-nic" {
  location            = azurerm_resource_group.RG.location
  name                = "spokevm-nic"
  resource_group_name = azurerm_resource_group.RG.name
  ip_configuration {
    name                          = "ipconfig1"
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.spokevm-pip.id
    subnet_id                     = azurerm_virtual_network.spoke-vnet.subnet.*.id[0]
  }
  timeouts {
    create = "2h"
    read = "2h"
    update = "2h"
    delete = "2h"
  }
  
}


#VM's
resource "azurerm_windows_virtual_machine" "hubvm" {
  admin_password        = var.E-password
  admin_username        = var.D-username
  location              = azurerm_resource_group.RG.location
  name                  = "hubvm"
  network_interface_ids = [azurerm_network_interface.hubvm-nic.id]
  resource_group_name   = azurerm_resource_group.RG.name
  size                  = "Standard_B2ms"
  identity {
    type = "SystemAssigned"
  }
  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }
  source_image_reference {
    offer     = "WindowsServer"
    publisher = "MicrosoftWindowsServer"
    sku       = "2022-datacenter-azure-edition"
    version   = "latest"
  }
  timeouts {
    create = "2h"
    read = "2h"
    update = "2h"
    delete = "2h"
  }
  
}



resource "azurerm_windows_virtual_machine" "spokevm" {
  admin_password        = var.E-password
  admin_username        = var.D-username
  location              = azurerm_resource_group.RG.location
  name                  = "spokevm"
  network_interface_ids = [azurerm_network_interface.spokevm-nic.id]
  resource_group_name   = azurerm_resource_group.RG.name
  size                  = "Standard_B2ms"
  identity {
    type = "SystemAssigned"
  }
  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }
  source_image_reference {
    offer     = "WindowsServer"
    publisher = "MicrosoftWindowsServer"
    sku       = "2022-datacenter-azure-edition"
    version   = "latest"
  }
  timeouts {
    create = "2h"
    read = "2h"
    update = "2h"
    delete = "2h"
  }
  
}

