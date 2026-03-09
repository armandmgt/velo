#include <ruby.h>
#include "fit.h"

void Init_ruby_fit() {
  VALUE cRubyFit;

  cRubyFit = rb_const_get(rb_cObject, rb_intern("RubyFit"));
}
