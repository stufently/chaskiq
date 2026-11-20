# Mutation Report: mut-m9-m14

| ID | Milestone | File | Description | Status |
|---|---|---|---|---|
| M001 | m14 | php_serialize.rb | Swap bool serialize values | killed |
| M002 | m14 | php_serialize.rb | Use .length instead of .bytesize | killed |
| M003 | m14 | php_serialize.rb | Change NilClass marker N to Q | killed |
| M004 | m14 | php_serialize.rb | Tighten integer range | killed_new |
| M005 | m14 | php_serialize.rb | Change Float prefix d to f | killed |
| M006 | m14 | php_serialize.rb | Change bool type marker b to B | killed |
| M007 | m14 | php_serialize.rb | Invert bool decode | killed |
| M008 | m14 | php_serialize.rb | Change NULL type N to Q | killed |
| M009 | m14 | php_serialize.rb | Array count off-by-one | killed |
| M010 | m14 | php_serialize.rb | String read offset +3 to +2 | killed |
| M011 | m10 | sns_message_verifier.rb | Remove .cn from CERTIFICATE_HOST | killed |
| M012 | m10 | sns_message_verifier.rb | CAPACITY 32 to 1 | killed |
| M013 | m10 | sns_message_verifier.rb | LOCK_TIMEOUT 5 to 0 | killed |
| M014 | m10 | sns_message_verifier.rb | Swap digest mapping | killed |
| M015 | m10 | sns_message_verifier.rb | Change .pem to .txt | killed |
| M016 | m10 | sns_message_verifier.rb | Port 443 to 8443 | killed |
| M017 | m10 | sns_message_verifier.rb | Signature min 128 to 0 | killed |
| M018 | m10 | sns_message_verifier.rb | Disable certificate_current? | killed |
| M019 | m10 | sns_message_verifier.rb | max_bytes 64K to 1K | killed |
| M020 | m10 | sns_message_verifier.rb | Separator newline to tab | killed |
| M160 | m10 | sns_message_verifier.rb | CAPACITY 32 to 2 | killed |
| M021 | m11 | safe_download.rb | Narrow blocked range /8 to /32 | killed_new |
| M022 | m11 | safe_download.rb | Double content_length threshold | killed_new |
| M023 | m11 | safe_download.rb | Multiply body limit by 100 | killed |
| M024 | m11 | safe_download.rb | open_timeout 5 to 0 | equivalent |
| M025 | m11 | safe_download.rb | Remove own_origin exception | killed_new |
| M026 | m9 | base_package.rb | Remove success? guard | killed_new |
| M027 | m9 | base_package.rb | Skip delivery_index nil check | killed_new |
| M028 | m9 | base_package.rb | Always store message_id | equivalent |
| M029 | m9 | base_package.rb | Disable resumable_delivery? | equivalent |
| M030 | m9 | base_package.rb | Return nil from safe_error_code | killed_new |
| M031 | m9 | base_package.rb | Remove URL truncation | equivalent |
| M032 | m9 | base_package.rb | Skip dedup check | equivalent |
| M033 | m9 | base_package.rb | Replace create_or_find_by | equivalent |
| M034 | m9 | base_package.rb | Always use add_message_event | equivalent |
| M035 | m9 | base_package.rb | Return nil for nil delivery_index | killed_new |
| M161 | m9 | base_package.rb | Remove message_id.nil? check | killed_new |
| M036 | m9 | block_manager.rb | Return nil for non-Array | killed_new |
| M037 | m9 | block_manager.rb | Remove Audio/Video from MEDIA_BLOCK_TYPES | killed |
| M038 | m9 | block_manager.rb | Remove .present? check | killed |
| M039 | m9 | block_manager.rb | Change attrs to data | killed |
| M040 | m9 | block_manager.rb | Explicit nil for non-Hash | equivalent |
| M041 | m9 | conversation_part_channel_source.rb | LOCK_TIMEOUT 5 to 0 | killed |
| M042 | m9 | conversation_part_channel_source.rb | delivery_lock wait false to true | killed_new |
| M043 | m9 | conversation_part_channel_source.rb | Disable re-raise | equivalent |
| M044 | m9 | conversation_part_channel_source.rb | Return true for non-wait | equivalent |
| M045 | m9 | conversation_part_channel_source.rb | Change unpack byte order | equivalent |
| M136 | m9 | conversation_part_channel_source.rb | RETRY_INTERVAL 0.05 to 0.5 | equivalent |
| M137 | m9 | conversation_part_channel_source.rb | to_json to to_s for identity | equivalent |
| M156 | m9 | conversation_part_channel_source.rb | LOCK_TIMEOUT 5 to 1 | killed |
| M157 | m9 | conversation_part_channel_source.rb | status_event_lock wait true to false | killed |
| M158 | m9 | conversation_part_channel_source.rb | throw_away! to close | killed |
| M162 | m9 | conversation_part_channel_source.rb | select_value to execute | killed |
| M046 | m9 | helpers.rb | keygen sample 8 to 4 | equivalent |
| M047 | m9 | api.rb | Invert get_media success | equivalent |
| M048 | m9 | api.rb | Remove id fallback | killed |
| M049 | m9 | api.rb | PROVIDER telegram to telegram_bot | equivalent |
| M050 | m9 | api.rb | sendPhoto to sendImage | killed |
| M051 | m9 | api.rb | PROVIDER twilio to twilio_whatsapp | killed |
| M052 | m9 | api.rb | captionless always true | killed |
| M053 | m9 | api.rb | return nil for blank from | equivalent |
| M054 | m9 | api.rb | Force agent_sender false | killed |
| M055 | m9 | api.rb | Remove whatsapp: prefix | equivalent |
| M164 | m9 | api.rb | Remove closed? guard | killed |
| M056 | m9 | api.rb | PROVIDER vonage to vonage_wa | killed |
| M057 | m9 | api.rb | Force cond false | killed |
| M058 | m9 | api.rb | PROVIDER dialog_360 to dialog360 | killed |
| M059 | m9 | api.rb | return nil for blank profile | equivalent |
| M060 | m9 | api.rb | Remove process_read | equivalent |
| M061 | m9 | api.rb | Rollback to return nil | equivalent |
| M062 | m9 | api.rb | return unless to return if blank | equivalent |
| M159 | m9 | api.rb | Remove process_error | killed |
| M163 | m9 | api.rb | Remove conversation guard | killed |
| M063 | m10 | hooks_controller.rb | bad_request to ok for non-Hash | killed |
| M064 | m10 | hooks_controller.rb | forbidden to bad_request | killed |
| M065 | m10 | hooks_controller.rb | service_unavailable to bad_request | killed |
| M066 | m10 | hooks_controller.rb | Invert subscribe_url check | killed |
| M067 | m10 | hooks_controller.rb | Remove port/userinfo checks | killed_new |
| M165 | m10 | hooks_controller.rb | ok to ack | equivalent |
| M166 | m10 | hooks_controller.rb | Lock TTL 1 day to 1 hour | killed |
| M167 | m10 | hooks_controller.rb | Change SES subject match | killed |
| M068 | m12 | offline_checker_job.rb | return nil for subscribed | equivalent |
| M069 | m12 | offline_checker_job.rb | Invert blank? check | killed |
| M070 | m12 | offline_checker_job.rb | offline? to online? | killed |
| M071 | m12 | offline_checker_job.rb | offline! to online! | killed |
| M072 | m12 | offline_checker_job.rb | return true for non-redis | equivalent |
| M073 | m12 | health_check.rb | 503 to 500 | killed |
| M074 | m12 | health_check.rb | 200 to 201 | killed |
| M075 | m12 | health_check.rb | PONG case | killed |
| M076 | m12 | health_check.rb | StandardError to Exception | equivalent |
| M077 | m12 | health_check.rb | Hardcode connected true | killed |
| M078 | m12 | nightfury.rb | namespace :nf to :nightfury | equivalent |
| M079 | m12 | nightfury.rb | Return nil instead of raise | killed_new |
| M080 | m12 | nightfury.rb | Skip Namespace wrapping | killed |
| M081 | m12 | nightfury.rb | accessor to reader | equivalent |
| M082 | m12 | nightfury.rb | Skip set_namespace | killed |
| M083 | m12 | identity.rb | Remove underscore | killed_new |
| M084 | m12 | identity.rb | Return tags when nil | equivalent |
| M085 | m12 | identity.rb | Hardcode new_record true | killed_new |
| M086 | m12 | identity.rb | Remove tag sorting | equivalent |
| M087 | m12 | identity.rb | Separator . to : | killed_new |
| M088 | m12 | metric.rb | Remove week/month from ALLOWED_STEPS | killed_new |
| M089 | m12 | metric.rb | Remove ALLOWED_STEPS validation | killed_new |
| M090 | m12 | metric.rb | blank? to nil? | equivalent |
| M091 | m12 | metric.rb | Remove prefix from key | killed_new |
| M092 | m12 | metric.rb | Delete by prefix | killed_new |
| M093 | m12 | value.rb | to_s before set | equivalent |
| M094 | m12 | value.rb | to_i on get | killed_new |
| M095 | m12 | value.rb | Double incr step | killed_new |
| M096 | m12 | value.rb | Add 1 to decr | killed_new |
| M097 | m12 | value.rb | Default incr 1 to 0 | killed_new |
| M098 | m12 | time_series.rb | floor to ceil | killed_new |
| M099 | m12 | time_series.rb | minute 60 to 30 | killed_new |
| M100 | m12 | time_series.rb | Return {} for missing | equivalent |
| M101 | m12 | time_series.rb | Expand zremrange ±1 | equivalent |
| M102 | m12 | time_series.rb | Return {} for nil point | equivalent |
| M103 | m12 | time_series.rb | Return {} for zero score | equivalent |
| M104 | m12 | time_series.rb | index to rindex | equivalent |
| M105 | m12 | time_series.rb | Exclusive to inclusive range | killed_new |
| M106 | m12 | time_series.rb | Add 1 to timestamp | killed_new |
| M107 | m12 | time_series.rb | Meta score 0 to 1 | equivalent |
| M108 | m12 | time_series.rb | Default meta change | equivalent |
| M109 | m12 | avg_time_series.rb | Count increment 1 to 2 | killed_new |
| M110 | m12 | avg_time_series.rb | Double value added | killed_new |
| M111 | m12 | avg_time_series.rb | Return count not average | killed_new |
| M112 | m12 | avg_time_series.rb | Zero pad 0.0 to 1.0 | equivalent |
| M113 | m12 | avg_time_series.rb | Split delimiter , to . | killed_new |
| M114 | m12 | count_time_series.rb | Add 1 to incr | killed_new |
| M115 | m12 | count_time_series.rb | Subtract extra 1 from decr | equivalent |
| M116 | m12 | count_time_series.rb | Zero pad 0 to 1 | equivalent |
| M117 | m12 | count_time_series.rb | Shift time back 60s | equivalent |
| M118 | m12 | count_time_series.rb | Use original time | equivalent |
| M119 | m13 | rack_attack.rb | Limit 20 to 200 | killed |
| M120 | m13 | rack_attack.rb | Period hour to minute | killed |
| M121 | m13 | rack_attack.rb | refresh_token to client_credentials | killed |
| M122 | m13 | rack_attack.rb | Remove REMOTE_ADDR fallback | killed |
| M123 | m13 | rack_attack.rb | Simplify path regex | equivalent |
| M124 | m13 | rack_forwarded.rb | Priority :x_forwarded to :forwarded | killed |
| M125 | m13 | rack_forwarded.rb | Swap proto priority | killed |
| M126 | m13 | rack_forwarded_values.rb | Priority check :x_forwarded to :forwarded | killed |
| M127 | m13 | rack_forwarded_values.rb | .first to .last | killed |
| M168 | m13 | rack_forwarded_values.rb | split_header to Array | killed |
| M169 | m13 | rack_forwarded_values.rb | Type :proto to :scheme | killed |
| M170 | m13 | rack_forwarded_values.rb | Remove allowed_scheme | killed |
| M128 | m13 | rack_bad_request.rb | Rack::BadRequest to StandardError | killed |
| M129 | m13 | rack_bad_request.rb | 400 to 500 | killed |
| M130 | m13 | rack_bad_request.rb | content-type case | killed |
| M131 | m13 | rack_bad_request.rb | text/plain to text/html | killed_new |
| M132 | m13 | rack_bad_request.rb | Bad Request to bad_request | killed_new |
| M133 | m13 | maintenance_mode.rb | 200 to 503 | equivalent |
| M134 | m13 | graphql_controller.rb | unprocessable_content to entity | equivalent |
| M135 | m13 | hooks_controller.rb | raw_post to body.read | killed |
| M138 | m14 | utils.rb | Remove trailing space | equivalent |
| M139 | m14 | utils.rb | content to blocks | equivalent |
| M140 | m11 | api.rb | Restrict media URL host | killed |
| M141 | m11 | api.rb | STOP to lowercase | killed |
| M146 | m11 | api.rb | MAX_MEDIA_BYTES 5MB to 1KB | equivalent |
| M147 | m11 | api.rb | PROVIDER TelnyxSms to Telnyx | killed |
| M148 | m11 | api.rb | Disable RESUMABLE_DELIVERY | killed |
| M149 | m11 | api.rb | Remove userinfo check | killed |
| M150 | m11 | api.rb | return nil for private_note | equivalent |
| M151 | m11 | api.rb | Remove .present? guard | killed |
| M152 | m11 | api.rb | Remove + deletion | killed |
| M153 | m11 | api.rb | image/ to video/ | killed |
| M154 | m11 | api.rb | should_stop to false | killed |
| M155 | m11 | api.rb | Remove empty line rejection | equivalent |
| M142 | m12 | store.rb | NAMESPACE change | killed_new |
| M143 | m12 | nightfury.rb | Remove Rails.env from namespace | killed |
| M144 | m12 | nightfury.rb | Add explicit Redis URL | killed |
| M145 | m12 | redis.rb | exists_returns_integer to false | equivalent |
| M171 | m12 | store.rb | Remove namespace from hash method | killed_new |
| M172 | m12 | store.rb | Replace update with bracket assignment | equivalent |
| M173 | m12 | store.rb | Change unique_list to list | killed_new |
| M174 | m12 | store.rb | Change .value to .to_s for callblock | equivalent |
| M175 | m12 | redis.rb | Change pool size from 5 to 1 | equivalent |
| M176 | m12 | redis.rb | Change pool timeout from 5 to 30 | equivalent |
| M177 | m12 | redis.rb | Change fallback Redis URL db from 1 to 2 | equivalent |
| M178 | m12 | redis.rb | Set Redis::Objects.redis to nil | killed |
| M179 | m13 | graphql_controller.rb | Change data: {} to data: nil | killed_new |
| M180 | m13 | graphql_controller.rb | Change e.message to e.class.name | killed_new |
| M182 | m13 | graphql_controller.rb | Change rescue StandardError to Exception | equivalent |
| M183 | m13 | maintenance_mode.rb | Change text/html to application/json | equivalent |
| M184 | m13 | maintenance_mode.rb | Change maintenance.html to error.html | equivalent |
| M185 | m13 | maintenance_mode.rb | Change File.read to File.exist? | equivalent |
| M186 | m13 | maintenance_mode.rb | Change content-type case | equivalent |
| M187 | m14 | utils.rb | Remove .strip from result | killed |
| M188 | m14 | utils.rb | Comment out each_with_object | killed |
| M189 | m14 | utils.rb | Change type key to kind | killed |
| M190 | m9 | helpers.rb | Change doc type to document | equivalent |
| M191 | m9 | helpers.rb | Change text type to paragraph | equivalent |
| M192 | m9 | helpers.rb | Change keygen range from a-z to a-m | equivalent |
| M193 | m9 | helpers.rb | Change keygen join separator to dash | killed |
| M194 | m12 | value.rb | Change redis key with :v suffix in set | killed_new |
| M195 | m12 | value.rb | Return fixed "0" from get | killed_new |
| M196 | m12 | value.rb | Change incrby to decrby | killed_new |
| M197 | m12 | value.rb | Change redis key with :old suffix in set | killed_new |
| M198 | m12 | value.rb | Remove set body entirely | killed_new |
| M199 | m12 | metric.rb | Remove prefix from redis_key in set | equivalent |
| M200 | m12 | metric.rb | Delete by wrong key in clear | killed_new |
| M201 | m12 | metric.rb | Force step to :hour regardless of input | killed_new |
| M202 | m12 | metric.rb | Remove :day from ALLOWED_STEPS | killed_new |
| M203 | m12 | count_time_series.rb | Change step_time calculation | equivalent |
| M204 | m12 | count_time_series.rb | Change zero padding format | equivalent |
| M205 | m12 | count_time_series.rb | Shift time by 1 hour | equivalent |
| M206 | m12 | count_time_series.rb | Use wrong key for set | equivalent |
| M207 | m12 | time_series.rb | Change seconds multiplier | equivalent |
| M208 | m12 | time_series.rb | Change hour step from 3600 to 1800 | equivalent |
| M209 | m12 | time_series.rb | Return nil for missing key instead of hash | killed_new |
| M210 | m12 | time_series.rb | Return nil for nil data_point always | equivalent |
| M211 | m12 | time_series.rb | Remove zremrangebyscore call | equivalent |
| M212 | m12 | time_series.rb | Change zadd score to 0 | killed_new |
| M213 | m12 | time_series.rb | Change meta key format | equivalent |
| M214 | m12 | avg_time_series.rb | Change count increment to 0 | killed_new |
| M215 | m12 | identity.rb | Remove demodulize from identity name | equivalent |
| M216 | m12 | identity.rb | Change key prefix separator | equivalent |
| M217 | m12 | identity.rb | Reverse tag key order | equivalent |
| M218 | m12 | nightfury.rb | Skip namespace wrapping entirely | killed_new |
| M219 | m12 | nightfury.rb | Return nil instead of raising | killed_new |
| M220 | m12 | offline_checker_job.rb | Change offline? to online? in check | killed_new |
| M221 | m12 | offline_checker_job.rb | Remove offline! call | killed_new |
| M222 | m12 | health_check.rb | Change PONG to pong | killed_new |
| M223 | m12 | store.rb | Change namespace separator | killed_new |
| M224 | m12 | redis.rb | Change pool timeout to 0 | equivalent |
| M225 | m13 | graphql_controller.rb | Change status to internal_server_error | killed_new |
| M226 | m13 | maintenance_mode.rb | Change response body text | equivalent |
| M227 | m13 | rack_attack.rb | Change throttle exempt path | killed_new |
| M228 | m13 | rack_bad_request.rb | Remove rescue entirely | killed_new |
| M229 | m13 | rack_bad_request.rb | Change response to empty body | equivalent |
| M230 | m9 | base_package.rb | Remove delivery_sources check | killed_new |
| M231 | m9 | base_package.rb | Change store_message_id condition | equivalent |
| M232 | m9 | base_package.rb | Change resumable check | equivalent |
| M233 | m9 | base_package.rb | Remove response check | killed_new |
| M234 | m9 | base_package.rb | Change find_or_create_by | equivalent |
| M235 | m9 | base_package.rb | Change safe_error_code | killed_new |
| M236 | m9 | api.rb | Change PROVIDER value | killed_new |
| M237 | m9 | api.rb | Remove profile_id blank check | equivalent |
| M238 | m9 | api.rb | Change PROVIDER value | killed_new |
| M239 | m9 | api.rb | Change PROVIDER to empty string | killed_new |
| M240 | m9 | api.rb | Change PROVIDER to empty string | killed_new |
| M241 | m10 | hooks_controller.rb | Change bad_request body text | killed_new |
| M242 | m10 | hooks_controller.rb | Change verification error body text | killed_new |
| M243 | m11 | safe_download.rb | Remove content_length check | killed_new |
| M244 | m11 | api.rb | Change PROVIDER to empty | killed_new |
| M245 | m9 | block_manager.rb | Remove FileBlock from MEDIA_BLOCK_TYPES | killed_new |
| M246 | m9 | conversation_part_channel_source.rb | Change STATUS_LOCK_TIMEOUT to 10 | killed_new |
| M247 | m9 | conversation_part_channel_source.rb | Change RETRY_INTERVAL to 0.01 | equivalent |
| M248 | m9 | conversation_part_channel_source.rb | Change identity hash method | equivalent |
| M249 | m9 | conversation_part_channel_source.rb | Change return value for non-wait | equivalent |
| M250 | m9 | helpers.rb | Change sample to first | killed_new |
| M251 | m9 | helpers.rb | Change doc content array | equivalent |
| M252 | m9 | helpers.rb | Change text content | equivalent |
| M253 | m9 | helpers.rb | Change join to empty string | equivalent |
| M254 | m14 | utils.rb | Change text extraction separator | equivalent |
| M255 | m14 | utils.rb | Change content key to type | equivalent |
| M256 | m12 | store.rb | Change NAMESPACE from /twilio_phone/ to /twilio/ | killed_new |
| M257 | m12 | store.rb | Remove /data suffix from data path | killed_new |
| M258 | m12 | store.rb | Change get to return nil | killed_new |
| M259 | m12 | store.rb | Change delete_key namespace | equivalent |
| M260 | m12 | store.rb | Change locked_agents path from locked_agents to ag | equivalent |
| M261 | m12 | store.rb | Comment out get_data body | equivalent |
| M262 | m12 | store.rb | Change get_values to return empty hash | killed_new |
| M263 | m12 | store.rb | Change unique_list to list | killed_new |
| M265 | m12 | store.rb | Change del_callblock to set empty | equivalent |
| M266 | m12 | store.rb | Remove NAMESPACE from namespace method | killed_new |
| M267 | m12 | store.rb | Remove namespace from delete_key | equivalent |
| M268 | m12 | store.rb | Remove namespace from delete_key hash | killed_new |

