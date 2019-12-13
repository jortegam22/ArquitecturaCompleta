//Resource Group Configuration

resource "azurerm_resource_group" "rg" {
  name     = var.resource_group_name
  location = var.resource_group_location
}

//IoTHub Configuration

resource "azurerm_iothub" "iothub" {
  name                = "eventiothub"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  
  sku {
    name     = "F1"
    tier     = "Standard"
    capacity = "1"
  }

endpoint {
    type                       = "AzureIotHub.EventHub"
    connection_string          = azurerm_eventhub_authorization_rule.datosaur.primary_connection_string
    name                       = "eventhubep"
    batch_frequency_in_seconds = 60
    max_chunk_size_in_bytes    = 10485760
    container_name             = azurerm_storage_container.ev.name 
    encoding                   = "Json"
    file_name_format           = "{iothub}/{partition}_{YYYY}_{MM}_{DD}_{HH}_{mm}"
  }

  route {
    name           = "eventhubep"
    source         = "DeviceMessages"
    condition      = "true"
    endpoint_names = ["eventhubep"]
    enabled        = true
  }
}

/*resource "azurerm_iothub_endpoint_eventhub" "eventhubep" {
  resource_group_name = azurerm_resource_group.rg.name
  iothub_name         = azurerm_iothub.iothub.name
  name                = "eventhubep"

  connection_string = azurerm_eventhub_authorization_rule.datosaur.primary_connection_string
}*/

//EventHub Configuration

resource "azurerm_eventhub_namespace" "datosns" {
  name                = "datoseh"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "Standard"
}

resource "azurerm_eventhub" "datoseh" {
  name                = "datoseh"
  namespace_name      = azurerm_eventhub_namespace.datosns.name
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  partition_count     = 2
  message_retention   = 1
}

resource "azurerm_eventhub_authorization_rule" "datosaur" {
  name                = "datosaur"
  namespace_name      = azurerm_eventhub_namespace.datosns.name
  eventhub_name       = azurerm_eventhub.datoseh.name
  resource_group_name = azurerm_resource_group.rg.name

  listen = true
  send   = true
  manage = true
}

//Storage Account and Containers Configuration

resource "azurerm_storage_account" "sa" {
  name                     = "prodsa"
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_storage_container" "ev" {
  name                  = "datos"
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

//prodASA Configuration

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
    FROM eventhub
  )

    SELECT *
    INTO blobstorage2
    FROM Eventos

    SELECT *
    INTO blobstorage
    FROM Eventos
    WHERE environment = 1 and eventType = 'Error'
  QUERY
}

resource "azurerm_eventhub_consumer_group" "cg" {
  name                = "proddatoscg"
  namespace_name      = azurerm_eventhub_namespace.datosns.name
  eventhub_name       = azurerm_eventhub.datoseh.name
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_stream_analytics_stream_input_eventhub" "asaevent" {
  name                         = "eventhub"
  stream_analytics_job_name    = azurerm_stream_analytics_job.asa.name
  resource_group_name          = azurerm_resource_group.rg.name
  eventhub_consumer_group_name = azurerm_eventhub_consumer_group.cg.name
  eventhub_name                = azurerm_eventhub.datoseh.name
  servicebus_namespace         = azurerm_eventhub_namespace.datosns.name
  shared_access_policy_key     = azurerm_eventhub_namespace.datosns.default_primary_key
  shared_access_policy_name    = "RootManageSharedAccessKey"

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
  path_pattern              = "datos"
  date_format               = "yyyy-MM-dd"
  time_format               = "HH"

  serialization {
    type            = "Json"
    encoding        = "UTF8"
    format          = "LineSeparated"
  }
}

resource "azurerm_stream_analytics_output_blob" "prodbs2" {
  name                      = "blobstorage2"
  stream_analytics_job_name = azurerm_stream_analytics_job.asa.name
  resource_group_name       = azurerm_resource_group.rg.name
  storage_account_name      = azurerm_storage_account.sa.name
  storage_account_key       = azurerm_storage_account.sa.primary_access_key
  storage_container_name    = azurerm_storage_container.ev.name
  path_pattern              = "datos"
  date_format               = "yyyy-MM-dd"
  time_format               = "HH"

  serialization {
    type            = "Json"
    encoding        = "UTF8"
    format          = "LineSeparated"
  }
}

//devASA Configuration

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
    FROM eventhub
  )
    SELECT *
    INTO blobstorage
    FROM Eventos
    WHERE environment = 0 and eventType = 'Error'
  QUERY
}

resource "azurerm_eventhub_consumer_group" "cg2" {
  name                = "devdatoscg"
  namespace_name      = azurerm_eventhub_namespace.datosns.name
  eventhub_name       = azurerm_eventhub.datoseh.name
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_stream_analytics_stream_input_eventhub" "asaevent2" {
  name                         = "eventhub"
  stream_analytics_job_name    = azurerm_stream_analytics_job.asa2.name
  resource_group_name          = azurerm_resource_group.rg.name
  eventhub_consumer_group_name = azurerm_eventhub_consumer_group.cg2.name
  eventhub_name                = azurerm_eventhub.datoseh.name
  servicebus_namespace         = azurerm_eventhub_namespace.datosns.name
  shared_access_policy_key     = azurerm_eventhub_namespace.datosns.default_primary_key
  shared_access_policy_name    = "RootManageSharedAccessKey"

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
  path_pattern              = "datos"
  date_format               = "yyyy-MM-dd"
  time_format               = "HH"

  serialization {
    type            = "Json"
    encoding        = "UTF8"
    format          = "LineSeparated"
  }
}