resource "azurerm_resource_group" "rg" {
  name     = var.resource_group_name
  location = var.resource_group_location
}

resource "azurerm_iothub" "iothub" {
  name                = "eventiothub"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  
  sku {
    name     = "F1"
    tier     = "Standard"
    capacity = "1"
  }

    route {
    name           = "eventos"
    source         = "DeviceMessages"
    condition      = "true"
    endpoint_names = ["eventos"]
    enabled        = true
  }

    route {
    name           = "asa"
    source         = "DeviceMessages"
    condition      = "true"
    endpoint_names = ["events"]
    enabled        = true
  }
}

resource "azurerm_iothub_endpoint_storage_container" "ihe" {
  resource_group_name = azurerm_resource_group.rg.name
  iothub_name         = azurerm_iothub.iothub.name
  name                = "eventos"

  container_name    = azurerm_storage_container.ev.name 
  connection_string = azurerm_storage_account.sa.primary_blob_connection_string

  file_name_format           = "{iothub}/{partition}_{YYYY}_{MM}_{DD}_{HH}_{mm}"
  batch_frequency_in_seconds = 60
  max_chunk_size_in_bytes    = 10485760
  encoding                   = "JSON"
}



resource "azurerm_storage_account" "sa" {
  name                     = "prodsa"
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_storage_container" "ev" {
  name                  = "eventos"
  storage_account_name  = azurerm_storage_account.sa.name
  container_access_type = "container"
}

resource "azurerm_storage_container" "prod" {
  name                  = "prod"
  storage_account_name  = azurerm_storage_account.sa.name
  container_access_type = "container"
}

resource "azurerm_storage_container" "dev" {
  name                  = "dev"
  storage_account_name  = azurerm_storage_account.sa.name
  container_access_type = "container"
}

resource "azurerm_stream_analytics_job" "asa" {
  name                                     = "prodASA"
  resource_group_name                      = azurerm_resource_group.rg.name
  location                                 = azurerm_resource_group.rg.location
  compatibility_level                      = "1.1"
  data_locale                              = "en-GB"
  events_late_arrival_max_delay_in_seconds = 60
  events_out_of_order_max_delay_in_seconds = 50
  events_out_of_order_policy               = "Adjust"
  output_error_policy                      = "Drop"
  streaming_units                          = 3

  transformation_query = <<QUERY
  WITH Eventos AS (
    SELECT *
    FROM iothub
  )
    SELECT *
    INTO blobstorage
    FROM Eventos
    WHERE environment = true and eventType = 'Error'
  QUERY
}

resource "azurerm_stream_analytics_stream_input_iothub" "prodiothub" {
  name                         = "iothub"
  stream_analytics_job_name    = azurerm_stream_analytics_job.asa.name
  resource_group_name          = azurerm_resource_group.rg.name
  endpoint                     = "messages/events"
  eventhub_consumer_group_name = "$Default"
  iothub_namespace             = azurerm_iothub.iothub.name
  shared_access_policy_key     = azurerm_iothub.iothub.shared_access_policy.0.primary_key
  shared_access_policy_name    = "iothubowner"

  serialization {
    type     = "Json"
    encoding = "UTF8"
  }
}

resource "azurerm_stream_analytics_output_blob" "prodbs" {
  name                      = "blobstorage"
  stream_analytics_job_name = azurerm_stream_analytics_job.asa.name
  resource_group_name       = azurerm_resource_group.rg.name
  storage_account_name      = azurerm_storage_account.sa.name
  storage_account_key       = azurerm_storage_account.sa.primary_access_key
  storage_container_name    = azurerm_storage_container.prod.name
  path_pattern              = "events"
  date_format               = "yyyy-MM-dd"
  time_format               = "HH"

  serialization {
    type            = "Json"
    encoding        = "UTF8"
    format          = "LineSeparated"
  }
}

resource "azurerm_stream_analytics_job" "asa2" {
  name                                     = "devASA"
  resource_group_name                      = azurerm_resource_group.rg.name
  location                                 = azurerm_resource_group.rg.location
  compatibility_level                      = "1.1"
  data_locale                              = "en-GB"
  events_late_arrival_max_delay_in_seconds = 60
  events_out_of_order_max_delay_in_seconds = 50
  events_out_of_order_policy               = "Adjust"
  output_error_policy                      = "Drop"
  streaming_units                          = 3

  transformation_query = <<QUERY
  WITH Eventos AS (
    SELECT *
    FROM iothub
  )
    SELECT *
    INTO blobstorage
    FROM Eventos
    WHERE environment = false and eventType = 'Error'
  QUERY
}

resource "azurerm_stream_analytics_stream_input_iothub" "deviothub" {
  name                         = "iothub"
  stream_analytics_job_name    = azurerm_stream_analytics_job.asa2.name
  resource_group_name          = azurerm_resource_group.rg.name
  endpoint                     = "messages/events"
  eventhub_consumer_group_name = "$Default"
  iothub_namespace             = azurerm_iothub.iothub.name
  shared_access_policy_key     = azurerm_iothub.iothub.shared_access_policy.0.primary_key
  shared_access_policy_name    = "iothubowner"

  serialization {
    type     = "Json"
    encoding = "UTF8"
  }
}

resource "azurerm_stream_analytics_output_blob" "devbs" {
  name                      = "blobstorage"
  stream_analytics_job_name = azurerm_stream_analytics_job.asa2.name
  resource_group_name       = azurerm_resource_group.rg.name
  storage_account_name      = azurerm_storage_account.sa.name
  storage_account_key       = azurerm_storage_account.sa.primary_access_key
  storage_container_name    = azurerm_storage_container.dev.name
  path_pattern              = "events"
  date_format               = "yyyy-MM-dd"
  time_format               = "HH"

  serialization {
    type            = "Json"
    encoding        = "UTF8"
    format          = "LineSeparated"
  }
}