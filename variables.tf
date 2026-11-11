variable "cidr_block" {
  type        = string
  description = "cidr_block for shopzany VPC"
  default     = "10.0.0.0/16"

}
variable "db_password" {
  type      = string
  sensitive = true
}