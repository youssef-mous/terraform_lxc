# terraform/test.tf
terraform {
  required_providers {
    lxd = {
      source = "terraform-lxd/lxd"
      version = "2.4.0"
    }
  }
}

provider "lxd" {}

resource "lxd_instance" "spark_master" {
  name      = "spark-master"
  image     = "images:debian/11"
  ephemeral = false
  profiles  = ["default"]

 provisioner "local-exec" {
  command = <<-EOT
    lxc exec ${self.name} -- apt-get update
    lxc exec ${self.name} -- apt-get install -y openssh-server python3
    lxc exec ${self.name} -- sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config
    lxc exec ${self.name} -- sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config
    lxc exec ${self.name} -- useradd -m -s /bin/bash debian
    lxc exec ${self.name} -- bash -c 'echo "debian:debian" | chpasswd'
    lxc exec ${self.name} -- usermod -aG sudo debian
    lxc exec ${self.name} -- systemctl restart ssh
  EOT
}

}

resource "lxd_instance" "spark_worker" {
  count     = var.worker_count
  name      = "spark-worker-${count.index + 1}"
  image     = "images:debian/11"
  ephemeral = false
  profiles  = ["default"]

  provisioner "local-exec" {
  command = <<-EOT
    lxc exec ${self.name} -- apt-get update
    lxc exec ${self.name} -- apt-get install -y openssh-server python3
    lxc exec ${self.name} -- sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config
    lxc exec ${self.name} -- sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config
    lxc exec ${self.name} -- useradd -m -s /bin/bash debian
    lxc exec ${self.name} -- bash -c 'echo "debian:debian" | chpasswd'
    lxc exec ${self.name} -- usermod -aG sudo debian
    lxc exec ${self.name} -- systemctl restart ssh
  EOT
}

}

data "external" "master_ip" {
  depends_on = [lxd_instance.spark_master]
  program = ["sh", "-c", "echo '{\"ip\": \"'$(lxc list spark-master -c 4 --format csv | cut -d' ' -f1)'\"}'"]
}

data "external" "worker_ips" {
  count = var.worker_count
  depends_on = [lxd_instance.spark_worker]
  program = ["sh", "-c", "echo '{\"ip\": \"'$(lxc list spark-worker-${count.index + 1} -c 4 --format csv | cut -d' ' -f1)'\"}'"]
}

resource "local_file" "ansible_inventory" {
  depends_on = [data.external.master_ip, data.external.worker_ips]
  content = templatefile("${path.module}/templates/inventory.tpl",
    {
      master_ip   = data.external.master_ip.result.ip
      worker_ips  = [for ip in data.external.worker_ips : ip.result.ip]
    }
  )
  filename = "${path.module}/../ansible/inventory.yml"
}

output "master_ip" {
  value = data.external.master_ip.result.ip
}

output "worker_ips" {
  value = [for ip in data.external.worker_ips : ip.result.ip]
}
