#include <ruby.h>
#include <ruby/io.h>
#include <stdio.h>
#include "fit_convert.h"
#include "fit.h"

struct ruby_fit_data {
   VALUE io;
};

static size_t memsize_ruby_fit(const void *ptr) {
  return sizeof(struct ruby_fit_data);
}

static const rb_data_type_t ruby_fit_type = {
  .wrap_struct_name = "ruby_fit",
  .function = {
    .dsize = memsize_ruby_fit,
  },
  .flags = RUBY_TYPED_FREE_IMMEDIATELY,
};

static VALUE
ruby_fit_alloc(VALUE klass) {
  struct ruby_fit_data *ruby_fit_ptr;

  return TypedData_Make_Struct(klass, struct ruby_fit_data, &ruby_fit_type, ruby_fit_ptr);
}

#define GetRubyFit(obj, ruby_fit_ptr) do {\
  TypedData_Get_Struct((obj), struct ruby_fit_data, &ruby_fit_type, (ruby_fit_ptr));\
} while (0)

static VALUE
ruby_fit_init(VALUE self, VALUE io) {
  Check_Type(io, T_FILE);

  struct ruby_fit_data *ruby_fit_ptr;
  GetRubyFit(self, ruby_fit_ptr);

  ruby_fit_ptr->io = io;

  return self;
}

static VALUE ruby_fit_print(VALUE self) {
  struct ruby_fit_data *ruby_fit_ptr;
  GetRubyFit(self, ruby_fit_ptr);

  rb_io_t *fptr;
  GetOpenFile(ruby_fit_ptr->io, fptr);
  FILE *fp = rb_io_stdio_file(fptr);

  FIT_UINT8 buf[8];
  FIT_CONVERT_RETURN convert_return = FIT_CONVERT_CONTINUE;
  FIT_UINT32 buf_size;
  FIT_UINT32 mesg_index = 0;
  FitConvert_Init(FIT_TRUE);

  while (!feof(fp) && (convert_return == FIT_CONVERT_CONTINUE)) {
    for (buf_size = 0; (buf_size < sizeof(buf)) && !feof(fp); buf_size++) {
      buf[buf_size] = (FIT_UINT8)getc(fp);
    }

    do {
      convert_return = FitConvert_Read(buf, buf_size);

      switch (convert_return) {
        case FIT_CONVERT_MESSAGE_AVAILABLE: {
          const FIT_UINT8 *mesg = FitConvert_GetMessageData();
          FIT_UINT16 mesg_num = FitConvert_GetMessageNumber();

          printf("Mesg %d (%d) - ", mesg_index++, mesg_num);

          switch(mesg_num) {
            case FIT_MESG_NUM_FILE_ID: {
              const FIT_FILE_ID_MESG *id = (FIT_FILE_ID_MESG *) mesg;
              printf("File ID: type=%u, number=%u\n", id->type, id->number);
              break;
            }

            case FIT_MESG_NUM_USER_PROFILE: {
              const FIT_USER_PROFILE_MESG *user_profile = (FIT_USER_PROFILE_MESG *) mesg;
              printf("User Profile: weight=%0.1fkg\n", user_profile->weight / 10.0f);
              break;
            }

            case FIT_MESG_NUM_ACTIVITY: {
              const FIT_ACTIVITY_MESG *activity = (FIT_ACTIVITY_MESG *) mesg;
              printf("Activity: timestamp=%u, type=%u, event=%u, event_type=%u, num_sessions=%u\n", activity->timestamp, activity->type, activity->event, activity->event_type, activity->num_sessions);
              {
                FIT_ACTIVITY_MESG old_mesg;
                old_mesg.num_sessions = 1;
                   FitConvert_RestoreFields(&old_mesg);
                printf("Restored num_sessions=1 - Activity: timestamp=%u, type=%u, event=%u, event_type=%u, num_sessions=%u\n", activity->timestamp, activity->type, activity->event, activity->event_type, activity->num_sessions);
              }
              break;
            }

            case FIT_MESG_NUM_SESSION: {
              const FIT_SESSION_MESG *session = (FIT_SESSION_MESG *) mesg;
              printf("Session: timestamp=%u\n", session->timestamp);
              break;
            }

            case FIT_MESG_NUM_LAP: {
              const FIT_LAP_MESG *lap = (FIT_LAP_MESG *) mesg;
              printf("Lap: timestamp=%u\n", lap->timestamp);
              break;
            }

            case FIT_MESG_NUM_RECORD: {
              const FIT_RECORD_MESG *record = (FIT_RECORD_MESG *) mesg;

              printf("Record: timestamp=%u", record->timestamp);

              if (record->distance != FIT_UINT32_INVALID) {
                 printf(", distance = %0.3fm", record->distance / 100.0f);
              }

              if (record->enhanced_speed != FIT_UINT32_INVALID) {
                 printf(", speed enhanced = %0.2fm/s", record->enhanced_speed / 1000.0f);
              }
              else if (record->speed != FIT_UINT16_INVALID) {
                 printf(", speed = %0.2fm/s", record->speed / 1000.0f);
              }

              printf("\n");
              break;
            }

            case FIT_MESG_NUM_EVENT: {
              const FIT_EVENT_MESG *event = (FIT_EVENT_MESG *) mesg;
              printf("Event: timestamp=%u\n", event->timestamp);
              break;
            }

            case FIT_MESG_NUM_DEVICE_INFO: {
              const FIT_DEVICE_INFO_MESG *device_info = (FIT_DEVICE_INFO_MESG *) mesg;
              printf("Device Info: timestamp=%u\n", device_info->timestamp);
              break;
            }

            default:
              printf("Unknown\n");
              break;
          }
          break;
        }

        default:
          break;
      }
    } while (convert_return == FIT_CONVERT_MESSAGE_AVAILABLE);
  }
  return self;
}


void Init_ruby_fit() {
  VALUE cRubyFit;

  cRubyFit = rb_const_get(rb_cObject, rb_intern("RubyFit"));
  rb_define_alloc_func(cRubyFit, ruby_fit_alloc);
  rb_define_method(cRubyFit, "initialize", ruby_fit_init, 1);
  rb_define_method(cRubyFit, "print", ruby_fit_print, 0);
}
