require 'mkmf'

extension_name = 'ruby_fit'

$defs << "-DFIT_USE_STDINT_H"
$defs << "-DFIT_PRODUCT_RELEASE"

dir_config(extension_name)       # The destination
create_makefile(extension_name)  # Create Makefile