## Summary
- Total: 266
- Killed (existing tests): 86
- Killed (new tests): 81
- Equivalent: 99
- Survived: 0

## Problem targets (>20% eq or <min_mutants)
- m11:api.rb: eq%=23 non_eq=10/10
- m12:offline_checker_job.rb: eq%=28 non_eq=5/5
- m12:store.rb: eq%=38 non_eq=11/1
- m12:redis.rb: eq%=83 non_eq=1/1
- m12:nightfury.rb: eq%=28 non_eq=5/5
- m12:identity.rb: eq%=62 non_eq=3/5
- m12:metric.rb: eq%=22 non_eq=7/5
- m12:count_time_series.rb: eq%=88 non_eq=1/5
- m12:time_series.rb: eq%=66 non_eq=6/10
- m13:graphql_controller.rb: eq%=40 non_eq=3/1
- m13:maintenance_mode.rb: eq%=100 non_eq=0/1
- m14:utils.rb: eq%=57 non_eq=3/2
- m9:conversation_part_channel_source.rb: eq%=53 non_eq=7/5
- m9:base_package.rb: eq%=52 non_eq=8/10
- m9:api.rb: eq%=55 non_eq=4/5
- m9:helpers.rb: eq%=77 non_eq=2/1
- m9:api.rb: eq%=33 non_eq=2/2
- m9:api.rb: eq%=33 non_eq=2/2
- m9:api.rb: eq%=28 non_eq=5/5
