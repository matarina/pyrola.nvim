def get_python_inspector(input_var):
    python_inspector = """
import sys
import inspect
import types
from collections import Counter, defaultdict

try:
    import pandas as pd
except Exception:
    pd = None

try:
    import numpy as np
except Exception:
    np = None

try:
    import torch
except Exception:
    torch = None

MAX_PREVIEW_ROWS = 20
MAX_PREVIEW_COLS = 10
MAX_SERIES_PREVIEW = 20
MAX_COUNT_ITEMS = 1000

if 'python_Var_inspector' not in globals():
    class UniversalInspector:
        def __init__(self):
            self.output_lines = []

        def _format_line(self, attr_name: str, value) -> str:
            return f"{attr_name:<15}║ {value}"

        def _add_line(self, line: str):
            self.output_lines.append(line)

        def _add_section(self, content: list):
            for line in content:
                self._add_line(str(line))

        def _section_title(self, title: str):
            if self.output_lines:
                self._add_line("")
            self._add_line(title)
            self._add_line("-" * 50)

        def _inspect_basic_type(self, obj):
            self._section_title("Summary")
            basic_info = [
                self._format_line("Type", type(obj).__name__),
                self._format_line("Memory", f"{sys.getsizeof(obj)} bytes")
            ]

            if isinstance(obj, (str, bytes, list, tuple, set, dict)):
                basic_info.append(self._format_line("Length", len(obj)))

            if isinstance(obj, (str, bytes, list, tuple, set)):
                try:
                    if len(obj) <= MAX_COUNT_ITEMS:
                        basic_info.append(self._format_line("Count", dict(Counter(obj))))
                except Exception:
                    pass

            self._add_section(basic_info)
            self._section_title("Content")
            self._add_section([repr(obj)])

        def _inspect_pandas_series(self, obj):
            self._section_title("Summary")
            series_info = [
                self._format_line("Type", "Pandas Series"),
                self._format_line("Length", len(obj)),
                self._format_line("Dtype", obj.dtype),
                self._format_line("Name", obj.name),
                self._format_line("Memory", f"{obj.memory_usage(deep=True)} bytes"),
                self._format_line("Null Count", obj.isnull().sum()),
                self._format_line("Unique", obj.is_unique),
            ]
            self._add_section(series_info)
            self._section_title("Preview")
            preview = obj if len(obj) <= MAX_SERIES_PREVIEW else obj.head(MAX_SERIES_PREVIEW)
            preview_info = [self._format_line("Head", preview.to_dict())]
            if len(obj) > MAX_SERIES_PREVIEW:
                preview_info.append(
                    self._format_line("Head Size", f"{MAX_SERIES_PREVIEW} of {len(obj)}")
                )
            self._add_section(preview_info)

        def _inspect_pandas_index(self, obj):
            self._section_title("Summary")
            index_info = [
                self._format_line("Type", type(obj).__name__),
                self._format_line("Length", len(obj)),
                self._format_line("Dtype", obj.dtype),
                self._format_line("Name", obj.name),
                self._format_line("Memory", f"{obj.memory_usage()} bytes"),
                self._format_line("Is Unique", obj.is_unique),
            ]
            self._add_section(index_info)
            self._section_title("Preview")
            preview = obj if len(obj) <= MAX_SERIES_PREVIEW else obj[:MAX_SERIES_PREVIEW]
            preview_info = [self._format_line("Values", list(preview))]
            if len(obj) > MAX_SERIES_PREVIEW:
                preview_info.append(
                    self._format_line("Preview Size", f"{MAX_SERIES_PREVIEW} of {len(obj)}")
                )
            self._add_section(preview_info)


        def _inspect_pandas_dataframe(self, obj):
            # Get basic DataFrame info
            df = obj
            truncated = False

            rows, cols = df.shape
            if rows > MAX_PREVIEW_ROWS:
                df = df.head(MAX_PREVIEW_ROWS)
                truncated = True
            if cols > MAX_PREVIEW_COLS:
                df = df.iloc[:, :MAX_PREVIEW_COLS]
                truncated = True

            self._section_title("Summary")
            df_info = [
                self._format_line("Type", "Pandas DataFrame"),
                self._format_line("Shape", f"{rows} rows × {cols} columns"),
                self._format_line("Memory", f"{obj.memory_usage(deep=True).sum()} bytes"),
                self._format_line("Columns", list(obj.columns)),
                self._format_line("dtypes", obj.dtypes.to_dict()),
            ]
            if truncated:
                df_info.append(
                    self._format_line(
                        "Preview",
                        f"{df.shape[0]} rows × {df.shape[1]} columns"
                    )
                )
            self._add_section(df_info)
            self._section_title("Preview")

            # Format the DataFrame as a plain text table
            pd_types = pd.api.types

            def format_value(value):
                if pd_types.is_scalar(value):
                    try:
                        if pd.isna(value):
                            return "NaN"
                    except Exception:
                        pass
                return str(value)

            def is_number(value):
                try:
                    return pd_types.is_number(value) and not isinstance(value, bool)
                except Exception:
                    return isinstance(value, (int, float)) and not isinstance(value, bool)

            # Get string representations of all values
            if hasattr(df, "map"):
                str_df = df.map(format_value)
            else:
                str_df = df.applymap(format_value)

            # Get maximum width for each column (including header)
            col_sep = "  "
            col_widths = {}
            for col in df.columns:
                col_widths[col] = max(
                    len(str(col)),
                    int(str_df[col].str.len().max() or 0)
                )

            index_name = df.index.name if df.index.name is not None else "index"
            index_values = [str(idx) for idx in df.index]
            index_width = max(len(str(index_name)), max((len(v) for v in index_values), default=0))

            # Create header
            header = (
                f"{str(index_name):>{index_width}}"
                + col_sep
                + col_sep.join(f"{str(col):>{col_widths[col]}}" for col in df.columns)
            )
            separator = (
                f"{'-' * index_width}"
                + col_sep
                + col_sep.join("-" * width for width in col_widths.values())
            )

            # Create rows
            rows = []
            for row_idx, (idx, row) in enumerate(zip(index_values, df.itertuples(index=False, name=None))):
                row_str = []
                for col_idx, value in enumerate(row):
                    col = df.columns[col_idx]
                    cell = str_df.iat[row_idx, col_idx]
                    if is_number(value):
                        row_str.append(cell.rjust(col_widths[col]))
                    else:
                        row_str.append(cell.ljust(col_widths[col]))
                rows.append(f"{idx:>{index_width}}" + col_sep + col_sep.join(row_str))

            # Combine all parts
            table = [
                header,
                separator,
                *rows
            ]

            self._add_section(table)

        def _inspect_class_or_instance(self, obj):
            is_class = inspect.isclass(obj)
            cls = obj if is_class else obj.__class__

            # Basic class info
            self._section_title("Summary")
            basic_info = [
                self._format_line("Type", "Class" if is_class else "Instance"),
                self._format_line("Name", cls.__name__),
                self._format_line("Module", cls.__module__),
                self._format_line("Base classes", [base.__name__ for base in cls.__bases__])
            ]
            self._add_section(basic_info)

            # Categorize attributes
            attrs = defaultdict(list)
            for name, value in inspect.getmembers(obj):
                if name.startswith('__'):
                    continue

                if inspect.ismethod(value) or inspect.isfunction(value):
                    attrs['Methods'].append((name, value))
                elif isinstance(value, property):
                    attrs['Properties'].append((name, value))
                elif isinstance(value, (staticmethod, classmethod)):
                    attrs['Class/Static Methods'].append((name, value))
                else:
                    attrs['Attributes'].append((name, value))

            # Display attributes by category
            for category, items in attrs.items():
                if items:
                    self._section_title(category)
                    category_info = []
                    for name, value in sorted(items, key=lambda x: x[0]):
                        try:
                            if inspect.ismethod(value) or inspect.isfunction(value):
                                try:
                                    sig = inspect.signature(value)
                                except Exception:
                                    sig = "(...)"
                                doc = value.__doc__ and value.__doc__.strip()
                                info = f"{name}{sig}"
                                if doc:
                                    info += f"\\n    Doc: {doc}"
                            else:
                                info = f"{name}: {type(value).__name__} = {repr(value)}"
                        except Exception as e:
                            info = f"{name}: <Error: {str(e)}>"
                        category_info.append(info)
                    self._add_section(category_info)

        def _inspect_function(self, obj):
            try:
                signature = str(inspect.signature(obj))
            except Exception:
                signature = "<unavailable>"
            self._section_title("Summary")
            func_info = [
                self._format_line("Type", "Function"),
                self._format_line("Name", obj.__name__),
                self._format_line("Module", obj.__module__),
                self._format_line("Signature", signature),
                self._format_line("Docstring", obj.__doc__ and obj.__doc__.strip())
            ]
            self._add_section(func_info)

            # Get source code if available
            try:
                source = inspect.getsource(obj)
                self._section_title("Source")
                self._add_section([source])
            except Exception:
                pass

        def _inspect_numpy_array(self, obj):
            self._section_title("Summary")
            array_info = [
                self._format_line("Type", "NumPy Array"),
                self._format_line("Shape", obj.shape),
                self._format_line("Dtype", obj.dtype),
                self._format_line("Size", obj.size),
                self._format_line("NDim", obj.ndim)
            ]
            self._add_section(array_info)
            self._section_title("Content")
            self._add_section([str(obj)])

        def _inspect_torch_tensor(self, obj):
            self._section_title("Summary")
            tensor_info = [
                self._format_line("Type", "PyTorch Tensor"),
                self._format_line("Shape", obj.shape),
                self._format_line("Dtype", obj.dtype),
                self._format_line("Device", obj.device),
                self._format_line("Requires Grad", obj.requires_grad)
            ]
            self._add_section(tensor_info)
            self._section_title("Content")
            self._add_section([str(obj)])

        def inspect(self, obj) -> str:
            self.output_lines = []

            # Determine the type and call appropriate inspector
            is_class = inspect.isclass(obj)
            obj_module = obj.__module__ if is_class else obj.__class__.__module__
            if obj_module == '__main__':
                self._inspect_class_or_instance(obj)
            elif inspect.isfunction(obj) or inspect.ismethod(obj):
                self._inspect_function(obj)
            elif pd is not None and isinstance(obj, pd.Series):
                self._inspect_pandas_series(obj)
            elif pd is not None and isinstance(obj, pd.Index):
                self._inspect_pandas_index(obj)
            elif np is not None and isinstance(obj, np.ndarray):
                self._inspect_numpy_array(obj)
            elif torch is not None and isinstance(obj, torch.Tensor):
                self._inspect_torch_tensor(obj)
            elif pd is not None and isinstance(obj, pd.DataFrame):
                self._inspect_pandas_dataframe(obj)
            else:
                self._inspect_basic_type(obj)

            return "\\n".join(self.output_lines)
    python_Var_inspector = UniversalInspector()

var_output = python_Var_inspector.inspect(<<<VAR>>>)
print(var_output)
"""
    return python_inspector.replace("<<<VAR>>>", str(input_var))


