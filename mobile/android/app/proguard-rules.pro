# shared_preferences_android 2.5 calls its Kotlin API from Dart through JNI, which R8 cannot
# see, and ships no rule to keep it: without this the release app stops before its first frame
# (NoSuchMethodError on SharedPreferencesApiRegistrar.getAll).
-keep class io.flutter.plugins.sharedpreferences.** { *; }
# The jni package looks these up by name to run and finish Kotlin suspend calls (kotlin/Result,
# kotlin/Unit, kotlin/coroutines/intrinsics/…); without them: "Didn't find class kotlin…".
-keep class kotlin.Unit { *; }
-keep class kotlin.Result { *; }
-keep class kotlin.Result$Failure { *; }
-keep class kotlin.coroutines.** { *; }
# Named in the plugin's generated constructors and enum accessors.
-keep class kotlin.enums.EnumEntries { *; }
-keep class kotlin.jvm.internal.DefaultConstructorMarker { *; }
