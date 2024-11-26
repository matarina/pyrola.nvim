# server_init.R

# Load necessary libraries
library(httpuv)
library(jsonlite)

# Helper function to retrieve global environment variables
get_global_env <- function() {
  obj_names <- ls(globalenv())
  lapply(obj_names, function(obj_name) {
    obj <- get(obj_name, envir = globalenv())
    list(
      name = obj_name,
      type = typeof(obj),
      class = if (is.null(class(obj))) "N/A" else paste(class(obj), collapse = ", "),
      length = length(obj),
      structure = capture.output(str(obj, vec.len = 2))
    )
  })
}

# Define request handlers
request_handlers <- list(
  
  # Handler to query all global variables
  query_global = function(request) {
    list(status = "success", global_env = get_global_env())
  },
  
  # Handler to view table data
  table_view = function(request) {
    obj_name <- request$obj
    if (exists(obj_name, envir = globalenv())) {
      obj <- get(obj_name, envir = globalenv())
      
      obj_class <- class(obj)
      if (any(obj_class %in% c("data.frame", "matrix", "data.table"))) {
        tmp_dir <- tempdir()
        timestamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
        csv_filename <- file.path(tmp_dir, paste0(obj_name, "_", timestamp, ".csv"))
        
        # Convert to data.frame if necessary
        if (!is.data.frame(obj)) {
          obj <- as.data.frame(obj)
        }
        
        write.csv(obj, file = csv_filename, row.names = TRUE, quote = FALSE)
        file_abs_path <- normalizePath(csv_filename)
        
        list(
          status = "success",
          type = "csv_path",
          data = file_abs_path
        )
      } else {
        list(status = "error", message = paste("Object", obj_name, "is not a data frame, matrix, or data table"))
      }
    } else {
      list(status = "error", message = paste("Object", obj_name, "does not exist!"))
    }
  },
  
  # Handler to inspect a specific object
  inspect = function(request) {
    obj_name <- request$obj
    if (exists(obj_name, envir = globalenv())) {
      obj <- get(obj_name, envir = globalenv())
      obj_class <- class(obj)
      
      info_str <- paste(
        "Type:", typeof(obj),
        "\nClass:", if (is.null(obj_class)) "N/A" else paste(obj_class, collapse = ", "),
        "\nLength:", length(obj),
        "\nStructure:\n", paste(capture.output(str(obj, vec.len = 2)), collapse = "\n"),
        sep = " "
      )
      list(
        status = "success",
        type = "info",
        data = info_str
      )
    } else {
      list(status = "error", message = paste("Object", obj_name, "does not exist!"))
    }
  }
)

# Function to initialize and start the server
init_server <- function(host = "127.0.0.1", port = 8000, handlers = request_handlers) {
  tryCatch({
    server <- httpuv::startServer(host, port, list(
      call = function(req) {
        # Read and parse the request body
        body <- rawToChar(req$rook.input$read())
        request <- fromJSON(body, simplifyVector = FALSE)
        
        # Identify and execute the appropriate handler
        handler <- handlers[[request$type]]
        response <- if (is.function(handler)) {
          handler(request)
        } else {
          list(status = "error", message = "Unknown request type")
        }
        
        # Return the JSON response
        list(
          status = 200L,
          headers = list("Content-Type" = "application/json"),
          body = toJSON(response, auto_unbox = TRUE, pretty = TRUE, force = TRUE)
        )
      }
    ))
    cat("R Server started on", host, ":", port, "\n")
    list(server = server, port = port)
  }, error = function(e) {
    cat("Failed to start R server:", e$message, "\n")
    NULL
  })
}

# Retrieve the port from environment variable or default to 8000
port <- as.integer(Sys.getenv("PORT", "8000"))

# Start the server
server <- init_server(port = port)


