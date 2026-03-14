require "mkmf"

extension_name = "ruby_fit/ruby_fit"

$defs << "-DFIT_USE_STDINT_H"
$defs << "-DFIT_PRODUCT_RELEASE"

$srcs = %w[
  ruby_fit.c
  fit.c
  fit_convert.c
  fit_crc.c
  fit_product.c
  fit_ram.c
]

$objs = $srcs.map { |src| src.sub(".c", ".#{$OBJEXT}") }

dir_config(extension_name)       # The destination
create_makefile(extension_name)  # Create Makefile
