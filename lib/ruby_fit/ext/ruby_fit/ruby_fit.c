#include <ruby.h>
#include <stdio.h>
#include "ruby.h"
#include "string.h"
#include "fit_convert.h"
#include "fit.h"

struct ruby_fit {
   FILE *file;
};

static const rb_data_type_t ruby_fit_type = {
   .file = NULL,
  };


static VALUE
ruby_fit_init(VALUE self, VALUE f) {
   struct ruby_fit *ptr;
   char *filename = RSTRING_PTR(f);

   Data_Get_Struct(self, struct ruby_fit, ptr);
  if((ptr->file = fopen(filename, "rb")) == NULL)
  {
    printf("Error opening file %s.\n", filename);
    return FIT_FALSE;
  }

  return self;
}

static VALUE ruby_fit_alloc(VALUE klass) {
   return TypedData_Wrap_Struct(klass, &ruby_fit_type, NULL);
}

static VALUE ruby_fit_print(VALUE self) {
   struct ruby_fit *ptr;

   Data_Get_Struct(self, struct ruby_fit, ptr);

  FILE *file = ptr->file;

   FIT_UINT8 buf[8];
   FIT_CONVERT_RETURN convert_return = FIT_CONVERT_CONTINUE;
   FIT_UINT32 buf_size;
   FIT_UINT32 mesg_index = 0;
#if defined(FIT_CONVERT_MULTI_THREAD)
   FIT_CONVERT_STATE state;
#endif
  VALUE result = rb_hash_new();
  rb_hash_aset(result, rb_str_new2("records"), rb_ary_new());
  while(!feof(file) && (convert_return == FIT_CONVERT_CONTINUE))
   {
      for(buf_size=0;(buf_size < sizeof(buf)) && !feof(file); buf_size++)
      {
         buf[buf_size] = (FIT_UINT8)getc(file);
      }

      do
      {
         #if defined(FIT_CONVERT_MULTI_THREAD)
            convert_return = FitConvert_Read(&state, buf, buf_size);
         #else
            convert_return = FitConvert_Read(buf, buf_size);
         #endif

         switch (convert_return)
         {
            case FIT_CONVERT_MESSAGE_AVAILABLE:
            {
               #if defined(FIT_CONVERT_MULTI_THREAD)
                  const FIT_UINT8 *mesg = FitConvert_GetMessageData(&state);
                  FIT_UINT16 mesg_num = FitConvert_GetMessageNumber(&state);
               #else
                  const FIT_UINT8 *mesg = FitConvert_GetMessageData();
                  FIT_UINT16 mesg_num = FitConvert_GetMessageNumber();
               #endif

               printf("Mesg %d (%d) - ", mesg_index++, mesg_num);

               switch(mesg_num)
               {
                  case FIT_MESG_NUM_FILE_ID:
                  {
                     const FIT_FILE_ID_MESG *id = (FIT_FILE_ID_MESG *) mesg;
                     printf("File ID: type=%u, number=%u\n", id->type, id->number);
                     rb_hash_aset(result, rb_str_new2("type"), INT2NUM(id->type));
                     rb_hash_aset(result, rb_str_new2("number"), INT2NUM(id->number));
                     break;
                  }

                  case FIT_MESG_NUM_USER_PROFILE:
                  {
                     const FIT_USER_PROFILE_MESG *user_profile = (FIT_USER_PROFILE_MESG *) mesg;
                     printf("User Profile: weight=%0.1fkg\n", user_profile->weight / 10.0f);
                     rb_hash_aset(result, rb_str_new2("wake_time"), INT2NUM(user_profile->wake_time));
                     rb_hash_aset(result, rb_str_new2("sleep_time"), INT2NUM(user_profile->sleep_time));
                     rb_hash_aset(result, rb_str_new2("dive_count"), INT2NUM(user_profile->dive_count));
                     rb_hash_aset(result, rb_str_new2("message_index"), INT2NUM(user_profile->message_index));
                     rb_hash_aset(result, rb_str_new2("weight"), INT2NUM(user_profile->weight));
                     rb_hash_aset(result, rb_str_new2("local_id"), INT2NUM(user_profile->local_id));
                     rb_hash_aset(result, rb_str_new2("user_running_step_length"), INT2NUM(user_profile->user_running_step_length));
                     rb_hash_aset(result, rb_str_new2("user_walking_step_length"), INT2NUM(user_profile->user_walking_step_length));
                     rb_hash_aset(result, rb_str_new2("friendly_name"), rb_str_new2(user_profile->friendly_name));
                     rb_hash_aset(result, rb_str_new2("gender"), INT2NUM(user_profile->gender));
                     rb_hash_aset(result, rb_str_new2("age"), INT2NUM(user_profile->age));
                     rb_hash_aset(result, rb_str_new2("height"), INT2NUM(user_profile->height));
                     rb_hash_aset(result, rb_str_new2("language"), INT2NUM(user_profile->language));
                     rb_hash_aset(result, rb_str_new2("elev_setting"), INT2NUM(user_profile->elev_setting));
                     rb_hash_aset(result, rb_str_new2("weight_setting"), INT2NUM(user_profile->weight_setting));
                     rb_hash_aset(result, rb_str_new2("resting_heart_rate"), INT2NUM(user_profile->resting_heart_rate));
                     rb_hash_aset(result, rb_str_new2("default_max_running_heart_rate"), INT2NUM(user_profile->default_max_running_heart_rate));
                     rb_hash_aset(result, rb_str_new2("default_max_biking_heart_rate"), INT2NUM(user_profile->default_max_biking_heart_rate));
                     rb_hash_aset(result, rb_str_new2("default_max_heart_rate"), INT2NUM(user_profile->default_max_heart_rate));
                     rb_hash_aset(result, rb_str_new2("hr_setting"), INT2NUM(user_profile->hr_setting));
                     rb_hash_aset(result, rb_str_new2("speed_setting"), INT2NUM(user_profile->speed_setting));
                     rb_hash_aset(result, rb_str_new2("dist_setting"), INT2NUM(user_profile->dist_setting));
                     rb_hash_aset(result, rb_str_new2("power_setting"), INT2NUM(user_profile->power_setting));
                     rb_hash_aset(result, rb_str_new2("activity_class"), INT2NUM(user_profile->activity_class));
                     rb_hash_aset(result, rb_str_new2("position_setting"), INT2NUM(user_profile->position_setting));
                     rb_hash_aset(result, rb_str_new2("temperature_setting"), INT2NUM(user_profile->temperature_setting));
                     rb_hash_aset(result, rb_str_new2("global_id"), rb_str_new2(user_profile->global_id));
                     rb_hash_aset(result, rb_str_new2("height_setting"), INT2NUM(user_profile->height_setting));
                     rb_hash_aset(result, rb_str_new2("depth_setting"), INT2NUM(user_profile->depth_setting));
                     break;
                  }

                  case FIT_MESG_NUM_ACTIVITY:
                  {
                     const FIT_ACTIVITY_MESG *activity = (FIT_ACTIVITY_MESG *) mesg;
                     printf("Activity: timestamp=%u, type=%u, event=%u, event_type=%u, num_sessions=%u\n", activity->timestamp, activity->type, activity->event, activity->event_type, activity->num_sessions);
                     {
                        FIT_ACTIVITY_MESG old_mesg;
                        old_mesg.num_sessions = 1;
                        #if defined(FIT_CONVERT_MULTI_THREAD)
                           FitConvert_RestoreFields(&state, &old_mesg);
                        #else
                           FitConvert_RestoreFields(&old_mesg);
                        #endif
                        printf("Restored num_sessions=1 - Activity: timestamp=%u, type=%u, event=%u, event_type=%u, num_sessions=%u\n", activity->timestamp, activity->type, activity->event, activity->event_type, activity->num_sessions);
                     }
                     break;
                  }

                  case FIT_MESG_NUM_SESSION:
                  {
                     const FIT_SESSION_MESG *session = (FIT_SESSION_MESG *) mesg;
                     printf("Session: timestamp=%u\n", session->timestamp);
                     break;
                  }

                  case FIT_MESG_NUM_LAP:
                  {
                     const FIT_LAP_MESG *lap = (FIT_LAP_MESG *) mesg;
                     printf("Lap: timestamp=%u\n", lap->timestamp);
//                     avg_speed
//                     max_speed
//                     avg_power
//                     max_power
//                     sport
//                     total_distance
                     break;
                  }

                  case FIT_MESG_NUM_RECORD:
                  {
                     const FIT_RECORD_MESG *record = (FIT_RECORD_MESG *) mesg;

                     printf("Record: timestamp=%u", record->timestamp);



                     VALUE array = rb_ary_new();
                     VALUE records = rb_hash_aref(result, rb_str_new2("records"));
                     VALUE record_h = rb_hash_new();
                     rb_hash_aset(record_h, rb_str_new2("timestamp"), INT2NUM(record->timestamp));
                     if (record->distance != FIT_UINT32_INVALID) {
//                        printf(", distance = %0.3fm", record->distance / 100.0f);
                        rb_hash_aset(record_h, rb_str_new2("distance"), DBL2NUM(record->distance));
                     }

                     if (record->enhanced_speed != FIT_UINT32_INVALID) {
//                        printf(", speed enhanced = %0.2fm/s", record->enhanced_speed / 1000.0f);
                        rb_hash_aset(record_h, rb_str_new2("enhanced_speed"), DBL2NUM(record->enhanced_speed));
                     }
                     else if (record->speed != FIT_UINT16_INVALID) {
                        rb_hash_aset(record_h, rb_str_new2("speed"), DBL2NUM(record->speed));
//                        printf(", speed = %0.2fm/s", record->speed / 1000.0f);
                     }

                     rb_ary_push(array, record_h);
                     VALUE new_array = rb_ary_concat(records, array);
                     rb_hash_aset(result, rb_str_new2("records"), new_array);

//                     printf("\n");
                     break;
                  }

                  case FIT_MESG_NUM_EVENT:
                  {
                     const FIT_EVENT_MESG *event = (FIT_EVENT_MESG *) mesg;
                     printf("Event: timestamp=%u\n", event->timestamp);
                     break;
                  }

                  case FIT_MESG_NUM_DEVICE_INFO:
                  {
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
   return result;
  }


void Init_ruby_fit() {
  VALUE cRubyFit;

  cRubyFit = rb_const_get(rb_cObject, rb_intern("RubyFit"));
  rb_define_alloc_func(cRubyFit, ruby_fit_alloc);
   rb_define_method(cRubyFit, "initialize", ruby_fit_init, 1);
   rb_define_method(cRubyFit, "print", ruby_fit_print, 0);
}
