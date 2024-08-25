library(httpuv)
library(jsonlite)

# Helper function to get information about the global environment
get_global_env <- function() {
  lapply(ls(globalenv()), function(obj_name) {
    obj_value <- get(obj_name, envir = globalenv())
    list(
      name = obj_name,
      type = typeof(obj_value),
      class = class(obj_value),
      length = length(obj_value),
      structure = capture.output(str(obj_value))
    )
  })
}

# Request handlers
request_handlers <- list(
  greet = function(request) {
    list(status = "success", message = "Hello! -- from server")
  },
  query_global = function(request) {
    list(status = "success", global_env = get_global_env())
  },
  inspect = function(request) {
    obj_name <- request$obj
    if (exists(obj_name, envir = .GlobalEnv)) {
      obj <- get(obj_name, envir = .GlobalEnv)
      list(
        status = "success",
        object = list(
          type = typeof(obj),
          class = class(obj),
          length = length(obj),
          content = capture.output(str(obj))
        )
      )
    } else {
      list(status = "error", message = paste("Object", obj_name, "does not exist!"))
    }
  },
  table_view = function(request) {
    table_name <- request$table
    if (exists(table_name, envir = .GlobalEnv)) {
      table <- get(table_name, envir = .GlobalEnv)
      tmp_file <- tempfile(fileext = ".csv")
      write.csv(table, file = tmp_file, row.names = FALSE)
      list(status = "success", filepath = tmp_file)
    } else {
      list(status = "error", message = paste("Table", table_name, "does not exist!"))
    }
  }
)

# Initialize and start the server
init_server <- function(host = "127.0.0.1", port = port , handlers = request_handlers) {
  tryCatch({
    server <- httpuv::startServer(host, port, list(
      call = function(req) {
        content <- req$rook.input$read_lines()
        request <- fromJSON(content, simplifyVector = FALSE)
        handler <- handlers[[request$type]]
        response <- if (is.function(handler)) {
          do.call(handler, list(request))
        } else {
          list(status = "error", message = "Unknown request type")
        }
        list(
          status = 200,
          headers = list("Content-Type" = "application/json"),
          body = toJSON(response, auto_unbox = TRUE, pretty = TRUE, force = TRUE)
        )
      }
    ))
    cat("Server started on", host, ":", port, "\n")
    list(server = server, port = port)
  }, error = function(e) {
    cat("Failed to start server:", e$message, "\n")
    NULL
  })
}
port <- Sys.getenv("PORT")
port = as.integer(port)
server <- init_server(port = port)