def get_r_inspector(input_var):
    r_inspector = """
format_line <- function(attr_name, value) {
  sprintf("%-15s║ %s", attr_name, as.character(value))
}

format_content <- function(attr_name, value) {
  paste0(paste0(rep("═", 50), collapse = ""), "\\n", value)
}

inspect_vector <- function(obj) {
  # Collect basic information
  info <- c(
    format_line("Type", typeof(obj)),
    format_line("Class", class(obj)),
    format_line("Length", length(obj)),
    format_line("Mode", mode(obj))
  )
  
  # Add attributes if any exist
  if (length(attributes(obj)) > 0) {
    info <- c(info, 
             format_line("Attributes", paste(names(attributes(obj)), collapse = ", ")))
  }
  
  # Add summary for numeric vectors
  if (is.numeric(obj)) {
    stats <- summary(obj)
    info <- c(info,
             format_line("Summary", paste(names(stats), stats, sep = ": ", collapse = ", ")))
  }
  
  # Add levels for factors
  if (is.factor(obj)) {
    info <- c(info,
             format_line("Levels", paste(levels(obj), collapse = ", ")))
  }
  
  # Add content preview
  preview <- if(length(obj) > 10) 
    paste0(paste(head(obj, 10), collapse = " "), "...") 
  else 
    paste(obj, collapse = " ")
  
  info <- c(info, format_content("Content", preview))
  
  paste(info, collapse = "\\n")
}

inspect_matrix <- function(obj) {
  info <- c(
    format_line("Type", "Matrix"),
    format_line("Dimensions", paste(dim(obj), collapse = " x ")),
    format_line("Storage Mode", storage.mode(obj))
  )
  
  if (is.numeric(obj)) {
    info <- c(info,
             format_line("Summary", paste(summary(as.vector(obj)), collapse = ", ")))
  }
  
  preview <- capture.output(print(if(nrow(obj) > 6) obj[1:6,] else obj))
  info <- c(info, format_content("Content", paste(preview, collapse = "\\n")))
  
  paste(info, collapse = "\\n")
}

inspect_dataframe <- function(obj) {
  info <- c(
    format_line("Type", "Data Frame"),
    format_line("Dimensions", paste(dim(obj), collapse = " x ")),
    format_line("Column Names", paste(names(obj), collapse = ", ")),
    format_line("Column Types", paste(sapply(obj, class), collapse = ", "))
  )
  
  # NA counts per column
  na_counts <- sapply(obj, function(x) sum(is.na(x)))
  if(sum(na_counts) > 0) {
    info <- c(info,
             format_line("NA counts", paste(names(na_counts), na_counts, sep = ": ", collapse = ", ")))
  }
  
  # Structure information
  str_output <- capture.output(str(obj))
  info <- c(info, format_line("Structure", paste(str_output[1], collapse = "")))
  
  # Data preview
  preview <- capture.output(print(if(nrow(obj) > 6) head(obj, 6) else obj))
  info <- c(info, "\\nData Content:", preview)
  
  paste(info, collapse = "\\n")
}

inspect_list <- function(obj) {
  info <- c(
    format_line("Type", "List"),
    format_line("Length", length(obj)),
    format_line("Names", paste(names(obj), collapse = ", "))
  )
  
  # Element types
  element_types <- sapply(obj, function(x) class(x)[1])
  info <- c(info,
           format_line("Element Types", paste(names(element_types), element_types, sep = ": ", collapse = ", ")))
  
  # Structure preview
  preview <- capture.output(str(obj, max.level = 2))
  info <- c(info, format_content("Structure", paste(preview, collapse = "\\n")))
  
  paste(info, collapse = "\\n")
}

inspect <- function(obj) {
  if (is.matrix(obj)) {
    return(inspect_matrix(obj))
  } else if (is.data.frame(obj)) {
    return(inspect_dataframe(obj))
  } else if (is.list(obj)) {
    return(inspect_list(obj))
  } else if (is.vector(obj) || is.factor(obj)) {
    return(inspect_vector(obj))
  } else {
    # Fallback for other types
    return(paste(
      format_line("Type", class(obj)[1]),
      format_line("Structure", paste(capture.output(str(obj)), collapse = "\\n")),
      sep = "\\n"
    ))
  }
}
cat(inspect(<<<VAR>>>))
"""
    return r_inspector.replace("<<<VAR>>>", str(input_var))
