
// Copyright (c) 2017, 2021, Oracle and/or its affiliates. All rights reserved.
// Licensed under the Mozilla Public License v2.0

variable "tenancy_ocid" {
  type = string
  default = "ocid1.tenancy.oc1..FILL"
}

variable "user_ocid" {
  type = string
  default = "ocid1.user.oc1..FILL"
}

# openssl rsa -pubout -outform DER -in ~/.oci/rsa.pem | openssl md5 -c
variable "fingerprint" {
  type = string
  default = "FILL"
}

variable "private_key_path" {
  type = string
  default = "/home/FILL/.oci/rsa.pem"
}

variable "ssh_public_key" {
  type = string
  default = "FILL"
}

variable "compartment_ocid" {
  type = string
  default = "ocid1.tenancy.oc1..FILL"
}

variable "region" {
  type = string
  default = "uk-london-1"
}

variable "availability_domain" {
  type = string
  default = "MJsT:UK-LONDON-1-AD-2"
}

provider "oci" {
  region           = var.region
  tenancy_ocid     = var.tenancy_ocid
  user_ocid        = var.user_ocid
  fingerprint      = var.fingerprint
  private_key_path = var.private_key_path
}

variable "images" {
  type = map(string)

  default = {
    # See https://docs.us-phoenix-1.oraclecloud.com/images/
    uk-london-1    = "ocid1.image.oc1.uk-london-1.aaaaaaaaglaxkbuflw642jnmdcvdilcnamnzr4zln45fmflx6l7c33qgpuha"
  }
}

resource "oci_core_virtual_network" "test_vcn" {
  cidr_block     = "10.1.0.0/16"
  compartment_id = var.compartment_ocid
  display_name   = "test_vcn"
}

resource "oci_core_subnet" "test_subnet" {
  cidr_block        = "10.1.20.0/24"
  display_name      = "testSubnet"
  security_list_ids = [oci_core_security_list.test_security_list.id]
  compartment_id    = var.compartment_ocid
  vcn_id            = oci_core_virtual_network.test_vcn.id
  route_table_id    = oci_core_route_table.test_route_table.id
  dhcp_options_id   = oci_core_virtual_network.test_vcn.default_dhcp_options_id
}

resource "oci_core_internet_gateway" "test_internet_gateway" {
  compartment_id = var.compartment_ocid
  display_name   = "testIG"
  vcn_id         = oci_core_virtual_network.test_vcn.id
}

resource "oci_core_route_table" "test_route_table" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_virtual_network.test_vcn.id
  display_name   = "testRouteTable"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.test_internet_gateway.id
  }
}

resource "oci_core_security_list" "test_security_list" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_virtual_network.test_vcn.id
  display_name   = "testSecurityList"

  egress_security_rules {
    protocol    = "6"
    destination = "0.0.0.0/0"
  }

  ingress_security_rules {
    protocol = "6"
    source   = "0.0.0.0/0"

    tcp_options {
      max = "22"
      min = "22"
    }
  }

  ingress_security_rules {
    protocol = "6"
    source   = "0.0.0.0/0"

    tcp_options {
      max = "16443"
      min = "16443"
    }
  }

  ingress_security_rules {
    protocol = "6"
    source   = "0.0.0.0/0"

    tcp_options {
      max = "80"
      min = "80"
    }
  }
}

# oci iam availability-domain list
resource "oci_core_instance" "microcube" {
  availability_domain = var.availability_domain
  compartment_id      = var.compartment_ocid
  display_name        = "microcube"
  shape               = "VM.Standard.A1.Flex"

  shape_config {
    memory_in_gbs = 6
    ocpus = 1
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.test_subnet.id
    display_name     = "primaryvnic"
    assign_public_ip = true
  }

  source_details {
    source_type = "image"
    source_id   = var.images[var.region]
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
  }

  connection {
    host = self.public_ip
    type     = "ssh"
    user     = "ubuntu"
    private_key = file("~/.ssh/id_rsa")
  }

  provisioner "remote-exec" {
    inline = [
      "sudo apt -qq update && sudo apt -qqy install docker.io && sudo snap install microk8s --classic --channel=1.22/stable",
      "sudo microk8s enable dns:169.254.169.254 storage",
      "mkdir -p $HOME/.kube/",
      "sudo microk8s config > $HOME/.kube/config",
      "sudo iptables -I INPUT -s 11.22.33.44/32 -j ACCEPT",
      "sudo sed '/^-A INPUT -j REJECT.*/i -I INPUT -s 11.22.33.44/32 -j ACCEPT' -i /etc/iptables/rules.v4",
      "curl -s ifconfig.co >ip",
      "echo IP.99 = $(cat ip) >ip1",
      "echo server: https://$(cat ip):16443 >ip2",
      "sudo sed -i '27 e cat ip1' /var/snap/microk8s/current/certs/csr.conf.template",
      "sudo microk8s stop && sudo microk8s start",
      "sudo microk8s config | sed  5d > microk8s-kubeconfig && sudo sed -i '5 e cat ip2' microk8s-kubeconfig && rm ip*",
      "curl -fsSL https://goss.rocks/install | sudo sh",
      "curl -s https://raw.githubusercontent.com/kmonticolo/terraform-microk8s-oci/main/goss.yaml -o goss.yaml",
      "sudo goss v",
    ]
  }
}
