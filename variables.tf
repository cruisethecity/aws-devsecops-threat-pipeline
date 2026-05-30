variable "db_password" {
  type        = string
  description = "The password for the RDS database admin user"
  sensitive   = true
}