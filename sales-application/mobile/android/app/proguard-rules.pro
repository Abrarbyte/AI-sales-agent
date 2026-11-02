# Flutter and the plugins keep what they need through their own consumer
# rules. Kept for flutter_local_notifications' Gson-serialised schedules.
-keep class com.dexterous.** { *; }
-keep class com.google.gson.** { *; }
-keepattributes Signature
-keepattributes *Annotation*
