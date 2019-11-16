resource "azurerm_resource_group" "rg" {
  name     = var.resource_group_name
  location = var.resource_group_location
}

resource "azurerm_iothub" "iothub" {
  name                = "eventiothub"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  #namespace = "TFM"

  sku {
    name     = "F1"
    tier     = "Standard"
    capacity = "1"
  }

  endpoint {
    type                       = "AzureIotHub.StorageContainer"
    connection_string          = azurerm_storage_account.sa.primary_blob_connection_string
    name                       = "export"
    batch_frequency_in_seconds = 60
    max_chunk_size_in_bytes    = 10485760
    container_name             = azurerm_storage_container.ev.name
    encoding                   = "Avro"
    file_name_format           = "{iothub}/{partition}_{YYYY}_{MM}_{DD}_{HH}_{mm}"
  }
  /*shared_access_policy{
    key_name = "hola"
    primary_key = ")H@MbQeThWmZq4t7w!z%C*F-JaNdRfUjXn2r5u8x/A?D(G+KbPeShVkYp3s6v9y$"
    secondary_key = "8x/A?D(G+KaPdSgVkYp3s6v9y$B&E)H@McQeThWmZq4t7w!z%C*F-JaNdRgUjXn2"
    permissions = "iothubowner"

  }*/
}

resource "azurerm_storage_account" "sa" {
  name                     = "prodsa"
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  #primary_access_key = azurerm_storage_account.primary_key
}

resource "azurerm_storage_container" "ev" {
  name                  = "eventos"
  storage_account_name  = azurerm_storage_account.sa.name
  container_access_type = "private"
}

resource "azurerm_storage_container" "prod" {
  name                  = "prod"
  storage_account_name  = azurerm_storage_account.sa.name
  container_access_type = "private"
}

resource "azurerm_storage_container" "dev" {
  name                  = "dev"
  storage_account_name  = azurerm_storage_account.sa.name
  container_access_type = "private"
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
    SELECT *
    INTO [${azurerm_storage_container.prod.name}]
    FROM [${azurerm_iothub.iothub.name}]
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
  path_pattern              = "some-pattern"
  date_format               = "yyyy-MM-dd"
  time_format               = "HH"

  serialization {
    type            = "Csv"
    encoding        = "UTF8"
    field_delimiter = ","
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
    SELECT *
    INTO [${azurerm_storage_container.dev.name}]
    FROM [${azurerm_iothub.iothub.name}]
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
  path_pattern              = "some-pattern"
  date_format               = "yyyy-MM-dd"
  time_format               = "HH"

  serialization {
    type            = "Csv"
    encoding        = "UTF8"
    field_delimiter = ","
  }
}