// LiveKit marks its audio session API experimental; it is the only way to set the session once
// its plugin is in the app, and the version is pinned, so a change shows up when it is raised.
// ignore_for_file: experimental_member_use

import 'dart:io';

import 'package:livekit_client/livekit_client.dart' as lk;

/// The phone's audio session. Once LiveKit's plugin is in the app it owns the session, and
/// flutter_webrtc's own audio helpers (Helper.setAppleAudioConfiguration, setSpeakerphoneOn and
/// the rest) do nothing; so the voice (mesh or media server) and the media server's game sound
/// set it through LiveKit's AudioManager, always by hand (its manual mode, so LiveKit never
/// changes it on its own), and to what the voice set before: a voice chat on the speaker (or
/// the headphones) that lets the game's sound mix in while in voice, plain playback after.
class PhoneAudio {
  static bool _voice = false;

  static final _voiceChat = lk.AudioSessionOptions.communication(
    apple: const lk.AppleAudioSessionConfiguration(
      category: lk.AppleAudioCategory.playAndRecord,
      categoryOptions: {
        lk.AppleAudioCategoryOption.mixWithOthers,
        lk.AppleAudioCategoryOption.allowBluetooth,
        lk.AppleAudioCategoryOption.allowBluetoothA2DP,
        lk.AppleAudioCategoryOption.defaultToSpeaker,
      },
      mode: lk.AppleAudioMode.voiceChat,
    ),
  );

  static final _playback = lk.AudioSessionOptions.mediaPlayback(
    apple: const lk.AppleAudioSessionConfiguration(
      category: lk.AppleAudioCategory.playback,
      categoryOptions: {lk.AppleAudioCategoryOption.mixWithOthers},
      mode: lk.AppleAudioMode.default_,
    ),
  );

  /// At start: the app sets the session itself from here on, LiveKit never on its own.
  static Future<void> takeOver() async {
    try {
      await lk.AudioManager.instance.setAudioSessionManagementMode(
        lk.AudioSessionManagementMode.manual,
      );
    } on Object {
      // Set by hand on the first voice anyway.
    }
  }

  /// A voice chat while in voice; back to plain playback (Remote Play's sound) after.
  static Future<void> voice(bool on) async {
    _voice = on;
    final audio = lk.AudioManager.instance;
    try {
      if (Platform.isIOS) {
        await audio.setAudioSessionOptions(on ? _voiceChat : _playback);
      } else if (Platform.isAndroid) {
        if (on) {
          await audio.setAudioSessionOptions(_voiceChat);
        } else {
          // Focus given back, the mode as it was, no communication device.
          await audio.deactivateAudioSession();
        }
      }
    } on Object {
      // The platform's defaults, then.
    }
  }

  /// The speaker, or the headphones or Bluetooth when they are there (iOS); the speaker
  /// (Android), as the voice always did.
  static Future<void> speaker() async {
    try {
      await lk.AudioManager.instance.setSpeakerOutputPreferred(
        true,
        force: Platform.isAndroid,
      );
    } on Object {
      // The earpiece, then; voice still works.
    }
  }

  /// The game's sound from the media server: plain playback on iOS unless a voice is on (which
  /// plays it too). Android plays it as it is.
  static Future<void> playback() async {
    if (_voice || !Platform.isIOS) return;
    try {
      await lk.AudioManager.instance.setAudioSessionOptions(_playback);
    } on Object {
      // As it is, then.
    }
  }
}
